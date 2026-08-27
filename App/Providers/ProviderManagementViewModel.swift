import AppKit
import Foundation
import Observation
import OmpKit

enum ProviderWorkspaceSection: Equatable, Sendable {
    case connections
    case usage
}

private struct ProviderServiceBox: Sendable {
    let events: AsyncStream<ProviderLoginEvent>
    let providers: @Sendable () async throws -> [ProviderLoginProvider]
    let login: @Sendable (String, Int) async throws -> Void
    let respond: @Sendable (String, [String: JSONValue]) async throws -> Void
    let cancelLogin: @Sendable () async -> Void
    let shutdown: @Sendable () async -> Void

    init<Service: ProviderManaging>(_ service: Service) {
        events = service.events
        providers = { try await service.providers() }
        login = { providerID, generation in
            try await service.login(providerID: providerID, generation: generation)
        }
        respond = { requestID, body in try await service.respond(requestID: requestID, body: body) }
        cancelLogin = { await service.cancelLogin() }
        shutdown = { await service.shutdown() }
    }
}

private struct UsageServiceBox: Sendable {
    let loadUsage: @Sendable () async throws -> OmpUsageSnapshot

    init<Service: OmpUsageLoading>(_ service: Service) {
        loadUsage = { try await service.loadUsage() }
    }
}

private func defaultProviderTimeFormat(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

private struct RefreshOperation {
    let id: Int
    let task: Task<Void, Never>
}

@MainActor
@Observable
final class ProviderManagementViewModel {
    var query = ""
    var isShowingAllProviders = false
    var selectedSection: ProviderWorkspaceSection = .connections
    private(set) var focusedConnectionsProviderID: String?
    private(set) var providers: [ProviderLoginProvider] = []
    private(set) var usage = ProviderUsagePresentation.empty
    private(set) var accountTier: ProviderAccountTier = .providerOnly
    private(set) var isLoadingProviders = false
    private(set) var isRefreshingUsage = false
    private(set) var providerMessage: String?
    private(set) var usageMessage: String?
    private(set) var activeLoginProviderID: String?
    private(set) var loginMessage: String?
    private(set) var loginMessageProviderID: String?
    private(set) var sheetRequest: ExtensionUIState?
    private(set) var lastUsageRefresh: Date?
    private(set) var pendingRemovalAccounts: Set<ProviderAccountKey> = []
    private(set) var removalMessage: String?
    private(set) var removalMessageProviderID: String?

    @ObservationIgnored private let providerService: ProviderServiceBox
    @ObservationIgnored private let usageService: UsageServiceBox
    @ObservationIgnored private let openURL: @MainActor @Sendable (URL) -> Void
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let formatTime: @Sendable (Date) -> String
    @ObservationIgnored private var extensionRouter = ExtensionUIRouter()
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var loginGeneration = 0
    @ObservationIgnored private var lastUsageSnapshot: OmpUsageSnapshot?
    @ObservationIgnored private var accountCapabilities: [String: ProviderAccountCapability] = [:]
    @ObservationIgnored private var accountSummaries: [String: [ProviderAccountSummary]] = [:]
    @ObservationIgnored private var accountUsage: [String: [ProviderAccountUsage]] = [:]
    /// Account refs `removeAccount` has confirmed removed — via the
    /// extension's authoritative `{removed, accounts}` reply — that the
    /// CLI-polled usage snapshot (`lastUsageSnapshot`) may still list,
    /// because that snapshot's own refresh cadence is decoupled from the
    /// extension-side removal that just happened. See
    /// `refreshAccountUsage`'s use of this set for the full mechanism this
    /// guards against (task-10b fix round 1, "Finding 2"). Cleared per ref
    /// once a snapshot-derived pass no longer contains it — the snapshot
    /// has caught up — and per provider by `retainAccountState` when that
    /// provider stops being authenticated.
    @ObservationIgnored private var removedAccountRefsAwaitingSnapshotCatchUp: [String: Set<String>] = [:]
    @ObservationIgnored private var loadedAccountUsageProviderIDs: Set<String> = []
    @ObservationIgnored private var unavailableAccountUsageProviderIDs: Set<String> = []
    @ObservationIgnored private var failedAccountCapabilityProviderIDs: Set<String> = []
    @ObservationIgnored private var usagePresentationRevision: UInt64 = 0
    @ObservationIgnored private var usageFailureGeneration = 0
    @ObservationIgnored private var isUsageSnapshotCurrentlyFailing = false
    @ObservationIgnored private var nextRefreshOperationID = 0
    @ObservationIgnored private var providerRefreshOperation: RefreshOperation?
    @ObservationIgnored private var usageRefreshOperation: RefreshOperation?
    @ObservationIgnored private weak var accountCoordinator: ProviderAccountCoordinator?
    // `var`, not `let`: installed after construction, matching
    // `ProviderAccountCoordinator.install(routingBackend:restartSession:)`'s
    // reasoning — the transport closes over session-level state
    // (`AppModel.accountChannelRegistry`) that does not exist yet at
    // `ProviderManagementViewModel` construction time, and this view model
    // itself gets rebuilt whenever the OMP executable changes, so
    // installation happens at every construction site, not once. `nil`
    // (the default) means no transport is available — no live session
    // channel, or the app hasn't wired one yet — and `removeAccount` throws
    // rather than pretending success; there is no stock-tier fallback for
    // removal (see `ProviderAccountTier.supportsRemoval`).
    @ObservationIgnored private var removeAccountTransport:
        (@MainActor (String, String) async throws -> ProviderAccountRemovalResult)?
    // Same `var`-not-`let`, installed-after-construction reasoning as
    // `removeAccountTransport` immediately above — this closure also closes
    // over `AppModel.accountChannelRegistry`. `nil` (the default, and also
    // what a live app has before any session's channel attaches) means
    // `resolveExtensionHello()` reports no hello available, which
    // `ProviderAccountTier.detect` already treats the same as a channel
    // that answered with an incompatible version: fail closed to
    // `.stockOMP`. See `resolveExtensionHello()` for why this is fetched at
    // most once rather than on every refresh.
    @ObservationIgnored private var tierHelloProvider: (@MainActor () async -> ProviderExtensionHello?)?
    @ObservationIgnored private var cachedExtensionHello: ProviderExtensionHello?

    init<ProviderService: ProviderManaging, UsageService: OmpUsageLoading>(
        providerService: ProviderService,
        usageService: UsageService,
        openURL: @escaping @MainActor @Sendable (URL) -> Void = { url in
            NSWorkspace.shared.open(url)
        },
        now: @escaping @Sendable () -> Date = Date.init,
        formatTime: @escaping @Sendable (Date) -> String = defaultProviderTimeFormat
    ) {
        self.providerService = ProviderServiceBox(providerService)
        self.usageService = UsageServiceBox(usageService)
        self.openURL = openURL
        self.now = now
        self.formatTime = formatTime
        consumeEvents(from: self.providerService.events)
    }

    var hasAuthenticatedProvider: Bool {
        providers.contains { $0.isAvailable && $0.isAuthenticated }
    }

    var visibleProviders: [ProviderLoginProvider] {
        let selected = isShowingAllProviders
            ? providers
            : providers.filter { Self.curatedProviderIDs.contains($0.id) || $0.isAuthenticated }
        let matching = query.isEmpty
            ? selected
            : selected.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || $0.id.localizedCaseInsensitiveContains(query)
            }
        return matching.sorted(by: Self.providerOrder)
    }

    var dockProviders: [ProviderUsageProvider] {
        usage.dockProviders
    }

    func connectionAccounts(providerID: String) -> [ProviderAccountSummary] {
        (accountSummaries[providerID] ?? []).enumerated().sorted { lhs, rhs in
            if lhs.element.connectionOrder != rhs.element.connectionOrder {
                return lhs.element.connectionOrder < rhs.element.connectionOrder
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    func supportsAccountManagement(providerID: String) -> Bool {
        accountCapabilities[providerID] == .accountRouting
    }

    func attachAccountCoordinator(_ coordinator: ProviderAccountCoordinator) {
        accountCoordinator = coordinator
        for (providerID, accounts) in accountSummaries {
            coordinator.reconcilePrimaryAccount(providerID: providerID, accounts: accounts)
        }
    }

    /// How `removeAccount` below reaches the extension's `remove_account`
    /// command. The live app installs this from `AppModel`, which is the
    /// only place session-scoped state (the account channel registry) exists
    /// — see `AppModel`'s call site for the full reasoning, mirroring
    /// `ProviderAccountCoordinator.install(routingBackend:restartSession:)`.
    func installAccountRemovalTransport(
        _ transport: (@MainActor (String, String) async throws -> ProviderAccountRemovalResult)?
    ) {
        removeAccountTransport = transport
    }

    /// How `refreshAccountUsage` below learns whether a live extension is
    /// answering, for `ProviderAccountTier.detect`'s `extensionHello`
    /// parameter. The live app installs this from `AppModel`, alongside
    /// `installAccountRemovalTransport` — see that call site's doc comment
    /// for the full reasoning shared by both installs.
    func installTierHelloProvider(_ provider: (@MainActor () async -> ProviderExtensionHello?)?) {
        tierHelloProvider = provider
        cachedExtensionHello = nil
    }

    func load() async {
        await refresh()
    }

    /// Invariant: the caller must already have a usage refresh started or in
    /// flight (e.g. `loadUsage()`/`refresh()`, or a fire-and-forget task that
    /// calls one) before or immediately alongside this call. Tier detection
    /// inside `refreshAccountUsage` needs a usage snapshot; on cold start it
    /// waits for `usageRefreshOperation` only if that property is already
    /// set, it does not start one itself. Every current production call site
    /// (`AppModel.swift`) calls the fire-and-forget `startProviderUsage(for:)`
    /// immediately before `loadProviders()`, and because both are MainActor
    /// jobs enqueued in that order, MainActor's serial FIFO executor
    /// guarantees `usageRefreshOperation` is set before this call's
    /// `refreshAccountUsage` reaches its wait-check — no explicit
    /// synchronization needed. A caller that invokes `loadProviders()` alone,
    /// with no usage refresh started or in flight, will see tier detection
    /// fail closed to `.providerOnly` on cold start with no error surfaced.
    func loadProviders() async {
        await refreshProviders(forceFresh: false)
    }

    func loadUsage() async {
        await refreshUsage(forceFresh: false)
    }

    func refresh() async {
        await refresh(forceFresh: false)
    }

    private func refresh(forceFresh: Bool) async {
        async let providerRefresh: Void = refreshProviders(forceFresh: forceFresh)
        async let usageRefresh: Void = refreshUsage(forceFresh: forceFresh)
        await providerRefresh
        await usageRefresh
    }

    func refreshIfStale() async {
        guard let lastUsageRefresh else {
            await refresh()
            return
        }
        guard now().timeIntervalSince(lastUsageRefresh) >= Self.staleRefreshInterval else { return }
        await refresh()
    }

    func login(_ provider: ProviderLoginProvider) async {
        guard provider.isAvailable, activeLoginProviderID == nil else { return }
        loginGeneration += 1
        let generation = loginGeneration
        activeLoginProviderID = provider.id
        loginMessage = nil
        loginMessageProviderID = nil
        sheetRequest = nil

        do {
            try await providerService.login(provider.id, generation)
            guard generation == loginGeneration else { return }
            await refresh(forceFresh: true)
            guard generation == loginGeneration else { return }
            clearLoginState()
        } catch {
            guard generation == loginGeneration else { return }
            sheetRequest = nil
            activeLoginProviderID = nil
            loginMessage = "Couldn’t connect to \(provider.name)."
            loginMessageProviderID = provider.id
        }
    }

    func removeAccount(
        _ account: ProviderAccountSummary,
        coordinator: ProviderAccountCoordinator
    ) async {
        attachAccountCoordinator(coordinator)
        let key = ProviderAccountKey(
            providerID: account.providerID,
            accountRef: account.accountRef)
        guard pendingRemovalAccounts.insert(key).inserted else { return }
        removalMessage = nil
        removalMessageProviderID = nil
        defer { pendingRemovalAccounts.remove(key) }

        do {
            let result = try await coordinator.removeAccount(
                providerID: account.providerID,
                accountRef: account.accountRef,
                accounts: connectionAccounts(providerID: account.providerID)
            ) { [removeAccountTransport, providerID = account.providerID, accountRef = account.accountRef] in
                guard let removeAccountTransport else {
                    throw ProviderAccountChannelError.unavailable
                }
                return try await removeAccountTransport(providerID, accountRef)
            }
            accountSummaries[account.providerID] = result.accounts
            // Finding 2 (task-10b fix round 1): `result.accounts` is
            // authoritative — straight from the extension's removal reply —
            // but the very next line's `refresh(forceFresh:)` can still
            // re-derive `accountSummaries[account.providerID]` from
            // `lastUsageSnapshot`, a CLI-polled snapshot on its own refresh
            // cadence that may not yet reflect this removal. Recording the
            // ref here (only when the authoritative reply actually omits
            // it — `result.removed` can be `false` while still reporting a
            // list that no longer contains it, e.g. the "already gone"
            // case below) tells that re-derivation to filter it out until
            // the snapshot itself agrees. See
            // `removedAccountRefsAwaitingSnapshotCatchUp`'s doc comment.
            if !result.accounts.contains(where: { $0.accountRef == account.accountRef }) {
                removedAccountRefsAwaitingSnapshotCatchUp[account.providerID, default: []]
                    .insert(account.accountRef)
            }
            coordinator.reconcilePrimaryAccount(
                providerID: account.providerID,
                accounts: result.accounts)
            accountUsage[account.providerID] = accountUsage[account.providerID]?.filter {
                $0.accountRef != account.accountRef
            }
            rebuildUsage(at: lastUsageRefresh ?? now())
            await refresh(forceFresh: true)
            if !result.removed {
                removalMessage = "Account is no longer available."
                removalMessageProviderID = account.providerID
            }
        } catch ProviderAccountRemovalError.noEligibleReplacement {
            await refresh(forceFresh: true)
            removalMessage = "Account couldn’t be removed because no replacement account is available."
            removalMessageProviderID = account.providerID
        } catch ProviderAccountRemovalError.reassignmentFailed(let count) {
            await refresh(forceFresh: true)
            removalMessage = count == 1
                ? "Account couldn’t be removed because 1 10x-managed session couldn’t switch."
                : "Account couldn’t be removed because \(count) 10x-managed sessions couldn’t switch."
            removalMessageProviderID = account.providerID
        } catch {
            await refresh(forceFresh: true)
            removalMessage = "Account couldn’t be removed."
            removalMessageProviderID = account.providerID
        }
    }

    func cancelLogin() async {
        loginGeneration += 1
        clearLoginState()
        await providerService.cancelLogin()
    }

    func shutdown() async {
        let events = eventTask
        eventTask = nil
        events?.cancel()
        let providers = providerRefreshOperation
        providerRefreshOperation = nil
        providers?.task.cancel()
        let usage = usageRefreshOperation
        usageRefreshOperation = nil
        usage?.task.cancel()

        await providerService.shutdown()
        await events?.value
        await providers?.task.value
        await usage?.task.value
    }

    func respond(to request: ExtensionUIState, with response: ExtensionUIResponse) async {
        do {
            try await providerService.respond(request.id, response.body)
            extensionRouter.removeRequest(id: request.id)
            sheetRequest = extensionRouter.sheetRequest
        } catch {
            loginMessage = "Couldn’t send the response."
            loginMessageProviderID = activeLoginProviderID
        }
    }

    func showAllProviders() {
        isShowingAllProviders = true
    }

    func focusConnections(providerID: String) {
        selectedSection = .connections
        focusedConnectionsProviderID = providerID
    }

    private func refreshProviders(forceFresh: Bool) async {
        while let operation = providerRefreshOperation {
            await operation.task.value
            if providerRefreshOperation?.id == operation.id {
                providerRefreshOperation = nil
            }
            guard forceFresh else { return }
        }

        let operation = makeProviderRefreshOperation()
        providerRefreshOperation = operation
        await operation.task.value
        if providerRefreshOperation?.id == operation.id {
            providerRefreshOperation = nil
        }
    }

    private func makeProviderRefreshOperation() -> RefreshOperation {
        nextRefreshOperationID += 1
        let id = nextRefreshOperationID
        let failureGeneration = usageFailureGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performProviderRefresh(usageFailureGeneration: failureGeneration)
        }
        return RefreshOperation(id: id, task: task)
    }

    private func performProviderRefresh(usageFailureGeneration: Int) async {
        isLoadingProviders = true
        defer { isLoadingProviders = false }

        do {
            providers = try await providerService.providers()
            retainAccountState(for: Set(providers.filter(\.isAuthenticated).map(\.id)))
            if usageFailureGeneration == self.usageFailureGeneration {
                rebuildUsage(at: lastUsageRefresh ?? now())
            }
            providerMessage = nil
            await refreshAccountUsage(for: providers.filter(\.isAuthenticated))
        } catch {
            providerMessage = "Providers couldn’t be loaded."
        }
    }

    private func refreshAccountUsage(for authenticatedProviders: [ProviderLoginProvider]) async {
        guard !authenticatedProviders.isEmpty else { return }
        // Tier detection reads the usage snapshot populated by the sibling
        // usage refresh kicked off alongside this one (see `refresh(forceFresh:)`).
        // On the very first refresh there may be no snapshot yet, so wait for
        // that one-time bootstrap. Once a snapshot exists, do NOT block on the
        // sibling for subsequent refreshes: accounts and their usage below
        // are both derived synchronously from whatever snapshot is already
        // on hand (`ProviderAccountUsageBackend`, Task 10b) — a slow or
        // failing CLI-wide usage fetch must not stall that derivation behind
        // it when a perfectly good previous snapshot is already available.
        // (A blocking, unconditional wait here deadlocks against exactly
        // that scenario — see
        // `refreshAccountUsageDoesNotBlockOnASlowSubsequentUsagePoll`, which
        // gates a second CLI usage load and confirms the provider refresh
        // still completes, from the old snapshot, while it's stalled.)
        if lastUsageSnapshot == nil {
            await usageRefreshOperation?.task.value
        }

        guard let snapshot = lastUsageSnapshot else {
            // No snapshot has ever loaded successfully: detection can't run.
            // Fail closed the same way an RPC failure used to.
            for provider in authenticatedProviders {
                failedAccountCapabilityProviderIDs.insert(provider.id)
            }
            providerMessage = "Provider accounts couldn’t be loaded."
            rebuildUsage(at: lastUsageRefresh ?? now())
            return
        }

        let extensionHello = await resolveExtensionHello()
        let tier = ProviderAccountTier.detect(snapshot: snapshot, extensionHello: extensionHello)
        accountTier = tier
        let capability: ProviderAccountCapability
        switch tier {
        case .extensionBacked, .stockOMP:
            capability = .accountRouting
        case .providerOnly:
            capability = .providerOnly
        }

        for provider in authenticatedProviders {
            accountCapabilities[provider.id] = capability
            failedAccountCapabilityProviderIDs.remove(provider.id)
            guard capability == .accountRouting else {
                accountSummaries.removeValue(forKey: provider.id)
                accountUsage.removeValue(forKey: provider.id)
                loadedAccountUsageProviderIDs.remove(provider.id)
                unavailableAccountUsageProviderIDs.remove(provider.id)
                rebuildUsage(at: lastUsageRefresh ?? now())
                continue
            }

            // Pure derivations over the snapshot already on hand — no RPC,
            // so no failure mode of their own (Task 10b: the RPC these used
            // to call, `providerService.accounts`/`accountUsage`, is gone;
            // Task 10 deleted its implementation and left only the
            // `ProviderAccountManaging` protocol default returning `[]`).
            // Both derive from the same `snapshot.reports` filtered by
            // `provider.id`, so an account from `accounts(from:providerID:)`
            // always has a matching entry from `usage(from:providerID:)` —
            // there is no longer a window where metadata is known but usage
            // isn't, or vice versa.
            var accounts = ProviderAccountUsageBackend.accounts(from: snapshot, providerID: provider.id)
            var usageEntries = ProviderAccountUsageBackend.usage(from: snapshot, providerID: provider.id)
            // Finding 2 (task-10b fix round 1): this snapshot may predate a
            // removal `removeAccount` already confirmed authoritatively —
            // see `removedAccountRefsAwaitingSnapshotCatchUp`'s doc comment.
            // Filtering here, not comparing snapshot recency, because nothing
            // about `OmpUsageSnapshot` identifies which refresh produced it;
            // the removed ref's continued presence in THIS derivation is
            // itself the staleness signal, and its absence is exactly the
            // "caught up" signal that clears the guard.
            if let pendingRemovals = removedAccountRefsAwaitingSnapshotCatchUp[provider.id] {
                let stillStale = pendingRemovals.intersection(accounts.map(\.accountRef))
                if stillStale.isEmpty {
                    removedAccountRefsAwaitingSnapshotCatchUp.removeValue(forKey: provider.id)
                } else {
                    accounts = accounts.filter { !stillStale.contains($0.accountRef) }
                    usageEntries = usageEntries.filter { !stillStale.contains($0.accountRef) }
                }
            }
            accountSummaries[provider.id] = accounts
            accountCoordinator?.reconcilePrimaryAccount(
                providerID: provider.id,
                accounts: accounts)
            accountUsage[provider.id] = usageEntries
            loadedAccountUsageProviderIDs.insert(provider.id)
            unavailableAccountUsageProviderIDs.remove(provider.id)
            // `isUsageSnapshotCurrentlyFailing` is live state (set by
            // `performUsageRefresh`), not a since-entry diff, so it reads
            // correctly even when that failure completed before this
            // function was entered — a per-account derivation succeeding
            // must not silently clear a CLI-wide snapshot failure, a
            // different failure domain.
            if unavailableAccountUsageProviderIDs.isEmpty && !isUsageSnapshotCurrentlyFailing {
                usageMessage = nil
            }
            rebuildUsage(at: now())
        }
    }

    /// Resolves the extension's `hello` handshake for `ProviderAccountTier
    /// .detect`, fetching it at most once per `ProviderManagementViewModel`
    /// instance (task-10b fix round 1, "Finding 1"). `tierHelloProvider` is
    /// installed post-construction by `AppModel`
    /// (`installTierHelloProvider`) because it closes over session-level
    /// state (`AppModel.accountChannelRegistry`) that doesn't exist at this
    /// view model's construction time — same reasoning as
    /// `removeAccountTransport`.
    ///
    /// Caching, not a fresh probe on every refresh: `refreshAccountUsage`
    /// runs on every `refresh()` — every login, every removal, the
    /// 5-minute stale timer — and the extension's answer is a fact about
    /// the running app's *bundled* build, not something that changes
    /// session to session. Once a well-formed reply arrives — compatible or
    /// not; an incompatible version is just as stable a fact as a
    /// compatible one — remembering it turns every later refresh's tier
    /// detection back into the free, synchronous comparison
    /// `ProviderAccountTier.detect` already was before this method existed.
    /// A `nil` result (no provider installed yet, no channel attached, or
    /// `ProviderAccountExtensionBackend.hello`'s bounded wait expired) is
    /// deliberately NOT cached, so the next refresh tries again once a
    /// channel exists — the only state in which repeated probing is
    /// possible, and each probe is short (`ProviderAccountExtensionBackend
    /// .helloTimeout`), so the cost stays bounded even then.
    private func resolveExtensionHello() async -> ProviderExtensionHello? {
        if let cachedExtensionHello { return cachedExtensionHello }
        guard let tierHelloProvider else { return nil }
        guard let hello = await tierHelloProvider() else { return nil }
        cachedExtensionHello = hello
        return hello
    }

    private func retainAccountState(for providerIDs: Set<String>) {
        accountCapabilities = accountCapabilities.filter { providerIDs.contains($0.key) }
        accountSummaries = accountSummaries.filter { providerIDs.contains($0.key) }
        accountUsage = accountUsage.filter { providerIDs.contains($0.key) }
        removedAccountRefsAwaitingSnapshotCatchUp = removedAccountRefsAwaitingSnapshotCatchUp
            .filter { providerIDs.contains($0.key) }
        loadedAccountUsageProviderIDs.formIntersection(providerIDs)
        unavailableAccountUsageProviderIDs.formIntersection(providerIDs)
        failedAccountCapabilityProviderIDs.formIntersection(providerIDs)
    }

    private func refreshUsage(forceFresh: Bool) async {
        while let operation = usageRefreshOperation {
            await operation.task.value
            if usageRefreshOperation?.id == operation.id {
                usageRefreshOperation = nil
            }
            guard forceFresh else { return }
        }

        let operation = makeUsageRefreshOperation()
        usageRefreshOperation = operation
        await operation.task.value
        if usageRefreshOperation?.id == operation.id {
            usageRefreshOperation = nil
        }
    }

    private func makeUsageRefreshOperation() -> RefreshOperation {
        nextRefreshOperationID += 1
        let id = nextRefreshOperationID
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performUsageRefresh()
        }
        return RefreshOperation(id: id, task: task)
    }

    private func performUsageRefresh() async {
        isRefreshingUsage = true
        defer { isRefreshingUsage = false }
        let previousUsage = usage
        let startingPresentationRevision = usagePresentationRevision

        do {
            let snapshot = try await usageService.loadUsage()
            let refreshDate = now()
            lastUsageSnapshot = snapshot
            usage = usagePresentation(from: snapshot, at: refreshDate)
            usagePresentationRevision &+= 1
            lastUsageRefresh = refreshDate
            isUsageSnapshotCurrentlyFailing = false
            if unavailableAccountUsageProviderIDs.isEmpty {
                usageMessage = nil
            }
        } catch {
            usageFailureGeneration += 1
            isUsageSnapshotCurrentlyFailing = true
            if usagePresentationRevision == startingPresentationRevision {
                usage = previousUsage
            }
            if let lastUsageRefresh {
                usageMessage = "Usage couldn’t be refreshed. Showing data from \(formatTime(lastUsageRefresh))."
            } else {
                usageMessage = "Usage couldn’t be loaded."
            }
        }
    }

    private func consumeEvents(from events: AsyncStream<ProviderLoginEvent>) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                self.consume(event)
            }
        }
    }

    private func consume(_ event: ProviderLoginEvent) {
        guard event.generation == loginGeneration, activeLoginProviderID != nil else { return }
        let request = event.request
        guard let state = ExtensionUIRouter.parse(request) else { return }

        switch state {
        case .openURL(_, let url, _):
            extensionRouter.consume(request)
            openURL(url)
        case .input:
            extensionRouter.consume(request)
            sheetRequest = extensionRouter.sheetRequest
        case .notification:
            extensionRouter.consume(request)
            guard let activeLoginProviderID,
                  let provider = providers.first(where: { $0.id == activeLoginProviderID })
            else {
                loginMessage = "Connection needs attention."
                loginMessageProviderID = nil
                return
            }
            loginMessage = "Connecting to \(provider.name)."
            loginMessageProviderID = provider.id
        case .cancel:
            extensionRouter.consume(request)
            sheetRequest = extensionRouter.sheetRequest
        default:
            break
        }
    }

    private func clearLoginState() {
        activeLoginProviderID = nil
        loginMessage = nil
        loginMessageProviderID = nil
        extensionRouter = ExtensionUIRouter()
        sheetRequest = nil
    }

    private func usagePresentation(from snapshot: OmpUsageSnapshot, at date: Date) -> ProviderUsagePresentation {
        lastUsageSnapshot = snapshot
        return combinedUsagePresentation(at: date)
    }

    private func rebuildUsage(at date: Date) {
        usage = combinedUsagePresentation(at: date)
        usagePresentationRevision &+= 1
    }

    private func combinedUsagePresentation(at date: Date) -> ProviderUsagePresentation {
        let providerNames = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0.name) })
        let providerOnly = ProviderUsagePresentation.make(
            snapshot: lastUsageSnapshot ?? .empty,
            providerNames: providerNames,
            now: date)
        let accountPresentation = ProviderUsagePresentation.makeAccountRouting(
            providerNames: providerNames,
            accounts: providers.flatMap { accountSummaries[$0.id] ?? [] },
            usage: providers.flatMap { accountUsage[$0.id] ?? [] },
            loadedUsageProviderIDs: loadedAccountUsageProviderIDs,
            usageUnavailableProviderIDs: unavailableAccountUsageProviderIDs,
            now: date)
        let accountProviders = Dictionary(
            uniqueKeysWithValues: accountPresentation.providers.map { ($0.id, $0) })
        let providerOnlyProviders = Dictionary(
            uniqueKeysWithValues: providerOnly.providers.map { ($0.id, $0) })
        var orderedProviderIDs = providers.map(\.id)
        for providerID in providerOnly.providers.map(\.id) + accountPresentation.providers.map(\.id)
        where !orderedProviderIDs.contains(providerID) {
            orderedProviderIDs.append(providerID)
        }
        // `accountCapabilities` is one tier-wide value applied to every
        // authenticated provider (`ProviderAccountTier` is detected once
        // for the whole snapshot, not per provider — see
        // `refreshAccountUsage`), so a provider can be classed
        // account-routing and still have zero accounts of its own: its own
        // `omp usage --json` report carries no per-account identity, e.g.
        // it appears only in `accountsWithoutUsage` (GitHub Copilot in the
        // fixture this was found against, next to a Cursor account that
        // does have identity). The correct per-provider signal for "does
        // this provider actually have a routed presentation to show" is
        // whether `accountProviders` — built just above from the real,
        // materialized account list — contains an entry for it, not
        // whether the tier-wide flag says routing is possible in general.
        // A provider with a real entry there is shown through it;
        // everything else (never routed, or routed but empty) falls back
        // to its own provider-only rendering instead of disappearing,
        // unless capability computation failed for it outright.
        let presentedProviders = orderedProviderIDs.compactMap { providerID -> ProviderUsageProvider? in
            if let routedProvider = accountProviders[providerID] {
                return routedProvider
            }
            if failedAccountCapabilityProviderIDs.contains(providerID) { return nil }
            return providerOnlyProviders[providerID]
        }
        let fallbackAccounts = providerOnly.accountsWithoutUsage.filter { account in
            guard let providerID = account.id.split(separator: ":", maxSplits: 1).first.map(String.init)
            else { return true }
            return accountProviders[providerID] == nil
                && !failedAccountCapabilityProviderIDs.contains(providerID)
        }
        let fallbackIssues = providerOnly.credentialIssues.filter { issue in
            accountProviders[issue.providerID] == nil
                && !failedAccountCapabilityProviderIDs.contains(issue.providerID)
        }
        return ProviderUsagePresentation(
            providers: presentedProviders,
            accountsWithoutUsage: fallbackAccounts,
            credentialIssues: fallbackIssues)
    }

    private static let staleRefreshInterval: TimeInterval = 300

    private static let curatedProviderIDs = [
        "openai-codex",
        "anthropic",
        "cursor",
        "google-gemini-cli",
    ]

    private static func providerOrder(
        _ lhs: ProviderLoginProvider,
        _ rhs: ProviderLoginProvider
    ) -> Bool {
        if lhs.isAuthenticated != rhs.isAuthenticated { return lhs.isAuthenticated }
        let lhsIndex = curatedProviderIDs.firstIndex(of: lhs.id) ?? Int.max
        let rhsIndex = curatedProviderIDs.firstIndex(of: rhs.id) ?? Int.max
        if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

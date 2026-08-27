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

        let tier = ProviderAccountTier.detect(snapshot: snapshot, extensionHello: nil)
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
            let accounts = ProviderAccountUsageBackend.accounts(from: snapshot, providerID: provider.id)
            accountSummaries[provider.id] = accounts
            accountCoordinator?.reconcilePrimaryAccount(
                providerID: provider.id,
                accounts: accounts)
            accountUsage[provider.id] = ProviderAccountUsageBackend.usage(from: snapshot, providerID: provider.id)
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

    private func retainAccountState(for providerIDs: Set<String>) {
        accountCapabilities = accountCapabilities.filter { providerIDs.contains($0.key) }
        accountSummaries = accountSummaries.filter { providerIDs.contains($0.key) }
        accountUsage = accountUsage.filter { providerIDs.contains($0.key) }
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
        let routedProviderIDs = Set(accountCapabilities.compactMap { key, value in
            value == .accountRouting ? key : nil
        })
        let providerOnlyExcludedIDs = routedProviderIDs.union(failedAccountCapabilityProviderIDs)
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
        let presentedProviders = orderedProviderIDs.compactMap { providerID in
            if routedProviderIDs.contains(providerID) {
                return accountProviders[providerID]
            }
            if providerOnlyExcludedIDs.contains(providerID) { return nil }
            return providerOnlyProviders[providerID]
        }
        let fallbackAccounts = providerOnly.accountsWithoutUsage.filter { account in
            let providerID = account.id.split(separator: ":", maxSplits: 1).first.map(String.init)
            return providerID.map { !providerOnlyExcludedIDs.contains($0) } ?? true
        }
        let fallbackIssues = providerOnly.credentialIssues.filter {
            !providerOnlyExcludedIDs.contains($0.providerID)
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

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
    let accountCapability: @Sendable (String) async throws -> ProviderAccountCapability
    let accounts: @Sendable (String) async throws -> [ProviderAccountSummary]
    let accountUsage: @Sendable (String) async throws -> [ProviderAccountUsage]
    let login: @Sendable (String, Int) async throws -> Void
    let respond: @Sendable (String, [String: JSONValue]) async throws -> Void
    let cancelLogin: @Sendable () async -> Void
    let shutdown: @Sendable () async -> Void

    init<Service: ProviderManaging>(_ service: Service) {
        events = service.events
        providers = { try await service.providers() }
        accountCapability = { try await service.accountCapability(providerID: $0) }
        accounts = { try await service.accounts(providerID: $0) }
        accountUsage = { try await service.accountUsage(providerID: $0) }
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
    private(set) var providers: [ProviderLoginProvider] = []
    private(set) var usage = ProviderUsagePresentation.empty
    private(set) var isLoadingProviders = false
    private(set) var isRefreshingUsage = false
    private(set) var providerMessage: String?
    private(set) var usageMessage: String?
    private(set) var activeLoginProviderID: String?
    private(set) var loginMessage: String?
    private(set) var loginMessageProviderID: String?
    private(set) var sheetRequest: ExtensionUIState?
    private(set) var lastUsageRefresh: Date?

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
    @ObservationIgnored private var usageFailureGeneration = 0
    @ObservationIgnored private var nextRefreshOperationID = 0
    @ObservationIgnored private var providerRefreshOperation: RefreshOperation?
    @ObservationIgnored private var usageRefreshOperation: RefreshOperation?

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

    func load() async {
        await refresh()
    }

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
        for provider in authenticatedProviders {
            do {
                let capability = try await providerService.accountCapability(provider.id)
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

                accountSummaries[provider.id] = try await providerService.accounts(provider.id)
                rebuildUsage(at: lastUsageRefresh ?? now())
                do {
                    accountUsage[provider.id] = try await providerService.accountUsage(provider.id)
                    loadedAccountUsageProviderIDs.insert(provider.id)
                    unavailableAccountUsageProviderIDs.remove(provider.id)
                    if unavailableAccountUsageProviderIDs.isEmpty {
                        usageMessage = nil
                    }
                } catch {
                    accountUsage.removeValue(forKey: provider.id)
                    loadedAccountUsageProviderIDs.remove(provider.id)
                    unavailableAccountUsageProviderIDs.insert(provider.id)
                    usageMessage = "Usage couldn’t be loaded."
                }
                rebuildUsage(at: now())
            } catch {
                failedAccountCapabilityProviderIDs.insert(provider.id)
                providerMessage = "Provider accounts couldn’t be loaded."
                rebuildUsage(at: lastUsageRefresh ?? now())
            }
        }
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

        do {
            let snapshot = try await usageService.loadUsage()
            let refreshDate = now()
            lastUsageSnapshot = snapshot
            usage = usagePresentation(from: snapshot, at: refreshDate)
            lastUsageRefresh = refreshDate
            if unavailableAccountUsageProviderIDs.isEmpty {
                usageMessage = nil
            }
        } catch {
            usageFailureGeneration += 1
            usage = previousUsage
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

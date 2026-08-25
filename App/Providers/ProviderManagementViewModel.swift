import AppKit
import Foundation
import Observation
import OmpKit

enum ProviderWorkspaceSection: Equatable, Sendable {
    case connections
    case usage
}

private struct ProviderServiceBox: Sendable {
    let events: AsyncStream<ExtensionUIRequest>
    let providers: @Sendable () async throws -> [ProviderLoginProvider]
    let login: @Sendable (String) async throws -> Void
    let respond: @Sendable (String, [String: JSONValue]) async throws -> Void
    let cancelLogin: @Sendable () async -> Void

    init<Service: ProviderManaging>(_ service: Service) {
        events = service.events
        providers = { try await service.providers() }
        login = { providerID in try await service.login(providerID: providerID) }
        respond = { requestID, body in try await service.respond(requestID: requestID, body: body) }
        cancelLogin = { await service.cancelLogin() }
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

    var railProviders: [ProviderUsageProvider] {
        usage.railProviders
    }

    func load() async {
        await refresh()
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
            try await providerService.login(provider.id)
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
            if usageFailureGeneration == self.usageFailureGeneration, let lastUsageSnapshot {
                usage = usagePresentation(from: lastUsageSnapshot, at: lastUsageRefresh ?? now())
            }
            providerMessage = nil
        } catch {
            providerMessage = "Providers couldn’t be loaded."
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
            usageMessage = nil
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

    private func consumeEvents(from events: AsyncStream<ExtensionUIRequest>) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await request in events {
                guard let self, !Task.isCancelled else { return }
                self.consume(request)
            }
        }
    }

    private func consume(_ request: ExtensionUIRequest) {
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
        ProviderUsagePresentation.make(
            snapshot: snapshot,
            providerNames: Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0.name) }),
            now: date)
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

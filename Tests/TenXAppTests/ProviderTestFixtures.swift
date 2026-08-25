import Foundation
import OmpKit
import Testing
@testable import TenXApp

actor FakeProviderService: ProviderManaging {
    nonisolated let events: AsyncStream<ExtensionUIRequest>

    private let continuation: AsyncStream<ExtensionUIRequest>.Continuation
    private var storedProviders: [ProviderLoginProvider]
    private var providerError: (any Error & Sendable)?
    private let loginGate: LoginGate?
    private var providerGates: [LoadGate] = []
    private(set) var providerLoadCount = 0
    private(set) var loginIDs: [String] = []
    private(set) var responses: [(String, [String: JSONValue])] = []
    private(set) var cancelCount = 0

    init(
        providers: [ProviderLoginProvider],
        providerError: (any Error & Sendable)? = nil,
        loginGate: LoginGate? = nil
    ) {
        storedProviders = providers
        self.providerError = providerError
        self.loginGate = loginGate
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    func providers() async throws -> [ProviderLoginProvider] {
        providerLoadCount += 1
        let result = storedProviders
        let gate = providerGates.isEmpty ? nil : providerGates.removeFirst()
        await gate?.started()
        await gate?.waitForRelease()
        if let providerError { throw providerError }
        return result
    }

    func login(providerID: String) async throws {
        loginIDs.append(providerID)
        await loginGate?.started()
        await loginGate?.waitForRelease()
        storedProviders = storedProviders.map { provider in
            guard provider.id == providerID else { return provider }
            return ProviderLoginProvider(
                id: provider.id,
                name: provider.name,
                isAvailable: provider.isAvailable,
                isAuthenticated: true)
        }
        await loginGate?.completed()
    }

    func respond(requestID: String, body: [String: JSONValue]) async throws {
        responses.append((requestID, body))
    }

    func cancelLogin() async {
        cancelCount += 1
    }

    func shutdown() async {
        continuation.finish()
    }

    func emit(_ request: ExtensionUIRequest) {
        continuation.yield(request)
    }

    func enqueueProviderGate(_ gate: LoadGate) {
        providerGates.append(gate)
    }

    func setProviders(_ providers: [ProviderLoginProvider]) {
        storedProviders = providers
    }
}

actor LoginGate {
    private var hasStarted = false
    private var hasCompleted = false
    private var isReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completionWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func started() {
        hasStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForStart() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func completed() {
        hasCompleted = true
        let waiters = completionWaiters
        completionWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForCompletion() async {
        guard !hasCompleted else { return }
        await withCheckedContinuation { completionWaiters.append($0) }
    }

    func waitForRelease() async {
        guard !isReleased else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

actor LoadGate {
    private var hasStarted = false
    private var isReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func started() {
        hasStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForStart() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func waitForRelease() async {
        guard !isReleased else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

enum FakeProviderError: Error, Sendable {
    case discoveryFailed
}

actor FakeUsageService: OmpUsageLoading {
    private let snapshot: OmpUsageSnapshot
    private(set) var loadCount = 0
    private var isFailing = false
    private var loadGates: [LoadGate] = []

    init(snapshot: OmpUsageSnapshot) {
        self.snapshot = snapshot
    }

    func loadUsage() async throws -> OmpUsageSnapshot {
        loadCount += 1
        let gate = loadGates.isEmpty ? nil : loadGates.removeFirst()
        await gate?.started()
        await gate?.waitForRelease()
        if isFailing { throw OmpUsageServiceError.loadFailed }
        return snapshot
    }

    func setFailing(_ value: Bool) {
        isFailing = value
    }

    func enqueueLoadGate(_ gate: LoadGate) {
        loadGates.append(gate)
    }
}

actor OpenURLRecorder {
    private var urls: [URL] = []
    private var waiters: [CheckedContinuation<URL, Never>] = []

    func append(_ url: URL) {
        urls.append(url)
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: url)
        }
    }

    func waitForURL() async -> URL {
        if let url = urls.last { return url }
        return await withCheckedContinuation { waiters.append($0) }
    }
}

@MainActor
func waitForModelState(
    _ predicate: @escaping @MainActor @Sendable () -> Bool
) async {
    await ModelStateWaiter(predicate: predicate).wait()
}

@MainActor
private final class ModelStateWaiter {
    private let predicate: @MainActor @Sendable () -> Bool
    private var continuation: CheckedContinuation<Void, Never>?

    init(predicate: @escaping @MainActor @Sendable () -> Bool) {
        self.predicate = predicate
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observe()
        }
    }

    private func observe() {
        var isSatisfied = false
        withObservationTracking {
            isSatisfied = predicate()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observe()
            }
        }
        guard isSatisfied, let continuation else { return }
        self.continuation = nil
        continuation.resume()
    }
}

@MainActor
func providerTestModel(
    providers: [ProviderLoginProvider],
    snapshot: OmpUsageSnapshot = .empty,
    providerError: (any Error & Sendable)? = nil,
    now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 100) }
) -> ProviderManagementViewModel {
    ProviderManagementViewModel(
        providerService: FakeProviderService(
            providers: providers,
            providerError: providerError),
        usageService: FakeUsageService(snapshot: snapshot),
        openURL: { _ in },
        now: now,
        formatTime: { _ in "4:00 PM" })
}

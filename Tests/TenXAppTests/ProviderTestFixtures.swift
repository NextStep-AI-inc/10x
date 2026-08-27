import Foundation
import OmpKit
import Testing
@testable import TenXApp

actor FakeProviderService: ProviderManaging {
    nonisolated let events: AsyncStream<ProviderLoginEvent>

    private let continuation: AsyncStream<ProviderLoginEvent>.Continuation
    private var storedProviders: [ProviderLoginProvider]
    private var providerError: (any Error & Sendable)?
    private var loginError: FakeProviderError?
    private var loginGates: [LoginGate]
    private let shutdownGate: LoadGate?
    private var providerGates: [LoadGate] = []
    private(set) var providerLoadCount = 0
    private(set) var loginIDs: [String] = []
    private(set) var responses: [(String, [String: JSONValue])] = []
    private(set) var cancelCount = 0
    private(set) var shutdownCount = 0

    init(
        providers: [ProviderLoginProvider],
        providerError: (any Error & Sendable)? = nil,
        loginError: FakeProviderError? = nil,
        loginGate: LoginGate? = nil,
        shutdownGate: LoadGate? = nil
    ) {
        storedProviders = providers
        self.providerError = providerError
        self.loginError = loginError
        self.loginGates = loginGate.map { [$0] } ?? []
        self.shutdownGate = shutdownGate
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

    func login(providerID: String, generation: Int) async throws {
        loginIDs.append(providerID)
        let gate = loginGates.isEmpty ? nil : loginGates.removeFirst()
        await gate?.started()
        await gate?.waitForRelease()
        if let loginError { throw loginError }
        storedProviders = storedProviders.map { provider in
            guard provider.id == providerID else { return provider }
            return ProviderLoginProvider(
                id: provider.id,
                name: provider.name,
                isAvailable: provider.isAvailable,
                isAuthenticated: true)
        }
        await gate?.completed()
    }

    func respond(requestID: String, body: [String: JSONValue]) async throws {
        responses.append((requestID, body))
    }

    func cancelLogin() async {
        cancelCount += 1
    }

    func shutdown() async {
        shutdownCount += 1
        continuation.finish()
        await shutdownGate?.started()
        await shutdownGate?.waitForRelease()
    }

    func emit(_ request: ExtensionUIRequest, generation: Int = 1) {
        continuation.yield(ProviderLoginEvent(request: request, generation: generation))
    }

    func enqueueProviderGate(_ gate: LoadGate) {
        providerGates.append(gate)
    }

    func enqueueLoginGate(_ gate: LoginGate) {
        loginGates.append(gate)
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
    case loginFailed
}

actor FakeUsageService: OmpUsageLoading {
    private var snapshot: OmpUsageSnapshot
    private(set) var loadCount = 0
    private var isFailing = false
    private var loadGates: [LoadGate] = []

    init(snapshot: OmpUsageSnapshot) {
        self.snapshot = snapshot
    }

    /// Changes what the *next* `loadUsage()` call returns. Account reads now
    /// derive from this snapshot (`ProviderAccountUsageBackend`) rather than
    /// a separate per-account RPC, so a test that needs the account list to
    /// grow or change after some action (e.g. login) must swap the snapshot
    /// itself instead of pushing new account data through the provider fake.
    func setSnapshot(_ snapshot: OmpUsageSnapshot) {
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

/// A usage snapshot carrying per-account identity (an email) for `providerID`,
/// which is what `ProviderAccountTier.detect` needs to see to select anything
/// beyond `.providerOnly`. Tests that exercise `.accountRouting` behavior via
/// the account-management fakes below need this instead of `.empty` now that
/// tier detection (not a per-test `capabilities:` override) decides it.
func accountRoutingUsageSnapshotFixture(
    providerID: String,
    email: String = "tanner@example.com"
) throws -> OmpUsageSnapshot {
    try JSONDecoder().decode(OmpUsageSnapshot.self, from: Data("""
    {"generatedAt":1,"reports":[
      {"provider":"\(providerID)","fetchedAt":1,"limits":[],"metadata":{"email":"\(email)"}}
    ],"accountsWithoutUsage":[],"disabledCredentials":[]}
    """.utf8))
}

/// One account's identity (plus an optional usage window and disabled-credential
/// flag) inside a `multiAccountUsageSnapshotFixture`. Mirrors exactly the
/// `OmpUsageReport.metadata` fields `ProviderAccountUsageBackend` reads
/// (`accountId`, `email`, `orgName`), so tests can drive real,
/// snapshot-derived accounts now that reads no longer go through a
/// per-account RPC a fake can hand back arbitrary refs for.
struct AccountSnapshotEntry {
    let accountID: String
    let email: String?
    let orgName: String?
    let isDisabled: Bool
    let remainingFraction: Double?

    init(
        accountID: String,
        email: String? = nil,
        orgName: String? = nil,
        isDisabled: Bool = false,
        remainingFraction: Double? = 0.5
    ) {
        self.accountID = accountID
        self.email = email
        self.orgName = orgName
        self.isDisabled = isDisabled
        self.remainingFraction = remainingFraction
    }

    /// The `accountRef` `ProviderAccountUsageBackend.accountRef(for:)` derives
    /// for this entry — computed via the same production hash
    /// (`ProviderAccountRef.make`) rather than an arbitrary test string, so
    /// assertions compare against what the real read path actually produces.
    func accountRef(providerID: String) -> String {
        ProviderAccountRef.make(
            providerID: providerID,
            accountID: accountID,
            email: email,
            orgID: nil,
            projectID: nil)!
    }
}

/// A usage snapshot carrying one `OmpUsageReport` per `accounts` entry, for
/// tests that need multiple distinguishable per-account identities —
/// `accountRoutingUsageSnapshotFixture` above only ever produces one.
/// `connectionOrder` on the resulting `ProviderAccountSummary` follows array
/// order, matching `ProviderAccountUsageBackend`'s enumerate-before-compactMap
/// contract.
func multiAccountUsageSnapshotFixture(
    providerID: String,
    accounts: [AccountSnapshotEntry]
) -> OmpUsageSnapshot {
    let reports = accounts.map { account -> OmpUsageReport in
        var metadata: [String: JSONValue] = ["accountId": .string(account.accountID)]
        if let email = account.email { metadata["email"] = .string(email) }
        if let orgName = account.orgName { metadata["orgName"] = .string(orgName) }
        let limits: [OmpUsageLimit] = account.remainingFraction.map { fraction in
            [OmpUsageLimit(
                id: "\(account.accountID):usage",
                label: "Usage",
                scope: OmpUsageScope(
                    provider: providerID,
                    accountId: account.accountID,
                    projectId: nil,
                    orgId: nil,
                    modelId: nil,
                    tier: nil,
                    windowId: nil,
                    shared: nil),
                window: nil,
                amount: OmpUsageAmount(
                    used: nil,
                    limit: nil,
                    remaining: nil,
                    usedFraction: nil,
                    remainingFraction: fraction,
                    unit: "percent"),
                status: nil,
                notes: nil)]
        } ?? []
        return OmpUsageReport(
            provider: providerID,
            fetchedAt: 1,
            limits: limits,
            metadata: metadata)
    }
    let disabledCredentials = accounts.filter(\.isDisabled).map { account in
        OmpDisabledCredential(
            id: 0,
            provider: providerID,
            type: "oauth",
            cause: "disabled",
            email: account.email,
            accountId: account.accountID,
            orgId: nil,
            orgName: account.orgName,
            disabledAtMs: 0)
    }
    return OmpUsageSnapshot(
        generatedAt: 1,
        reports: reports,
        accountsWithoutUsage: [],
        disabledCredentials: disabledCredentials)
}

func providerAccountFixture(
    providerID: String,
    ref: String,
    label: String,
    order: Int,
    availability: ProviderAccountAvailability = .available,
    detailLabel: String? = nil
) -> ProviderAccountSummary {
    ProviderAccountSummary(
        providerID: providerID,
        accountRef: ref,
        displayLabel: label,
        detailLabel: detailLabel,
        connectionOrder: order,
        availability: availability)
}

func providerAccountUsageFixture(
    providerID: String,
    ref: String,
    windows: [ProviderAccountUsageWindow]
) -> ProviderAccountUsage {
    ProviderAccountUsage(
        providerID: providerID,
        accountRef: ref,
        refreshedAt: Date(timeIntervalSince1970: 1),
        usageWindows: windows)
}

func providerAccountUsageWindowFixture(
    id: String,
    label: String,
    sourceIndex: Int = 0,
    duration: ProviderAccountUsageWindow.Duration? = nil,
    remainingFraction: Double? = 0.5,
    resetsAt: Date? = nil,
    status: String? = nil
) -> ProviderAccountUsageWindow {
    ProviderAccountUsageWindow(
        id: id,
        label: label,
        duration: duration,
        sourceIndex: sourceIndex,
        remainingFraction: remainingFraction,
        resetsAt: resetsAt,
        status: status)
}

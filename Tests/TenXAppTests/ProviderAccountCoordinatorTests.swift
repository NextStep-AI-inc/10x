import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Suite @MainActor struct ProviderAccountCoordinatorTests {
    private let providerID = "openai-codex"

    @Test func thisSessionPinsOnlyTheMatchingOpenSession() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = FakeProviderAccountSession(providerID: providerID, accountRef: "acct_A")
        let second = FakeProviderAccountSession(providerID: providerID, accountRef: "acct_B")
        coordinator.register(first)
        coordinator.register(second)

        await coordinator.useAccount(
            "acct_C",
            providerID: providerID,
            scope: .thisSession,
            openSessionID: first.id)

        #expect(first.pins == ["acct_C"])
        #expect(second.pins.isEmpty)
        #expect(coordinator.activeAccountRefs[first.id] == "acct_C")
    }

    @Test func allCurrentPinsIdleSessionsAndQueuesTheLatestChoiceForGeneratingSessions() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = FakeProviderAccountSession(providerID: providerID, accountRef: "acct_A")
        let second = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_B",
            runtimeState: .streaming)
        let otherProvider = FakeProviderAccountSession(
            providerID: "anthropic",
            accountRef: "acct_other")
        coordinator.register(first)
        coordinator.register(second)
        coordinator.register(otherProvider)

        await coordinator.useAccount(
            "acct_C",
            providerID: providerID,
            scope: .allCurrentSessions,
            openSessionID: first.id)
        await coordinator.useAccount(
            "acct_D",
            providerID: providerID,
            scope: .allCurrentSessions,
            openSessionID: first.id)

        #expect(first.pins == ["acct_C", "acct_D"])
        #expect(second.pins.isEmpty)
        #expect(otherProvider.pins.isEmpty)
        #expect(coordinator.pendingAccountRef(sessionID: second.id) == "acct_D")

        second.setGenerating(false)
        await coordinator.sessionDidBecomeIdle(second.id)

        #expect(second.pins == ["acct_D"])
        #expect(coordinator.pendingAccountRef(sessionID: second.id) == nil)
    }

    @Test func allNewSessionsChangesOnlyThePrimaryPreference() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let current = FakeProviderAccountSession(providerID: providerID, accountRef: "acct_A")
        coordinator.register(current)

        await coordinator.useAccount(
            "acct_C",
            providerID: providerID,
            scope: .allNewSessions,
            openSessionID: current.id)

        #expect(current.pins.isEmpty)
        #expect(coordinator.primaryAccountRef(providerID: providerID) == "acct_C")
    }

    @Test func partialFailureContinuesAndPublishesOnlyASanitizedSummary() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let failing = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_A",
            failingAccountRefs: ["acct_secret"])
        let succeeding = FakeProviderAccountSession(providerID: providerID, accountRef: "acct_B")
        coordinator.register(failing)
        coordinator.register(succeeding)

        await coordinator.useAccount(
            "acct_secret",
            providerID: providerID,
            scope: .allCurrentSessions,
            openSessionID: failing.id)

        #expect(failing.pins.isEmpty)
        #expect(succeeding.pins == ["acct_secret"])
        #expect(coordinator.failureSummary == "Couldn’t switch 1 session.")
        #expect(coordinator.failureSummary?.contains("acct_secret") == false)
        #expect(coordinator.failureSummary?.contains("credential") == false)
    }

    @Test func exactCountsMoveOnNewerAccountEventsWithoutDoubleCounting() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_A",
            runtimeState: .streaming)
        let second = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_A",
            runtimeState: .streaming)
        coordinator.register(first)
        coordinator.register(second)
        let accountA = ProviderAccountKey(providerID: providerID, accountRef: "acct_A")
        let accountB = ProviderAccountKey(providerID: providerID, accountRef: "acct_B")

        #expect(coordinator.generatingCounts == [accountA: 2])

        coordinator.session(first.id, didChangeAccount: accountEvent(ref: "acct_B", sequence: 2))
        coordinator.session(first.id, didChangeAccount: accountEvent(ref: "acct_A", sequence: 2))
        coordinator.session(first.id, didChangeAccount: accountEvent(ref: "acct_A", sequence: 1))

        #expect(coordinator.activeAccountRefs[first.id] == "acct_B")
        #expect(coordinator.generatingCounts == [accountA: 1, accountB: 1])

        coordinator.session(first.id, didChangeAccount: accountEvent(ref: "acct_A", sequence: 3))

        #expect(coordinator.generatingCounts == [accountA: 2])
    }

    @Test func runtimeUpdatesChangeExactCountsAndCleanupRemovesAllSessionState() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_A",
            runtimeState: .idle)
        coordinator.register(session)
        let key = ProviderAccountKey(providerID: providerID, accountRef: "acct_A")

        session.setGenerating(true)
        coordinator.update(sessionID: session.id, providerID: providerID, isGenerating: true)
        #expect(coordinator.generatingCounts == [key: 1])

        await coordinator.useAccount(
            "acct_C",
            providerID: providerID,
            scope: .allCurrentSessions,
            openSessionID: session.id)
        session.setGenerating(true)
        coordinator.update(sessionID: session.id, providerID: providerID, isGenerating: true)
        await coordinator.useAccount(
            "acct_D",
            providerID: providerID,
            scope: .allCurrentSessions,
            openSessionID: session.id)
        coordinator.unregister(sessionID: session.id)

        #expect(coordinator.managedSessions.isEmpty)
        #expect(coordinator.activeAccountRefs.isEmpty)
        #expect(coordinator.generatingCounts.isEmpty)
        #expect(coordinator.pendingAccountRef(sessionID: session.id) == nil)
    }

    @Test func providerChangeWithoutAnAccountRemovesThePreviousExactAttribution() throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_A",
            runtimeState: .streaming)
        coordinator.register(session)

        session.setProvider("anthropic", accountRef: nil)
        coordinator.update(sessionID: session.id, providerID: "anthropic", isGenerating: true)

        #expect(coordinator.activeAccountRefs[session.id] == nil)
        #expect(coordinator.generatingCounts.isEmpty)
        #expect(coordinator.activeCounts == ["anthropic": 1])
    }

    @Test func queuedRoutesFailSafelyWhenTheSessionProviderChangesOrDisappears() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let changed = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_A",
            runtimeState: .streaming)
        let missing = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_B",
            runtimeState: .streaming)
        coordinator.register(changed)
        coordinator.register(missing)

        await coordinator.useAccount(
            "acct_private",
            providerID: providerID,
            scope: .allCurrentSessions,
            openSessionID: nil)
        changed.setProvider("anthropic", accountRef: nil)
        changed.setGenerating(false)
        coordinator.update(sessionID: changed.id, providerID: "anthropic", isGenerating: false)
        missing.setProvider(nil, accountRef: nil)
        missing.setGenerating(false)
        coordinator.update(sessionID: missing.id, providerID: nil, isGenerating: false)

        await coordinator.sessionDidBecomeIdle(changed.id)
        await coordinator.sessionDidBecomeIdle(missing.id)

        #expect(changed.pins.isEmpty)
        #expect(missing.pins.isEmpty)
        #expect(coordinator.pendingAccountRef(sessionID: changed.id) == nil)
        #expect(coordinator.pendingAccountRef(sessionID: missing.id) == nil)
        #expect(coordinator.failureSummary == "Couldn’t switch 2 sessions.")
        #expect(coordinator.failureSummary?.contains(providerID) == false)
        #expect(coordinator.failureSummary?.contains("acct_private") == false)
    }

    @Test func newerReentrantChoiceWinsAcrossEveryRecordedCurrentSession() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pause = PinPause()
        let first = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_A",
            pinHook: { accountRef in
                if accountRef == "acct_C" { await pause.pause() }
            })
        let second = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_B",
            pinHook: { accountRef in
                if accountRef == "acct_C" { await pause.pause() }
            })
        coordinator.register(first)
        coordinator.register(second)

        let older = Task {
            await coordinator.useAccount(
                "acct_C",
                providerID: providerID,
                scope: .allCurrentSessions,
                openSessionID: nil)
        }
        await pause.waitUntilStarted()
        let newer = Task {
            await coordinator.useAccount(
                "acct_D",
                providerID: providerID,
                scope: .allCurrentSessions,
                openSessionID: nil)
        }
        await Task.yield()
        await pause.release()
        await older.value
        await newer.value

        #expect(first.currentProviderAccountRef == "acct_D")
        #expect(second.currentProviderAccountRef == "acct_D")
        #expect(first.pins.last == "acct_D")
        #expect(second.pins.last == "acct_D")
    }

    @Test func queuedSuccessDoesNotClearAnUnrelatedPartialFailure() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let failing = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_A",
            failingAccountRefs: ["acct_C"])
        let generating = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_B",
            runtimeState: .streaming)
        coordinator.register(failing)
        coordinator.register(generating)

        await coordinator.useAccount(
            "acct_C",
            providerID: providerID,
            scope: .allCurrentSessions,
            openSessionID: nil)
        #expect(coordinator.failureSummary == "Couldn’t switch 1 session.")

        generating.setGenerating(false)
        coordinator.update(sessionID: generating.id, providerID: providerID, isGenerating: false)
        await coordinator.sessionDidBecomeIdle(generating.id)

        #expect(generating.currentProviderAccountRef == "acct_C")
        #expect(coordinator.failureSummary == "Couldn’t switch 1 session.")
    }

    @Test func successfulExplicitOperationClearsThePreviousFailure() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_A",
            failingAccountRefs: ["acct_bad"])
        coordinator.register(session)

        await coordinator.useAccount(
            "acct_bad",
            providerID: providerID,
            scope: .thisSession,
            openSessionID: session.id)
        #expect(coordinator.failureSummary == "Couldn’t switch 1 session.")

        await coordinator.useAccount(
            "acct_B",
            providerID: providerID,
            scope: .thisSession,
            openSessionID: session.id)

        #expect(session.currentProviderAccountRef == "acct_B")
        #expect(coordinator.failureSummary == nil)
    }

    @Test func olderFailureCompletionCannotOverwriteANewerSuccessfulChoice() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pause = PinPause()
        let session = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_A",
            failingAccountRefs: ["acct_bad"],
            pinHook: { accountRef in
                if accountRef == "acct_bad" { await pause.pause() }
            })
        coordinator.register(session)

        let older = Task {
            await coordinator.useAccount(
                "acct_bad",
                providerID: providerID,
                scope: .thisSession,
                openSessionID: session.id)
        }
        await pause.waitUntilStarted()
        let newer = Task {
            await coordinator.useAccount(
                "acct_B",
                providerID: providerID,
                scope: .thisSession,
                openSessionID: session.id)
        }
        await pause.release()
        await older.value
        await newer.value

        #expect(session.currentProviderAccountRef == "acct_B")
        #expect(coordinator.failureSummary == nil)
    }

    @Test func allNewSessionsSuccessClearsThePreviousFailure() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_A",
            failingAccountRefs: ["acct_bad"])
        coordinator.register(session)
        await coordinator.useAccount(
            "acct_bad",
            providerID: providerID,
            scope: .thisSession,
            openSessionID: session.id)
        #expect(coordinator.failureSummary == "Couldn’t switch 1 session.")

        await coordinator.useAccount(
            "acct_primary",
            providerID: providerID,
            scope: .allNewSessions,
            openSessionID: nil)

        #expect(coordinator.primaryAccountRef(providerID: providerID) == "acct_primary")
        #expect(coordinator.failureSummary == nil)
    }

    private func accountEvent(ref: String, sequence: Int) -> ProviderAccountChangedEvent {
        ProviderAccountChangedEvent(
            providerID: providerID,
            accountRef: ref,
            reason: .automaticFailover,
            sequence: sequence)
    }
}

@MainActor
private final class FakeProviderAccountSession: ProviderAccountSession {
    let id = UUID()
    var providerID: String?
    var runtimeState: SessionRuntimeState
    private(set) var currentProviderAccountRef: String?
    private(set) var providerAccountSequence: Int
    private(set) var pins: [String] = []
    private let failingAccountRefs: Set<String>
    private let pinHook: @MainActor (String) async -> Void

    init(
        providerID: String?,
        accountRef: String?,
        sequence: Int = 0,
        runtimeState: SessionRuntimeState = .idle,
        failingAccountRefs: Set<String> = [],
        pinHook: @escaping @MainActor (String) async -> Void = { _ in }
    ) {
        self.providerID = providerID
        currentProviderAccountRef = accountRef
        providerAccountSequence = sequence
        self.runtimeState = runtimeState
        self.failingAccountRefs = failingAccountRefs
        self.pinHook = pinHook
    }

    func setGenerating(_ isGenerating: Bool) {
        runtimeState = isGenerating ? .streaming : .idle
    }

    func setProvider(_ providerID: String?, accountRef: String?) {
        self.providerID = providerID
        currentProviderAccountRef = accountRef
    }

    func setProviderAccount(
        providerID: String,
        accountRef: String
    ) async throws -> SetSessionProviderAccountResult {
        await pinHook(accountRef)
        if failingAccountRefs.contains(accountRef) {
            throw FakeProviderAccountError.failed("credential acct_secret should stay private")
        }
        pins.append(accountRef)
        providerAccountSequence += 1
        currentProviderAccountRef = accountRef
        return SetSessionProviderAccountResult(
            account: ProviderAccountSummary(
                providerID: providerID,
                accountRef: accountRef,
                displayLabel: "Account",
                connectionOrder: 0,
                availability: .available,
                isActiveForSession: true),
            sequence: providerAccountSequence)
    }
}

private actor PinPause {
    private var isReleased = false
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        didStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private enum FakeProviderAccountError: Error {
    case failed(String)
}

@MainActor
private func makeCoordinator() throws -> (
    coordinator: ProviderAccountCoordinator,
    defaults: UserDefaults,
    suiteName: String
) {
    let suiteName = "TenXAppTests.ProviderAccountCoordinator.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return (
        ProviderAccountCoordinator(
            primaryStore: ProviderPrimaryPreferenceStore(defaults: defaults)),
        defaults,
        suiteName)
}

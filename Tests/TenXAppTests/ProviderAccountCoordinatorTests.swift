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

    init(
        providerID: String?,
        accountRef: String?,
        sequence: Int = 0,
        runtimeState: SessionRuntimeState = .idle,
        failingAccountRefs: Set<String> = []
    ) {
        self.providerID = providerID
        currentProviderAccountRef = accountRef
        providerAccountSequence = sequence
        self.runtimeState = runtimeState
        self.failingAccountRefs = failingAccountRefs
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

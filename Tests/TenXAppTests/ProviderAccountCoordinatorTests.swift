import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Suite @MainActor struct ProviderAccountCoordinatorTests {
    private let providerID = "openai-codex"

    @Test func scopeAvailabilityTracksManagedAndOpenSessionsForTheProvider() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(coordinator.scopeAvailability(
            providerID: providerID,
            openSessionID: nil) == .newSessionsOnly)

        let session = FakeProviderAccountSession(providerID: providerID, accountRef: "acct_A")
        coordinator.register(session)

        #expect(coordinator.scopeAvailability(
            providerID: providerID,
            openSessionID: nil) == ProviderAccountScopeAvailability(
                isThisSessionAvailable: false,
                areAllCurrentSessionsAvailable: true))
        #expect(coordinator.scopeAvailability(
            providerID: providerID,
            openSessionID: session.id) == .all)
        #expect(coordinator.scopeAvailability(
            providerID: "anthropic",
            openSessionID: session.id) == .newSessionsOnly)
    }

    @Test func hasPendingWorkTracksManagedTurnsForASession() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = FakeProviderAccountSession(providerID: providerID, accountRef: "acct_A")
        coordinator.register(session)

        #expect(!coordinator.hasPendingWork(sessionID: session.id))
        #expect(coordinator.beginManagedTurn(sessionID: session.id))
        #expect(coordinator.hasPendingWork(sessionID: session.id))
        coordinator.endManagedTurn(sessionID: session.id)
        #expect(!coordinator.hasPendingWork(sessionID: session.id))

        coordinator.unregister(sessionID: session.id)
        #expect(!coordinator.hasPendingWork(sessionID: session.id))
    }

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

    @Test func automaticFailoverChangesOnlyTheAffectedSessionAndKeepsThePrimary() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let affected = FakeProviderAccountSession(providerID: providerID, accountRef: "acct_A")
        let unrelated = FakeProviderAccountSession(providerID: providerID, accountRef: "acct_A")
        coordinator.register(affected)
        coordinator.register(unrelated)
        await coordinator.useAccount(
            "acct_A",
            providerID: providerID,
            scope: .allNewSessions,
            openSessionID: nil)

        coordinator.session(
            affected.id,
            didChangeAccount: accountEvent(ref: "acct_B", sequence: 1))

        #expect(coordinator.activeAccountRefs[affected.id] == "acct_B")
        #expect(coordinator.activeAccountRefs[unrelated.id] == "acct_A")
        #expect(coordinator.primaryAccountRef(providerID: providerID) == "acct_A")
        #expect(affected.pins.isEmpty)
        #expect(unrelated.pins.isEmpty)
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

    @Test func preparingFirstPromptWaitsThroughANewerCurrentSessionRoute() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        await coordinator.useAccount(
            "acct_A",
            providerID: providerID,
            scope: .allNewSessions,
            openSessionID: nil)
        let creationSnapshot = coordinator.newSessionPrimarySnapshot()
        let pause = PinPause()
        let session = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: nil,
            pinHook: { accountRef in
                if accountRef == "acct_A" { await pause.pause() }
            })
        coordinator.register(session)

        let preparation = Task {
            await coordinator.prepareForFirstPrompt(
                sessionID: session.id,
                primarySnapshot: creationSnapshot)
        }
        await pause.waitUntilStarted()
        let newerRoute = Task {
            await coordinator.useAccount(
                "acct_B",
                providerID: providerID,
                scope: .allCurrentSessions,
                openSessionID: nil)
        }
        await pause.release()
        await preparation.value

        #expect(session.currentProviderAccountRef == "acct_B")
        #expect(session.pins.last == "acct_B")
        await newerRoute.value
    }

    @Test func creationSnapshotKeepsItsPrimaryWhenTheNewSessionPreferenceChanges() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        await coordinator.useAccount(
            "acct_A",
            providerID: providerID,
            scope: .allNewSessions,
            openSessionID: nil)
        let creationSnapshot = coordinator.newSessionPrimarySnapshot()
        await coordinator.useAccount(
            "acct_B",
            providerID: providerID,
            scope: .allNewSessions,
            openSessionID: nil)
        let session = FakeProviderAccountSession(providerID: providerID, accountRef: nil)
        coordinator.register(session)

        await coordinator.prepareForFirstPrompt(
            sessionID: session.id,
            primarySnapshot: creationSnapshot)

        #expect(session.pins == ["acct_A"])
        #expect(coordinator.primaryAccountRef(providerID: providerID) == "acct_B")
    }

    @Test func completedRouteNewerThanCreationSnapshotIsNotReplacedByThePrimary() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        await coordinator.useAccount(
            "acct_A",
            providerID: providerID,
            scope: .allNewSessions,
            openSessionID: nil)
        let creationSnapshot = coordinator.newSessionPrimarySnapshot()
        let session = FakeProviderAccountSession(providerID: providerID, accountRef: nil)
        coordinator.register(session)
        await coordinator.useAccount(
            "acct_B",
            providerID: providerID,
            scope: .allCurrentSessions,
            openSessionID: nil)

        await coordinator.prepareForFirstPrompt(
            sessionID: session.id,
            primarySnapshot: creationSnapshot)

        #expect(session.pins == ["acct_B"])
        #expect(session.currentProviderAccountRef == "acct_B")
    }

    @Test func inFlightFailedRouteNewerThanCreationFallsBackToCapturedPrimary() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        await coordinator.useAccount(
            "acct_A",
            providerID: providerID,
            scope: .allNewSessions,
            openSessionID: nil)
        let creationSnapshot = coordinator.newSessionPrimarySnapshot()
        let pause = PinPause()
        let session = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: nil,
            failingAccountRefs: ["acct_B"],
            pinHook: { accountRef in
                if accountRef == "acct_B" { await pause.pause() }
            })
        coordinator.register(session)
        let newerRoute = Task {
            await coordinator.useAccount(
                "acct_B",
                providerID: providerID,
                scope: .allCurrentSessions,
                openSessionID: nil)
        }
        await pause.waitUntilStarted()

        let preparation = Task {
            await coordinator.prepareForFirstPrompt(
                sessionID: session.id,
                primarySnapshot: creationSnapshot)
        }
        await pause.release()
        await preparation.value
        await newerRoute.value

        #expect(session.pins == ["acct_A"])
        #expect(session.currentProviderAccountRef == "acct_A")
        #expect(coordinator.failureSummary == "Couldn’t switch 1 session.")
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

    @Test func nonLastRemovalWithoutAnEligibleReplacementIsRejectedBeforeMutation() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        await coordinator.useAccount(
            "acct_A",
            providerID: providerID,
            scope: .allNewSessions,
            openSessionID: nil)
        let unavailable = providerAccountFixture(
            providerID: providerID,
            ref: "acct_B",
            label: "Unavailable",
            order: 1,
            availability: .unavailable)
        var removeCalls = 0

        do {
            _ = try await coordinator.removeAccount(
                providerID: providerID,
                accountRef: "acct_A",
                accounts: [removalAccounts[0], unavailable]
            ) {
                removeCalls += 1
                return ProviderAccountRemovalResult(removed: true, accounts: [unavailable])
            }
            Issue.record("Expected no eligible replacement error")
        } catch ProviderAccountRemovalError.noEligibleReplacement {
        } catch {
            Issue.record("Unexpected removal error: \(error)")
        }

        #expect(removeCalls == 0)
        #expect(coordinator.primaryAccountRef(providerID: providerID) == "acct_A")
        #expect(coordinator.pendingRemovalAccounts.isEmpty)
    }

    @Test func removalBarrierWaitsForProviderFailoverAndRepinsBeforeExactRemoval() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_B",
            runtimeState: .streaming)
        coordinator.register(session)
        let rpcGate = PinPause()
        var removeCalls = 0
        let removal = Task {
            try await coordinator.removeAccount(
                providerID: providerID,
                accountRef: "acct_A",
                accounts: removalAccounts
            ) {
                removeCalls += 1
                await rpcGate.pause()
                #expect(session.currentProviderAccountRef == "acct_B")
                return ProviderAccountRemovalResult(removed: true, accounts: [self.removalAccounts[1]])
            }
        }
        await waitForCoordinatorCondition { !coordinator.pendingRemovalAccounts.isEmpty }

        #expect(removeCalls == 0)
        session.setProvider(providerID, accountRef: "acct_A")
        coordinator.session(session.id, didChangeAccount: accountEvent(ref: "acct_A", sequence: 1))
        session.setGenerating(false)
        coordinator.update(sessionID: session.id, providerID: providerID, isGenerating: false)
        await coordinator.sessionDidBecomeIdle(session.id)
        await rpcGate.waitUntilStarted()
        #expect(session.pins == ["acct_B"])
        await rpcGate.release()
        _ = try await removal.value

        #expect(removeCalls == 1)
        #expect(session.currentProviderAccountRef == "acct_B")
    }

    @Test func removalBarrierRejectsNewTurnsAndRegistrationsUntilTheRPCFinishes() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = FakeProviderAccountSession(providerID: providerID, accountRef: "acct_B")
        #expect(coordinator.register(session))
        #expect(coordinator.beginManagedTurn(sessionID: session.id))
        let rpcGate = PinPause()
        var removeCalls = 0
        let removal = Task {
            try await coordinator.removeAccount(
                providerID: providerID,
                accountRef: "acct_A",
                accounts: removalAccounts
            ) {
                removeCalls += 1
                await rpcGate.pause()
                return ProviderAccountRemovalResult(removed: true, accounts: [self.removalAccounts[1]])
            }
        }
        await waitForCoordinatorCondition { !coordinator.pendingRemovalAccounts.isEmpty }

        #expect(removeCalls == 0)
        #expect(!coordinator.canCreateManagedSession)
        coordinator.endManagedTurn(sessionID: session.id)
        await rpcGate.waitUntilStarted()

        let late = FakeProviderAccountSession(providerID: providerID, accountRef: "acct_A")
        #expect(!coordinator.beginManagedTurn(sessionID: session.id))
        #expect(!coordinator.register(late))
        #expect(coordinator.managedSessions[late.id] == nil)

        await rpcGate.release()
        _ = try await removal.value
        #expect(coordinator.canCreateManagedSession)
    }

    @Test func removalBarrierWaitsForAPreRegisteredLoadingSessionToResolveAndRepin() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = FakeProviderAccountSession(
            providerID: nil,
            accountRef: nil,
            runtimeState: .loading)
        coordinator.register(session)
        var removeCalls = 0
        let removal = Task {
            try await coordinator.removeAccount(
                providerID: providerID,
                accountRef: "acct_A",
                accounts: removalAccounts
            ) {
                removeCalls += 1
                #expect(session.currentProviderAccountRef == "acct_B")
                return ProviderAccountRemovalResult(removed: true, accounts: [self.removalAccounts[1]])
            }
        }
        await waitForCoordinatorCondition { !coordinator.pendingRemovalAccounts.isEmpty }

        #expect(removeCalls == 0)
        session.setProvider(providerID, accountRef: "acct_A")
        session.setGenerating(false)
        coordinator.update(sessionID: session.id, providerID: providerID, isGenerating: false)
        await coordinator.sessionDidBecomeIdle(session.id)
        _ = try await removal.value

        #expect(session.pins == ["acct_B"])
        #expect(removeCalls == 1)
    }

    @Test func removingThePrimaryPersistsItsReplacementBeforeIdleSessionsMove() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        await coordinator.useAccount(
            "acct_A",
            providerID: providerID,
            scope: .allNewSessions,
            openSessionID: nil)
        var primaryObservedDuringPin: String?
        let session = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_A",
            pinHook: { _ in
                primaryObservedDuringPin = coordinator.primaryAccountRef(providerID: self.providerID)
            })
        coordinator.register(session)
        var removeCalls = 0

        let result = try await coordinator.removeAccount(
            providerID: providerID,
            accountRef: "acct_A",
            accounts: removalAccounts
        ) {
            removeCalls += 1
            #expect(session.currentProviderAccountRef == "acct_B")
            return ProviderAccountRemovalResult(removed: true, accounts: [self.removalAccounts[1]])
        }

        #expect(result.removed)
        #expect(primaryObservedDuringPin == "acct_B")
        #expect(coordinator.primaryAccountRef(providerID: providerID) == "acct_B")
        #expect(session.pins == ["acct_B"])
        #expect(removeCalls == 1)
    }

    @Test func primaryRepairPreservesConnectionsOrderWhenAccountOrdersMatch() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        await coordinator.useAccount(
            "acct_primary",
            providerID: providerID,
            scope: .allNewSessions,
            openSessionID: nil)
        let target = providerAccountFixture(
            providerID: providerID,
            ref: "acct_primary",
            label: "Primary",
            order: 0)
        let firstRemaining = providerAccountFixture(
            providerID: providerID,
            ref: "acct_Z",
            label: "First remaining",
            order: 1)
        let secondRemaining = providerAccountFixture(
            providerID: providerID,
            ref: "acct_A",
            label: "Second remaining",
            order: 1)

        _ = try await coordinator.removeAccount(
            providerID: providerID,
            accountRef: target.accountRef,
            accounts: [target, firstRemaining, secondRemaining]
        ) {
            #expect(coordinator.primaryAccountRef(providerID: self.providerID) == "acct_Z")
            return ProviderAccountRemovalResult(
                removed: true,
                accounts: [firstRemaining, secondRemaining])
        }

        #expect(coordinator.primaryAccountRef(providerID: providerID) == "acct_Z")
    }

    @Test func generatingRemovalQueuesAReplacementAndAwaitsTheTurn() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_A",
            runtimeState: .streaming)
        coordinator.register(session)
        var removeCalls = 0
        let removal = Task {
            try await coordinator.removeAccount(
                providerID: providerID,
                accountRef: "acct_A",
                accounts: removalAccounts
            ) {
                removeCalls += 1
                #expect(session.runtimeState == .idle)
                #expect(session.currentProviderAccountRef == "acct_B")
                #expect(coordinator.pendingAccountRef(sessionID: session.id) == nil)
                return ProviderAccountRemovalResult(removed: true, accounts: [self.removalAccounts[1]])
            }
        }
        await waitForCoordinatorCondition {
            coordinator.pendingAccountRef(sessionID: session.id) == "acct_B"
        }

        #expect(removeCalls == 0)
        #expect(session.pins.isEmpty)

        session.setGenerating(false)
        coordinator.update(sessionID: session.id, providerID: providerID, isGenerating: false)
        await coordinator.sessionDidBecomeIdle(session.id)
        _ = try await removal.value

        #expect(session.pins == ["acct_B"])
        #expect(removeCalls == 1)
    }

    @Test func removalRejectsNewSwitchesToItsTargetAndCancelsAnExistingTargetQueue() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_B",
            runtimeState: .streaming)
        coordinator.register(session)
        await coordinator.useAccount(
            "acct_A",
            providerID: providerID,
            scope: .thisSession,
            openSessionID: session.id)
        #expect(coordinator.pendingAccountRef(sessionID: session.id) == "acct_A")
        let gate = PinPause()
        let removal = Task {
            try await coordinator.removeAccount(
                providerID: providerID,
                accountRef: "acct_A",
                accounts: removalAccounts
            ) {
                #expect(coordinator.pendingAccountRef(sessionID: session.id) == nil)
                await gate.pause()
                return ProviderAccountRemovalResult(removed: true, accounts: [self.removalAccounts[1]])
            }
        }
        await waitForCoordinatorCondition { !coordinator.pendingRemovalAccounts.isEmpty }

        await coordinator.useAccount(
            "acct_A",
            providerID: providerID,
            scope: .thisSession,
            openSessionID: session.id)

        #expect(coordinator.pendingRemovalAccounts == [
            ProviderAccountKey(providerID: providerID, accountRef: "acct_A"),
        ])
        #expect(coordinator.pendingAccountRef(sessionID: session.id) == nil)
        #expect(session.pins.isEmpty)
        #expect(coordinator.failureSummary == "Account is no longer available.")
        session.setGenerating(false)
        coordinator.update(sessionID: session.id, providerID: providerID, isGenerating: false)
        await coordinator.sessionDidBecomeIdle(session.id)
        await gate.waitUntilStarted()
        await gate.release()
        _ = try await removal.value
    }

    @Test func removalAwaitsAnInFlightSwitchToItsTargetBeforeExactRemoval() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pinGate = PinPause()
        let session = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_B",
            pinHook: { accountRef in
                if accountRef == "acct_A" {
                    await pinGate.pause()
                }
            })
        coordinator.register(session)
        let switchToTarget = Task {
            await coordinator.useAccount(
                "acct_A",
                providerID: providerID,
                scope: .thisSession,
                openSessionID: session.id)
        }
        await pinGate.waitUntilStarted()
        var removeCalls = 0
        let removal = Task {
            try await coordinator.removeAccount(
                providerID: providerID,
                accountRef: "acct_A",
                accounts: removalAccounts
            ) {
                removeCalls += 1
                #expect(session.currentProviderAccountRef == "acct_B")
                return ProviderAccountRemovalResult(removed: true, accounts: [self.removalAccounts[1]])
            }
        }
        await waitForCoordinatorCondition { !coordinator.pendingRemovalAccounts.isEmpty }

        #expect(removeCalls == 0)
        await pinGate.release()
        await switchToTarget.value
        _ = try await removal.value

        #expect(session.pins == ["acct_A", "acct_B"])
        #expect(removeCalls == 1)
    }

    @Test func removalAwaitsAnExistingManualQueueAwayFromTheTarget() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_A",
            runtimeState: .streaming)
        coordinator.register(session)
        await coordinator.useAccount(
            "acct_C",
            providerID: providerID,
            scope: .thisSession,
            openSessionID: session.id)
        var removeCalls = 0
        let removal = Task {
            try await coordinator.removeAccount(
                providerID: providerID,
                accountRef: "acct_A",
                accounts: removalAccounts + [providerAccountFixture(
                    providerID: providerID,
                    ref: "acct_C",
                    label: "Manual",
                    order: 2)]
            ) {
                removeCalls += 1
                #expect(session.currentProviderAccountRef == "acct_C")
                #expect(coordinator.pendingAccountRef(sessionID: session.id) == nil)
                return ProviderAccountRemovalResult(removed: true, accounts: [])
            }
        }
        await Task.yield()

        #expect(removeCalls == 0)
        #expect(coordinator.pendingAccountRef(sessionID: session.id) == "acct_C")

        session.setGenerating(false)
        coordinator.update(sessionID: session.id, providerID: providerID, isGenerating: false)
        await coordinator.sessionDidBecomeIdle(session.id)
        _ = try await removal.value

        #expect(session.pins == ["acct_C"])
        #expect(removeCalls == 1)
    }

    @Test func removingTheLastAccountAwaitsGeneratingButDoesNotRepin() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        await coordinator.useAccount(
            "acct_A",
            providerID: providerID,
            scope: .allNewSessions,
            openSessionID: nil)
        let onlyAccount = removalAccounts[0]
        let session = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_A",
            runtimeState: .streaming)
        coordinator.register(session)
        var removeCalls = 0
        let removal = Task {
            try await coordinator.removeAccount(
                providerID: providerID,
                accountRef: "acct_A",
                accounts: [onlyAccount]
            ) {
                removeCalls += 1
                #expect(session.runtimeState == .idle)
                return ProviderAccountRemovalResult(removed: true, accounts: [])
            }
        }
        await waitForCoordinatorCondition { !coordinator.pendingRemovalAccounts.isEmpty }

        #expect(removeCalls == 0)
        #expect(session.pins.isEmpty)
        #expect(coordinator.primaryAccountRef(providerID: providerID) == nil)

        session.setGenerating(false)
        coordinator.update(sessionID: session.id, providerID: providerID, isGenerating: false)
        await coordinator.sessionDidBecomeIdle(session.id)
        _ = try await removal.value

        #expect(removeCalls == 1)
        #expect(session.pins.isEmpty)
    }

    @Test func partialRepinFailurePreventsExactRemoval() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        await coordinator.useAccount(
            "acct_A",
            providerID: providerID,
            scope: .allNewSessions,
            openSessionID: nil)
        let failing = FakeProviderAccountSession(
            providerID: providerID,
            accountRef: "acct_A",
            failingAccountRefs: ["acct_B"])
        let succeeding = FakeProviderAccountSession(providerID: providerID, accountRef: "acct_A")
        coordinator.register(failing)
        coordinator.register(succeeding)
        var removeCalls = 0

        do {
            _ = try await coordinator.removeAccount(
                providerID: providerID,
                accountRef: "acct_A",
                accounts: removalAccounts
            ) {
                removeCalls += 1
                return ProviderAccountRemovalResult(removed: true, accounts: [])
            }
            Issue.record("Expected reassignment failure")
        } catch ProviderAccountRemovalError.reassignmentFailed(let count) {
            #expect(count == 1)
        } catch {
            Issue.record("Unexpected removal error: \(error)")
        }

        #expect(failing.currentProviderAccountRef == "acct_A")
        #expect(succeeding.currentProviderAccountRef == "acct_A")
        #expect(succeeding.pins == ["acct_B", "acct_A"])
        #expect(coordinator.primaryAccountRef(providerID: providerID) == "acct_A")
        #expect(removeCalls == 0)
        #expect(coordinator.pendingRemovalAccounts.isEmpty)
    }

    @Test func removalRPCFailureRestoresPrimaryAndSessionsAlreadyRepinned() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        await coordinator.useAccount(
            "acct_A",
            providerID: providerID,
            scope: .allNewSessions,
            openSessionID: nil)
        let session = FakeProviderAccountSession(providerID: providerID, accountRef: "acct_A")
        coordinator.register(session)

        do {
            _ = try await coordinator.removeAccount(
                providerID: providerID,
                accountRef: "acct_A",
                accounts: removalAccounts
            ) {
                throw FakeProviderAccountError.removalFailed
            }
            Issue.record("Expected removal RPC failure")
        } catch FakeProviderAccountError.removalFailed {
        } catch {
            Issue.record("Unexpected removal error: \(error)")
        }

        #expect(session.currentProviderAccountRef == "acct_A")
        #expect(session.pins == ["acct_B", "acct_A"])
        #expect(coordinator.primaryAccountRef(providerID: providerID) == "acct_A")
        #expect(coordinator.pendingRemovalAccounts.isEmpty)
    }

    private var removalAccounts: [ProviderAccountSummary] {
        [
            providerAccountFixture(
                providerID: providerID,
                ref: "acct_A",
                label: "Primary",
                order: 0),
            providerAccountFixture(
                providerID: providerID,
                ref: "acct_B",
                label: "Replacement",
                order: 1),
        ]
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
private func waitForCoordinatorCondition(
    _ predicate: @escaping @MainActor () -> Bool
) async {
    for _ in 0..<100 where !predicate() {
        await Task.yield()
    }
    #expect(predicate())
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
    case removalFailed
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

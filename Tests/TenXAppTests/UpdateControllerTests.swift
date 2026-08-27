import Foundation
import Testing
@testable import TenXApp

@MainActor
final class StubUpdateChecker: UpdateChecking {
    let state = UpdateState()
    private(set) var checkCount = 0
    private(set) var lastCheckWasUserInitiated: Bool?
    var onCheck: (@MainActor (UpdateState) -> Void)?

    private(set) var cancelCount = 0

    func check(isUserInitiated: Bool) {
        checkCount += 1
        lastCheckWasUserInitiated = isUserInitiated
        state.beginCheck()
        onCheck?(state)
    }

    func cancelCheck() {
        cancelCount += 1
        state.reset()
    }

    func accept() {}
    func dismiss() { state.reset() }
}

/// A `StubUpdateChecker` pre-configured to answer "nothing new" the instant it is
/// asked, matching what the real driver reports when the feed has nothing newer.
/// Fixtures that don't care about update behavior use this as their default checker
/// rather than a bare `StubUpdateChecker()`: a bare stub leaves `state.phase` at
/// `.checking`, so `checkAtLaunch` spawns its deadline task and depends on whatever
/// `sleep` closure the fixture's `StartupTiming` happens to use for unrelated
/// purposes — some of which ignore the duration they're given and sleep for real
/// seconds. Answering synchronously lets `checkAtLaunch` return through its
/// `guard case .checking` before the deadline task is ever spawned.
@MainActor
func stubUpdateCheckerReportingNoUpdate() -> StubUpdateChecker {
    let checker = StubUpdateChecker()
    checker.onCheck = { $0.reset() }
    return checker
}

@MainActor
@Test func theLaunchCheckReturnsAsSoonAsSparkleAnswers() async {
    let checker = StubUpdateChecker()
    checker.onCheck = { $0.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0") }

    await checker.checkAtLaunch(deadline: .seconds(3), sleep: { _ in
        Issue.record("The deadline must not be awaited once the check has answered")
    })

    #expect(checker.checkCount == 1)
    #expect(checker.lastCheckWasUserInitiated == false)
    #expect(checker.cancelCount == 0)
    #expect(checker.state.isAwaitingDecision)
}

@MainActor
@Test func theLaunchCheckGivesUpAtTheDeadlineWithoutFailing() async {
    let checker = StubUpdateChecker()

    await checker.checkAtLaunch(deadline: .milliseconds(1), sleep: { _ in })

    #expect(checker.cancelCount == 1)
    #expect(checker.state.phase == .idle)
    #expect(!checker.state.isPresentingUpdate)
}

/// Closes a review finding on `SplashUpdateDriver.isUserInitiated`: it is mutable,
/// long-lived state with no internal reset. If a menu-initiated check left it `true`,
/// a later launch-time check that errored would surface a visible `Update failed` on a
/// cold launch, which the advisory launch gate forbids. `UpdateController.check(isUserInitiated:)`
/// closes this by assigning the flag at the top of every check path, so a launch check
/// that follows a menu check is never mistaken for user-initiated.
@MainActor
@Test func aLaunchCheckAfterAMenuCheckIsNotTreatedAsUserInitiated() {
    let controller = UpdateController(prepareForInstall: {})

    controller.check(isUserInitiated: true)
    #expect(controller.isUserInitiatedForTesting)

    controller.check(isUserInitiated: false)
    #expect(!controller.isUserInitiatedForTesting)
}

/// Invariant I5: `state.phase` must become `.checking` synchronously, before
/// `checkAtLaunch` ever awaits anything. `SPUUpdater.checkForUpdates()` does not call
/// back into the user driver synchronously (confirmed by reading `SPUUpdater.m`) — it
/// hops through an install-status probe and back onto the main queue first. If nothing
/// set the phase until that callback landed, the launch gate could observe `.idle`
/// immediately after `check()` returned, treat "hasn't started yet" as "already
/// finished," and return with the real check still silently in flight.
/// `UpdateController.check(isUserInitiated:)` closes this by calling `state.beginCheck()`
/// itself, before asking Sparkle to check at all.
@MainActor
@Test func checkingBeginsSynchronouslyBeforeSparkleIsAskedToCheck() {
    let controller = UpdateController(prepareForInstall: {})

    controller.check(isUserInitiated: false)

    #expect(controller.state.phase == .checking)
}

/// Invariant I4: a deadline that elapses after the check has already answered must not
/// touch state. `cancelCheck()` calls `state.reset()`, so firing it late would silently
/// wipe a legitimate `.available` offer off the splash. This drives the deadline task
/// past its `sleep` and into its phase guard only after the real answer has already
/// landed, proving the guard — not merely the task's own cancellation flag — is what
/// protects the offer.
@MainActor
@Test func aDeadlineThatElapsesAfterTheAnswerLeavesTheOfferUntouched() async {
    let checker = StubUpdateChecker()

    // Rather than racing two independently-scheduled tasks against each other (which
    // proved to be a genuine, unpredictable scheduling race — not merely a slow test —
    // when tried), the answer is applied synchronously from inside the `sleep`
    // closure itself. This deterministically reproduces "the real answer already
    // landed by the time the deadline task wakes up and checks state," which is the
    // condition the guard exists to handle, without depending on which of two
    // continuations a scheduler happens to run first.
    await checker.checkAtLaunch(deadline: .seconds(1), sleep: { @MainActor _ in
        checker.state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")
    })

    #expect(checker.cancelCount == 0)
    #expect(checker.state.phase == .available(newVersion: "0.2.0", currentVersion: "0.1.0"))
}

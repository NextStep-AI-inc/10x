import Foundation
import Sparkle

@MainActor
protocol UpdateChecking: AnyObject {
    var state: UpdateState { get }
    func check(isUserInitiated: Bool)
    func cancelCheck()
    func accept()
    func dismiss()
}

extension UpdateChecking {
    /// Runs the advisory launch check. Returns when the check answers or when `deadline`
    /// elapses, whichever comes first. It never throws, never fails, and never reports a
    /// problem to the user, because a launch must not depend on network health.
    ///
    /// The deadline runs as an independent, unstructured task rather than inside a
    /// `TaskGroup`. A `TaskGroup` implicitly awaits every child before returning, and
    /// `UpdateState`'s wait is not cancellation-aware — pairing the two would deadlock
    /// whenever the deadline elapsed first, because nothing would be left to resume the
    /// still-suspended waiter. An unstructured task has no such join: this function's
    /// own progress depends only on `state.waitForCheckOutcome()`, and the deadline task
    /// either resolves that wait itself (by cancelling the check) or is discarded once
    /// the real answer already resolved it.
    ///
    /// The deadline task re-checks `state.phase` before cancelling: if the real answer
    /// already landed by the time the deadline fires, cancelling would call
    /// `cancelCheck()` → `state.reset()` and silently wipe a legitimate offer off the
    /// splash. Guarding on the phase (not just on the task's own cancellation flag)
    /// closes that window even if the deadline and the real answer land at nearly the
    /// same instant.
    func checkAtLaunch(
        deadline: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) async {
        check(isUserInitiated: false)
        // If the check already answered synchronously inside `check()` (as a test
        // double may), skip the deadline task entirely rather than spawning it and
        // relying on cancellation to stop it in time — a debug-build async call can
        // still interleave a queued task's body before a synchronous caller reaches
        // its next line, so a spawn-then-cancel race is not a reliable guarantee.
        guard case .checking = state.phase else { return }
        let deadlineTask = Task { @MainActor in
            try? await sleep(deadline)
            guard !Task.isCancelled, case .checking = state.phase else { return }
            cancelCheck()
        }
        await state.waitForCheckOutcome()
        deadlineTask.cancel()
    }
}

@MainActor
final class UpdateController: UpdateChecking {
    let state: UpdateState
    private let updater: SPUUpdater
    private let driver: SplashUpdateDriver

    init(
        state: UpdateState = UpdateState(),
        currentVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        prepareForInstall: @escaping @MainActor () async -> Void
    ) {
        self.state = state
        let driver = SplashUpdateDriver(
            state: state,
            currentVersion: currentVersion,
            prepareForInstall: prepareForInstall)
        self.driver = driver
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: driver,
            delegate: nil)
    }

    /// Must be called once before any check. A failure here means the bundle is missing
    /// its feed or key, which is a build defect rather than a user-facing condition.
    func start() {
        do {
            try updater.start()
        } catch {
            state.fail(.unknown)
        }
    }

    /// Both paths use `checkForUpdates()` rather than `checkForUpdatesInBackground()`.
    /// The background variant is governed by Sparkle's own scheduling permission, which
    /// `SUEnableAutomaticChecks = NO` disables, so it would silently do nothing.
    ///
    /// `state.beginCheck()` runs here, synchronously, rather than being left to the
    /// driver's `showUserInitiatedUpdateCheck` callback. `SPUUpdater.checkForUpdates()`
    /// does not reach the user driver synchronously — it hops through an install-status
    /// probe and back onto the main queue before Sparkle calls back into `driver`. If
    /// the launch gate relied on that callback alone, `waitForCheckOutcome()` could see
    /// `state.phase` still `.idle` immediately after this call returns, treat "hasn't
    /// started yet" as "already finished," and return with the check still silently in
    /// flight — exactly the abandoned-check hazard `cancelCheck()` exists to prevent.
    /// The driver's own later `beginCheck()` call is harmless: `waitForCheckOutcome`
    /// loops on `while case .checking`, so a redundant transition re-suspends instead
    /// of escaping.
    func check(isUserInitiated: Bool) {
        driver.isUserInitiated = isUserInitiated
        state.beginCheck()
        updater.checkForUpdates()
    }

    func cancelCheck() { driver.cancelCheck() }

    func accept() { driver.acceptUpdate() }

    func dismiss() { driver.dismissUpdate() }

    /// Read-only test hook exposing the flag `check(isUserInitiated:)` sets on the
    /// driver. Production code never reads this; it exists so a test can prove a menu
    /// check followed by a launch check leaves the flag `false` for the launch check.
    var isUserInitiatedForTesting: Bool { driver.isUserInitiated }
}

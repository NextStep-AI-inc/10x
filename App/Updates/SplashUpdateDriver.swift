import Foundation
import Sparkle

@MainActor
final class SplashUpdateDriver: NSObject, SPUUserDriver {
    /// Set before each check. Controls whether an up-to-date result is shown or stays silent.
    var isUserInitiated = false

    private let state: UpdateState
    private let currentVersion: String
    private let prepareForInstall: @MainActor () async -> Void
    private var decision: CheckedContinuation<SPUUserUpdateChoice, Never>?
    private var checkCancellation: (() -> Void)?

    /// Set by `cancelCheck()`, cleared by the next `beginCheck(isUserInitiated:)`.
    /// Sparkle's own cancellation handler stops being able to abort a check the moment
    /// the appcast finishes loading, so this is what actually refuses a late offer.
    /// See `cancelCheck()`.
    private var isAbandoned = false

    /// Guards `showDownloadDidReceiveExpectedContentLength` against Sparkle invoking it
    /// more than once for the same download (for example across a redirect). Only the
    /// first value is applied; see that method for why.
    private var hasReceivedExpectedContentLength = false

    init(
        state: UpdateState,
        currentVersion: String,
        prepareForInstall: @escaping @MainActor () async -> Void
    ) {
        self.state = state
        self.currentVersion = currentVersion
        self.prepareForInstall = prepareForInstall
        super.init()
    }

    // MARK: Splash actions

    func acceptUpdate() { resume(.install) }

    /// `Not now` / `Close` dismisses this check. It deliberately does not use `.skip`,
    /// which would make Sparkle refuse to offer this version ever again.
    ///
    /// When a Sparkle decision is pending, resuming it is the whole job: Sparkle then
    /// tears the session down and calls `dismissUpdateInstallation`, which clears the
    /// offer. When none is pending the splash owns the phase outright, and nothing else
    /// will ever clear it — a `.failed` from the menu watchdog, or an `.upToDate` result
    /// whose acknowledgement Sparkle already consumed. Without this the `Close` and
    /// `Not now` buttons on those screens did nothing at all.
    func dismissUpdate() {
        guard resume(.dismiss) else {
            state.reset()
            return
        }
    }

    /// Clears the per-check flags. Called by `UpdateController.check(isUserInitiated:)`
    /// before Sparkle is asked to check, so a check that follows an abandoned one is not
    /// itself treated as abandoned.
    func beginCheck(isUserInitiated: Bool) {
        self.isUserInitiated = isUserInitiated
        isAbandoned = false
    }

    // MARK: SPUUserDriver

    func show(
        _ request: SPUUpdatePermissionRequest
    ) async -> SUUpdatePermissionResponse {
        SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        checkCancellation = cancellation
        state.beginCheck(isUserInitiated: isUserInitiated)
    }

    /// Called when the launch gate gives up at its deadline.
    ///
    /// Sparkle's own cancellation handler is asked first, but it cannot be relied on:
    /// `SPUUserInitiatedUpdateDriver` guards that block with `_showingUserInitiatedProgress`,
    /// and clears the flag in `basicDriverDidFinishLoadingAppcast` — before
    /// `showUpdateFound` reaches this driver. Once the appcast has loaded, invoking it is
    /// a no-op and the check runs to completion regardless. `isAbandoned` is what
    /// actually refuses the late offer, so a check the launch gate has walked away from
    /// cannot reappear over a workspace the user is already using.
    func cancelCheck() {
        isAbandoned = true
        let cancellation = checkCancellation
        checkCancellation = nil
        cancellation?()
        resume(.dismiss)
        state.reset()
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state updateState: SPUUserUpdateState
    ) async -> SPUUserUpdateChoice {
        await offerUpdate(version: appcastItem.displayVersionString)
    }

    /// The body of `showUpdateFound`, split out only because `SPUUserUpdateState` has no
    /// public initializer, so a test cannot call the callback itself. Nothing in the
    /// offer depends on that parameter.
    func offerUpdate(version: String) async -> SPUUserUpdateChoice {
        checkCancellation = nil
        // A check the launch gate already walked away from must not paint an offer over
        // a workspace the user has moved on to. See `cancelCheck()`.
        guard !isAbandoned else { return .dismiss }
        state.showAvailable(newVersion: version, currentVersion: currentVersion)
        return await awaitDecision()
    }

    func showUpdateNotFoundWithError(_ error: any Error) async {
        checkCancellation = nil
        if isUserInitiated {
            state.showUpToDate(currentVersion: currentVersion)
        } else {
            state.reset()
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        hasReceivedExpectedContentLength = false
        state.beginDownload()
    }

    /// Sparkle's header for this method notes it "may be called more than once for the
    /// same download in rare scenarios" (e.g. a redirect). `UpdateState.setExpectedBytes`
    /// overwrites the expected total unconditionally, so a later, larger value would make
    /// the progress fraction jump backward for bytes already received. Only the first
    /// value seen for a given download is applied; later calls are ignored.
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        guard !hasReceivedExpectedContentLength else { return }
        hasReceivedExpectedContentLength = true
        state.setExpectedBytes(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        state.addReceivedBytes(length)
    }

    func showDownloadDidStartExtractingUpdate() {
        state.beginInstalling()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        state.setExtractionFraction(progress)
    }

    /// The user already consented at the offer. Prompting again would be a second gate
    /// on a decision they have made, so this returns `.install` after the runtime is torn
    /// down. Awaiting `prepareForInstall` is what guarantees no OMP child survives.
    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        await prepareForInstall()
        return .install
    }

    /// Sparkle sends the application a quit event before this callback. The driver must
    /// not send another one while `AppTerminationDelegate` is preparing its asynchronous
    /// reply, because a nested `NSApplication.terminate(_:)` blocks the main actor and
    /// prevents that reply from completing.
    func showInstallingUpdate(
        withApplicationTerminated _: Bool,
        retryTerminatingApplication _: @escaping () -> Void
    ) {
        state.beginRelaunching()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
        state.reset()
    }

    /// A launch check that errors before it produced anything must say nothing at all.
    /// Painting `Update failed` across a cold launch because DNS was slow is exactly the
    /// failure surface the advisory rules exist to prevent. Once the user has asked for
    /// an update, or once one is in flight, the failure is theirs to see.
    func showUpdaterError(_ error: any Error) async {
        resume(.dismiss)
        checkCancellation = nil
        if !isUserInitiated, case .checking = state.phase {
            state.reset()
        } else {
            state.fail(Self.failure(for: error))
        }
    }

    /// Sparkle calls this when it is finished with the session. It means "take down the
    /// progress UI", not "take down everything": `SPUUIBasedUpdateDriver._abortUpdateWithError:`
    /// hands the error to `showUpdaterError` / `showUpdateNotFoundWithError` first and
    /// calls this one main-queue turn after the acknowledgement returns. Sparkle's own
    /// standard driver honours that split — its `dismissUpdateInstallation` closes the
    /// checking window, the status controller and the update alert, and leaves the error
    /// alert it just put up standing.
    ///
    /// Resetting unconditionally erased `.failed` and `.upToDate` about a turn after they
    /// appeared, which made `Try again`, `Not now` and `Close` unreachable, blinked a
    /// menu check that found nothing open and shut, and dropped a failed update straight
    /// into the workspace. Only the phases Sparkle is actually driving are cleared here;
    /// the outcome phases belong to the splash until the user dismisses them.
    func dismissUpdateInstallation() {
        resume(.dismiss)
        switch state.phase {
        case .checking, .available, .downloading, .verifying, .installing:
            state.reset()
        case .idle, .upToDate, .relaunching, .failed:
            break
        }
    }

    // MARK: Failure mapping

    static func failure(for error: any Error) -> UpdateFailure {
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain else { return .unknown }
        switch nsError.code {
        case Int(SUError.signatureError.rawValue):
            return .verification
        case Int(SUError.downloadError.rawValue),
             Int(SUError.temporaryDirectoryError.rawValue):
            return .download
        case Int(SUError.installationError.rawValue),
             Int(SUError.relaunchError.rawValue):
            return .installation
        default:
            return .unknown
        }
    }

    // MARK: Decision plumbing

    func awaitDecisionForTesting() async -> SPUUserUpdateChoice {
        await awaitDecision()
    }

    /// Read-only test hook: true once `awaitDecision()`'s continuation is registered.
    /// Production code never reads this. Tests that trigger a decision via `acceptUpdate()`,
    /// `dismissUpdate()`, or `cancelCheck()` after starting an `async let` awaiter poll this
    /// instead of assuming the child task has already registered — on a serial actor it has
    /// not necessarily done so yet, so triggering too early would resolve nothing.
    var hasPendingDecisionForTesting: Bool { decision != nil }

    private func awaitDecision() async -> SPUUserUpdateChoice {
        await withCheckedContinuation { continuation in
            decision?.resume(returning: .dismiss)
            decision = continuation
        }
    }

    /// Returns `true` when a Sparkle decision was actually waiting on this answer.
    /// Callers use that to tell "Sparkle owns what happens next" from "nothing is
    /// listening, so the splash must clean up after itself".
    @discardableResult
    private func resume(_ choice: SPUUserUpdateChoice) -> Bool {
        guard let decision else { return false }
        self.decision = nil
        decision.resume(returning: choice)
        return true
    }
}

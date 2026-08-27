import AppKit
import Foundation
import Sparkle

@MainActor
final class SplashUpdateDriver: NSObject, SPUUserDriver {
    /// Set before each check. Controls whether an up-to-date result is shown or stays silent.
    var isUserInitiated = false

    private let state: UpdateState
    private let currentVersion: String
    private let prepareForInstall: @MainActor () async -> Void
    private let terminate: @MainActor () -> Void
    private var decision: CheckedContinuation<SPUUserUpdateChoice, Never>?
    private var checkCancellation: (() -> Void)?

    /// Guards `showDownloadDidReceiveExpectedContentLength` against Sparkle invoking it
    /// more than once for the same download (for example across a redirect). Only the
    /// first value is applied; see that method for why.
    private var hasReceivedExpectedContentLength = false

    init(
        state: UpdateState,
        currentVersion: String,
        prepareForInstall: @escaping @MainActor () async -> Void,
        terminate: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
        self.state = state
        self.currentVersion = currentVersion
        self.prepareForInstall = prepareForInstall
        self.terminate = terminate
        super.init()
    }

    // MARK: Splash actions

    func acceptUpdate() { resume(.install) }

    /// `Not now` dismisses this check. It deliberately does not use `.skip`, which
    /// would make Sparkle refuse to offer this version ever again.
    func dismissUpdate() { resume(.dismiss) }

    // MARK: SPUUserDriver

    func show(
        _ request: SPUUpdatePermissionRequest
    ) async -> SUUpdatePermissionResponse {
        SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        checkCancellation = cancellation
        state.beginCheck()
    }

    /// Called when the launch gate gives up at its deadline. Cancelling through Sparkle's
    /// own handler is what prevents a late `showUpdateFound` from stranding a decision
    /// continuation with no window left to resolve it.
    func cancelCheck() {
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
        checkCancellation = nil
        state.showAvailable(
            newVersion: appcastItem.displayVersionString,
            currentVersion: currentVersion)
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

    /// Sparkle cannot swap the bundle while the app it is replacing is still running.
    /// `applicationTerminated == false` means it is waiting on us to quit, and the
    /// driver owns that: nothing else in the app knows an install is in flight. Without
    /// this the installer sits waiting forever while the splash shows `Relaunching 10x`,
    /// and the only way out is quitting by hand.
    ///
    /// `AppModel.shutdown()` has already run, awaited in `showReadyToInstallAndRelaunch`
    /// before we consented, so the OMP children are already reaped by this point.
    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        state.beginRelaunching()
        guard !applicationTerminated else { return }
        terminate()
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

    func dismissUpdateInstallation() {
        resume(.dismiss)
        state.reset()
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

    private func resume(_ choice: SPUUserUpdateChoice) {
        guard let decision else { return }
        self.decision = nil
        decision.resume(returning: choice)
    }
}

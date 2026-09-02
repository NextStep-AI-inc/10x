import Foundation
import Observation

enum UpdateFailure: Equatable, Sendable {
    case verification
    case download
    case installation
    case unknown

    var detail: String {
        switch self {
        case .verification: "The download could not be verified."
        case .download: "The download did not finish. Check your connection."
        case .installation: "The update could not be installed."
        case .unknown: "The update could not be completed."
        }
    }
}

enum UpdatePhase: Equatable, Sendable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case available(newVersion: String, currentVersion: String)
    case downloading(receivedBytes: UInt64, expectedBytes: UInt64)
    case verifying
    case installing(extractionFraction: Double)
    case relaunching
    case failed(UpdateFailure)
}

enum UpdateStepID: String, CaseIterable, Sendable {
    case download
    case verify
    case install
    case relaunch

    var title: String {
        switch self {
        case .download: "Downloading update"
        case .verify: "Verifying download"
        case .install: "Installing update"
        case .relaunch: "Relaunching 10x"
        }
    }
}

@MainActor
@Observable
final class UpdateState {
    private(set) var phase: UpdatePhase = .idle
    @ObservationIgnored private(set) var isUserInitiatedCheck = false
    @ObservationIgnored private var lastActiveIndex: Int?
    @ObservationIgnored private var phaseWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// A launch check must stay invisible: nobody asked for it, and painting the splash
    /// over a cold launch for a network round trip is exactly what the advisory rules
    /// forbid. A check the user asked for is the opposite case. Without this, `Try again`
    /// made the window vanish for up to fifteen seconds, and `Check for Updates...` gave
    /// no feedback at all for the same stretch.
    var isPresentingUpdate: Bool {
        switch phase {
        case .idle: false
        case .checking: isUserInitiatedCheck
        default: true
        }
    }

    var isAwaitingDecision: Bool {
        if case .available = phase { return true }
        return false
    }

    /// One umbrella per screen. `.failed` previously fell through to a default of
    /// "Installing update", so the largest text on the failure screen named a step that
    /// had usually never run, and during the download it repeated the ledger's own third
    /// row. "Updating 10x" covers the whole run, including the run that failed, and
    /// duplicates no row title.
    var heading: String {
        switch phase {
        case .idle, .checking: "Checking for updates"
        case .available: "Update available"
        case .upToDate: "No updates available"
        case .downloading, .verifying, .installing, .relaunching, .failed: "Updating 10x"
        }
    }

    var footerTitle: String {
        switch phase {
        case .idle, .checking: "Checking for updates"
        case .upToDate(let current): "10x \(current)"
        case .available(let new, _): "10x \(new)"
        case .downloading: UpdateStepID.download.title
        case .verifying: UpdateStepID.verify.title
        case .installing: UpdateStepID.install.title
        case .relaunching: UpdateStepID.relaunch.title
        case .failed: "Update failed"
        }
    }

    var footerDetail: String {
        switch phase {
        case .idle, .checking: "Looking for a newer version"
        case .upToDate: "This is the newest version."
        case .available(_, let current): "You have \(current)."
        case .downloading(let received, let expected):
            Self.byteProgress(received: received, expected: expected)
        case .verifying: "Checking the signature"
        case .installing: "Replacing the application"
        case .relaunching: "Reopening with the new version"
        case .failed(let failure): failure.detail
        }
    }

    var signalProgress: Double? {
        switch phase {
        case .downloading(let received, let expected):
            guard expected > 0 else { return 0 }
            return 0.8 * min(1, Double(received) / Double(expected))
        case .verifying: return 0.8
        case .installing(let fraction): return 0.85 + 0.15 * min(max(fraction, 0), 1)
        case .relaunching: return 1
        default: return nil
        }
    }

    /// The install steps, but only when there is an install run to describe. A menu
    /// check that found nothing, and one that timed out before anything started, were
    /// both rendering four `Queued` steps that could never run.
    var rows: [SplashLedgerRow] {
        guard hasInstallRun else { return [] }
        return UpdateStepID.allCases.enumerated().map { index, step in
            SplashLedgerRow(id: step.rawValue, title: step.title, status: status(at: index))
        }
    }

    /// True while an install exists or can still be started from what is on screen. A
    /// failure only counts when a step had actually begun: `lastActiveIndex` is nil for a
    /// check that failed before reaching the download.
    private var hasInstallRun: Bool {
        switch phase {
        case .idle, .checking, .upToDate: false
        case .available, .downloading, .verifying, .installing, .relaunching: true
        case .failed: lastActiveIndex != nil
        }
    }

    static func byteProgress(received: UInt64, expected: UInt64) -> String {
        // Sparkle reports the expected length after the download has already started, so
        // the first frame is 0 of 0. `allowsNonnumericFormatting` would render that as
        // "Zero KB", which reads as a broken download rather than a starting one.
        guard received > 0 || expected > 0 else { return "Starting the download" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        let receivedText = formatter.string(fromByteCount: Int64(clamping: received))
        guard expected > 0 else { return receivedText }
        return "\(receivedText) of \(formatter.string(fromByteCount: Int64(clamping: expected)))"
    }

    func beginCheck(isUserInitiated: Bool = false) {
        lastActiveIndex = nil
        isUserInitiatedCheck = isUserInitiated
        setPhase(.checking)
    }

    func showAvailable(newVersion: String, currentVersion: String) {
        setPhase(.available(newVersion: newVersion, currentVersion: currentVersion))
    }

    func showUpToDate(currentVersion: String) {
        setPhase(.upToDate(currentVersion: currentVersion))
    }

    func beginDownload() {
        lastActiveIndex = 0
        setPhase(.downloading(receivedBytes: 0, expectedBytes: 0))
    }

    func setExpectedBytes(_ bytes: UInt64) {
        guard case .downloading(let received, _) = phase else { return }
        setPhase(.downloading(receivedBytes: received, expectedBytes: bytes))
    }

    func addReceivedBytes(_ bytes: UInt64) {
        guard case .downloading(let received, let expected) = phase else { return }
        let total = received &+ bytes
        if expected > 0, total >= expected {
            beginVerifying()
        } else {
            setPhase(.downloading(receivedBytes: total, expectedBytes: expected))
        }
    }

    func beginVerifying() {
        lastActiveIndex = 1
        setPhase(.verifying)
    }

    func beginInstalling() {
        lastActiveIndex = 2
        setPhase(.installing(extractionFraction: 0))
    }

    func setExtractionFraction(_ fraction: Double) {
        guard case .installing = phase else { return }
        setPhase(.installing(extractionFraction: fraction.isFinite ? fraction : 0))
    }

    func beginRelaunching() {
        lastActiveIndex = 3
        setPhase(.relaunching)
    }

    func fail(_ failure: UpdateFailure) {
        setPhase(.failed(failure))
    }

    func reset() {
        lastActiveIndex = nil
        isUserInitiatedCheck = false
        setPhase(.idle)
    }

    /// Resolves as soon as an in-flight check produces any outcome. Returns immediately
    /// when no check is running, so the launch gate can await it unconditionally.
    /// Cancelling the waiting task also resolves it; see `nextPhaseChange`.
    func waitForCheckOutcome() async {
        while case .checking = phase, !Task.isCancelled { await nextPhaseChange() }
    }

    /// Resolves once the splash has no update content left to show. Returns immediately
    /// when nothing is presented, so the handoff gate can await it unconditionally.
    ///
    /// This is a loop rather than a single wait because an update can move through
    /// several presented phases before it is finished with the window: offered,
    /// downloading, failed, then dismissed. Handoff must wait for the end of that
    /// sequence, not the end of the first step, or a failed update strands the splash
    /// with no workspace and no recovery.
    ///
    /// Cancellation resolves it too, and that is load bearing rather than tidiness.
    /// Accepting an update at launch runs `AppModel.shutdown()` from inside Sparkle's
    /// install callback: shutdown cancels the startup task and then awaits it, while the
    /// startup task is parked right here. Nothing moves the phase off a presenting one
    /// during an install (the one production caller of `reset()` on that path is
    /// `dismissUpdateInstallation`, which Sparkle only reaches after the reply shutdown
    /// is blocking), so a wait that ignored cancellation deadlocked the install
    /// permanently. Callers must treat a cancelled return as "the gate never opened" and
    /// not proceed; see `AppModel.runStartupAttempt`.
    func waitWhilePresenting() async {
        while isPresentingUpdate, !Task.isCancelled { await nextPhaseChange() }
    }

    private func setPhase(_ newPhase: UpdatePhase) {
        phase = newPhase
        let waiters = phaseWaiters
        phaseWaiters.removeAll()
        for waiter in waiters.values { waiter.resume() }
    }

    /// Suspends until the next phase change, or until the calling task is cancelled.
    /// Waiters are keyed so a cancellation can release exactly one of them without
    /// disturbing the others.
    private func nextPhaseChange() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Cancellation that lands before registration would otherwise never be
                // seen: `onCancel` has already run by then and found nothing to release.
                guard !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                phaseWaiters[id] = continuation
            }
        } onCancel: {
            Task { @MainActor in self.releaseWaiter(id) }
        }
    }

    private func releaseWaiter(_ id: UUID) {
        phaseWaiters.removeValue(forKey: id)?.resume()
    }

    private var activeIndex: Int? {
        switch phase {
        case .downloading: 0
        case .verifying: 1
        case .installing: 2
        case .relaunching: 3
        default: nil
        }
    }

    private func status(at index: Int) -> StartupStageStatus {
        if case .failed = phase {
            guard let failedIndex = lastActiveIndex else { return .queued }
            if index < failedIndex { return .ready }
            return index == failedIndex ? .stopped : .queued
        }
        guard let active = activeIndex else { return .queued }
        if index < active { return .ready }
        return index == active ? .loading : .queued
    }
}

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
    @ObservationIgnored private var lastActiveIndex: Int?
    @ObservationIgnored private var phaseWaiters: [CheckedContinuation<Void, Never>] = []

    var isPresentingUpdate: Bool {
        switch phase {
        case .idle, .checking: false
        default: true
        }
    }

    var isAwaitingDecision: Bool {
        if case .available = phase { return true }
        return false
    }

    var heading: String {
        switch phase {
        case .available: "Update available"
        case .upToDate: "No updates available"
        default: "Installing update"
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

    var rows: [SplashLedgerRow] {
        UpdateStepID.allCases.enumerated().map { index, step in
            SplashLedgerRow(id: step.rawValue, title: step.title, status: status(at: index))
        }
    }

    static func byteProgress(received: UInt64, expected: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let receivedText = formatter.string(fromByteCount: Int64(clamping: received))
        guard expected > 0 else { return receivedText }
        return "\(receivedText) of \(formatter.string(fromByteCount: Int64(clamping: expected)))"
    }

    func beginCheck() {
        lastActiveIndex = nil
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
        setPhase(.idle)
    }

    /// Resolves as soon as an in-flight check produces any outcome. Returns immediately
    /// when no check is running, so the launch gate can await it unconditionally.
    func waitForCheckOutcome() async {
        while case .checking = phase { await nextPhaseChange() }
    }

    /// Resolves once the splash has no update content left to show. Returns immediately
    /// when nothing is presented, so the handoff gate can await it unconditionally.
    ///
    /// This is a loop rather than a single wait because an update can move through
    /// several presented phases before it is finished with the window: offered,
    /// downloading, failed, then dismissed. Handoff must wait for the end of that
    /// sequence, not the end of the first step, or a failed update strands the splash
    /// with no workspace and no recovery.
    func waitWhilePresenting() async {
        while isPresentingUpdate { await nextPhaseChange() }
    }

    private func setPhase(_ newPhase: UpdatePhase) {
        phase = newPhase
        let waiters = phaseWaiters
        phaseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func nextPhaseChange() async {
        await withCheckedContinuation { phaseWaiters.append($0) }
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

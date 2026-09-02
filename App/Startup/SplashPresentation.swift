import SwiftUI

struct SplashLedgerRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let status: StartupStageStatus

    var accessibilityLabel: String { "\(title), \(status.rawValue)" }
}

enum SplashFooterTone: Equatable, Sendable {
    case working
    case failed
}

struct SplashAction: Identifiable {
    enum Kind: Equatable, Sendable {
        case primary
        case secondary
    }

    let id: String
    let title: String
    let kind: Kind
    let perform: @MainActor () -> Void
}

struct SplashPresentation {
    let heading: String
    let accessibilityLabel: String
    let rows: [SplashLedgerRow]
    /// Names what the ledger is a list of. The two presentations share
    /// `StartupLedgerView`, which had "Startup preparation" hardcoded, so VoiceOver
    /// announced the update steps as startup steps.
    let ledgerAccessibilityLabel: String
    let isSignalAnimating: Bool
    let isSignalFailed: Bool
    let signalProgress: Double?
    let footerTitle: String
    let footerTone: SplashFooterTone
    let footerDetail: String
    let actions: [SplashAction]
}

extension SplashPresentation {
    /// What makes this a different screen rather than the same one making progress: the
    /// umbrella heading, whether it is a failure, and which actions are offered.
    /// `SplashView` drives focus and the spoken summary off changes to this, because the
    /// failure tone alone missed the update offered during startup, which is neither an
    /// appearance nor a failure.
    var screenSignature: String {
        let actionIDs = actions.map(\.id).joined(separator: ",")
        return "\(heading)|\(footerTone == .failed)|\(actionIDs)"
    }
}

extension SplashPresentation {
    @MainActor
    static func startup(
        state: StartupState,
        onRetry: @escaping @MainActor () -> Void,
        onContinue: @escaping @MainActor () -> Void
    ) -> SplashPresentation {
        let isRecovery = state.phase == .recovery
        return SplashPresentation(
            heading: "Preparing your workspace",
            accessibilityLabel: "Preparing your workspace",
            rows: state.rows,
            ledgerAccessibilityLabel: "Startup preparation",
            isSignalAnimating: state.isSignalAnimating,
            isSignalFailed: isRecovery,
            signalProgress: nil,
            footerTitle: state.footerTitle,
            footerTone: isRecovery ? .failed : .working,
            footerDetail: state.footerDetail,
            actions: isRecovery
                ? [
                    SplashAction(
                        id: "retry", title: "Retry", kind: .primary, perform: onRetry),
                    SplashAction(
                        id: "continue",
                        title: "Continue to workspace",
                        kind: .secondary,
                        perform: onContinue),
                ]
                : [])
    }
}

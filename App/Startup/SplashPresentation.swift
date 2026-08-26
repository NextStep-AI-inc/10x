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
    let isSignalAnimating: Bool
    let isSignalFailed: Bool
    let signalProgress: Double?
    let footerTitle: String
    let footerTone: SplashFooterTone
    let footerDetail: String
    let actions: [SplashAction]
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

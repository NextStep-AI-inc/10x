import SwiftUI

extension SplashPresentation {
    @MainActor
    static func update(
        state: UpdateState,
        onInstall: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void,
        onRetry: @escaping @MainActor () -> Void
    ) -> SplashPresentation {
        var isFailed = false
        if case .failed = state.phase { isFailed = true }

        let actions: [SplashAction]
        switch state.phase {
        case .available:
            actions = [
                SplashAction(
                    id: "install",
                    title: "Install and Relaunch",
                    kind: .primary,
                    perform: onInstall),
                SplashAction(
                    id: "dismiss", title: "Not now", kind: .secondary, perform: onDismiss),
            ]
        case .failed:
            actions = [
                SplashAction(id: "retry", title: "Try again", kind: .primary, perform: onRetry),
                SplashAction(
                    id: "dismiss", title: "Not now", kind: .secondary, perform: onDismiss),
            ]
        case .upToDate:
            actions = [
                SplashAction(id: "close", title: "Close", kind: .primary, perform: onDismiss),
            ]
        default:
            actions = []
        }

        return SplashPresentation(
            heading: state.heading,
            accessibilityLabel: state.heading,
            rows: state.rows,
            isSignalAnimating: false,
            isSignalFailed: isFailed,
            signalProgress: state.signalProgress,
            footerTitle: state.footerTitle,
            footerTone: isFailed ? .failed : .working,
            footerDetail: state.footerDetail,
            actions: actions)
    }
}

import Foundation
import SwiftUI

enum AppWindowID {
    static let startup = "startup"
    static let workspace = "workspace"
}

struct StartupSceneView: View {
    let model: AppModel

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        SplashView(
            presentation: presentation,
            buildVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        .task { await model.bootstrap() }
        .onChange(of: model.startupState.handoffGeneration, initial: true) { _, _ in
            guard model.startupState.consumeWorkspaceOpenRequest() else { return }
            Task { @MainActor in
                openWindow(id: AppWindowID.workspace)
            }
        }
        .onChange(of: model.updateState.isPresentingUpdate) { _, isPresenting in
            guard !isPresenting, model.startupState.phase == .handoff else { return }
            dismissWindow(id: AppWindowID.startup)
        }
    }

    @MainActor
    private var presentation: SplashPresentation {
        guard model.updateState.isPresentingUpdate else {
            return SplashPresentation.startup(
                state: model.startupState,
                onRetry: { Task { await model.retryStartup() } },
                onContinue: { Task { await model.continueToWorkspace() } })
        }
        return SplashPresentation.update(
            state: model.updateState,
            onInstall: { model.acceptUpdate() },
            onDismiss: { model.dismissUpdate() },
            onRetry: { model.retryUpdate() })
    }
}

import Foundation
import SwiftUI

enum AppWindowID {
    static let startup = "startup"
    static let workspace = "workspace"
}

struct StartupSceneView: View {
    let model: AppModel

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SplashView(
            presentation: SplashPresentation.startup(
                state: model.startupState,
                onRetry: { Task { await model.retryStartup() } },
                onContinue: { Task { await model.continueToWorkspace() } }),
            buildVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        .task { await model.bootstrap() }
        .onChange(of: model.startupState.handoffGeneration, initial: true) { _, _ in
            guard model.startupState.consumeWorkspaceOpenRequest() else { return }
            Task { @MainActor in
                openWindow(id: AppWindowID.workspace)
            }
        }
    }
}

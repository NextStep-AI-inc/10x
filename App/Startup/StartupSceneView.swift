import Foundation
import SwiftUI

enum AppWindowID {
    static let startup = "startup"
    static let workspace = "workspace"
}

struct StartupSceneView: View {
    let model: AppModel

    @Environment(\.openWindow) private var openWindow
    @State private var handledHandoffGeneration = 0

    var body: some View {
        SplashView(
            state: model.startupState,
            buildVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            onRetry: { Task { await model.retryStartup() } },
            onContinue: { Task { await model.continueToWorkspace() } })
        .task { await model.bootstrap() }
        .onChange(of: model.startupState.handoffGeneration, initial: true) {
            _, generation in
            guard generation > handledHandoffGeneration else { return }
            handledHandoffGeneration = generation
            Task { @MainActor in
                openWindow(id: AppWindowID.workspace)
            }
        }
    }
}

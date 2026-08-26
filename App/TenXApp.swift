import AppKit
import SwiftUI

@main
struct TenXApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(AppTerminationDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Preparing your workspace", id: AppWindowID.startup) {
            StartupSceneView(model: model)
                .onAppear {
                    appDelegate.shutdown = { await model.shutdown() }
                }
        }
        .defaultSize(width: 640, height: 400)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        .windowStyle(.plain)
        .windowBackgroundDragBehavior(.enabled)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(
            model.startupState.phase == .handoff ? .suppressed : .presented)

        WindowGroup("10x", id: AppWindowID.workspace) {
            WorkspaceSceneView(
                model: model,
                scenePhase: scenePhase,
                onAppear: {
                    appDelegate.shutdown = { await model.shutdown() }
                })
        }
        .defaultLaunchBehavior(
            model.startupState.phase == .handoff ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}

private struct WorkspaceSceneView: View {
    let model: AppModel
    let scenePhase: ScenePhase
    let onAppear: @MainActor () -> Void

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        AppShellView(model: model)
            .frame(minWidth: 760, minHeight: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                onAppear()
                Task { @MainActor in
                    await model.workspaceDidOpen()
                    dismissWindow(id: AppWindowID.startup)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await model.refreshProvidersIfNeeded() }
            }
    }
}

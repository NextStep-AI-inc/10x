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
            AppShellView(model: model)
                .frame(minWidth: 760, minHeight: 560)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    appDelegate.shutdown = { await model.shutdown() }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await model.refreshProvidersIfNeeded() }
                }
        }
        .defaultLaunchBehavior(
            model.startupState.phase == .handoff ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}

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
        .commands {
            CommandGroup(after: .appInfo) {
                // Disabled rather than hidden until handoff: the menu bar is global and
                // this command is reachable while only the splash is showing, but there
                // is nothing to check from there — the advisory launch check already
                // owns `updateState` for that whole window, and a menu click racing it
                // would collide with it. Gating on `phase == .handoff` (rather than
                // `updateState.phase` directly) means the item is disabled for the exact
                // stretch during which a launch check could be in flight, and enabled
                // only once `prepareUpdates` has unconditionally finished (it is awaited
                // by the same task group `requestHandoff` waits on) — so whenever this
                // is clickable, `updateState.phase` can never still be `.checking` from
                // the launch path. A disabled-but-visible item is preferable to one that
                // appears and disappears, which reads as broken.
                Button("Check for Updates…") {
                    model.checkForUpdatesFromMenu()
                }
                .disabled(model.startupState.phase != .handoff)
            }
        }
    }
}

private struct WorkspaceSceneView: View {
    let model: AppModel
    let scenePhase: ScenePhase
    let onAppear: @MainActor () -> Void

    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

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
            .onChange(of: model.updateState.isPresentingUpdate) { _, isPresenting in
                guard isPresenting else { return }
                openWindow(id: AppWindowID.startup)
            }
    }
}

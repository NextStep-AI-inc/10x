import AppKit
import SwiftUI

@main
struct TenXApp: App {
    @State private var model: AppModel
    private let fixtureConfiguration: SessionMapFixtureScene.Configuration?
    private let fixtureStartupError: String?
    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(AppTerminationDelegate.self) private var appDelegate

    init() {
        let environment = ProcessInfo.processInfo.environment
        do {
            if let route = try UIFixtureRoute.resolve(environment: environment) {
                let configuration = try SessionMapFixtureScene.make(
                    route: route,
                    environment: environment)
                fixtureConfiguration = configuration
                fixtureStartupError = nil
                _model = State(initialValue: configuration.model)
            } else {
                // Before anything can spawn: a Finder launch inherits LaunchServices'
                // PATH, which cannot resolve OMP's `bun` interpreter.
                OmpProcessEnvironment.install()
                fixtureConfiguration = nil
                fixtureStartupError = nil
                _model = State(initialValue: AppModel())
            }
        } catch {
            fixtureConfiguration = nil
            fixtureStartupError = error.localizedDescription
            _model = State(initialValue: SessionMapFixtureScene.inertModelForStartupFailure())
        }
    }

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
            fixtureConfiguration == nil && fixtureStartupError == nil
                && model.startupState.phase != .handoff ? .presented : .suppressed)

        WindowGroup(fixtureConfiguration?.title ?? "10x", id: AppWindowID.workspace) {
            if let fixtureConfiguration {
                SessionMapFixtureScene(configuration: fixtureConfiguration)
                    .onAppear {
                        appDelegate.shutdown = { await model.shutdown() }
                    }
            } else if let fixtureStartupError {
                VStack(alignment: .leading, spacing: 10) {
                    Text("UI fixture unavailable")
                        .font(TenXTypography.accent(size: 16))
                    Text(fixtureStartupError)
                        .font(TenXTypography.body(size: 12))
                        .textSelection(.enabled)
                }
                .padding(24)
                .frame(minWidth: 520, minHeight: 220, alignment: .topLeading)
            } else {
                WorkspaceSceneView(
                    model: model,
                    scenePhase: scenePhase,
                    onAppear: {
                        appDelegate.shutdown = { await model.shutdown() }
                    })
            }
        }
        .defaultLaunchBehavior(
            fixtureConfiguration != nil || fixtureStartupError != nil
                || model.startupState.phase == .handoff ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(
            width: fixtureConfiguration == nil ? 1_180 : 1_440,
            height: fixtureConfiguration == nil ? 760 : 900)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            TenXCommands(model: model)
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

import SwiftUI

@main
struct TenXApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AppShellView(model: model)
            .frame(minWidth: 760, minHeight: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await model.bootstrap() }
            .onChange(of: model.supervision.hasAnyActivity) {
                model.updateEmergencyShortcut()
            }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Use Computer") {
                    Task { await model.beginComputerUse() }
                }
                .keyboardShortcut("c", modifiers: [.shift, .command])
                .disabled(model.activeSession?.isComposerAvailable != true)
            }
        }

        MenuBarExtra(isInserted: computerMenuBinding) {
            ComputerUseMenuBarView(
                client: model.supervision,
                onOpenSession: { daemonSession in model.openSession(forDaemonSession: daemonSession) },
                openableSessionIDs: model.openableDaemonSessionIDs)
        } label: {
            Label("10x Computer", systemImage: "display")
        }
    }

    private var computerMenuBinding: Binding<Bool> {
        Binding(
            get: { model.supervision.hasAnyActivity },
            set: { _ in }) // insertion is state-driven; nothing to do on removal
    }
}

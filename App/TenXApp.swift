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

        MenuBarExtra(isInserted: computerMenuBinding) {
            ComputerUseMenuBarView(client: model.supervision)
        } label: {
            Label("10x Computer", systemImage: "display")
        }
    }

    private var computerMenuBinding: Binding<Bool> {
        Binding(
            get: { model.supervision.hasAnyActivity },
            set: { _ in })
    }
}

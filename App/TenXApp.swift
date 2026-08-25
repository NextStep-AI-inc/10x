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
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}

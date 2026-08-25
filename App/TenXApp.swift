import SwiftUI

@main
struct TenXApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                switch model.route {
                case .setup:
                    SetupView(model: model)
                case .newSession:
                    VStack(spacing: 10) {
                        BrandWordmark(width: 42)
                        Text("Start a session")
                            .font(TenXTypography.title(size: 32))
                    }
                case .session:
                    Text("Session")
                case .settings:
                    Text("Settings")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TenXPalette.color(TenXPalette.canvasHex))
            .task { await model.bootstrap() }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}

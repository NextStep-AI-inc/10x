import SwiftUI

struct AppShellView: View {
    let model: AppModel

    @State private var railExpansion = RailExpansionModel()

    var body: some View {
        Group {
            if model.route == .setup {
                SetupView(model: model)
            } else {
                HStack(spacing: 0) {
                    FloatingRailView(model: model, expansion: railExpansion)
                    routeCanvas
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(TenXPalette.color(TenXPalette.canvasHex))
    }

    @ViewBuilder
    private var routeCanvas: some View {
        switch model.route {
        case .setup:
            EmptyView()
        case .newSession:
            NewSessionView(model: model)
        case .session:
            Text("Session")
                .font(TenXTypography.title(size: 32))
        case .settings:
            Text("Settings")
                .font(TenXTypography.title(size: 32))
        }
    }
}

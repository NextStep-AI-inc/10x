import SwiftUI

struct AppShellView: View {
    let model: AppModel

    @State private var railExpansion = RailExpansionModel()

    var body: some View {
        Group {
            if model.route == .setup {
                SetupView(model: model)
            } else {
                ZStack(alignment: .leading) {
                    routeCanvas
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.leading, 64)
                    FloatingRailView(model: model, expansion: railExpansion)
                }
                .overlay(alignment: .topTrailing) {
                    ShellTopActionsView(model: model)
                        .padding(.top, 16)
                        .padding(.trailing, 18)
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
            if let activeSession = model.activeSession {
                ActiveSessionView(controller: activeSession)
            } else {
                Text("Session unavailable")
                    .font(TenXTypography.body(size: 13))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
        case .settings:
            Text("Settings")
                .font(TenXTypography.title(size: 32))
        }
    }
}

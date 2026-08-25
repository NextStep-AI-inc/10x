import SwiftUI

struct AppShellView: View {
    let model: AppModel

    @State private var railExpansion = RailExpansionModel()

    var body: some View {
        Group {
            if model.route == .setup {
                SetupView(model: model)
            } else if model.route == .providerSetup {
                if let providerModel = model.providerModel {
                    ProviderSetupView(
                        model: providerModel,
                        onContinue: model.completeProviderSetup)
                }
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
                .overlay {
                    if model.isSearchPresented {
                        SearchModalView(
                            sessions: model.sessions,
                            onOpen: model.openSearchResult,
                            onClose: model.closeSearch)
                    }
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
        case .providerSetup:
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
            if let settingsModel = model.settingsModel {
                SettingsView(
                    model: settingsModel,
                    onOpenProviders: { model.openProviders(.connections) })
            } else {
                Text("OMP settings unavailable")
                    .font(TenXTypography.body(size: 13))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
        case .providers:
            if let providerModel = model.providerModel {
                ProvidersView(model: providerModel)
            } else {
                Text("Providers unavailable")
                    .font(TenXTypography.body(size: 13))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
        }
    }
}

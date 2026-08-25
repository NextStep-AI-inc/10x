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
        .overlay {
            if let request = model.pendingDeletion {
                SessionDeletionConfirmationView(
                    request: request,
                    onCancel: model.cancelDeletion,
                    onDelete: {
                        Task { await model.confirmDeletion() }
                    })
            }
        }
        .alert(
            "Session action failed",
            isPresented: sessionActionErrorIsPresented,
            presenting: model.sessionActionError
        ) { _ in
            Button("OK") {
                model.dismissSessionActionError()
            }
        } message: { message in
            Text(message)
        }
    }

    private var sessionActionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { model.sessionActionError != nil },
            set: { isPresented in
                if !isPresented {
                    model.dismissSessionActionError()
                }
            })
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
        case .archivedSessions:
            ArchivedSessionsView(model: model)
        case .settings:
            if let settingsModel = model.settingsModel {
                SettingsView(model: settingsModel)
            } else {
                Text("OMP settings unavailable")
                    .font(TenXTypography.body(size: 13))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
        }
    }
}

import SwiftUI

struct AppShellView: View {
    let model: AppModel

    @State private var railExpansion = RailExpansionModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.route == .setup {
                SetupView(model: model)
            } else {
                ZStack(alignment: .leading) {
                    routeCanvas
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.leading, railExpansion.contentLeadingInset)
                        .environment(model.idePreferenceStore)
                        .environment(\.fileOpenService, model.fileOpenService)
                        .environment(\.openIDEPreferences, OpenIDEPreferencesAction {
                            model.openSettings(focus: .preferredIDE)
                        })
                    FloatingRailView(model: model, expansion: railExpansion)
                }
                .animation(railAnimation, value: railExpansion.isExpanded)
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

    private var railAnimation: Animation? {
        RailExpansionTransition.animationDuration(reduceMotion: reduceMotion)
            .map { .easeInOut(duration: $0) }
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
            if let settingsModel = model.settingsModel {
                SettingsView(
                    model: settingsModel,
                    registry: model.ideRegistry,
                    store: model.idePreferenceStore,
                    focusTarget: model.settingsFocusTarget,
                    onFocusConsumed: model.consumeSettingsFocus)
            } else {
                Text("OMP settings unavailable")
                    .font(TenXTypography.body(size: 13))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
        }
    }
}

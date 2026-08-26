import SwiftUI

struct AppShellView: View {
    let model: AppModel

    @State private var railExpansion: RailExpansionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel, railExpansion: RailExpansionModel = RailExpansionModel()) {
        self.model = model
        _railExpansion = State(initialValue: railExpansion)
    }

    var body: some View {
        ZStack {
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
                        GeometryReader { geometry in
                            if let providerModel = model.providerModel,
                               !providerModel.dockProviders.isEmpty {
                                let dockProviders = providerModel.dockProviders
                                let compactLayout = ProviderUsageDockLayout.compact(
                                    shellWidth: geometry.size.width,
                                    contentLeadingInset: railExpansion.contentLeadingInset,
                                    providerCount: dockProviders.count,
                                    hasComposer: hasComposer)

                                ProviderUsageDockView(
                                    providers: dockProviders,
                                    activeCounts: model.providerActivityCounts,
                                    isForegroundGenerating: model.isForegroundSessionGenerating,
                                    compactLayout: compactLayout)
                                    .padding(.trailing, 16)
                                    .padding(.bottom, 16)
                                    .frame(
                                        maxWidth: .infinity,
                                        maxHeight: .infinity,
                                        alignment: .bottomTrailing)
                            }
                        }
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
            .disabled(isSessionInteractionBlocked)
            .accessibilityHidden(isSessionInteractionBlocked)

            if let request = model.pendingDeletion {
                SessionDeletionConfirmationView(
                    request: request,
                    onCancel: model.cancelDeletion,
                    onDelete: {
                        Task { await model.confirmDeletion() }
                    })
            }
        }
        .background(TenXPalette.color(TenXPalette.canvasHex))
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
            get: {
                !isSessionInteractionBlocked && model.sessionActionError != nil
            },
            set: { isPresented in
                if !isPresented && !isSessionInteractionBlocked {
                    model.dismissSessionActionError()
                }
            })
    }

    private var isSessionInteractionBlocked: Bool {
        model.pendingDeletion != nil || model.isSessionMutationInFlight
    }

    private var railAnimation: Animation? {
        RailExpansionTransition.animationDuration(reduceMotion: reduceMotion)
            .map { .easeInOut(duration: $0) }
    }

    private var hasComposer: Bool {
        switch model.route {
        case .newSession, .session:
            return true
        default:
            return false
        }
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
        case .archivedSessions:
            ArchivedSessionsView(model: model)
        case .settings:
            if let settingsModel = model.settingsModel {
                SettingsView(
                    model: settingsModel,
                    registry: model.ideRegistry,
                    store: model.idePreferenceStore,
                    focusTarget: model.settingsFocusTarget,
                    onFocusConsumed: model.consumeSettingsFocus,
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

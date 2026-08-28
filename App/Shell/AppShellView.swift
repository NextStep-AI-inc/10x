import SwiftUI

struct AppShellView: View {
    let model: AppModel

    @State private var railExpansion: RailExpansionModel
    @State private var isBrandMenuPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel, railExpansion: RailExpansionModel = RailExpansionModel()) {
        self.model = model
        _railExpansion = State(initialValue: railExpansion)
    }

    var body: some View {
        ZStack {
            Group {
                if case .onboarding(let step) = model.route {
                    OnboardingView(model: model, step: step)
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
                        FloatingRailView(
                            model: model,
                            expansion: railExpansion,
                            isBrandMenuPresented: $isBrandMenuPresented)
                    }
                    .animation(railAnimation, value: railExpansion.isExpanded)
                    .overlay {
                        if isBrandMenuPresented {
                            brandMenuOverlay
                        }
                    }
                    .animation(brandMenuAnimation, value: isBrandMenuPresented)
                    .overlay {
                        GeometryReader { geometry in
                            usageDock(shellWidth: geometry.size.width)
                        }
                    }
                    .overlay {
                        if model.isSearchPresented {
                            SearchModalView(
                                sessions: model.sessions,
                                service: model.sessionSearch,
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
        .onChange(of: model.isSearchPresented) { _, presented in
            if presented { isBrandMenuPresented = false }
        }
        .onChange(of: model.route) { _, _ in
            isBrandMenuPresented = false
        }
    }

    private var brandMenuOverlay: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isBrandMenuPresented = false }
                .onExitCommand { isBrandMenuPresented = false }

            BrandActionsMenuView(model: model, isPresented: $isBrandMenuPresented)
                .padding(.leading, 15)
                .padding(.top, 54)
                .transition(brandMenuTransition)
        }
    }

    private var brandMenuAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.88)
    }

    private var brandMenuTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .asymmetric(
                insertion: .modifier(
                    active: BrandMenuDrawerModifier(progress: 0),
                    identity: BrandMenuDrawerModifier(progress: 1)),
                removal: .modifier(
                    active: BrandMenuDrawerModifier(progress: 0),
                    identity: BrandMenuDrawerModifier(progress: 1)))
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
        case .onboarding:
            EmptyView()
        case .newSession:
            NewSessionView(model: model)
        case .session:
            if let activeSession = model.activeSession {
                ActiveSessionView(
                    controller: activeSession,
                    controls: model.composerControls)
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
                    onBack: { model.leaveSettings() },
                    providerModel: model.providerModel,
                    accountCoordinator: model.sessionActivityRegistry)
            } else {
                Text("OMP settings unavailable")
                    .font(TenXTypography.body(size: 13))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
        case .providers:
            if let providerModel = model.providerModel {
                ProvidersView(
                    model: providerModel,
                    accountCoordinator: model.sessionActivityRegistry)
            } else {
                Text("Providers unavailable")
                    .font(TenXTypography.body(size: 13))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
        }
    }

    @ViewBuilder
    private func usageDock(shellWidth: CGFloat) -> some View {
        if let providerModel = model.providerModel, !providerModel.dockProviders.isEmpty {
            let dockProviders = providerModel.dockProviders
            let compactLayout = ProviderUsageDockLayout.compact(
                shellWidth: shellWidth,
                contentLeadingInset: railExpansion.contentLeadingInset,
                providerCount: dockProviders.count,
                hasComposer: hasComposer)

            ProviderUsageDockView(
                providers: dockProviders,
                activeCounts: model.providerActivityCounts,
                generatingCounts: model.accountGeneratingCounts,
                isForegroundGenerating: model.isForegroundSessionGenerating,
                compactLayout: compactLayout,
                accountScopeSatisfaction: model.accountScopeSatisfaction(
                    openSessionID: model.activeSessionIdentityToken),
                pendingRemovalAccounts: model.pendingRemovalAccounts,
                requiresRestartToSwitch: providerModel.accountTier.requiresRestartToSwitch,
                activeSessionIdentityToken: model.activeSessionIdentityToken,
                onUseAccount: { accountRef, scope in
                    let openSessionID = model.activeSessionIdentityToken
                    Task {
                        await model.useProviderAccount(
                            accountRef,
                            scope: scope,
                            openSessionID: openSessionID)
                    }
                },
                onManageAccounts: { providerID in
                    model.manageProviderAccounts(providerID: providerID)
                })
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
}

private struct BrandMenuDrawerModifier: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1, y: max(progress, 0.001), anchor: .topLeading)
            .offset(y: (1 - progress) * -8)
    }

}

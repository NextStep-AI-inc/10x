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
                    GeometryReader { shell in
                        let providerWidth = ProviderUsageDockLayout.footerWidth(
                            providers: model.providerModel?.dockProviders ?? [])
                        let providerPlacement = ProviderUsageDockLayout.placement(
                            availableWidth: shell.size.width,
                            factsMinWidth: 380,
                            actionsMinWidth: 200,
                            providerWidth: providerWidth)
                        VStack(spacing: 0) {
                            ZStack(alignment: .leading) {
                                routeCanvas
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(.leading, railExpansion.contentLeadingInset)
                                FloatingRailView(
                                    model: model,
                                    expansion: railExpansion,
                                    isBrandMenuPresented: $isBrandMenuPresented)
                            }
                            WorkspaceDockView(
                                model: model,
                                isFocusBlocked: isComposerFocusBlocked,
                                routeCanvasLeadingInset: railExpansion.contentLeadingInset,
                                providerWidth: providerWidth,
                                providerPlacement: providerPlacement)
                        }
                        .environment(model.idePreferenceStore)
                        .environment(model.toolDetailPreferenceStore)
                        .environment(\.fileOpenService, model.fileOpenService)
                        .environment(\.openIDEPreferences, OpenIDEPreferencesAction {
                            model.openSettings(focus: .preferredIDE)
                        })
                        .environment(\.openReportedSession, OpenReportedSessionAction { path in
                            await model.openReportedChildSession(path: path)
                        })
                        .animation(railAnimation, value: railExpansion.isExpanded)
                        .overlay {
                            if isBrandMenuPresented {
                                brandMenuOverlay
                            }
                        }
                        .animation(brandMenuAnimation, value: isBrandMenuPresented)
                        .overlay(alignment: .bottomTrailing) {
                            usageDock(placement: providerPlacement)
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

            if let request = model.pendingRename {
                SessionRenameView(
                    request: request,
                    isSaving: model.isSessionMutationInFlight,
                    onDraftChange: model.updateRenameDraft,
                    onCancel: model.cancelRename,
                    onSave: {
                        Task { await model.confirmRename() }
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
        model.pendingDeletion != nil
            || model.pendingRename != nil
            || model.isSessionMutationInFlight
    }

    private var isComposerFocusBlocked: Bool {
        isSessionInteractionBlocked || model.isSearchPresented || isBrandMenuPresented
            || model.sessionActionError != nil
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

    private var hasComposerAttachments: Bool {
        switch model.route {
        case .newSession:
            return !model.newSessionAttachments.isEmpty
        case .session:
            return !(model.activeSession?.attachments.isEmpty ?? true)
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
                    controls: model.composerControls,
                    commands: model.composerCommands,
                    onReviewPrompt: { model.reviewFailedPrompt(activeSession) })
                    .environment(\.renameCurrentSession, model.requestRenameCurrentSession)
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
                    harnessNoticeStore: model.harnessNoticePreferenceStore,
                    availableModels: model.composerControls?.models ?? [],
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
    private func usageDock(placement: ProviderUsageDockPlacement) -> some View {
        if let providerModel = model.providerModel, !providerModel.dockProviders.isEmpty {
            let dockProviders = providerModel.dockProviders

            ProviderUsageDockView(
                providers: dockProviders,
                activeCounts: model.providerActivityCounts,
                generatingCounts: model.accountGeneratingCounts,
                isForegroundGenerating: model.isForegroundSessionGenerating,
                compactLayout: ProviderUsageDockCompactLayout(
                    wheelDiameter: ProviderUsageDockLayout.inComposer28,
                    trailingOffset: 0,
                    bottomOffset: hasComposer && placement == .aboveLine
                        ? ProviderUsageDockLayout.aboveLineBottomOffset(
                            hasAttachments: hasComposerAttachments)
                        : 0),
                accountScopeSatisfaction: model.accountScopeSatisfaction(
                    openSessionID: model.activeSessionIdentityToken),
                accountScopeAvailability: model.accountScopeAvailability(
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

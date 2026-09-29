import AppKit
import SwiftUI

enum WorkspaceDockRouting {
    static func resetFlyout(
        _ flyout: inout ComposerFlyout?,
        whenRouteChangesFrom oldRoute: AppRoute,
        to newRoute: AppRoute
    ) {
        if oldRoute != newRoute { flyout = nil }
    }
}

struct WorkspaceDockView: View {
    let model: AppModel
    let isFocusBlocked: Bool
    var routeCanvasLeadingInset: CGFloat = 0
    var providerWidth: CGFloat = 0
    var providerPlacement: ProviderUsageDockPlacement = .belowLine

    @State private var flyout: ComposerFlyout?

    var body: some View {
        Group {
            switch model.route {
            case .newSession:
                composer(
                    draft: Bindable(model).newSessionDraft,
                    attachments: Bindable(model).newSessionAttachments,
                    presentation: .newSession(
                        projectURL: model.selectedProjectURL,
                        projectURLs: ProjectSessionGrouper.choosableProjectURLs(
                            from: model.sessions,
                            including: model.selectedProjectURL,
                            knownProjectURLs: model.knownProjectURLs),
                        onChooseProject: model.chooseProject,
                        onAddExistingFolder: addExistingFolder),
                    controlsMode: .newSession,
                    focusRequest: model.newSessionFocusRequest,
                    signalPresentation: .workspace(generatingCount: generatingCount),
                    signalCompactionPhase: .none,
                    onSignalRevealComplete: { _ in },
                    onSend: {
                        flyout = nil
                        model.startNewSession(
                            prompt: model.newSessionDraft,
                            attachments: model.newSessionAttachments)
                    })
            case .session:
                if let controller = model.activeSession {
                    composer(
                        draft: Bindable(controller).draft,
                        attachments: Bindable(controller).attachments,
                        presentation: .active(controller: controller),
                        controlsMode: .activeSession,
                        focusRequest: 0,
                        signalPresentation: .session(
                            runtimeState: controller.runtimeState,
                            contextPercent: controller.contextPercentage,
                            hasPendingUserInput: controller.hasPendingUserInput,
                            isRetrying: controller.isSignalRetrying,
                            hasTerminalRetryFailure: controller.hasTerminalRetryFailure,
                            compactionPhase: controller.signalCompactionPhase,
                            isRecoveryPresented: controller.isRecoveryPresented,
                            isIntentionallyStopped: controller.isIntentionallyStopped),
                        signalCompactionPhase: controller.signalCompactionPhase,
                        onSignalRevealComplete: controller.completeSignalReveal,
                        onSend: { Task { await controller.sendPrompt() } })
                } else {
                    workspaceFooter
                }
            case .archivedSessions, .settings, .providers:
                workspaceFooter
            case .onboarding:
                EmptyView()
            }
        }
        .onChange(of: model.route) { oldRoute, newRoute in
            WorkspaceDockRouting.resetFlyout(&flyout, whenRouteChangesFrom: oldRoute, to: newRoute)
        }
        .onChange(of: model.activeSessionIdentityToken) { _, _ in flyout = nil }
        .onChange(of: model.newSessionFocusRequest) { _, _ in flyout = nil }
        .onExitCommand { flyout = nil }
        .environment(\.fileReferenceBaseURL, model.activeSession?.projectURL)
    }

    private func composer(
        draft: Binding<String>,
        attachments: Binding<[ComposerAttachment]>,
        presentation: ComposerPresentation,
        controlsMode: ComposerControlsMode,
        focusRequest: Int,
        signalPresentation: WorkspaceSignalPresentation,
        signalCompactionPhase: SessionCompactionSignalPhase,
        onSignalRevealComplete: @escaping (UInt64) -> Void,
        onSend: @escaping () -> Void
    ) -> some View {
        ComposerView(
            draft: draft,
            attachments: attachments,
            flyout: $flyout,
            presentation: presentation,
            controls: model.composerControls,
            commands: model.composerCommands,
            controlsMode: controlsMode,
            focusRequest: focusRequest,
            signalPresentation: signalPresentation,
            signalCompactionPhase: signalCompactionPhase,
            onSignalRevealComplete: onSignalRevealComplete,
            isFocusBlocked: isFocusBlocked,
            routeCanvasLeadingInset: routeCanvasLeadingInset,
            providerWidth: providerWidth,
            providerPlacement: providerPlacement,
            onSend: onSend)
    }

    private var workspaceFooter: some View {
        VStack(spacing: 0) {
            WorkspaceSignalView(
                presentation: .workspace(generatingCount: generatingCount),
                compactionPhase: .none,
                onRevealComplete: { _ in })
                .frame(height: 32)
                .padding(.top, -12)
            Text(WorkspaceSignalPresentation.workspace(generatingCount: generatingCount).label)
                .font(TenXTypography.body(size: 10, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .frame(height: 42)
        }
    }

    private var generatingCount: Int {
        model.generatingSessionCount
    }

    private func addExistingFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.chooseProject(url)
    }
}

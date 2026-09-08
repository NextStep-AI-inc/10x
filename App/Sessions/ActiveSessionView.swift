import SwiftUI

struct ActiveSessionView: View {
    let controller: SessionController
    var controls: ComposerControlsModel?
    var commands: ComposerCommandModel?
    var onReviewPrompt: (() -> Void)? = nil

    @State private var flyout: ComposerFlyout?

    var body: some View {
        VStack(spacing: 0) {
            SessionHeaderView(controller: controller)

            TranscriptView(controller: controller)
                .id(controller.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if controller.isRecoveryPresented,
               case .stopped(let code, _) = controller.runtimeState {
                RuntimeRecoveryView(
                    exitCode: code,
                    onRestart: { Task { await controller.restart() } },
                    onOpenLog: controller.openLog,
                    onDismiss: controller.dismissRecovery)
                .frame(maxWidth: 780)
                .padding(.horizontal, 42)
                .padding(.bottom, 16)
            }

            if controller.sessionPath == nil, case .stopped = controller.runtimeState,
               !controller.draft.isEmpty, let onReviewPrompt {
                Button("Review stopped prompt", action: onReviewPrompt)
                    .buttonStyle(GhostActionStyle())
                    .padding(.bottom, 12)
            }

            if controller.isRecoveryPresented, case .failed = controller.runtimeState {
                RuntimeRecoveryView(exitCode: nil,
                    onRestart: { Task { await controller.restart() } },
                    onOpenLog: controller.openLog, onDismiss: controller.dismissRecovery,
                    failureDescription: controller.sessionPath == nil
                        ? "The session could not start. Review your preserved prompt before trying again."
                        : "The session command could not finish. Check the log before retrying; delivery may be unconfirmed.",
                    canRestart: controller.sessionPath != nil,
                    onReviewPrompt: controller.sessionPath == nil ? onReviewPrompt : nil)
                    .frame(maxWidth: 780)
                    .padding(.horizontal, 42)
                    .padding(.bottom, 16)
            }

            ComposerView(
                draft: Bindable(controller).draft,
                attachments: Bindable(controller).attachments,
                flyout: $flyout,
                presentation: .active(controller: controller),
                controls: controls,
                commands: commands,
                controlsMode: .activeSession,
                onSend: {
                    Task { await controller.sendPrompt() }
                })
            .frame(maxWidth: 780)
            .padding(.horizontal, 42)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // This view keeps its identity across session switches, so the shelf
        // would otherwise stay open over a transcript it no longer belongs to.
        .onChange(of: controller.id) { _, _ in flyout = nil }
        .environment(\.fileReferenceBaseURL, controller.projectURL)
        .sheet(isPresented: logBinding) {
            ScrollView {
                Text(controller.logText)
                    .font(TenXTypography.mono(size: 11))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
            .frame(minWidth: 620, minHeight: 360)
        }
        .onExitCommand { flyout = nil }
    }

    private var logBinding: Binding<Bool> {
        Binding(
            get: { controller.isLogPresented },
            set: { isPresented in
                if !isPresented { controller.dismissLog() }
            })
    }
}

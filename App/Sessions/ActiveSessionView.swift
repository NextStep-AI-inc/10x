import SwiftUI

struct ActiveSessionView: View {
    let controller: SessionController
    var controls: ComposerControlsModel?

    @State private var flyout: ComposerFlyout?

    var body: some View {
        ZStack {
            if flyout != nil {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { flyout = nil }
            }

            VStack(spacing: 0) {
                SessionHeaderView(controller: controller)

                TranscriptView(controller: controller)
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

                ComposerView(
                    draft: Bindable(controller).draft,
                    flyout: $flyout,
                    presentation: .active(controller: controller),
                    controls: controls,
                    controlsMode: .activeSession,
                    onSend: {
                        Task { await controller.sendPrompt() }
                    })
                .frame(maxWidth: 780)
                .padding(.horizontal, 42)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(1)
        }
        .environment(\.fileReferenceBaseURL, controller.projectURL)
        .sheet(item: extensionSheetBinding) { request in
            ExtensionInputSheet(
                request: request,
                onSubmit: { value in
                    Task { await controller.respond(to: request, with: .value(value)) }
                },
                onCancel: {
                    Task {
                        await controller.respond(
                            to: request,
                            with: .cancelled(timedOut: false))
                    }
                })
        }
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

    private var extensionSheetBinding: Binding<ExtensionUIState?> {
        Binding(
            get: { controller.extensionSheetRequest },
            set: { state in
                guard state == nil, let request = controller.extensionSheetRequest else { return }
                Task {
                    await controller.respond(
                        to: request,
                        with: .cancelled(timedOut: false))
                }
            })
    }

    private var logBinding: Binding<Bool> {
        Binding(
            get: { controller.isLogPresented },
            set: { isPresented in
                if !isPresented { controller.dismissLog() }
            })
    }
}

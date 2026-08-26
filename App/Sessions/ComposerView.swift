import OmpKit
import SwiftUI

enum ComposerPresentation {
    case newSession(
        projectURL: URL?,
        projectURLs: [URL],
        onChooseProject: (URL) -> Void,
        onAddExistingFolder: () -> Void)
    case active(controller: SessionController)
}

struct ComposerView: View {
    @Binding var draft: String
    @Binding var isProjectFlyoutPresented: Bool
    let presentation: ComposerPresentation
    let controls: ComposerControlsModel?
    let controlsMode: ComposerControlsMode
    let onSend: () -> Void

    init(
        draft: Binding<String>,
        isProjectFlyoutPresented: Binding<Bool> = .constant(false),
        presentation: ComposerPresentation,
        controls: ComposerControlsModel? = nil,
        controlsMode: ComposerControlsMode = .newSession,
        onSend: @escaping () -> Void
    ) {
        _draft = draft
        _isProjectFlyoutPresented = isProjectFlyoutPresented
        self.presentation = presentation
        self.controls = controls
        self.controlsMode = controlsMode
        self.onSend = onSend
    }

    private var canSend: Bool {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        switch presentation {
        case .newSession(let projectURL, _, _, _):
            return projectURL != nil
        case .active(let controller):
            return controller.isComposerAvailable
        }
    }

    var body: some View {
        composerCard
            .onExitCommand {
                isProjectFlyoutPresented = false
            }
    }

    private var composerCard: some View {
        VStack(spacing: 0) {
            TextEditor(text: $draft)
                .font(TenXTypography.body(size: 14))
                .scrollContentBackground(.hidden)
                .padding(16)
                .frame(height: 58)
                .disabled(!isAvailable)
                .accessibilityLabel("Session prompt")
                .accessibilityHint(composerModeLabel)

            HStack(spacing: 4) {
                footerControls

                Spacer()

                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(canSend
                            ? TenXPalette.color(TenXPalette.nearBlackHex)
                            : TenXPalette.color(TenXPalette.separatorHex))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel(sendLabel)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .zIndex(isProjectFlyoutPresented ? 1 : 0)

            if let errorMessage = controls?.errorMessage {
                Text(errorMessage)
                    .font(TenXTypography.body(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .background(.white)
        .overlay {
            Rectangle()
                .stroke(borderColor, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var footerControls: some View {
        switch presentation {
        case .newSession(let projectURL, let projectURLs, let onChooseProject, let onAddExistingFolder):
            ChooseProjectControl(
                projectURL: projectURL,
                projectURLs: projectURLs,
                onChoose: onChooseProject,
                onAddExistingFolder: onAddExistingFolder,
                isPresented: $isProjectFlyoutPresented)

            Button("Local") {}
                .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.nearBlackHex)))

            if let controls {
                ComposerSessionControlsView(model: controls, mode: controlsMode)
            }

        case .active(let controller):
            if controller.runtimeState == .streaming {
                behaviorButton("Steer", behavior: .steer, controller: controller)
                behaviorButton("Follow up", behavior: .followUp, controller: controller)
            }
            if let controls {
                ComposerSessionControlsView(model: controls, mode: controlsMode)
            } else {
                Text(controller.modelName)
                    .font(TenXTypography.body(size: 10, weight: .medium))
                Text(controller.thinkingLevel)
                    .font(TenXTypography.body(size: 10, weight: .medium))
            }
            if controller.queuedMessageCount > 0 {
                Text("\(controller.queuedMessageCount) queued")
                    .font(TenXTypography.body(size: 10, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
            }
        }
    }

    private func behaviorButton(
        _ title: String,
        behavior: StreamingBehavior,
        controller: SessionController
    ) -> some View {
        Button(title) {
            controller.selectStreamingBehavior(behavior)
        }
        .buttonStyle(GhostActionStyle(color: behaviorColor(behavior, controller: controller)))
        .accessibilityLabel("Composer mode, \(title)")
        .accessibilityValue(controller.streamingBehavior == behavior ? "Selected" : "Not selected")
    }

    private func behaviorColor(
        _ behavior: StreamingBehavior,
        controller: SessionController
    ) -> Color {
        let isSelected: Bool
        switch (behavior, controller.streamingBehavior) {
        case (.steer, .steer?), (.followUp, .followUp?):
            isSelected = true
        default:
            isSelected = false
        }
        return TenXPalette.color(isSelected ? TenXPalette.cyanHex : TenXPalette.nearBlackHex)
    }

    private var isAvailable: Bool {
        switch presentation {
        case .newSession:
            return true
        case .active(let controller):
            return controller.isComposerAvailable
        }
    }

    private var sendLabel: String {
        switch presentation {
        case .newSession: return "Start session"
        case .active: return "Send message"
        }
    }

    private var composerModeLabel: String {
        switch presentation {
        case .newSession:
            return "New session prompt"
        case .active(let controller) where controller.runtimeState == .streaming:
            let mode = controller.streamingBehavior == .followUp ? "Follow up" : "Steer"
            return "Active session prompt, \(mode) mode"
        case .active:
            return "Active session prompt"
        }
    }

    private var borderColor: Color {
        guard isAvailable else { return TenXPalette.color(TenXPalette.separatorHex) }
        return TenXPalette.color(TenXPalette.nearBlackHex)
    }
}

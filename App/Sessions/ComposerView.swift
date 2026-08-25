import OmpKit
import SwiftUI

enum ComposerPresentation {
    case newSession(projectURL: URL?, onChooseProject: () -> Void)
    case active(controller: SessionController)
}

struct ComposerView: View {
    @Binding var draft: String
    let presentation: ComposerPresentation
    let onSend: () -> Void

    private var canSend: Bool {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        switch presentation {
        case .newSession(let projectURL, _):
            return projectURL != nil
        case .active(let controller):
            return controller.isComposerAvailable
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $draft)
                .font(TenXTypography.body(size: 14))
                .scrollContentBackground(.hidden)
                .padding(16)
                .frame(height: 58)
                .disabled(!isAvailable)
                .accessibilityLabel("Session prompt")

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
        case .newSession(let projectURL, let onChooseProject):
            Button(action: onChooseProject) {
                Label(projectURL?.lastPathComponent ?? "Choose project", systemImage: "folder")
            }
            .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.cyanHex)))

            Button("Local") {}
                .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.nearBlackHex)))
            Button("GPT-5.6") {}
                .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.nearBlackHex)))
            Button("High") {}
                .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.nearBlackHex)))

        case .active(let controller):
            if controller.runtimeState == .streaming {
                behaviorButton("Steer", behavior: .steer, controller: controller)
                behaviorButton("Follow up", behavior: .followUp, controller: controller)
            }
            Text(controller.modelName)
                .font(TenXTypography.body(size: 10, weight: .medium))
            Text(controller.thinkingLevel)
                .font(TenXTypography.body(size: 10, weight: .medium))
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

    private var borderColor: Color {
        guard isAvailable else { return TenXPalette.color(TenXPalette.separatorHex) }
        return TenXPalette.color(TenXPalette.nearBlackHex)
    }
}

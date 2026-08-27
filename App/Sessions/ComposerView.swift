import OmpKit
import SwiftUI

enum ComposerFlyout: Equatable {
    case project
    case model
}

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
    @Binding var flyout: ComposerFlyout?
    let presentation: ComposerPresentation
    let controls: ComposerControlsModel?
    let controlsMode: ComposerControlsMode
    let onSend: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isEditorFocused: Bool
    static let editorPadding: CGFloat = 16
    /// SwiftUI's padding plus the line-fragment padding NSTextView adds inside it.
    static let textInset: CGFloat = 21
    static let minEditorHeight: CGFloat = 58
    static let maxEditorHeight: CGFloat = 220

    init(
        draft: Binding<String>,
        flyout: Binding<ComposerFlyout?> = .constant(nil),
        presentation: ComposerPresentation,
        controls: ComposerControlsModel? = nil,
        controlsMode: ComposerControlsMode = .newSession,
        onSend: @escaping () -> Void
    ) {
        _draft = draft
        _flyout = flyout
        self.presentation = presentation
        self.controls = controls
        self.controlsMode = controlsMode
        self.onSend = onSend
    }

    /// Plain Return sends (or is swallowed while sending is unavailable);
    /// Shift/Option/Command/Control+Return fall through to the text view.
    nonisolated static func handleReturn(
        modifiers: EventModifiers,
        canSend: Bool,
        send: () -> Void
    ) -> KeyPress.Result {
        guard modifiers.isDisjoint(with: [.shift, .option, .command, .control]) else {
            return .ignored
        }
        if canSend { send() }
        return .handled
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
            .animation(shelfAnimation, value: flyout)
            .onExitCommand {
                flyout = nil
            }
            // The composer is the only thing to type into on either screen, so
            // it takes focus as soon as it can accept a keystroke.
            .onAppear { isEditorFocused = isAvailable }
            .onChange(of: isAvailable) { _, isAvailable in
                if isAvailable { isEditorFocused = true }
            }
    }

    private var shelfAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.16)
    }

    private var composerCard: some View {
        VStack(spacing: 0) {
            editor

            HStack(spacing: 4) {
                footerControls

                Spacer()

                primaryAction
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

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
        // Fill and border live in one background layer: an overlay border would
        // paint over card content, and the model flyout is card content.
        .background {
            Rectangle()
                .fill(.white)
                .overlay {
                    Rectangle()
                        .stroke(borderColor, lineWidth: 1)
                }
        }
        .overlay(alignment: .bottomLeading) {
            projectShelfOverlay
        }
    }

    @ViewBuilder
    private var projectShelfOverlay: some View {
        if flyout == .project,
           case .newSession(
            let projectURL,
            let projectURLs,
            let onChooseProject,
            let onAddExistingFolder
           ) = presentation {
            ChooseProjectShelf(
                projectURLs: projectURLs,
                selectedProjectURL: projectURL,
                triggerTitle: projectURL?.lastPathComponent ?? "Choose project",
                onChoose: {
                    onChooseProject($0)
                    flyout = nil
                },
                onAddExistingFolder: {
                    flyout = nil
                    onAddExistingFolder()
                },
                onToggle: {
                    flyout = nil
                })
            .padding(.leading, 10)
            .padding(.bottom, 10)
            .transition(shelfTransition)
        }
    }

    private var shelfTransition: AnyTransition {
        if reduceMotion { return .identity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity.combined(with: .offset(y: 4)))
    }

    /// Grows with the draft instead of scrolling a fixed two-line window, so a
    /// paragraph-length prompt stays readable while it is being written.
    private var editor: some View {
        // A hidden copy of the draft is the only thing in this stack with an
        // intrinsic height, and the editor rides above it as an overlay so it
        // cannot push the box taller. Sizing therefore lands in the same layout
        // pass that draws the text, with no measure-then-resize frame.
        Text(draft.isEmpty || draft.hasSuffix("\n") ? draft + " " : draft)
            .font(TenXTypography.body(size: 14))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Self.textInset)
            .padding(.vertical, Self.editorPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .hidden()
            .overlay(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(placeholder)
                        .font(TenXTypography.body(size: 14))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .padding(.horizontal, Self.textInset)
                        .padding(.vertical, Self.editorPadding)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                TextEditor(text: $draft)
                    .font(TenXTypography.body(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(Self.editorPadding)
                    .focused($isEditorFocused)
                    .disabled(!isAvailable)
                    .onKeyPress(keys: [.return], phases: .down) { press in
                        Self.handleReturn(
                            modifiers: press.modifiers,
                            canSend: canSend,
                            send: onSend)
                    }
                    .accessibilityLabel("Session prompt")
                    .accessibilityHint(composerModeLabel)
            }
            .frame(minHeight: Self.minEditorHeight, maxHeight: Self.maxEditorHeight)
            // Without this the clamp is a range the parent can fill, and any
            // spare vertical space in the window inflates the box to its cap.
            .fixedSize(horizontal: false, vertical: true)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: draft)
    }

    private var placeholder: String {
        switch presentation {
        case .newSession:
            return "Describe the task"
        case .active(let controller) where controller.runtimeState == .streaming:
            return "Steer or follow up"
        case .active:
            return "Send a message"
        }
    }

    /// One button, because there is only ever one obvious next move: send what
    /// is typed, or stop the run there is nothing to add to.
    private var primaryAction: some View {
        let isStop = stoppableController != nil
        let isEnabled = isStop || canSend
        return Button {
            if let controller = stoppableController {
                Task { await controller.abort() }
            } else {
                onSend()
            }
            isEditorFocused = true
        } label: {
            Group {
                if isStop {
                    // A square, not stop.fill: the symbol's rounded corners are
                    // the only radius in a composer built from straight edges.
                    Rectangle().frame(width: 9, height: 9)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                }
            }
                .foregroundStyle(isEnabled
                    ? Color.white
                    : TenXPalette.color(TenXPalette.mutedTextHex))
                .frame(width: 28, height: 28)
                .background(isEnabled
                    ? TenXPalette.color(TenXPalette.nearBlackHex)
                    : TenXPalette.color(TenXPalette.hoverNeutralHex))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(isStop ? "Stop the response" : sendLabel)
        .accessibilityLabel(isStop ? "Stop response" : sendLabel)
    }

    /// Stop takes over only when there is no draft to send: with text in the
    /// box the button still has to send it, or Steer and Follow up are dead.
    private var stoppableController: SessionController? {
        guard case .active(let controller) = presentation,
              controller.runtimeState == .streaming,
              draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return controller
    }

    @ViewBuilder
    private var footerControls: some View {
        switch presentation {
        case .newSession(let projectURL, _, _, _):
            ChooseProjectControl(
                projectURL: projectURL,
                isPresented: Binding(
                    get: { flyout == .project },
                    set: { flyout = $0 ? .project : nil }))

            if let controls {
                ComposerSessionControlsView(
                    model: controls,
                    mode: controlsMode,
                    isPresented: Binding(
                        get: { flyout == .model },
                        set: { flyout = $0 ? .model : nil }))
            }

        case .active(let controller):
            if controller.runtimeState == .streaming {
                behaviorButton("Steer", behavior: .steer, controller: controller)
                behaviorButton("Follow up", behavior: .followUp, controller: controller)
            }
            if let controls {
                ComposerSessionControlsView(
                    model: controls,
                    mode: controlsMode,
                    isPresented: Binding(
                        get: { flyout == .model },
                        set: { flyout = $0 ? .model : nil }))
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

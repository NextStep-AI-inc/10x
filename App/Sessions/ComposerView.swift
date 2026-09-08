import AppKit
import OmpKit
import SwiftUI
import UniformTypeIdentifiers

enum ComposerFlyout: Equatable {
    case project
    case model
    case commands
}

enum ComposerCommandKeyAction: Sendable {
    case move(CommandBrowserMove)
    case cycle(CommandBrowserCycle)
    case sourceIndex(Int)
    case activate
    case complete
    case back
}

extension ComposerCommandKeyAction: Equatable {
    static func == (lhs: ComposerCommandKeyAction, rhs: ComposerCommandKeyAction) -> Bool {
        switch (lhs, rhs) {
        case (.move(.previous), .move(.previous)),
             (.move(.next), .move(.next)),
             (.move(.first), .move(.first)),
             (.move(.last), .move(.last)),
             (.move(.pagePrevious), .move(.pagePrevious)),
             (.move(.pageNext), .move(.pageNext)),
             (.cycle(.forward), .cycle(.forward)),
             (.cycle(.backward), .cycle(.backward)),
             (.activate, .activate),
             (.complete, .complete),
             (.back, .back):
            return true
        case (.sourceIndex(let lhsIndex), .sourceIndex(let rhsIndex)):
            return lhsIndex == rhsIndex
        default:
            return false
        }
    }
}

enum ComposerCommandKeyRouting {
    static let keys: Set<KeyEquivalent> = [
        .upArrow,
        .downArrow,
        .home,
        .end,
        .pageUp,
        .pageDown,
        .tab,
        .return,
        .escape,
        KeyEquivalent("1"),
        KeyEquivalent("2"),
        KeyEquivalent("3"),
        KeyEquivalent("4"),
        KeyEquivalent("5"),
        KeyEquivalent("6"),
        KeyEquivalent("7"),
    ]

    nonisolated static func route(
        _ key: KeyEquivalent,
        modifiers: EventModifiers
    ) -> ComposerCommandKeyAction? {
        let controlShift: EventModifiers = [.control, .shift]
        if key == .tab, modifiers.intersection(controlShift) == controlShift,
           modifiers.intersection([.option, .command]).isEmpty
        {
            return .cycle(.backward)
        }
        if key == .tab, modifiers.intersection([.control]) == [.control],
           modifiers.intersection([.shift, .option, .command]).isEmpty
        {
            return .cycle(.forward)
        }
        if let index = sourceIndex(for: key, modifiers: modifiers) {
            return .sourceIndex(index)
        }
        guard modifiers.intersection([.shift, .option, .command, .control]).isEmpty else {
            return nil
        }
        switch key {
        case .upArrow:
            return .move(.previous)
        case .downArrow:
            return .move(.next)
        case .home:
            return .move(.first)
        case .end:
            return .move(.last)
        case .pageUp:
            return .move(.pagePrevious)
        case .pageDown:
            return .move(.pageNext)
        case .return:
            return .activate
        case .tab:
            return .complete
        case .escape:
            return .back
        default:
            return nil
        }
    }

    private static func sourceIndex(
        for key: KeyEquivalent,
        modifiers: EventModifiers
    ) -> Int? {
        guard modifiers.intersection([.command]) == [.command],
              modifiers.intersection([.shift, .option, .control]).isEmpty
        else { return nil }

        switch key {
        case KeyEquivalent("1"): return 1
        case KeyEquivalent("2"): return 2
        case KeyEquivalent("3"): return 3
        case KeyEquivalent("4"): return 4
        case KeyEquivalent("5"): return 5
        case KeyEquivalent("6"): return 6
        case KeyEquivalent("7"): return 7
        default: return nil
        }
    }
}

enum ComposerCommandActivationAction: Equatable, Sendable {
    case useCommandModel
    case sendUnchangedDraft
}

enum ComposerCommandActivationRouting {
    nonisolated static func action(
        isNewSession: Bool,
        hasVisibleRows: Bool,
        hasSelection: Bool
    ) -> ComposerCommandActivationAction {
        isNewSession && !hasVisibleRows && !hasSelection
            ? .sendUnchangedDraft
            : .useCommandModel
    }
}

enum ComposerCommandFocusRouting {
    nonisolated static func shouldRestoreEditorFocus(
        effect: CommandBrowserEffect,
        isPresented: Bool,
        route: CommandBrowserRoute
    ) -> Bool {
        switch effect {
        case .none:
            return false
        case .keepDraft:
            return !isPresented || route == .root
        case .replaceDraft:
            if case .native = route { return false }
            return true
        case .dismiss, .executed:
            return true
        }
    }
}

enum ComposerCommandSourceSwitchFocusRouting {
    nonisolated static func shouldRestoreEditorFocus(
        didSwitch: Bool,
        previousRoute: CommandBrowserRoute,
        currentRoute: CommandBrowserRoute
    ) -> Bool {
        guard didSwitch, case .native = previousRoute else { return false }
        return currentRoute == .root
    }
}

enum ComposerCommandQueryRouting {
    nonisolated static func query(
        draft: String,
        route: CommandBrowserRoute
    ) -> String {
        if case .native(.model) = route { return "" }
        return CommandBrowserPresentation.parseDraft(draft)?.query ?? ""
    }
}

enum ComposerCommandDismissalAction: Equatable, Sendable {
    case dismissCommands
    case hideFlyoutOnly
}

enum ComposerCommandDismissalRouting {
    nonisolated static func action(for flyout: ComposerFlyout?) -> ComposerCommandDismissalAction {
        flyout == .commands ? .dismissCommands : .hideFlyoutOnly
    }
}

enum ComposerReturnRouting {
    nonisolated static func shortcut(for modifiers: EventModifiers) -> ComposerReturnShortcut? {
        let relevant = modifiers.intersection([.shift, .option, .command, .control])
        return switch relevant {
        case []: .enter
        case [.command]: .commandEnter
        case [.shift]: .shiftEnter
        default: nil
        }
    }

    nonisolated static func behavior(
        for action: ComposerReturnAction,
        primary: StreamingBehavior
    ) -> StreamingBehavior? {
        switch action {
        case .primary:
            primary
        case .alternate:
            primary == .steer ? .followUp : .steer
        case .newline:
            nil
        }
    }
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
    @Binding var attachments: [ComposerAttachment]
    @Binding var flyout: ComposerFlyout?
    let presentation: ComposerPresentation
    let controls: ComposerControlsModel?
    let commands: ComposerCommandModel?
    let controlsMode: ComposerControlsMode
    let focusRequest: Int
    let interactionPreferences: ComposerInteractionPreferences
    let onSend: () -> Void

    @Environment(\.composerProviderDockWidth) private var providerDockWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isEditorFocused: Bool
    @State private var attachmentMessage: String?
    @State private var commandQuery = ""
    @State private var suppressedCommandDraft: String?
    @State private var isDropTargeted = false
    static let editorPadding: CGFloat = 16
    /// SwiftUI's padding plus the line-fragment padding NSTextView adds inside it.
    static let textInset: CGFloat = 21
    static let minEditorHeight: CGFloat = 58
    static let maxEditorHeight: CGFloat = 220

    init(
        draft: Binding<String>,
        attachments: Binding<[ComposerAttachment]> = .constant([]),
        flyout: Binding<ComposerFlyout?> = .constant(nil),
        presentation: ComposerPresentation,
        controls: ComposerControlsModel? = nil,
        commands: ComposerCommandModel? = nil,
        controlsMode: ComposerControlsMode = .newSession,
        focusRequest: Int = 0,
        interactionPreferences: ComposerInteractionPreferences = .shared,
        onSend: @escaping () -> Void
    ) {
        _draft = draft
        _attachments = attachments
        _flyout = flyout
        self.presentation = presentation
        self.controls = controls
        self.commands = commands
        self.controlsMode = controlsMode
        self.focusRequest = focusRequest
        self.interactionPreferences = interactionPreferences
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
        let hasContent = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
        guard hasContent else { return false }
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
                switch ComposerCommandDismissalRouting.action(for: flyout) {
                case .dismissCommands:
                    dismissCommands()
                case .hideFlyoutOnly:
                    flyout = nil
                }
            }
            // The composer is the only thing to type into on either screen, so
            // it takes focus as soon as it can accept a keystroke.
            .task(id: focusRequest) {
                await Task.yield()
                guard !Task.isCancelled else { return }
                isEditorFocused = isAvailable
            }
            .onChange(of: isAvailable) { _, isAvailable in
                if isAvailable {
                    isEditorFocused = true
                    observeDraftForCommands(draft)
                } else {
                    dismissCommands()
                }
            }
            .onChange(of: draft) { _, draft in
                observeDraftForCommands(draft)
            }
    }

    private var shelfAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.16)
    }

    private var composerCard: some View {
        VStack(spacing: 0) {
            editor

            if !attachments.isEmpty {
                ComposerAttachmentsView(attachments: attachments, onRemove: remove)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    attachButton
                    footerControls.fixedSize()
                    Spacer(minLength: 8)
                    actionControls
                }
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        attachButton
                        footerControls
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 4) {
                        Spacer(minLength: 0)
                        actionControls
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            if let errorMessage = attachmentMessage ?? controls?.errorMessage {
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
                .fill(TenXPalette.surfaceElevated)
                .overlay {
                    Rectangle()
                        .stroke(borderColor, lineWidth: 1)
                }
        }
        .overlay(alignment: .bottomLeading) {
            projectShelfOverlay
        }
        .overlay(alignment: .topLeading) {
            commandBrowserOverlay
        }
        .overlay {
            if isDropTargeted {
                Rectangle()
                    .stroke(TenXPalette.color(TenXPalette.cyanHex), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            add(urls: urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        // Concrete image types only. Plain and rich text never carry these, so
        // an ordinary paste still reaches the editor.
        .onPasteCommand(of: [.png, .jpeg, .tiff]) { providers in
            add(providers: providers)
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

    @ViewBuilder
    private var commandBrowserOverlay: some View {
        if flyout == .commands, let commands, let controls {
            CommandBrowserView(
                model: commands,
                controls: controls,
                query: $commandQuery,
                onEffect: applyCommandEffect,
                onDismiss: dismissCommands,
                restoreEditorFocus: restoreEditorFocus)
            .background {
                CommandBrowserKeyboardMonitor(route: commands.route) { action in
                    handleCommandKeyAction(action, model: commands)
                    return true
                }
            }
            .frame(height: CommandBrowserMetrics.maximumHeight)
            .offset(y: -CommandBrowserMetrics.maximumHeight)
            .transition(shelfTransition)
            .zIndex(2)
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
                    .onKeyPress(keys: ComposerCommandKeyRouting.keys, phases: .down, action: handleEditorKey)
                    .accessibilityLabel("Session prompt")
                    .accessibilityHint(composerModeLabel)
                    .background(ComposerTextViewConfigurator())
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

    private var attachButton: some View {
        Button(action: chooseAttachments) {
            Image(systemName: "paperclip")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .help("Attach an image. Images can also be dropped or pasted here.")
        .accessibilityLabel("Attach an image")
    }

    private func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        panel.prompt = "Attach"

        guard panel.runModal() == .OK else { return }
        add(urls: panel.urls)
        isEditorFocused = true
    }

    private func remove(_ id: ComposerAttachment.ID) {
        attachments.removeAll { $0.id == id }
        attachmentMessage = nil
    }

    private func observeDraftForCommands(_ draft: String) {
        if suppressedCommandDraft == draft {
            suppressedCommandDraft = nil
            syncCommandQuery()
            return
        }
        guard isAvailable, let commands else {
            if flyout == .commands { flyout = nil }
            commandQuery = ""
            return
        }
        if commands.updateDraft(draft) {
            flyout = .commands
            syncCommandQuery()
        } else if flyout == .commands {
            flyout = nil
            commandQuery = ""
        }
    }

    private func handleEditorKey(_ press: KeyPress) -> KeyPress.Result {
        if flyout == .commands, let commands, commands.isPresented {
            if let commandAction = ComposerCommandKeyRouting.route(
                press.key,
                modifiers: press.modifiers
            ) {
                guard CommandBrowserKeyboardCapturePolicy.shouldCapture(
                    commandAction,
                    route: commands.route
                ) else { return .ignored }
                handleCommandKeyAction(commandAction, model: commands)
                return .handled
            }
        }

        guard press.key == .return else { return .ignored }
        guard let shortcut = ComposerReturnRouting.shortcut(for: press.modifiers) else {
            return .ignored
        }
        let action = interactionPreferences.action(for: shortcut)
        guard action != .newline else { return .ignored }
        if canSend { submit(action) }
        return .handled
    }

    private func handleCommandKeyAction(
        _ action: ComposerCommandKeyAction,
        model: ComposerCommandModel
    ) {
        switch action {
        case .move(let move):
            if case .subcommands = model.route {
                model.moveSubcommandSelection(move)
            } else {
                model.moveSelection(move)
            }
        case .cycle(let cycle):
            let previousRoute = model.route
            let didSwitch = model.cycleSource(cycle)
            if didSwitch {
                syncCommandQuery()
                if ComposerCommandSourceSwitchFocusRouting.shouldRestoreEditorFocus(
                    didSwitch: didSwitch,
                    previousRoute: previousRoute,
                    currentRoute: model.route)
                {
                    restoreEditorFocus()
                }
            }
        case .sourceIndex(let index):
            let previousRoute = model.route
            let didSwitch = model.selectVisibleSource(at: index)
            if didSwitch {
                syncCommandQuery()
                if ComposerCommandSourceSwitchFocusRouting.shouldRestoreEditorFocus(
                    didSwitch: didSwitch,
                    previousRoute: previousRoute,
                    currentRoute: model.route)
                {
                    restoreEditorFocus()
                }
            }
        case .activate:
            if Self.commandActivationAction(
                presentation: presentation,
                model: model) == .sendUnchangedDraft
            {
                onSend()
                dismissCommands()
                return
            }
            Task {
                let effect = await model.activate(attachments: attachments)
                applyCommandEffect(effect)
            }
        case .complete:
            applyCommandEffect(model.complete())
        case .back:
            applyCommandEffect(model.back())
        }
    }

    private func applyCommandEffect(_ effect: CommandBrowserEffect) {
        switch effect {
        case .none, .keepDraft:
            break
        case .dismiss:
            flyout = nil
            commandQuery = ""
        case .replaceDraft(let text):
            suppressedCommandDraft = text
            draft = text
            if commands?.isPresented == false {
                flyout = nil
                commandQuery = ""
            }
        case .executed:
            if case .newSession = presentation {
                draft = ""
                attachments = []
            }
            flyout = nil
            commandQuery = ""
        }
        syncCommandQuery()
        if ComposerCommandFocusRouting.shouldRestoreEditorFocus(
            effect: effect,
            isPresented: commands?.isPresented ?? false,
            route: commands?.route ?? .root)
        {
            restoreEditorFocus()
        }
    }

    private func dismissCommands() {
        _ = commands?.dismiss()
        if flyout == .commands { flyout = nil }
        commandQuery = ""
        restoreEditorFocus()
    }

    private func restoreEditorFocus() {
        isEditorFocused = isAvailable
    }

    private func syncCommandQuery() {
        commandQuery = ComposerCommandQueryRouting.query(
            draft: draft,
            route: commands?.route ?? .root)
    }

    private static func commandActivationAction(
        presentation: ComposerPresentation,
        model: ComposerCommandModel
    ) -> ComposerCommandActivationAction {
        let isNewSession: Bool
        switch presentation {
        case .newSession:
            isNewSession = true
        case .active:
            isNewSession = false
        }
        return ComposerCommandActivationRouting.action(
            isNewSession: isNewSession,
            hasVisibleRows: !model.visibleRows.isEmpty,
            hasSelection: model.selectedRowID != nil)
    }

    /// Images are staged; anything else becomes a path in the message, which is
    /// what the agent can actually act on.
    private func add(urls: [URL]) {
        var skipped: [String] = []
        var paths: [String] = []
        for url in urls {
            guard ComposerAttachmentEncoder.isImage(url) else {
                paths.append(url.path)
                continue
            }
            guard attachments.count < ComposerAttachmentEncoder.maximumCount else {
                skipped.append(url.lastPathComponent)
                continue
            }
            guard let attachment = ComposerAttachmentEncoder.attachment(fromFileAt: url) else {
                skipped.append(url.lastPathComponent)
                continue
            }
            attachments.append(attachment)
        }
        if !paths.isEmpty { appendToDraft(paths.joined(separator: "\n")) }
        report(skipped: skipped)
    }

    private func add(providers: [NSItemProvider]) {
        guard attachments.count < ComposerAttachmentEncoder.maximumCount else {
            report(skipped: ["Pasted image"])
            return
        }
        for provider in providers {
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else { return }
                Task { @MainActor in
                    guard attachments.count < ComposerAttachmentEncoder.maximumCount,
                          let attachment = ComposerAttachmentEncoder.attachment(
                            from: image,
                            name: "Pasted image")
                    else { return }
                    attachments.append(attachment)
                    attachmentMessage = nil
                }
            }
        }
    }

    private func appendToDraft(_ text: String) {
        if draft.isEmpty {
            draft = text
        } else if draft.hasSuffix("\n") {
            draft += text
        } else {
            draft += "\n" + text
        }
    }

    private func report(skipped: [String]) {
        guard !skipped.isEmpty else {
            attachmentMessage = nil
            return
        }
        let limit = ComposerAttachmentEncoder.maximumCount
        attachmentMessage = skipped.count == 1
            ? "Could not attach \(skipped[0]). The limit is \(limit) images."
            : "Could not attach \(skipped.count) images. The limit is \(limit)."
    }

    @ViewBuilder
    private var actionControls: some View {
        if let controller = streamingController {
            providerDockSlot
            behaviorMenu(controller)
            sendButton
            stopButton(controller)
        } else {
            providerDockSlot
            sendButton
            if case .active(let controller) = presentation, controller.runtimeState == .loading {
                stopButton(controller)
            }
        }
    }

    @ViewBuilder
    private var providerDockSlot: some View {
        if providerDockWidth > 0 {
            Color.clear
                .frame(width: providerDockWidth, height: ProviderAccountStackGeometry.minimumHitTarget)
                .anchorPreference(key: ComposerProviderDockAnchorKey.self, value: .bounds) { $0 }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var sendButton: some View {
        Button {
            submit(.primary)
            isEditorFocused = true
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(canSend
                    ? TenXPalette.onEmphasis
                    : TenXPalette.color(TenXPalette.mutedTextHex))
                .frame(width: 28, height: 28)
                .background(canSend
                    ? TenXPalette.color(TenXPalette.nearBlackHex)
                    : TenXPalette.color(TenXPalette.hoverNeutralHex))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .help(sendLabel)
        .accessibilityLabel(sendLabel)
    }

    private func stopButton(_ controller: SessionController) -> some View {
        Button {
            Task { await controller.abort() }
            isEditorFocused = true
        } label: {
            Rectangle()
                .frame(width: 9, height: 9)
                .foregroundStyle(TenXPalette.onEmphasis)
                .frame(width: 28, height: 28)
                .background(TenXPalette.color(TenXPalette.nearBlackHex))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Stop the response")
        .accessibilityLabel("Stop response")
    }

    private func behaviorMenu(_ controller: SessionController) -> some View {
        Menu {
            Button("Steer") { controller.selectStreamingBehavior(.steer) }
            Button("Follow up") { controller.selectStreamingBehavior(.followUp) }
        } label: {
            Text(controller.streamingBehavior == .followUp ? "Follow up" : "Steer")
                .font(TenXTypography.body(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Composer send action")
        .accessibilityValue(controller.streamingBehavior == .followUp ? "Follow up" : "Steer")
    }

    private var streamingController: SessionController? {
        guard case .active(let controller) = presentation,
              controller.runtimeState == .streaming
        else { return nil }
        return controller
    }

    private func submit(_ action: ComposerReturnAction) {
        attachmentMessage = nil
        switch presentation {
        case .newSession:
            onSend()
        case .active(let controller):
            let defaultPrimary: StreamingBehavior = interactionPreferences.defaultSendAction == .steer
                ? .steer
                : .followUp
            let primary = controller.streamingBehavior ?? defaultPrimary
            let behavior = ComposerReturnRouting.behavior(for: action, primary: primary)
            Task { await controller.sendPrompt(behaviorOverride: behavior) }
        }
    }

    @ViewBuilder
    private var footerControls: some View {
        switch presentation {
        case .newSession(let projectURL, _, _, _):
            ChooseProjectControl(
                projectURL: projectURL,
                isPresented: Binding(
                    get: { flyout == .project },
                    set: { setFlyout($0 ? .project : nil) }))

            if let controls {
                ComposerSessionControlsView(
                    model: controls,
                    mode: controlsMode,
                    isPresented: Binding(
                        get: { flyout == .model },
                        set: { setFlyout($0 ? .model : nil) }))
            }

        case .active(let controller):
            if let controls {
                ComposerSessionControlsView(
                    model: controls,
                    mode: controlsMode,
                    isPresented: Binding(
                        get: { flyout == .model },
                        set: { setFlyout($0 ? .model : nil) }))
            } else {
                Text(controller.modelName)
                    .font(TenXTypography.body(size: 10, weight: .medium))
                Text(controller.thinkingLevel)
                    .font(TenXTypography.body(size: 10, weight: .medium))
            }
            ContextUsageControl(
                usage: controller.contextUsage,
                breakdown: controller.contextBreakdown,
                isLoading: controller.isContextLoading,
                errorMessage: controller.contextErrorMessage,
                onRefresh: { await controller.refreshContextDetails() })
            if controller.queuedMessageCount > 0 {
                Text("\(controller.queuedMessageCount) queued")
                    .font(TenXTypography.body(size: 10, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
            }
        }
    }

    private func setFlyout(_ next: ComposerFlyout?) {
        if next == .project || next == .model {
            _ = commands?.dismiss()
            commandQuery = ""
        }
        flyout = next
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

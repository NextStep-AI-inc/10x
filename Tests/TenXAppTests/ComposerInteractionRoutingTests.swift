import AppKit
import OmpKit
import Observation
import SwiftUI
import Testing
@testable import TenXApp

@MainActor
@Observable
private final class ComposerDraftProbe {
    var text = "BEFORE | AFTER"
}

@MainActor
@Test func fileInsertionUpdatesTheSwiftUIEditorBinding() async throws {
    let draft = ComposerDraftProbe()
    let bridge = ComposerTextEditorBridge()
    let editor = Text(draft.text).hidden().overlay {
        TextEditor(text: Bindable(draft).text)
            .padding(16)
            .onKeyPress(keys: ComposerCommandKeyRouting.keys, phases: .down) { _ in .handled }
            .background(ComposerTextViewConfigurator(bridge: bridge))
    }
    let host = NSHostingView(rootView: editor)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 200),
                          styleMask: [], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(50))

    func textViews(in view: NSView) -> [NSTextView] {
        if let textView = view as? NSTextView { return [textView] }
        return view.subviews.flatMap { textViews(in: $0) }
    }
    let textView = try #require(textViews(in: host).first)
    textView.setSelectedRange(NSRange(location: 9, length: 0))

    #expect(bridge.insertFilePaths(["/tmp/selected file.txt"]))
    try await Task.sleep(for: .milliseconds(50))
    #expect(draft.text == "BEFORE | \n/tmp/selected file.txt\nAFTER")
    #expect(textView.string == draft.text)
}

@MainActor
@Test func composerEditorInsertsLongFilePathsAtTheCurrentSelectionAndSupportsUndo() throws {
    let bridge = ComposerTextEditorBridge()
    let marker = ComposerTextViewConfigurationMarker(bridge: bridge)
    let textView = NSTextView()
    textView.allowsUndo = true
    textView.string = "Review this next"
    textView.setSelectedRange(NSRange(location: 11, length: 0))
    let container = NSView()
    container.addSubview(textView)
    container.addSubview(marker)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                          styleMask: [], backing: .buffered, defer: false)
    window.contentView = container
    bridge.connect(textView, owner: marker)

    let path = "/tmp/A project with spaces/Sources/An unusually long filename.swift"
    #expect(bridge.insertFilePaths([path]))
    #expect(textView.string == "Review this\n\(path)\n next")
    #expect(textView.selectedRange() == NSRange(location: 13 + path.utf16.count, length: 0))

    let undoManager = try #require(textView.undoManager)
    undoManager.undo()
    #expect(textView.string == "Review this next")
}

@MainActor
@Test func composerEditorRejectsAnEditorAfterItsMarkerLeavesTheView() {
    let bridge = ComposerTextEditorBridge()
    let marker = ComposerTextViewConfigurationMarker(bridge: bridge)
    let textView = NSTextView()
    textView.string = "Keep this"
    let container = NSView()
    container.addSubview(textView)
    container.addSubview(marker)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                          styleMask: [], backing: .buffered, defer: false)
    window.contentView = container
    bridge.connect(textView, owner: marker)

    marker.removeFromSuperview()

    #expect(!bridge.insertFilePaths(["/tmp/other.swift"]))
    #expect(textView.string == "Keep this")
}

@MainActor
@Test func markedTextReturnCommitsCompositionBeforeAnOrdinaryReturnRoutes() {
    let bridge = ComposerTextEditorBridge()
    let marker = ComposerTextViewConfigurationMarker(bridge: bridge)
    let textView = NSTextView()
    let container = NSView()
    container.addSubview(textView)
    container.addSubview(marker)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                          styleMask: [], backing: .buffered, defer: false)
    window.contentView = container
    bridge.connect(textView, owner: marker)
    textView.setMarkedText(
        NSAttributedString(string: "候補"),
        selectedRange: NSRange(location: 2, length: 0),
        replacementRange: NSRange(location: NSNotFound, length: 0))

    #expect(bridge.hasMarkedText)
    #expect(ComposerReturnRouting.shortcut(for: [], isComposing: bridge.hasMarkedText) == nil)

    textView.unmarkText()
    #expect(!bridge.hasMarkedText)
    #expect(ComposerReturnRouting.shortcut(for: [], isComposing: bridge.hasMarkedText) == .enter)
}

@MainActor
@Test func commandFlyoutReturnDefersToMarkedTextBeforeActivation() {
    let bridge = ComposerTextEditorBridge()
    let marker = ComposerTextViewConfigurationMarker(bridge: bridge)
    let textView = NSTextView()
    let container = NSView()
    container.addSubview(textView)
    container.addSubview(marker)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                          styleMask: [], backing: .buffered, defer: false)
    window.contentView = container
    bridge.connect(textView, owner: marker)
    textView.setMarkedText(
        NSAttributedString(string: "候補"),
        selectedRange: NSRange(location: 2, length: 0),
        replacementRange: NSRange(location: NSNotFound, length: 0))

    #expect(ComposerCommandKeyRouting.route(.return, modifiers: []) == .activate)
    #expect(ComposerInputMethodRouting.shouldDeferToInputMethod(
        isComposing: bridge.hasMarkedText))

    textView.unmarkText()
    #expect(!ComposerInputMethodRouting.shouldDeferToInputMethod(
        isComposing: bridge.hasMarkedText))
}

@Test func composerFeedbackKeepsAttachmentAndModelFailuresIndependent() {
    #expect(ComposerFeedback.messages(
        attachment: "Could not attach diagram.png.",
        model: "Models couldn’t be loaded.") == [
            "Could not attach diagram.png.",
            "Models couldn’t be loaded.",
        ])
    #expect(ComposerFeedback.messages(
        attachment: nil,
        model: "Models couldn’t be loaded.") == ["Models couldn’t be loaded."])
    #expect(ComposerFeedback.messages(
        attachment: "Same failure",
        model: "Same failure") == ["Same failure"])
}

@Test func composerReturnRoutingRecognizesOnlyConfiguredShortcuts() {
    #expect(ComposerReturnRouting.shortcut(for: []) == .enter)
    #expect(ComposerReturnRouting.shortcut(for: [.command]) == .commandEnter)
    #expect(ComposerReturnRouting.shortcut(for: [.shift]) == .shiftEnter)
    #expect(ComposerReturnRouting.shortcut(for: [.option]) == nil)
    #expect(ComposerReturnRouting.shortcut(for: [.control]) == nil)
}

@Test func primaryAndAlternateResolveAgainstTheCurrentStreamingBehavior() {
    #expect(ComposerReturnRouting.behavior(for: .primary, primary: .steer) == .steer)
    #expect(ComposerReturnRouting.behavior(for: .alternate, primary: .steer) == .followUp)
    #expect(ComposerReturnRouting.behavior(for: .primary, primary: .followUp) == .followUp)
    #expect(ComposerReturnRouting.behavior(for: .alternate, primary: .followUp) == .steer)
    #expect(ComposerReturnRouting.behavior(for: .newline, primary: .steer) == nil)
}

@Test func blockedComposerDoesNotReclaimFocus() {
    #expect(ComposerView.editorHeight == 106)
    #expect(ComposerView.scrollFadeHeight == 24)
    #expect(ComposerFocusRouting.shouldFocusEditor(
        isAvailable: true, isFocusBlocked: false, hasBlockingSheet: false))
    #expect(!ComposerFocusRouting.shouldFocusEditor(
        isAvailable: true, isFocusBlocked: true, hasBlockingSheet: false))
    #expect(!ComposerFocusRouting.shouldFocusEditor(
        isAvailable: true, isFocusBlocked: false, hasBlockingSheet: true))
    #expect(!ComposerFocusRouting.shouldFocusEditor(
        isAvailable: false, isFocusBlocked: false, hasBlockingSheet: false))
}

@Test func commandMonitorPassesKeysWhenComposerFocusIsBlocked() throws {
    let keys: [(UInt16, String)] = [(36, "\r"), (125, ""), (48, "\t"), (53, "")]
    for (keyCode, characters) in keys {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 1, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))

        for (isAvailable, isFocusBlocked, hasBlockingSheet) in [
            (false, false, false), (true, true, false), (true, false, true),
        ] {
            var didHandle = false
            let result = CommandBrowserKeyboardEventRouting.result(for: event, route: .root) { _ in
                guard ComposerFocusRouting.shouldFocusEditor(
                    isAvailable: isAvailable,
                    isFocusBlocked: isFocusBlocked,
                    hasBlockingSheet: hasBlockingSheet
                ) else { return false }
                didHandle = true
                return true
            }
            #expect(result == .pass)
            #expect(!didHandle)
        }

        #expect(CommandBrowserKeyboardEventRouting.result(for: event, route: .root) { _ in
            ComposerFocusRouting.shouldFocusEditor(
                isAvailable: true, isFocusBlocked: false, hasBlockingSheet: false)
        } == .consume)
    }
}

@MainActor
@Test func routeSwitchClosesFlyoutWithoutLosingDraft() {
    let model = AppModel()
    model.newSessionDraft = "Keep this draft"
    var flyout: ComposerFlyout? = .model

    WorkspaceDockRouting.resetFlyout(&flyout, whenRouteChangesFrom: .newSession, to: .archivedSessions)

    #expect(flyout == nil)
    #expect(model.newSessionDraft == "Keep this draft")
}

@MainActor
@Test func editorScrollReportsOnlyScrolledTextViewport() async throws {
    let bridge = ComposerTextEditorBridge()
    let marker = ComposerTextViewConfigurationMarker(bridge: bridge)
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 106))
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 500))
    textView.string = String(repeating: "Long draft line\n", count: 30)
    scrollView.documentView = textView
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 106))
    container.addSubview(scrollView)
    container.addSubview(marker)
    let window = NSWindow(contentRect: container.bounds,
                          styleMask: [], backing: .buffered, defer: false)
    window.contentView = container

    var scrollStates: [Bool] = []
    bridge.onScrollStateChange = { scrollStates.append($0) }
    bridge.connect(textView, owner: marker)
    #expect(scrollStates.last == false)

    scrollView.contentView.scroll(to: NSPoint(x: 0, y: 120))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    try await Task.sleep(for: .milliseconds(50))
    #expect(scrollStates.last == true)
}

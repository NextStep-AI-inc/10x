import AppKit
import OmpKit
import SwiftUI
import Testing
@testable import TenXApp

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

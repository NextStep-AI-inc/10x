import AppKit
import SwiftUI
import Testing
@testable import TenXApp

@Test func anImageOnTheClipboardStagesAsImageData() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.setData(try solidPNG(width: 8, height: 8), forType: .png)

    guard case .images(let images) = ComposerPasteboard.content(of: pasteboard) else {
        Issue.record("expected image data, got \(ComposerPasteboard.content(of: pasteboard))")
        return
    }
    #expect(images.count == 1)
}

@Test func anImageCopiedWithTextStillStagesTheImage() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.setData(try solidPNG(width: 8, height: 8), forType: .png)
    pasteboard.setString("https://example.com/image.png", forType: .string)

    guard case .images = ComposerPasteboard.content(of: pasteboard) else {
        Issue.record("expected image data, got \(ComposerPasteboard.content(of: pasteboard))")
        return
    }
}

@Test func anImageFileCopiedInFinderStagesTheFile() {
    let url = URL(filePath: "/tmp/screenshot.png")
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.writeObjects([url as NSURL])

    guard case .imageFiles(let urls) = ComposerPasteboard.content(of: pasteboard) else {
        Issue.record("expected image files, got \(ComposerPasteboard.content(of: pasteboard))")
        return
    }
    #expect(urls == [url])
}

@Test func aNonImageFilePasteIsLeftToTheEditor() {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.writeObjects([URL(filePath: "/tmp/notes.txt") as NSURL])

    guard case .none = ComposerPasteboard.content(of: pasteboard) else {
        Issue.record("expected none, got \(ComposerPasteboard.content(of: pasteboard))")
        return
    }
}

@Test func plainTextPasteIsLeftToTheEditor() {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.setString("hello", forType: .string)

    guard case .none = ComposerPasteboard.content(of: pasteboard) else {
        Issue.record("expected none, got \(ComposerPasteboard.content(of: pasteboard))")
        return
    }
}

@Test func onlyUnmodifiedCommandVIsIntercepted() {
    #expect(ComposerPasteboard.isPasteShortcut(modifiers: .command, characters: "v"))
    #expect(ComposerPasteboard.isPasteShortcut(modifiers: .command, characters: "V"))
    #expect(!ComposerPasteboard.isPasteShortcut(modifiers: [.command, .shift], characters: "v"))
    #expect(!ComposerPasteboard.isPasteShortcut(modifiers: [.command, .option], characters: "v"))
    #expect(!ComposerPasteboard.isPasteShortcut(modifiers: [], characters: "v"))
    #expect(!ComposerPasteboard.isPasteShortcut(modifiers: .command, characters: "c"))
    #expect(!ComposerPasteboard.isPasteShortcut(modifiers: .command, characters: nil))
}

@MainActor @Test func commandVStagesAClipboardImageWhileTheEditorIsFocused() async throws {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.setData(try solidPNG(width: 8, height: 8), forType: .png)

    let harness = try await ComposerHarness()
    harness.monitor.pasteboard = pasteboard
    try await harness.focusEditor()
    defer { harness.close() }

    harness.sendCommandV()

    #expect(harness.attachments.count == 1)
    #expect(harness.attachments.first?.name == "Pasted image")
}

/// The monitor must decline a text paste rather than consume it, so ⌘V keeps
/// its normal meaning in the editor. What the editor then does with the event
/// is AppKit's menu dispatch, not the composer's contract.
@MainActor @Test func commandVWithTextOnTheClipboardIsLeftToTheEditor() async throws {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.setString("hello paste", forType: .string)

    let harness = try await ComposerHarness()
    harness.monitor.pasteboard = pasteboard
    try await harness.focusEditor()
    defer { harness.close() }

    #expect(harness.commandVInterception() == nil)

    harness.sendCommandV()

    #expect(harness.attachments.isEmpty)
}

@MainActor @Test func commandVDoesNotStageWhenTheEditorIsNotFocused() async throws {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.setData(try solidPNG(width: 8, height: 8), forType: .png)

    let harness = try await ComposerHarness()
    harness.monitor.pasteboard = pasteboard
    try await harness.focusEditor()
    defer { harness.close() }

    harness.window.makeFirstResponder(harness.window.contentView)
    try await harness.waitFor("the editor to resign focus") {
        !(harness.window.firstResponder is NSTextView)
    }

    harness.sendCommandV()

    #expect(harness.attachments.isEmpty)
}

/// The workspace is a `WindowGroup`, so two windows — each with its own
/// composer — can be open at once, and a background window's editor stays
/// first responder in its own window. A local key monitor is process-wide, so
/// only the composer in the window the event belongs to may stage the paste.
@MainActor @Test func commandVOnlyStagesInTheWindowTheKeyEventBelongsTo() async throws {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.setData(try solidPNG(width: 8, height: 8), forType: .png)

    let background = try await ComposerHarness()
    background.monitor.pasteboard = pasteboard
    try await background.focusEditor()
    defer { background.close() }

    let key = try await ComposerHarness()
    key.monitor.pasteboard = pasteboard
    try await key.focusEditor()
    defer { key.close() }

    key.sendCommandV()

    #expect(key.attachments.count == 1)
    #expect(background.attachments.isEmpty)
}

/// A `TextField` — the model picker's search box, say — edits through the
/// window's shared field editor, which is an `NSTextView` as well. A paste
/// aimed at one of those belongs to the field, not to the composer.
@MainActor @Test func commandVWhileATextFieldIsFocusedIsLeftToThatField() async throws {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.setData(try solidPNG(width: 8, height: 8), forType: .png)

    let harness = try await ComposerHarness()
    harness.monitor.pasteboard = pasteboard
    try await harness.focusTextField()
    defer { harness.close() }

    harness.sendCommandV()

    #expect(harness.attachments.isEmpty)
}

/// A real composer in a real window, so the test exercises the production
/// event path: key event -> monitor -> pasteboard classification -> staging.
@MainActor
private final class ComposerHarness {
    let window: NSWindow
    let monitor: ComposerPasteMonitorView
    private let attachmentsBox = StateBox<[ComposerAttachment]>([])
    private let draftBox = StateBox("")

    var attachments: [ComposerAttachment] { attachmentsBox.value }
    var draft: String { draftBox.value }

    init() async throws {
        let view = ComposerView(
            draft: Binding(get: { [draftBox] in draftBox.value }, set: { [draftBox] in draftBox.value = $0 }),
            attachments: Binding(
                get: { [attachmentsBox] in attachmentsBox.value },
                set: { [attachmentsBox] in attachmentsBox.value = $0 }),
            presentation: .newSession(
                projectURL: URL(filePath: "/tmp"),
                projectURLs: [URL(filePath: "/tmp")],
                onChooseProject: { _ in },
                onAddExistingFolder: {}),
            onSend: {})
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        var found: ComposerPasteMonitorView?
        try await waitForCondition("the paste monitor to install") {
            found = window.contentView?.firstDescendant(of: ComposerPasteMonitorView.self)
            return found != nil
        }
        monitor = try #require(found)
    }

    func close() {
        window.close()
    }

    /// Under `xcodebuild` the test host never becomes the active application,
    /// so SwiftUI's own focus request cannot reach the window's responder
    /// chain. Installing the editor as first responder is what activating the
    /// app would have done.
    func focusEditor() async throws {
        var found: NSTextView?
        try await waitForCondition("the editor to exist") { [window] in
            found = window.contentView?.firstDescendant(of: NSTextView.self)
            return found != nil
        }
        let editor = try #require(found)
        window.makeFirstResponder(editor)
        try await waitForCondition("the editor to take focus") { [window] in
            window.firstResponder === editor
        }
    }

    func focusTextField() async throws {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
        try await waitForCondition("the field editor to take focus") { [window] in
            (window.firstResponder as? NSTextView)?.isFieldEditor == true
        }
    }

    func sendCommandV() {
        NSApp.sendEvent(commandVEvent())
    }

    /// What the monitor decides for a ⌘V in this window, without dispatching
    /// the event.
    func commandVInterception() -> ComposerPasteboard.Content? {
        monitor.interception(for: commandVEvent())
    }

    private func commandVEvent() -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "v",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: 9)!
    }

    func waitFor(
        _ description: String,
        condition: @escaping () -> Bool
    ) async throws {
        try await waitForCondition(description, condition: condition)
    }
}

@MainActor
private func waitForCondition(
    _ description: String,
    condition: @escaping () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(5)
    while clock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("timed out waiting for \(description)")
}

private final class StateBox<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

extension NSView {
    fileprivate func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        for subview in subviews {
            if let match = subview.firstDescendant(of: type) { return match }
        }
        return nil
    }
}

private func solidPNG(width: Int, height: Int) throws -> Data {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.unlockFocus()
    let tiff = try #require(image.tiffRepresentation)
    let representation = try #require(NSBitmapImageRep(data: tiff))
    return try #require(representation.representation(using: .png, properties: [:]))
}

import AppKit
import SwiftUI

/// What a paste can stage in the composer, read straight from a pasteboard.
///
/// A focused text editor claims every `paste:` from the responder chain, so
/// the composer's `onPasteCommand` never runs while the editor has focus —
/// and for an image-only clipboard the editor inserts nothing at all. The
/// only place the composer sees the paste first is as a key event, before
/// the menu dispatches it, so ⌘V is intercepted there and this decides
/// whether the interception stages images or lets a normal text paste
/// through.
enum ComposerPasteboard {
    enum Content: Equatable {
        /// A file copied in Finder arrives as a URL. Carries every URL, not
        /// just the images: non-image files degrade to a path in the draft,
        /// the same as a drop.
        case imageFiles([URL])
        /// Screenshots and copied images arrive as image data.
        case images([NSImage])
        /// Anything else: a text paste the editor handles.
        case none
    }

    static func content(of pasteboard: NSPasteboard) -> Content {
        // Files win over image data so a Finder copy keeps its real name;
        // `.urlReadingFileURLsOnly` keeps a browser copy's web URL out.
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL],
           urls.contains(where: { ComposerAttachmentEncoder.isImage($0) }) {
            return .imageFiles(urls)
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           !images.isEmpty {
            return .images(images)
        }
        return .none
    }

    /// Plain ⌘V only. Modified pastes (⌘⇧V, ⌥⌘V) keep their text-editor
    /// meaning, and ⌘V with the wrong key is not a paste at all.
    static func isPasteShortcut(
        modifiers: NSEvent.ModifierFlags,
        characters: String?
    ) -> Bool {
        modifiers.intersection(.deviceIndependentFlagsMask) == .command
            && characters?.lowercased() == "v"
    }

    /// Whether a responder is the text editor that would otherwise swallow the
    /// paste. Field editors are excluded: `NSTextField` — every SwiftUI
    /// `TextField`, including the model picker's search box — edits through the
    /// window's shared field editor, which is an `NSTextView` too, and a paste
    /// aimed at one of those belongs to it, not to the composer.
    static func isComposerEditor(_ responder: NSResponder?) -> Bool {
        guard let textView = responder as? NSTextView else { return false }
        return !textView.isFieldEditor
    }
}

/// The composer's ⌘V interceptor, as an invisible view so the monitor's
/// lifetime follows the composer's window exactly.
struct ComposerPasteMonitor: NSViewRepresentable {
    let onPaste: (ComposerPasteboard.Content) -> Void

    func makeNSView(context: Context) -> ComposerPasteMonitorView {
        ComposerPasteMonitorView()
    }

    func updateNSView(_ view: ComposerPasteMonitorView, context: Context) {
        view.onPaste = onPaste
    }

    static func dismantleNSView(_ view: ComposerPasteMonitorView, coordinator: ()) {
        view.stopMonitoring()
    }
}

final class ComposerPasteMonitorView: NSView {
    var onPaste: ((ComposerPasteboard.Content) -> Void)?
    /// Tests point this at a private pasteboard; production reads the general one.
    var pasteboard: NSPasteboard = .general

    private var keyMonitor: Any?

    /// Never intercepts a click; this view exists only to own the monitor.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    /// Teardown is driven by the view's window lifecycle and by
    /// `dismantleNSView`, never by `deinit`: a nonisolated `deinit` cannot
    /// touch the monitor token under strict concurrency.
    func stopMonitoring() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func startMonitoring() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let content = self.interception(for: event) else { return event }
            self.onPaste?(content)
            return nil
        }
    }

    /// What this event would stage, or `nil` when the composer must let the
    /// event through to the responder chain.
    ///
    /// A local monitor is process-wide, so the event's window is what scopes
    /// the interception to this composer: two workspace windows each install
    /// one, and a background window's editor stays first responder in its own
    /// window. Interception then requires that this window's focused responder
    /// is the editor that would otherwise swallow the paste; with anything else
    /// focused the event falls through to `onPasteCommand`.
    func interception(for event: NSEvent) -> ComposerPasteboard.Content? {
        guard ComposerPasteboard.isPasteShortcut(
                modifiers: event.modifierFlags,
                characters: event.charactersIgnoringModifiers),
              let window, event.window === window,
              ComposerPasteboard.isComposerEditor(window.firstResponder)
        else { return nil }
        let content = ComposerPasteboard.content(of: pasteboard)
        if case .none = content { return nil }
        return content
    }
}

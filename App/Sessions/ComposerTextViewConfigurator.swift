import AppKit
import SwiftUI

struct ComposerTextViewConfigurator: NSViewRepresentable {
    let bridge: ComposerTextEditorBridge

    func makeNSView(context: Context) -> ComposerTextViewConfigurationMarker {
        let view = ComposerTextViewConfigurationMarker(bridge: bridge)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: ComposerTextViewConfigurationMarker, context: Context) {
        nsView.configureTextViewWhenAvailable()
    }
}

@MainActor
final class ComposerTextEditorBridge {
    private weak var textView: NSTextView?
    private weak var owner: ComposerTextViewConfigurationMarker?

    func connect(_ textView: NSTextView, owner: ComposerTextViewConfigurationMarker) {
        self.textView = textView
        self.owner = owner
    }

    func disconnect(owner: ComposerTextViewConfigurationMarker) {
        guard self.owner === owner else { return }
        textView = nil
        self.owner = nil
    }

    var hasMarkedText: Bool {
        guard let textView,
              let owner,
              owner.window != nil,
              owner.nearestTextView() === textView
        else { return false }
        return textView.hasMarkedText()
    }

    @discardableResult
    func insertFilePaths(_ paths: [String]) -> Bool {
        guard !paths.isEmpty,
              let textView,
              let owner,
              owner.window != nil,
              owner.nearestTextView() === textView
        else { return false }

        let source = Array(textView.string.utf16)
        let selection = textView.selectedRange()
        guard selection.location <= source.count,
              NSMaxRange(selection) <= source.count
        else { return false }

        var insertion = paths.joined(separator: "\n")
        if selection.location > 0,
           source[selection.location - 1] != 0x0A {
            insertion = "\n" + insertion
        }
        if NSMaxRange(selection) < source.count,
           source[NSMaxRange(selection)] != 0x0A {
            insertion += "\n"
        }
        textView.insertText(insertion, replacementRange: selection)
        return true
    }
}

final class ComposerTextViewConfigurationMarker: NSView {
    private let bridge: ComposerTextEditorBridge

    init(bridge: ComposerTextEditorBridge) {
        self.bridge = bridge
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            bridge.disconnect(owner: self)
            return
        }
        configureTextViewWhenAvailable()
    }

    func configureTextViewWhenAvailable() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let textView = nearestTextView() else { return }
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            bridge.connect(textView, owner: self)
        }
    }

    fileprivate func nearestTextView() -> NSTextView? {
        var ancestor = superview
        while let view = ancestor {
            if let textView = view.descendants.compactMap({ $0 as? NSTextView }).first {
                return textView
            }
            ancestor = view.superview
        }
        return nil
    }
}

private extension NSView {
    var descendants: [NSView] {
        subviews + subviews.flatMap(\.descendants)
    }
}

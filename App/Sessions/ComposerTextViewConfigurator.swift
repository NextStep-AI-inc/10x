import AppKit
import SwiftUI

struct ComposerTextViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ComposerTextViewConfigurationMarker {
        let view = ComposerTextViewConfigurationMarker()
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: ComposerTextViewConfigurationMarker, context: Context) {
        nsView.configureTextViewWhenAvailable()
    }
}

final class ComposerTextViewConfigurationMarker: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTextViewWhenAvailable()
    }

    func configureTextViewWhenAvailable() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let textView = nearestTextView() else { return }
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
        }
    }

    private func nearestTextView() -> NSTextView? {
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

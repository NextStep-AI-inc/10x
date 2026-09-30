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
    var onScrollStateChange: ((Bool) -> Void)? {
        didSet { reportScrollState() }
    }
    var onContentHeightChange: ((CGFloat) -> Void)? {
        didSet { reportContentHeight() }
    }

    func connect(_ textView: NSTextView, owner: ComposerTextViewConfigurationMarker) {
        self.textView = textView
        self.owner = owner
        owner.observeScrollAndTextChanges(in: textView)
        reportContentHeight()
        reportScrollState()
    }

    func disconnect(owner: ComposerTextViewConfigurationMarker) {
        guard self.owner === owner else { return }
        textView = nil
        self.owner = nil
        onScrollStateChange?(false)
    }

    fileprivate func reportScrollState() {
        guard let textView,
              let clipView = textView.enclosingScrollView?.contentView,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            onScrollStateChange?(false)
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let isOverflowing = layoutManager.usedRect(for: textContainer).height > clipView.bounds.height
        onScrollStateChange?(isOverflowing && clipView.bounds.minY > 1)
    }

    fileprivate func reportContentHeight() {
        guard let textView, let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }
        layoutManager.ensureLayout(for: textContainer)
        onContentHeightChange?(layoutManager.usedRect(for: textContainer).height)
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
    private var scrollObservation: NSObjectProtocol?
    private var textObservation: NSObjectProtocol?
    private weak var observedTextView: NSTextView?

    init(bridge: ComposerTextEditorBridge) {
        self.bridge = bridge
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            stopObserving()
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

    fileprivate func observeScrollAndTextChanges(in textView: NSTextView) {
        guard observedTextView !== textView else { return }
        stopObserving()
        observedTextView = textView
        guard let clipView = textView.enclosingScrollView?.contentView else { return }
        clipView.postsBoundsChangedNotifications = true
        scrollObservation = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.bridge.reportContentHeight()
                self.bridge.reportScrollState()
            }
        }
        textObservation = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.bridge.reportContentHeight()
                self.bridge.reportScrollState()
            }
        }
    }

    private func stopObserving() {
        if let scrollObservation { NotificationCenter.default.removeObserver(scrollObservation) }
        if let textObservation { NotificationCenter.default.removeObserver(textObservation) }
        scrollObservation = nil
        textObservation = nil
        observedTextView = nil
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

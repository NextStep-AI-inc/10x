import AppKit
import SwiftUI

struct ComposerSessionControlsView: View {
    let model: ComposerControlsModel
    let mode: ComposerControlsMode
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var availablePanelWidth = ModelPickerMetrics.panelWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        trigger
            .overlay(alignment: .bottomLeading) { flyout }
            .background {
                ModelPickerWidthReader { width in
                    availablePanelWidth = width
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isPresented)
            .onChange(of: isPresented) { _, isPresented in
                if !isPresented { query = "" }
            }
    }

    private var trigger: some View {
        Button {
            isPresented.toggle()
        } label: {
            Text(ComposerControlsPresentation.triggerTitle(for: model.selectedModel))
                .lineLimit(1)
        }
        .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.nearBlackHex)))
        .opacity(isPresented ? 0 : 1)
        .accessibilityHidden(isPresented)
        // Never disabled: the panel owns the loading and empty copy, and gating
        // the trigger on the same predicate makes that copy unreachable.
        .accessibilityLabel("Model")
        .accessibilityValue(ComposerControlsPresentation.triggerTitle(for: model.selectedModel))
        .accessibilityHint("Shows model menu")
    }

    @ViewBuilder
    private var flyout: some View {
        if isPresented {
            ModelPickerFlyout(
                sections: ComposerControlsPresentation.pickerSections(
                    models: model.models,
                    recents: model.recentModels,
                    favorites: model.favoriteModels,
                    query: query),
                selectedModel: model.selectedModel,
                thinkingOptions: model.thinkingOptions,
                thinkingLevel: model.thinkingLevel,
                isFastModeVisible: model.isFastModeVisible,
                isFastModeEnabled: model.isFastModeEnabled,
                isLoading: model.isLoading,
                isMutating: model.isMutating,
                hasCatalog: !model.models.isEmpty,
                triggerTitle: ComposerControlsPresentation.triggerTitle(
                    for: model.selectedModel),
                query: $query,
                onSelectModel: { selection in
                    // Committing a model closes the menu, the way every menu on
                    // this platform does. Effort and Fast stay open: those are
                    // settings for the model just picked, not a second choice.
                    isPresented = false
                    Task { await model.selectModel(selection, mode: mode) }
                },
                onSelectThinking: { level in
                    Task { await model.selectThinking(level, mode: mode) }
                },
                onToggleFastMode: { enabled in
                    Task { await model.setFastMode(enabled, mode: mode) }
                },
                onToggle: { isPresented = false },
                favoriteModelIDs: Set(model.favoriteModels.map(\.id)),
                onToggleFavorite: model.toggleFavorite,
                panelWidth: ModelPickerMetrics.resolvedPanelWidth(
                    availableWidth: availablePanelWidth))
            .transition(transition)
        }
    }

    private var transition: AnyTransition {
        if reduceMotion { return .identity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity.combined(with: .offset(y: 4)))
    }
}

private struct ModelPickerWidthReader: NSViewRepresentable {
    let onChange: @MainActor (CGFloat) -> Void

    func makeNSView(context: Context) -> ModelPickerWidthReaderView {
        ModelPickerWidthReaderView()
    }

    func updateNSView(_ view: ModelPickerWidthReaderView, context: Context) {
        view.onChange = onChange
        view.reportAvailableWidth()
    }
}

private final class ModelPickerWidthReaderView: NSView {
    var onChange: (@MainActor (CGFloat) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportAvailableWidth()
    }

    override func layout() {
        super.layout()
        reportAvailableWidth()
    }

    func reportAvailableWidth() {
        guard let window else { return }
        let origin = convert(bounds.origin, to: nil)
        onChange?(window.contentLayoutRect.maxX - origin.x - 8)
    }
}

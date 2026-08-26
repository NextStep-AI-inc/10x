import SwiftUI

struct ComposerSessionControlsView: View {
    let model: ComposerControlsModel
    let mode: ComposerControlsMode
    @Binding var isPresented: Bool

    @State private var query = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        trigger
            .overlay(alignment: .bottomLeading) { flyout }
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
        .disabled(model.isLoading && model.models.isEmpty)
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
                    Task { await model.selectModel(selection, mode: mode) }
                },
                onSelectThinking: { level in
                    Task { await model.selectThinking(level, mode: mode) }
                },
                onToggleFastMode: { enabled in
                    Task { await model.setFastMode(enabled, mode: mode) }
                },
                onToggle: { isPresented = false })
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

import AppKit
import SwiftUI

struct ComposerSessionControlsView: View {
    let model: ComposerControlsModel
    let mode: ComposerControlsMode
    @Binding var isPresented: Bool
    var onRestoreFocus: () -> Void = {}

    @State private var query = ""
    @State private var anchor: FlyoutWindowAnchor?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        trigger
            .background {
                FlyoutWindowAnchorReader { nextAnchor in
                    if anchor != nextAnchor { anchor = nextAnchor }
                }
            }
            .overlay(alignment: .topLeading) { flyout }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isPresented)
            .onChange(of: isPresented) { _, isPresented in
                if !isPresented { query = "" }
            }
    }

    private var trigger: some View {
        Button {
            if isPresented {
                closeAndRestoreFocus()
            } else {
                isPresented = true
            }
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
                    closeAndRestoreFocus()
                    Task { await model.selectModel(selection, mode: mode) }
                },
                onSelectThinking: { level in
                    Task { await model.selectThinking(level, mode: mode) }
                },
                onToggleFastMode: { enabled in
                    Task { await model.setFastMode(enabled, mode: mode) }
                },
                onToggle: closeAndRestoreFocus,
                favoriteModelIDs: Set(model.favoriteModels.map(\.id)),
                onToggleFavorite: model.toggleFavorite,
                panelWidth: resolvedPlacement.panelFrame.width,
                placement: resolvedPlacement,
                triggerWidth: anchor?.triggerFrame.width,
                onDismiss: { isPresented = false })
            .offset(x: panelOffsetX, y: panelOffsetY)
            .transition(transition)
            .zIndex(3)
        }
    }

    private var pickerSections: [ModelPickerSection] {
        ComposerControlsPresentation.pickerSections(
            models: model.models,
            recents: model.recentModels,
            favorites: model.favoriteModels,
            query: query)
    }

    private var desiredPanelSize: CGSize {
        let width = min(
            ModelPickerMetrics.panelWidth,
            max(1, anchor?.usableBounds.width ?? ModelPickerMetrics.panelWidth))
        let listHeight = ModelPickerMetrics.listHeight(
            rowCount: pickerSections.reduce(0) { $0 + $1.models.count },
            sectionCount: pickerSections.count)
        let settingsHeight = ModelPickerMetrics.settingsHeight(
            optionCount: model.thinkingOptions.count,
            panelWidth: width,
            showsFastMode: model.isFastModeVisible)
        return CGSize(
            width: width,
            height: ModelPickerMetrics.searchHeight
                + ModelPickerMetrics.separatorHeight
                + listHeight
                + settingsHeight)
    }

    private var placement: FlyoutPlacement? {
        anchor.map {
            FlyoutPlacement.resolve(
                triggerFrame: $0.triggerFrame,
                desiredPanelSize: desiredPanelSize,
                usableBounds: $0.usableBounds,
                preferredDirection: .above)
        }
    }

    private var resolvedPlacement: FlyoutPlacement {
        placement ?? FlyoutPlacement(
            direction: .above,
            panelFrame: CGRect(origin: .zero, size: desiredPanelSize),
            triggerOffsetX: 0,
            isHeightConstrained: false)
    }

    private var panelOffsetX: CGFloat {
        guard let anchor, let placement else { return 0 }
        return placement.panelFrame.minX - anchor.triggerFrame.minX
    }

    private var panelOffsetY: CGFloat {
        resolvedPlacement.direction == .above ? -resolvedPlacement.panelFrame.height : 0
    }

    private var transition: AnyTransition {
        if reduceMotion { return .identity }
        let offset = resolvedPlacement.direction == .above ? 8.0 : -8.0
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: offset)),
            removal: .opacity.combined(with: .offset(y: offset / 2)))
    }

    private func closeAndRestoreFocus() {
        isPresented = false
        onRestoreFocus()
    }
}

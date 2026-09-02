import SwiftUI

enum ModelPickerMetrics {
    static let panelWidth: CGFloat = 300
    static let rowHeight: CGFloat = 26
    static let headerHeight: CGFloat = 18
    static let searchHeight: CGFloat = 32
    static let settingsRowHeight: CGFloat = 28
    static let maxListHeight: CGFloat = 260
    static let triggerHeight: CGFloat = 28
    static let separatorHeight: CGFloat = 1

    /// Empty content reserves two rows: the connect-a-provider line wraps at this
    /// width, and a one-row frame would clip its second line.
    static func listHeight(rowCount: Int, sectionCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 2 * rowHeight }
        let content = CGFloat(rowCount) * rowHeight + CGFloat(sectionCount) * headerHeight
        return min(content, maxListHeight)
    }

    /// Trigger step of the silhouette: never narrower than 44, never wider than the panel.
    static func bottomWidth(triggerWidth: CGFloat) -> CGFloat {
        min(max(44, triggerWidth), panelWidth)
    }
}

private struct ModelTriggerWidthKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ModelPickerFlyout: View {
    let sections: [ModelPickerSection]
    let selectedModel: ComposerModelInfo?
    let thinkingOptions: [String]
    let thinkingLevel: String
    let isFastModeVisible: Bool
    let isFastModeEnabled: Bool
    let isLoading: Bool
    let isMutating: Bool
    let hasCatalog: Bool
    let triggerTitle: String
    @Binding var query: String
    let onSelectModel: (ComposerModelInfo) -> Void
    let onSelectThinking: (String) -> Void
    let onToggleFastMode: (Bool) -> Void
    let onToggle: () -> Void

    @State private var measuredTriggerWidth: CGFloat = 0

    nonisolated static func rowID(section: String, model: String) -> String {
        ModelPickerContent.rowID(section: section, model: model)
    }

    nonisolated static func flatIndex(
        sections: [ModelPickerSection],
        section: Int,
        row: Int
    ) -> Int {
        ModelPickerContent.flatIndex(sections: sections, section: section, row: row)
    }

    nonisolated static func highlightIndex(from current: Int, delta: Int, rowCount: Int) -> Int {
        ModelPickerContent.highlightIndex(from: current, delta: delta, rowCount: rowCount)
    }

    private var listHeight: CGFloat {
        ModelPickerMetrics.listHeight(
            rowCount: sections.reduce(0) { $0 + $1.models.count },
            sectionCount: sections.count)
    }

    private var settingsHeight: CGFloat {
        var height: CGFloat = 0
        if !thinkingOptions.isEmpty || isFastModeVisible {
            height += ModelPickerMetrics.separatorHeight
        }
        if !thinkingOptions.isEmpty {
            height += ModelPickerMetrics.settingsRowHeight
        }
        if isFastModeVisible {
            height += ModelPickerMetrics.settingsRowHeight
        }
        return height
    }

    private var topHeight: CGFloat {
        ModelPickerMetrics.searchHeight
            + ModelPickerMetrics.separatorHeight
            + listHeight
            + settingsHeight
    }

    private var bottomWidth: CGFloat {
        // ~intrinsic width of the chip until the real measure lands.
        let trigger = measuredTriggerWidth > 0 ? measuredTriggerWidth : 120
        return ModelPickerMetrics.bottomWidth(triggerWidth: trigger)
    }

    private var silhouette: TwoRectShelfShape {
        TwoRectShelfShape(
            topWidth: ModelPickerMetrics.panelWidth,
            topHeight: topHeight,
            bottomWidth: bottomWidth,
            bottomHeight: ModelPickerMetrics.triggerHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelPickerContent(
                sections: sections,
                selectedModel: selectedModel,
                isLoading: isLoading,
                isMutating: isMutating,
                hasCatalog: hasCatalog,
                query: $query,
                onSelectModel: onSelectModel,
                onCancel: onToggle)
            settingsRegion
            triggerPiece
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: ModelPickerMetrics.triggerHeight)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ModelTriggerWidthKey.self,
                            value: geometry.size.width)
                    }
                }
        }
        .onPreferenceChange(ModelTriggerWidthKey.self) { measuredTriggerWidth = $0 }
        .frame(
            width: ModelPickerMetrics.panelWidth,
            height: topHeight + ModelPickerMetrics.triggerHeight,
            alignment: .topLeading)
        .background { silhouette.fill(TenXPalette.color(TenXPalette.canvasHex)) }
        .overlay {
            silhouette.stroke(TenXPalette.color(TenXPalette.nearBlackHex), lineWidth: 1)
        }
        .dismissesOnOutsideInteraction(silhouette: silhouette, onDismiss: onToggle)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Model")
        .accessibilityValue(triggerTitle)
    }

    private var separator: some View {
        Rectangle()
            .fill(TenXPalette.color(TenXPalette.separatorHex))
            .frame(width: ModelPickerMetrics.panelWidth, height: ModelPickerMetrics.separatorHeight)
    }

    @ViewBuilder
    private var settingsRegion: some View {
        // One rule above the whole settings region: a Fast-mode-only model would
        // otherwise abut the list with nothing dividing them.
        if !thinkingOptions.isEmpty || isFastModeVisible {
            separator
        }

        if !thinkingOptions.isEmpty {
            HStack(spacing: 2) {
                Text("EFFORT")
                    .font(TenXTypography.mono(size: 9, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .frame(width: 44, alignment: .leading)
                ForEach(thinkingOptions, id: \.self) { level in
                    effortChip(level)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(
                width: ModelPickerMetrics.panelWidth,
                height: ModelPickerMetrics.settingsRowHeight)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Effort")
            // The chip reads lowercase per the spec diagram; only VoiceOver
            // capitalizes, matching the footer chip this row replaced.
            .accessibilityValue(thinkingLevel.capitalized)
        }

        if isFastModeVisible {
            HStack(spacing: 2) {
                Text("Fast mode")
                    .font(TenXTypography.body(size: 12))
                    .accessibilityHidden(true)
                Spacer()
                Toggle("Fast mode", isOn: Binding(
                    get: { isFastModeEnabled },
                    set: onToggleFastMode))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(TenXPalette.color(TenXPalette.cyanHex))
                    .disabled(isMutating)
                    .accessibilityLabel("Fast mode")
                    .accessibilityValue(isFastModeEnabled ? "On" : "Off")
            }
            .padding(.horizontal, 10)
            .frame(
                width: ModelPickerMetrics.panelWidth,
                height: ModelPickerMetrics.settingsRowHeight)
        }
    }

    private func effortChip(_ level: String) -> some View {
        SelectionChip(title: level, isSelected: level == thinkingLevel) {
            onSelectThinking(level)
        }
        .disabled(isMutating)
    }

    private var triggerPiece: some View {
        Button(action: onToggle) {
            Text(triggerTitle).lineLimit(1)
        }
        .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.nearBlackHex)))
        .accessibilityLabel("Model")
        .accessibilityValue(triggerTitle)
        .accessibilityHint("Menu open")
    }
}

struct ModelPickerRow: View {
    let model: ComposerModelInfo
    let showsProviderTag: Bool
    let isSelected: Bool
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(isSelected ? TenXPalette.color(TenXPalette.cyanHex) : .clear)
                    .frame(width: 2)
                Text(model.name)
                    .font(TenXTypography.body(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if showsProviderTag {
                    Text(model.provider)
                        .font(TenXTypography.mono(size: 9))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .lineLimit(1)
                }
            }
            .padding(.trailing, 10)
            .frame(
                maxWidth: .infinity,
                minHeight: ModelPickerMetrics.rowHeight,
                alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // One background, not two: the shared component already renders the hover
        // and selected wash, and the keyboard highlight is the same visual state.
        .background(FlyoutRowBackground(isSelected: isSelected || isHighlighted))
        .accessibilityLabel(model.name)
        .accessibilityValue(ComposerControlsPresentation.rowAccessibilityValue(
            provider: model.provider,
            isSelected: isSelected))
    }
}

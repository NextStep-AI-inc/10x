import SwiftUI

enum ModelPickerMetrics {
    static let panelWidth: CGFloat = 440
    static let compactEffortThreshold: CGFloat = 390
    static let rowHeight: CGFloat = 26
    static let headerHeight: CGFloat = 18
    static let searchHeight: CGFloat = 32
    static let settingsRowHeight: CGFloat = 28
    static let effortTitleHeight: CGFloat = 30
    static let effortSegmentHeight: CGFloat = 34
    static let effortGridSpacing: CGFloat = 1
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
    static func bottomWidth(
        triggerWidth: CGFloat,
        panelWidth: CGFloat = panelWidth
    ) -> CGFloat {
        min(max(44, triggerWidth), panelWidth)
    }

    static func effortColumnCount(optionCount: Int, panelWidth: CGFloat) -> Int {
        guard optionCount > 0 else { return 0 }
        if panelWidth < compactEffortThreshold, optionCount > 4 { return 3 }
        return optionCount
    }

    static func effortRowCount(optionCount: Int, panelWidth: CGFloat) -> Int {
        let columns = effortColumnCount(optionCount: optionCount, panelWidth: panelWidth)
        guard columns > 0 else { return 0 }
        return Int(ceil(Double(optionCount) / Double(columns)))
    }

    static func effortSegmentsHeight(optionCount: Int, panelWidth: CGFloat) -> CGFloat {
        let rowCount = effortRowCount(optionCount: optionCount, panelWidth: panelWidth)
        return CGFloat(rowCount) * effortSegmentHeight
            + CGFloat(max(0, rowCount - 1)) * effortGridSpacing
    }

    static func effortLabel(_ level: String) -> String {
        level == "xhigh" ? "Extra high" : level.capitalized
    }

    static func settingsHeight(
        optionCount: Int,
        panelWidth: CGFloat,
        showsFastMode: Bool
    ) -> CGFloat {
        guard optionCount > 0 || showsFastMode else { return 0 }
        let effortHeight = optionCount > 0
            ? effortTitleHeight
                + effortSegmentsHeight(optionCount: optionCount, panelWidth: panelWidth)
            : 0
        return separatorHeight + effortHeight + (showsFastMode ? settingsRowHeight : 0)
    }

    static func resolvedPanelWidth(availableWidth: CGFloat) -> CGFloat {
        min(panelWidth, max(1, availableWidth))
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
    var favoriteModelIDs: Set<String> = []
    var onToggleFavorite: (ComposerModelInfo) -> Void = { _ in }
    var panelWidth: CGFloat = ModelPickerMetrics.panelWidth

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
        ModelPickerMetrics.settingsHeight(
            optionCount: thinkingOptions.count,
            panelWidth: panelWidth,
            showsFastMode: isFastModeVisible)
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
        return ModelPickerMetrics.bottomWidth(triggerWidth: trigger, panelWidth: panelWidth)
    }

    private var silhouette: TwoRectShelfShape {
        TwoRectShelfShape(
            topWidth: panelWidth,
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
                onCancel: onToggle,
                favoriteModelIDs: favoriteModelIDs,
                onToggleFavorite: onToggleFavorite,
                panelWidth: panelWidth)
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
            width: panelWidth,
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
            .frame(width: panelWidth, height: ModelPickerMetrics.separatorHeight)
    }

    @ViewBuilder
    private var settingsRegion: some View {
        // One rule above the whole settings region: a Fast-mode-only model would
        // otherwise abut the list with nothing dividing them.
        if !thinkingOptions.isEmpty || isFastModeVisible {
            separator
        }

        if !thinkingOptions.isEmpty {
            HStack {
                Text("EFFORT")
                    .font(TenXTypography.mono(size: 9, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                Spacer()
                Text(ModelPickerMetrics.effortLabel(thinkingLevel))
                    .font(TenXTypography.body(size: 11))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
            }
            .padding(.horizontal, 10)
            .frame(
                width: panelWidth,
                height: ModelPickerMetrics.effortTitleHeight)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: ModelPickerMetrics.effortGridSpacing),
                    count: ModelPickerMetrics.effortColumnCount(
                        optionCount: thinkingOptions.count,
                        panelWidth: panelWidth)),
                spacing: ModelPickerMetrics.effortGridSpacing
            ) {
                ForEach(thinkingOptions, id: \.self) { level in
                    effortChip(level)
                }
            }
            .background(TenXPalette.color(TenXPalette.separatorHex))
            .overlay {
                Rectangle()
                    .stroke(TenXPalette.color(TenXPalette.separatorHex), lineWidth: 1)
            }
            .padding(.horizontal, 10)
            .frame(
                width: panelWidth,
                height: ModelPickerMetrics.effortSegmentsHeight(
                    optionCount: thinkingOptions.count,
                    panelWidth: panelWidth))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Effort")
            .accessibilityValue(ModelPickerMetrics.effortLabel(thinkingLevel))
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
                width: panelWidth,
                height: ModelPickerMetrics.settingsRowHeight)
        }
    }

    private func effortChip(_ level: String) -> some View {
        let isSelected = level == thinkingLevel
        return Button {
            onSelectThinking(level)
        } label: {
            Text(ModelPickerMetrics.effortLabel(level))
                .font(TenXTypography.body(size: 11))
                .foregroundStyle(isSelected
                    ? TenXPalette.onEmphasis
                    : TenXPalette.color(TenXPalette.mutedTextHex))
                .frame(maxWidth: .infinity, minHeight: ModelPickerMetrics.effortSegmentHeight)
                .background(isSelected
                    ? TenXPalette.color(TenXPalette.nearBlackHex)
                    : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isMutating)
        .accessibilityLabel("Effort: \(ModelPickerMetrics.effortLabel(level))")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
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
    let isFavorite: Bool
    let isSelectionDisabled: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(isSelected ? TenXPalette.color(TenXPalette.cyanHex) : .clear)
                        .frame(width: 2)
                    Text(model.name)
                        .font(TenXTypography.body(
                            size: 12,
                            weight: isSelected ? .semibold : .regular))
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
                .padding(.trailing, 6)
                .frame(
                    maxWidth: .infinity,
                    minHeight: ModelPickerMetrics.rowHeight,
                    alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSelectionDisabled)
            .accessibilityLabel(model.name)
            .accessibilityValue(ComposerControlsPresentation.rowAccessibilityValue(
                provider: model.provider,
                isSelected: isSelected))

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TenXPalette.color(
                        isFavorite ? TenXPalette.cyanHex : TenXPalette.mutedTextHex))
                    .frame(width: 32, height: ModelPickerMetrics.rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(isFavorite ? "Remove" : "Add") favorite, \(model.name), \(model.provider)")
            .accessibilityValue(isFavorite ? "Favorite" : "Not favorite")
        }
        .background(FlyoutRowBackground(isSelected: isSelected || isHighlighted))
    }
}

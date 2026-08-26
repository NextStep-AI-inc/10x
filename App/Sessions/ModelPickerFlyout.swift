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

    @State private var highlightedIndex = 0
    @State private var measuredTriggerWidth: CGFloat = 0
    @FocusState private var isSearchFocused: Bool

    /// Flat visible row order for keyboard navigation. Section headers are skipped.
    private var flatModels: [ComposerModelInfo] {
        sections.flatMap(\.models)
    }

    private var listHeight: CGFloat {
        ModelPickerMetrics.listHeight(
            rowCount: flatModels.count,
            sectionCount: sections.count)
    }

    private var settingsHeight: CGFloat {
        var height: CGFloat = 0
        if !thinkingOptions.isEmpty {
            height += ModelPickerMetrics.settingsRowHeight + ModelPickerMetrics.separatorHeight
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
            searchField
            separator
            listRegion.frame(height: listHeight)
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
        .task {
            await Task.yield()
            isSearchFocused = true
            highlightedIndex = flatModels.firstIndex { $0.id == selectedModel?.id } ?? 0
        }
        .onChange(of: query) { _, _ in highlightedIndex = 0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Model")
        .accessibilityValue(triggerTitle)
    }

    private var separator: some View {
        Rectangle()
            .fill(TenXPalette.color(TenXPalette.separatorHex))
            .frame(width: ModelPickerMetrics.panelWidth, height: ModelPickerMetrics.separatorHeight)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
            TextField("Search models", text: $query)
                .textFieldStyle(.plain)
                .font(TenXTypography.body(size: 12))
                .focused($isSearchFocused)
                .onKeyPress(keys: [.upArrow, .downArrow, .return], phases: .down, action: handleKey)
        }
        .padding(.horizontal, 10)
        .frame(width: ModelPickerMetrics.panelWidth, height: ModelPickerMetrics.searchHeight)
        .accessibilityLabel("Search models")
    }

    /// A focused TextField consumes the arrow keys for caret movement, so the
    /// field intercepts them rather than relying on default responder behavior.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !flatModels.isEmpty else { return .ignored }
        switch press.key {
        case .upArrow:
            highlightedIndex = max(highlightedIndex - 1, 0)
            return .handled
        case .downArrow:
            highlightedIndex = min(highlightedIndex + 1, flatModels.count - 1)
            return .handled
        case .return:
            guard flatModels.indices.contains(highlightedIndex) else { return .ignored }
            onSelectModel(flatModels[highlightedIndex])
            return .handled
        default:
            return .ignored
        }
    }

    @ViewBuilder
    private var listRegion: some View {
        if isLoading, !hasCatalog {
            message("Loading models…")
        } else if !hasCatalog {
            message("No models available. Connect a provider in Settings.")
        } else if sections.isEmpty {
            message("No models match that search.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { offset, section in
                        sectionHeader(section.title)
                        ForEach(Array(section.models.enumerated()), id: \.element.id) { index, model in
                            ModelPickerRow(
                                model: model,
                                showsProviderTag: section.showsProviderTag,
                                isSelected: model.id == selectedModel?.id,
                                isHighlighted: flatIndex(section: offset, row: index)
                                    == highlightedIndex,
                                action: { onSelectModel(model) })
                            .disabled(isMutating)
                        }
                    }
                }
            }
            .frame(width: ModelPickerMetrics.panelWidth)
        }
    }

    private func flatIndex(section: Int, row: Int) -> Int {
        sections.prefix(section).reduce(row) { $0 + $1.models.count }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(TenXTypography.body(size: 11))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            .padding(.horizontal, 10)
            .frame(
                width: ModelPickerMetrics.panelWidth,
                alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .center)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(TenXTypography.mono(size: 9, weight: .semibold))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            .padding(.horizontal, 10)
            .frame(
                width: ModelPickerMetrics.panelWidth,
                height: ModelPickerMetrics.headerHeight,
                alignment: .leading)
    }

    @ViewBuilder
    private var settingsRegion: some View {
        if !thinkingOptions.isEmpty {
            separator
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
            .accessibilityValue(thinkingLevel)
        }

        if isFastModeVisible {
            HStack(spacing: 2) {
                Text("Fast mode")
                    .font(TenXTypography.body(size: 12))
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
        let isSelected = level == thinkingLevel
        return Button {
            onSelectThinking(level)
        } label: {
            Text(level)
                .font(TenXTypography.body(size: 11))
                .foregroundStyle(isSelected
                    ? Color.white
                    : TenXPalette.color(TenXPalette.mutedTextHex))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(isSelected
                    ? TenXPalette.color(TenXPalette.nearBlackHex)
                    : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isMutating)
        .accessibilityLabel(level)
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

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

    /// Scroll targets in the same flat order as `flatModels`. Row ids collide by
    /// design — the selected model shows under RECENT and under its provider —
    /// so every target is section-qualified.
    private var flatRowIDs: [String] {
        sections.flatMap { section in
            section.models.map { Self.rowID(section: section.id, model: $0.id) }
        }
    }

    /// Spec: the highlight starts on the current selection, or on the first row
    /// while a query is active.
    private var selectedFlatIndex: Int {
        flatModels.firstIndex { $0.id == selectedModel?.id } ?? 0
    }

    nonisolated static func rowID(section: String, model: String) -> String {
        "\(section)/\(model)"
    }

    /// Flat keyboard index of a row, counting only rows in the sections above it.
    nonisolated static func flatIndex(
        sections: [ModelPickerSection],
        section: Int,
        row: Int
    ) -> Int {
        sections.prefix(section).reduce(row) { $0 + $1.models.count }
    }

    /// Clamped highlight movement: `delta` is -1 for Up and +1 for Down.
    nonisolated static func highlightIndex(from current: Int, delta: Int, rowCount: Int) -> Int {
        guard rowCount > 0 else { return 0 }
        return min(max(current + delta, 0), rowCount - 1)
    }

    private var listHeight: CGFloat {
        ModelPickerMetrics.listHeight(
            rowCount: flatModels.count,
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
        .dismissesOnOutsideInteraction(silhouette: silhouette, onDismiss: onToggle)
        .task {
            await Task.yield()
            isSearchFocused = true
            highlightedIndex = selectedFlatIndex
        }
        .onChange(of: query) { _, newQuery in
            let isSearching = !newQuery
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            highlightedIndex = isSearching ? 0 : selectedFlatIndex
        }
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
            highlightedIndex = Self.highlightIndex(
                from: highlightedIndex, delta: -1, rowCount: flatModels.count)
            return .handled
        case .downArrow:
            highlightedIndex = Self.highlightIndex(
                from: highlightedIndex, delta: 1, rowCount: flatModels.count)
            return .handled
        case .return:
            // Keyboard and pointer agree: no commit races an in-flight setModel.
            guard !isMutating else { return .handled }
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sections.enumerated()), id: \.element.id) { offset, section in
                            sectionHeader(section.title)
                            ForEach(Array(section.models.enumerated()), id: \.element.id) { index, model in
                                ModelPickerRow(
                                    model: model,
                                    showsProviderTag: section.showsProviderTag,
                                    isSelected: model.id == selectedModel?.id,
                                    isHighlighted: Self.flatIndex(
                                        sections: sections,
                                        section: offset,
                                        row: index) == highlightedIndex,
                                    action: { onSelectModel(model) })
                                .disabled(isMutating)
                                .id(Self.rowID(section: section.id, model: model.id))
                            }
                        }
                    }
                }
                .frame(width: ModelPickerMetrics.panelWidth)
                // The list caps at ten visible rows, so the highlight has to be
                // carried into view or Return commits a model nobody can see.
                .onChange(of: highlightedIndex) { _, index in
                    guard flatRowIDs.indices.contains(index) else { return }
                    proxy.scrollTo(flatRowIDs[index], anchor: .center)
                }
            }
        }
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
        let isSelected = level == thinkingLevel
        return Button {
            onSelectThinking(level)
        } label: {
            Text(level)
                .font(TenXTypography.body(size: 11))
                .foregroundStyle(isSelected
                    ? TenXPalette.onEmphasis
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

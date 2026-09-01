import SwiftUI

struct ModelPickerContent: View {
    let sections: [ModelPickerSection]
    let selectedModel: ComposerModelInfo?
    let isLoading: Bool
    let isMutating: Bool
    let hasCatalog: Bool
    @Binding var query: String
    let onSelectModel: (ComposerModelInfo) -> Void
    let onCancel: () -> Void

    @State private var highlightedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var flatModels: [ComposerModelInfo] {
        sections.flatMap(\.models)
    }

    private var flatRowIDs: [String] {
        sections.flatMap { section in
            section.models.map { Self.rowID(section: section.id, model: $0.id) }
        }
    }

    private var selectedFlatIndex: Int {
        flatModels.firstIndex { $0.id == selectedModel?.id } ?? 0
    }

    nonisolated static func rowID(section: String, model: String) -> String {
        "\(section)/\(model)"
    }

    nonisolated static func flatIndex(
        sections: [ModelPickerSection],
        section: Int,
        row: Int
    ) -> Int {
        sections.prefix(section).reduce(row) { $0 + $1.models.count }
    }

    nonisolated static func highlightIndex(from current: Int, delta: Int, rowCount: Int) -> Int {
        guard rowCount > 0 else { return 0 }
        return min(max(current + delta, 0), rowCount - 1)
    }

    private var listHeight: CGFloat {
        ModelPickerMetrics.listHeight(
            rowCount: flatModels.count,
            sectionCount: sections.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
            separator
            listRegion.frame(height: listHeight)
        }
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
                .onKeyPress(keys: [.upArrow, .downArrow, .return, .escape], phases: .down, action: handleKey)
        }
        .padding(.horizontal, 10)
        .frame(width: ModelPickerMetrics.panelWidth, height: ModelPickerMetrics.searchHeight)
        .accessibilityLabel("Search models")
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .escape:
            onCancel()
            return .handled
        case .upArrow:
            guard !flatModels.isEmpty else { return .ignored }
            highlightedIndex = Self.highlightIndex(
                from: highlightedIndex, delta: -1, rowCount: flatModels.count)
            return .handled
        case .downArrow:
            guard !flatModels.isEmpty else { return .ignored }
            highlightedIndex = Self.highlightIndex(
                from: highlightedIndex, delta: 1, rowCount: flatModels.count)
            return .handled
        case .return:
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
}

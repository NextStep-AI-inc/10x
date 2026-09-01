import SwiftUI

struct CommandBrowserNativeControlsView: View {
    let commandModel: ComposerCommandModel
    let controls: ComposerControlsModel
    @Binding var query: String
    let onEffect: (CommandBrowserEffect) -> Void
    let restoreEditorFocus: () -> Void

    @State private var highlightedIndex = 0
    @FocusState private var isFocused: Bool

    private var command: AppCommand? {
        guard case .native(let command) = commandModel.route else { return nil }
        return command
    }

    private var rows: [NativeControlRow] {
        Self.nativeRows(
            command: command,
            thinkingOptions: controls.thinkingOptions,
            thinkingLevel: controls.thinkingLevel,
            isFastModeVisible: controls.isFastModeVisible,
            isFastModeEnabled: controls.isFastModeEnabled)
    }

    nonisolated static func nativeRows(
        command: AppCommand?,
        thinkingOptions: [String],
        thinkingLevel: String,
        isFastModeVisible: Bool,
        isFastModeEnabled: Bool
    ) -> [NativeControlRow] {
        switch command {
        case .model, nil:
            return []
        case .effort:
            return thinkingOptions.map { effort in
                NativeControlRow(title: effort, detail: effort == thinkingLevel ? "Status" : nil)
            }
        case .fast:
            guard isFastModeVisible else { return [] }
            return [
                NativeControlRow(title: "On", detail: isFastModeEnabled ? "Status" : nil),
                NativeControlRow(title: "Off", detail: isFastModeEnabled ? nil : "Status"),
                NativeControlRow(title: "Status", detail: isFastModeEnabled ? "On" : "Off"),
            ]
        }
    }

    nonisolated static func shouldRestoreEditorFocus(
        effect: CommandBrowserEffect,
        isPresented: Bool,
        route: CommandBrowserRoute
    ) -> Bool {
        effect != .none && (!isPresented || route == .root)
    }

    nonisolated static func currentNativeHighlightIndex(
        command: AppCommand?,
        rows: [NativeControlRow],
        thinkingLevel: String,
        isFastModeEnabled: Bool,
        previousIndex: Int
    ) -> Int {
        guard !rows.isEmpty else { return 0 }

        let selectedTitle: String? = switch command {
        case .effort:
            thinkingLevel
        case .fast:
            isFastModeEnabled ? "On" : "Off"
        case .model, nil:
            nil
        }

        if let selectedTitle, let selectedIndex = rows.firstIndex(where: { $0.title == selectedTitle }) {
            return selectedIndex
        }

        return min(max(previousIndex, 0), rows.count - 1)
    }

    var body: some View {
        Group {
            switch command {
            case .model:
                modelChild
            case .effort:
                rowChild(title: "Effort")
            case .fast:
                rowChild(title: "Fast mode")
            case nil:
                EmptyView()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var modelChild: some View {
        VStack(alignment: .leading, spacing: 0) {
            nativeHeader("Model")
            ModelPickerContent(
                sections: ComposerControlsPresentation.pickerSections(
                    models: controls.models,
                    recents: controls.recentModels,
                    query: query),
                selectedModel: controls.selectedModel,
                isLoading: controls.isLoading,
                isMutating: controls.isMutating,
                hasCatalog: !controls.models.isEmpty,
                query: $query,
                onSelectModel: { model in
                    Task {
                        let effect = await commandModel.applyModel(model)
                        finishNativeAction(effect)
                    }
                },
                onCancel: handleBack)
            if let message = commandModel.inlineMessage {
                inlineMessage(message)
            }
        }
        .frame(width: ModelPickerMetrics.panelWidth, alignment: .topLeading)
        .background(TenXPalette.color(TenXPalette.canvasHex))
        .overlay {
            Rectangle()
                .stroke(TenXPalette.color(TenXPalette.nearBlackHex), lineWidth: 1)
        }
        .accessibilityLabel("Model")
    }

    private func rowChild(title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            nativeHeader(title)
            Rectangle()
                .fill(TenXPalette.color(TenXPalette.separatorHex))
                .frame(width: ModelPickerMetrics.panelWidth, height: ModelPickerMetrics.separatorHeight)
            ForEach(Array(rows.enumerated()), id: \.element.title) { index, row in
                nativeRow(row, isHighlighted: index == highlightedIndex)
            }
            if let message = commandModel.inlineMessage {
                inlineMessage(message)
            } else if !rows.isEmpty {
                appliesNote
            }
        }
        .frame(width: ModelPickerMetrics.panelWidth, alignment: .topLeading)
        .background(TenXPalette.color(TenXPalette.canvasHex))
        .overlay {
            Rectangle()
                .stroke(TenXPalette.color(TenXPalette.nearBlackHex), lineWidth: 1)
        }
        .focusable()
        .focused($isFocused)
        .onAppear {
            resetHighlightedIndex()
        }
        .task {
            await Task.yield()
            isFocused = true
        }
        .onChange(of: rows) { _, rows in
            resetHighlightedIndex(rows: rows)
        }
        .onChange(of: controls.thinkingLevel) { _, _ in
            resetHighlightedIndex()
        }
        .onChange(of: controls.isFastModeEnabled) { _, _ in
            resetHighlightedIndex()
        }
        .onKeyPress(keys: [.upArrow, .downArrow, .return, .escape], phases: .down, action: handleRowsKey)
        .accessibilityLabel(title)
    }

    private func nativeHeader(_ title: String) -> some View {
        Text(title)
            .font(TenXTypography.mono(size: 9, weight: .semibold))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            .padding(.horizontal, 10)
            .frame(
                width: ModelPickerMetrics.panelWidth,
                height: ModelPickerMetrics.headerHeight,
                alignment: .leading)
    }

    private func nativeRow(_ row: NativeControlRow, isHighlighted: Bool) -> some View {
        Button {
            activate(row.title)
        } label: {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(rowIsSelected(row) ? TenXPalette.color(TenXPalette.cyanHex) : .clear)
                    .frame(width: 2)
                Text(row.title)
                    .font(TenXTypography.body(size: 12, weight: rowIsSelected(row) ? .semibold : .regular))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let detail = row.detail {
                    Text(detail)
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
        .disabled(controls.isMutating)
        .background(FlyoutRowBackground(isSelected: isHighlighted))
        .accessibilityLabel(row.title)
        .accessibilityValue(row.detail ?? "")
    }

    private var appliesNote: some View {
        Text("Applies to the next request")
            .font(TenXTypography.body(size: 11))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            .padding(.horizontal, 10)
            .frame(
                width: ModelPickerMetrics.panelWidth,
                height: ModelPickerMetrics.settingsRowHeight,
                alignment: .leading)
    }

    private func inlineMessage(_ message: String) -> some View {
        Text(message)
            .font(TenXTypography.body(size: 11))
            .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            .padding(.horizontal, 10)
            .frame(
                width: ModelPickerMetrics.panelWidth,
                height: ModelPickerMetrics.settingsRowHeight,
                alignment: .leading)
    }

    private func rowIsSelected(_ row: NativeControlRow) -> Bool {
        switch command {
        case .effort:
            row.title == controls.thinkingLevel
        case .fast:
            (row.title == "On" && controls.isFastModeEnabled)
                || (row.title == "Off" && !controls.isFastModeEnabled)
        case .model, nil:
            false
        }
    }

    private func handleRowsKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .escape:
            handleBack()
            return .handled
        case .upArrow:
            guard !rows.isEmpty else { return .ignored }
            highlightedIndex = ModelPickerContent.highlightIndex(
                from: highlightedIndex,
                delta: -1,
                rowCount: rows.count)
            return .handled
        case .downArrow:
            guard !rows.isEmpty else { return .ignored }
            highlightedIndex = ModelPickerContent.highlightIndex(
                from: highlightedIndex,
                delta: 1,
                rowCount: rows.count)
            return .handled
        case .return:
            guard rows.indices.contains(highlightedIndex) else { return .ignored }
            activate(rows[highlightedIndex].title)
            return .handled
        default:
            return .ignored
        }
    }

    private func activate(_ title: String) {
        guard !controls.isMutating else { return }
        switch command {
        case .effort:
            Task {
                let effect = await commandModel.applyEffort(title)
                finishNativeAction(effect)
            }
        case .fast:
            if title == "Status" {
                handleBack()
            } else {
                Task {
                    let effect = await commandModel.applyFast(title == "On")
                    finishNativeAction(effect)
                }
            }
        case .model, nil:
            break
        }
    }

    private func handleBack() {
        onEffect(commandModel.back())
        restoreEditorFocus()
    }

    private func resetHighlightedIndex(rows currentRows: [NativeControlRow]? = nil) {
        highlightedIndex = Self.currentNativeHighlightIndex(
            command: command,
            rows: currentRows ?? rows,
            thinkingLevel: controls.thinkingLevel,
            isFastModeEnabled: controls.isFastModeEnabled,
            previousIndex: highlightedIndex)
    }

    private func finishNativeAction(_ effect: CommandBrowserEffect) {
        onEffect(effect)
        if Self.shouldRestoreEditorFocus(
            effect: effect,
            isPresented: commandModel.isPresented,
            route: commandModel.route)
        {
            restoreEditorFocus()
        }
    }
}

struct NativeControlRow: Equatable {
    let title: String
    let detail: String?
}

import OmpKit
import SwiftUI

enum CommandBrowserMetrics {
    static let sourceWidth: CGFloat = 132
    static let resultWidth: CGFloat = 286
    static let minimumDetailWidth: CGFloat = 210
    static let rowHeight: CGFloat = 34
    static let headerHeight: CGFloat = 34
    static let minimumHeight: CGFloat = 220
    static let maximumHeight: CGFloat = 360
}

enum CommandBrowserSourceSelectionNavigation: Equatable, Sendable {
    case stayRoot
    case backToRoot
}

struct CommandBrowserView: View {
    let model: ComposerCommandModel
    let controls: ComposerControlsModel
    @Binding var query: String
    let onEffect: (CommandBrowserEffect) -> Void
    let onDismiss: () -> Void
    let restoreEditorFocus: () -> Void

    @Environment(\.accessibilityAnnouncer) private var announcer
    @State private var announcedCatalogState = ""
    @State private var announcedSourceState = ""

    private var selectedSourceItem: CommandBrowserSourceItem? {
        model.sources.first { $0.id == model.selectedSource }
    }

    var body: some View {
        GeometryReader { geometry in
            let panelSize = Self.panelSize(for: geometry.size)
            let width = panelSize.width
            let height = panelSize.height
            let showsDetail = width >= CommandBrowserMetrics.sourceWidth
                + CommandBrowserMetrics.resultWidth
                + CommandBrowserMetrics.minimumDetailWidth
            let resultWidth = showsDetail
                ? CommandBrowserMetrics.resultWidth
                : max(0, width - CommandBrowserMetrics.sourceWidth - 1)
            VStack(spacing: 0) {
                header(width: width)
                separator(width: width)
                HStack(spacing: 0) {
                    sourceRail
                        .frame(width: CommandBrowserMetrics.sourceWidth, alignment: .topLeading)
                    verticalSeparator
                    resultList(width: resultWidth)
                        .frame(width: resultWidth, alignment: .topLeading)
                    if showsDetail {
                        verticalSeparator
                        detailOrChild
                            .frame(
                                width: width - CommandBrowserMetrics.sourceWidth
                                    - CommandBrowserMetrics.resultWidth - 2,
                                alignment: .topLeading)
                    }
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .background(TenXPalette.color(TenXPalette.canvasHex))
            .overlay(Rectangle().stroke(TenXPalette.color(TenXPalette.nearBlackHex), lineWidth: 1))
            .dismissesOnOutsideInteraction(silhouette: Rectangle(), onDismiss: dismiss)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Commands")
            .accessibilityValue(accessibilitySummary)
            .accessibilityHint(CommandBrowserAccessibility.helpText())
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    model.moveSelection(.next)
                case .decrement:
                    model.moveSelection(.previous)
                @unknown default:
                    break
                }
            }
            .accessibilityActions {
                ForEach(CommandBrowserAccessibility.rootSourceActions(model.sources), id: \.source) { action in
                    Button(action.name) {
                        selectSource(action.source)
                    }
                }
            }
            .onAppear {
                announcer.announce("Commands")
            }
            .onChange(of: model.catalogState) { _, state in
                announceCatalogState(state)
            }
            .onChange(of: sourceAnnouncementState) { _, state in
                announceSelectedSource(state)
            }
            .onChange(of: model.inlineMessage) { _, message in
                if let message, !message.isEmpty {
                    announcer.announce(message)
                }
            }
        }
        .frame(
            minHeight: CommandBrowserMetrics.minimumHeight,
            maxHeight: CommandBrowserMetrics.maximumHeight,
            alignment: .topLeading)
    }

    private var sourceRail: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.sources.enumerated()), id: \.element.id) { index, item in
                CommandBrowserSourceRow(
                    item: item,
                    isSelected: item.id == model.selectedSource,
                    action: {
                        selectSource(item.id)
                    })
                    .accessibilitySortPriority(Double(model.sources.count - index))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sources")
    }

    private func resultList(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let heading = model.visibleRows.isEmpty ? emptyHeading : nil {
                Text(heading)
                    .font(TenXTypography.mono(size: 9, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .padding(.horizontal, 10)
                    .frame(
                        width: width,
                        height: CommandBrowserMetrics.rowHeight,
                        alignment: .leading)
            }
            if !model.visibleRows.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.visibleRows.enumerated()), id: \.element.id) { index, row in
                                CommandBrowserResultRow(
                                    row: row,
                                    isSelected: row.id == model.selectedRowID,
                                    position: index + 1,
                                    count: model.visibleRows.count,
                                    action: {
                                        model.highlight(row.id)
                                        activateHighlightedRow()
                                    })
                                    .id(row.id)
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                    .onAppear {
                        scrollToSelectedRow(with: proxy)
                    }
                    .onChange(of: model.selectedRowID) {
                        scrollToSelectedRow(with: proxy)
                    }
                    .onChange(of: model.visibleRows.map(\.id)) {
                        scrollToSelectedRow(with: proxy)
                    }
                }
            } else if let message = emptyBody {
                Text(message)
                    .font(TenXTypography.body(size: 12))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                    .frame(width: width, alignment: .topLeading)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Results")
    }

    @ViewBuilder
    private var detailOrChild: some View {
        switch model.route {
        case .native:
            CommandBrowserNativeControlsView(
                commandModel: model,
                controls: controls,
                query: $query,
                onEffect: onEffect,
                restoreEditorFocus: restoreEditorFocus)
        case .subcommands(let rowID):
            if let row = model.visibleRows.first(where: { $0.id == rowID }) ?? model.highlightedRow {
                subcommandPane(row)
            } else {
                detailPane
            }
        case .arguments:
            detailPane
        case .root:
            detailPane
        }
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message = model.inlineMessage {
                detailTitle("Status")
                detailText(message, color: TenXPalette.signalRedHex)
            } else if let row = model.highlightedRow {
                detailTitle(row.source == .app ? "APP CONTROL" : row.source.rawValue.uppercased())
                Text("/\(row.canonicalName)")
                    .font(TenXTypography.mono(size: 14, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    .lineLimit(2)
                    .help("/\(row.canonicalName)")
                detailText(row.summary)
                detailMetadata(for: row)
            } else {
                EmptyView()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Details")
    }

    private func subcommandPane(_ row: CommandBrowserRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            detailTitle("/\(row.canonicalName)")
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
            ForEach(row.subcommands, id: \.name) { subcommand in
                Button {
                    onEffect(model.selectSubcommand(named: subcommand.name))
                    restoreEditorFocus()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(subcommand.name)
                            .font(TenXTypography.mono(size: 12, weight: .semibold))
                            .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                            .lineLimit(1)
                        if let description = subcommand.description, !description.isEmpty {
                            Text(description)
                                .font(TenXTypography.body(size: 11))
                                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                                .lineLimit(2)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: CommandBrowserMetrics.rowHeight, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(FlyoutRowBackground(isSelected: false))
                .accessibilityLabel(subcommand.name)
                .accessibilityValue(subcommand.description ?? subcommand.usage ?? "")
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Subcommands")
        .accessibilityValue("Expanded")
    }

    private func detailMetadata(for row: CommandBrowserRow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let executionNote = row.executionNote {
                detailPair("Enter", executionNote)
            } else {
                detailPair("Enter", row.source == .app ? "Open control" : "Open")
            }
            detailPair("Tab", row.inputHint == nil && row.subcommands.isEmpty ? "Complete in prompt" : "Complete with input")
            if !row.aliases.isEmpty {
                detailPair("Aliases", row.aliases.joined(separator: ", "))
            }
            if let inputHint = row.inputHint {
                detailPair("Input", inputHint)
            }
            if !row.subcommands.isEmpty {
                detailPair("Subcommands", "\(row.subcommands.count)")
            }
            detailPair("Source", row.source.rawValue)
        }
    }

    private func detailTitle(_ value: String) -> some View {
        Text(value)
            .font(TenXTypography.mono(size: 9, weight: .semibold))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
    }

    private func detailText(_ value: String, color: Int = TenXPalette.nearBlackHex) -> some View {
        Text(value.isEmpty ? "No description available." : value)
            .font(TenXTypography.body(size: 12))
            .foregroundStyle(TenXPalette.color(color))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func detailPair(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(TenXTypography.mono(size: 9, weight: .semibold))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(TenXTypography.body(size: 11))
                .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                .lineLimit(2)
                .help(value)
        }
    }

    private func header(width: CGFloat) -> some View {
        HStack(spacing: 12) {
            Text("COMMANDS")
                .font(TenXTypography.mono(size: 9, weight: .semibold))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            Spacer(minLength: 12)
            Text("↑↓ move  ⌃⇥ source  ↵ open  Esc close")
                .font(TenXTypography.mono(size: 9))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: CommandBrowserMetrics.headerHeight, alignment: .leading)
    }

    private func separator(width: CGFloat) -> some View {
        Rectangle()
            .fill(TenXPalette.color(TenXPalette.separatorHex))
            .frame(width: width, height: 1)
    }

    private var verticalSeparator: some View {
        Rectangle()
            .fill(TenXPalette.color(TenXPalette.separatorHex))
            .frame(width: 1)
    }

    private var emptyHeading: String? {
        if let inlineMessage = model.inlineMessage { return inlineMessage }
        if let item = selectedSourceItem, item.count == 0, let message = item.message {
            return message == "Start a session to use OMP commands."
                ? message
                : "Session commands unavailable"
        }
        return model.visibleRows.isEmpty ? modelPresentationHeading : nil
    }

    private var modelPresentationHeading: String? {
        let selected = model.selectedSource
        let rows = model.visibleRows
        if rows.isEmpty, model.catalogState == .loading, selected != .app {
            return "Loading session commands…"
        }
        if rows.isEmpty, !query.isEmpty {
            return "No commands match “/\(query)”."
        }
        if rows.isEmpty {
            return selectedSourceItem?.message ?? currentPresentationHeadingFallback
        }
        return nil
    }

    private var currentPresentationHeadingFallback: String? {
        if case .unavailable = model.catalogState {
            return "Session commands unavailable"
        }
        return nil
    }

    private var emptyBody: String? {
        if let item = selectedSourceItem, item.count == 0, let message = item.message {
            return message == emptyHeading ? nil : message
        }
        if model.visibleRows.isEmpty, case .unavailable = model.catalogState {
            return "Model, Effort, and Fast remain available. Retry after the session reconnects."
        }
        return nil
    }

    private var accessibilitySummary: String {
        guard let item = selectedSourceItem else {
            return CommandBrowserAccessibility.helpText()
        }
        return CommandBrowserAccessibility.sourceSelectionAnnouncement(
            source: item.id,
            count: item.count,
            message: item.message)
    }

    private var sourceAnnouncementState: String {
        guard let item = selectedSourceItem else { return "" }
        return [
            item.id.rawValue,
            "\(item.count)",
            item.message ?? "",
        ].joined(separator: "|")
    }

    private func activateHighlightedRow() {
        Task {
            let effect = await model.activate()
            onEffect(effect)
            if CommandBrowserNativeControlsView.shouldRestoreEditorFocus(
                effect: effect,
                isPresented: model.isPresented,
                route: model.route) {
                restoreEditorFocus()
            }
        }
    }

    static func panelSize(for available: CGSize) -> CGSize {
        CGSize(
            width: min(available.width, 780),
            height: min(
                max(available.height, CommandBrowserMetrics.minimumHeight),
                CommandBrowserMetrics.maximumHeight))
    }

    static func sourceSelectionNavigation(for route: CommandBrowserRoute) -> CommandBrowserSourceSelectionNavigation {
        route == .root ? .stayRoot : .backToRoot
    }

    static func selectedRowScrollTarget(
        _ selectedRowID: CommandBrowserRowID?,
        visibleRows: [CommandBrowserRow]
    ) -> CommandBrowserRowID? {
        guard let selectedRowID else { return nil }
        return CommandBrowserPresentation.retainedSelection(selectedRowID, in: visibleRows)
    }

    private func dismiss() {
        onEffect(model.dismiss())
        onDismiss()
        restoreEditorFocus()
    }

    private func selectSource(_ source: CommandBrowserSource) {
        if Self.sourceSelectionNavigation(for: model.route) == .backToRoot {
            onEffect(model.back())
        }
        model.selectSource(source)
    }

    private func scrollToSelectedRow(with proxy: ScrollViewProxy) {
        guard let target = Self.selectedRowScrollTarget(model.selectedRowID, visibleRows: model.visibleRows) else { return }
        proxy.scrollTo(target, anchor: .center)
    }

    private func announceCatalogState(_ state: ComposerCommandCatalogState) {
        let signature: String
        let message: String?
        switch state {
        case .loading:
            signature = "loading"
            message = "Loading session commands…"
        case .available(let commands):
            signature = "available-\(commands.count)"
            message = CommandBrowserAccessibility.catalogLoadedAnnouncement(count: commands.count)
        case .unavailable:
            signature = "unavailable"
            message = "Session commands unavailable"
        }
        guard signature != announcedCatalogState else { return }
        announcedCatalogState = signature
        if let message {
            announcer.announce(message)
        }
    }

    private func announceSelectedSource(_ state: String) {
        guard !state.isEmpty, state != announcedSourceState else { return }
        announcedSourceState = state
        if let item = selectedSourceItem {
            announcer.announce(CommandBrowserAccessibility.sourceSelectionAnnouncement(
                source: item.id,
                count: item.count,
                message: item.message))
        }
    }
}

private struct CommandBrowserSourceRow: View {
    let item: CommandBrowserSourceItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Rectangle()
                    .fill(isSelected ? TenXPalette.color(TenXPalette.cyanHex) : .clear)
                    .frame(width: 2)
                Text(item.id.rawValue)
                    .font(TenXTypography.body(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected
                        ? TenXPalette.color(TenXPalette.cyanHex)
                        : TenXPalette.color(TenXPalette.nearBlackHex))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(item.count)")
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .lineLimit(1)
            }
            .padding(.trailing, 10)
            .frame(
                maxWidth: .infinity,
                minHeight: CommandBrowserMetrics.rowHeight,
                alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(FlyoutRowBackground(isSelected: isSelected))
        .accessibilityLabel(CommandBrowserAccessibility.sourceLabel(item.id))
        .accessibilityValue(CommandBrowserAccessibility.sourceValue(count: item.count))
        .accessibilityHint(item.message ?? "Show \(item.id.rawValue) commands")
        .accessibilityAction(named: Text(item.id.rawValue), action)
    }
}

private struct CommandBrowserResultRow: View {
    let row: CommandBrowserRow
    let isSelected: Bool
    let position: Int
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(isSelected ? TenXPalette.color(TenXPalette.cyanHex) : .clear)
                    .frame(width: 2)
                Text("/\(row.canonicalName)")
                    .font(TenXTypography.mono(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    .lineLimit(1)
                    .help("/\(row.canonicalName)")
                Spacer(minLength: 8)
                Text(row.summary)
                    .font(TenXTypography.body(size: 11))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .lineLimit(1)
                    .help(row.summary)
            }
            .padding(.trailing, 10)
            .frame(
                maxWidth: .infinity,
                minHeight: CommandBrowserMetrics.rowHeight,
                alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(FlyoutRowBackground(isSelected: isSelected))
        .accessibilityLabel(CommandBrowserAccessibility.rowLabel(
            name: row.canonicalName,
            description: row.summary,
            source: row.source.rawValue,
            position: position,
            count: count,
            executionNote: row.executionNote))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(row.inputHint ?? CommandBrowserAccessibility.helpText())
    }
}

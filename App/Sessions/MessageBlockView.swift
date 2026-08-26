import SwiftUI

struct MessageBlockView: View {
    let block: ContentBlock

    static let proseFontSize: CGFloat = 15
    static let proseLineSpacing: CGFloat = 4

    @ViewBuilder
    var body: some View {
        switch block {
        case .paragraph(let content):
            richText(content)
                .font(TenXTypography.body(size: Self.proseFontSize))
        case .heading(let level, let content):
            richText(content)
                .font(TenXTypography.body(
                    size: level == 1 ? 19 : max(Self.proseFontSize, 18 - CGFloat(level)),
                    weight: .semibold))
                .padding(.top, level == 1 ? 3 : 0)
        case .list(let list):
            ContentListView(list: list)
        case .quote(let blocks):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, child in
                    MessageBlockView(block: child)
                }
            }
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(TenXPalette.color(TenXPalette.nearBlackHex))
                    .frame(width: 2)
            }
        case .table(let table):
            ContentTableView(table: table)
        case .divider:
            Divider()
        case .source(let source):
            CodeBlockView(source: source)
        case .unsupported(let label):
            Text(label)
                .font(TenXTypography.body(size: 12))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
    }

    private func richText(_ content: InlineContent) -> some View {
        Text(content.attributed)
            .lineSpacing(Self.proseLineSpacing)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ContentListView: View {
    let list: ContentList

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker(for: item, index: index))
                            .font(TenXTypography.body(size: 13, weight: .semibold))
                            .frame(width: 22, alignment: .trailing)
                        Text(item.content.attributed)
                            .font(TenXTypography.body(size: MessageBlockView.proseFontSize))
                            .lineSpacing(MessageBlockView.proseLineSpacing)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                        ContentListView(list: child)
                            .padding(.leading, 22)
                    }
                }
            }
        }
    }

    private func marker(for item: ContentListItem, index: Int) -> String {
        if let isChecked = item.isChecked { return isChecked ? "✓" : "○" }
        return switch list.style {
        case .unordered, .task: "•"
        case .ordered(let start): "\(start + index)."
        }
    }
}

private struct ContentTableView: View {
    let table: ContentTable

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tableGrid(isScrollable: false)
            ScrollView(.horizontal) {
                tableGrid(isScrollable: true)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(10)
        .background(TenXPalette.color(TenXPalette.hoverNeutralHex))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func tableGrid(isScrollable: Bool) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 7) {
            tableRow(table.headers, isHeader: true, isScrollable: isScrollable)
            GridRow {
                Divider()
                    .gridCellColumns(table.headers.count)
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, cells in
                tableRow(cells, isHeader: false, isScrollable: isScrollable)
            }
        }
        .frame(maxWidth: isScrollable ? nil : .infinity, alignment: .leading)
    }

    private func tableRow(
        _ cells: [InlineContent],
        isHeader: Bool,
        isScrollable: Bool
    ) -> some View {
        GridRow {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell.attributed)
                    .font(TenXTypography.body(
                        size: 12,
                        weight: isHeader ? .semibold : .regular))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: isScrollable, vertical: true)
                    .frame(maxWidth: isScrollable ? nil : .infinity, alignment: .leading)
            }
        }
    }
}

import SwiftUI

struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        arrangement(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = arrangement(proposal: proposal, subviews: subviews).rows
        for row in rows {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size))
            }
        }
    }

    private func arrangement(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, rows: [Row]) {
        let maximumWidth = proposal.width ?? .greatestFiniteMagnitude
        var rows: [Row] = []
        var row = Row(y: 0, height: 0, items: [])
        var x: CGFloat = 0

        for index in subviews.indices {
            let measuredSize = subviews[index].sizeThatFits(
                ProposedViewSize(width: proposal.width, height: nil))
            let size = CGSize(
                width: min(measuredSize.width, maximumWidth),
                height: measuredSize.height)
            if x > 0, x + size.width > maximumWidth {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing, height: 0, items: [])
                x = 0
            }
            row.items.append(Item(index: index, x: x, size: size))
            row.height = max(row.height, size.height)
            x += size.width + spacing
        }
        if !row.items.isEmpty { rows.append(row) }
        let width = rows.flatMap(\.items).map { $0.x + $0.size.width }.max() ?? 0
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return (CGSize(width: min(width, maximumWidth), height: height), rows)
    }

    private struct Item {
        let index: Int
        let x: CGFloat
        let size: CGSize
    }

    private struct Row {
        let y: CGFloat
        var height: CGFloat
        var items: [Item]
    }
}

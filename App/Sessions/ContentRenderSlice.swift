import Foundation

struct ContentRenderSlice: Equatable, Sendable {
    let document: ContentDocument
    let consumedUnits: Int
    let hasMore: Bool
}

struct ContentDocumentRenderState: Equatable {
    private(set) var source: String?
    private(set) var version: UUID?
    var reveal = ProgressiveReveal(initialLimit: 160, pageSize: 160)

    init(document: ContentDocument? = nil) {
        source = document?.source
        version = document?.renderVersion
    }

    func effective(for document: ContentDocument) -> Self {
        guard let source, let version else { return Self(document: document) }
        if version == document.renderVersion { return self }
        guard document.source.count > source.count,
              document.source.hasPrefix(source)
        else { return Self(document: document) }
        var continued = self
        continued.source = document.source
        continued.version = document.renderVersion
        return continued
    }
}

enum ContentRenderSlicer {
    static func slice(_ document: ContentDocument, limit: Int) -> ContentRenderSlice {
        var budget = Budget(limit: max(0, limit))
        let blocks = document.blocks.compactMap { slice($0, budget: &budget) }
        return ContentRenderSlice(
            document: ContentDocument(
                source: document.source,
                blocks: blocks,
                renderVersion: document.renderVersion),
            consumedUnits: budget.consumed,
            hasMore: budget.consumed < unitCount(document))
    }

    static func unitCount(_ document: ContentDocument) -> Int {
        document.blocks.reduce(0) { $0 + unitCount($1) }
    }

    private static func unitCount(_ block: ContentBlock) -> Int {
        switch block {
        case .paragraph, .heading, .divider, .image, .unsupported:
            1
        case .list(let list):
            unitCount(list)
        case .quote(let blocks):
            blocks.reduce(0) { $0 + unitCount($1) }
        case .table(let table):
            (table.headers.isEmpty ? 0 : 1) + table.rows.count
        case .source(let source):
            source.lines.count
        }
    }

    private static func unitCount(_ list: ContentList) -> Int {
        list.items.reduce(0) { result, item in
            result + 1 + item.children.reduce(0) { $0 + unitCount($1) }
        }
    }

    private static func slice(
        _ block: ContentBlock,
        budget: inout Budget
    ) -> ContentBlock? {
        switch block {
        case .paragraph, .heading, .divider, .image, .unsupported:
            guard budget.consume() else { return nil }
            return block
        case .list(let list):
            guard let list = slice(list, budget: &budget) else { return nil }
            return .list(list)
        case .quote(let blocks):
            let blocks = blocks.compactMap { slice($0, budget: &budget) }
            return blocks.isEmpty ? nil : .quote(blocks)
        case .table(let table):
            guard !table.headers.isEmpty, budget.consume() else { return nil }
            var rows: [[InlineContent]] = []
            for row in table.rows {
                guard budget.consume() else { break }
                rows.append(row)
            }
            return .table(ContentTable(headers: table.headers, rows: rows))
        case .source(let source):
            let count = min(budget.remaining, source.lines.count)
            guard count > 0 else { return nil }
            guard budget.consume(count) else { return nil }
            return .source(SourcePresentation(
                language: source.language,
                text: source.text,
                lines: Array(source.lines.prefix(count)),
                contentID: source.contentID))
        }
    }

    private static func slice(
        _ list: ContentList,
        budget: inout Budget
    ) -> ContentList? {
        var items: [ContentListItem] = []
        for item in list.items {
            guard budget.consume() else { break }
            let children = item.children.compactMap { slice($0, budget: &budget) }
            items.append(ContentListItem(
                content: item.content,
                isChecked: item.isChecked,
                children: children))
        }
        return items.isEmpty ? nil : ContentList(style: list.style, items: items)
    }

    private struct Budget {
        let limit: Int
        var consumed = 0

        var remaining: Int { limit - consumed }

        mutating func consume(_ count: Int = 1) -> Bool {
            guard count <= remaining else { return false }
            consumed += count
            return true
        }
    }
}

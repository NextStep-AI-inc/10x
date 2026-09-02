import Foundation

struct ContentDocument: Equatable, Sendable {
    let source: String
    let blocks: [ContentBlock]
    let renderIdentity: Int

    init(source: String, blocks: [ContentBlock]) {
        self.source = source
        self.blocks = blocks
        renderIdentity = Self.makeRenderIdentity(source: source, blocks: blocks)
    }

    static let empty = ContentDocument(source: "", blocks: [])

    var plainText: String {
        blocks.map(\.plainText).joined(separator: "\n")
    }

    var images: [ContentImage] {
        blocks.compactMap { block in
            guard case .image(let image) = block else { return nil }
            return image
        }
    }

    private static func makeRenderIdentity(source: String, blocks: [ContentBlock]) -> Int {
        var hasher = Hasher()
        hasher.combine(source)
        hasher.combine(blocks.count)
        blocks.forEach { combine($0, into: &hasher) }
        return hasher.finalize()
    }

    private static func combine(_ block: ContentBlock, into hasher: inout Hasher) {
        switch block {
        case .paragraph(let content):
            hasher.combine(0); hasher.combine(content.source)
        case .heading(let level, let content):
            hasher.combine(1); hasher.combine(level); hasher.combine(content.source)
        case .list(let list):
            hasher.combine(2); combine(list, into: &hasher)
        case .quote(let blocks):
            hasher.combine(3)
            hasher.combine(blocks.count)
            blocks.forEach { combine($0, into: &hasher) }
        case .table(let table):
            hasher.combine(4)
            hasher.combine(table.headers.count)
            table.headers.forEach { hasher.combine($0.source) }
            hasher.combine(table.rows.count)
            table.rows.forEach { row in
                hasher.combine(row.count)
                row.forEach { hasher.combine($0.source) }
            }
        case .divider:
            hasher.combine(5)
        case .source(let source):
            hasher.combine(6); hasher.combine(source.language); hasher.combine(source.text)
        case .image(let image):
            hasher.combine(7); hasher.combine(image.data); hasher.combine(image.mimeType)
        case .unsupported(let label):
            hasher.combine(8); hasher.combine(label)
        }
    }

    private static func combine(_ list: ContentList, into hasher: inout Hasher) {
        switch list.style {
        case .unordered: hasher.combine(0)
        case .ordered(let start): hasher.combine(1); hasher.combine(start)
        case .task: hasher.combine(2)
        }
        hasher.combine(list.items.count)
        for item in list.items {
            hasher.combine(item.content.source)
            hasher.combine(item.isChecked)
            hasher.combine(item.children.count)
            item.children.forEach { combine($0, into: &hasher) }
        }
    }
}

indirect enum ContentBlock: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case paragraph
        case heading
        case list
        case quote
        case table
        case divider
        case source
        case image
        case unsupported
    }

    case paragraph(InlineContent)
    case heading(level: Int, content: InlineContent)
    case list(ContentList)
    case quote([ContentBlock])
    case table(ContentTable)
    case divider
    case source(SourcePresentation)
    case image(ContentImage)
    case unsupported(label: String)

    var kind: Kind {
        switch self {
        case .paragraph: .paragraph
        case .heading: .heading
        case .list: .list
        case .quote: .quote
        case .table: .table
        case .divider: .divider
        case .source: .source
        case .image: .image
        case .unsupported: .unsupported
        }
    }

    var plainText: String {
        switch self {
        case .paragraph(let content), .heading(_, let content):
            content.plainText
        case .list(let list):
            list.plainText
        case .quote(let blocks):
            blocks.map(\.plainText).joined(separator: "\n")
        case .table(let table):
            ([table.headers] + table.rows).map { row in
                row.map(\.plainText).joined(separator: "\t")
            }.joined(separator: "\n")
        case .divider:
            ""
        case .source(let source):
            source.text
        case .image(let image):
            image.label
        case .unsupported(let label):
            label
        }
    }
}

/// An image carried inside a message, decoded from the session file's base64.
struct ContentImage: Equatable, Sendable {
    let data: Data
    let mimeType: String

    /// Read aloud and used as the plain-text stand-in when the image cannot be
    /// shown, so a transcript copied to the clipboard still records it.
    var label: String { "Image attachment" }
}

struct InlineContent: Equatable, Sendable {
    let source: String
    let attributed: AttributedString

    var plainText: String {
        String(attributed.characters)
    }
}

struct ContentList: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        case unordered
        case ordered(start: Int)
        case task
    }

    let style: Style
    let items: [ContentListItem]

    var plainText: String {
        items.map { item in
            ([item.content.plainText] + item.children.map(\.plainText))
                .joined(separator: "\n")
        }.joined(separator: "\n")
    }
}

struct ContentListItem: Equatable, Sendable {
    let content: InlineContent
    let isChecked: Bool?
    let children: [ContentList]
}

struct ContentTable: Equatable, Sendable {
    let headers: [InlineContent]
    let rows: [[InlineContent]]
}

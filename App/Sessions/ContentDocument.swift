import Foundation

struct ContentDocument: Equatable, Sendable {
    let source: String
    let blocks: [ContentBlock]
    let renderVersion: UUID
    let predecessorRenderVersion: UUID?

    init(
        source: String,
        blocks: [ContentBlock],
        renderVersion: UUID = UUID(),
        predecessorRenderVersion: UUID? = nil
    ) {
        self.source = source
        self.blocks = blocks
        self.renderVersion = renderVersion
        self.predecessorRenderVersion = predecessorRenderVersion
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source && lhs.blocks == rhs.blocks
    }

    func assigningRenderLineage(after previous: Self) -> Self {
        if self == previous {
            return Self(
                source: source,
                blocks: blocks,
                renderVersion: previous.renderVersion,
                predecessorRenderVersion: previous.predecessorRenderVersion)
        }
        guard source.count > previous.source.count,
              source.hasPrefix(previous.source)
        else { return self }
        return Self(
            source: source,
            blocks: blocks,
            renderVersion: renderVersion,
            predecessorRenderVersion: previous.renderVersion)
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

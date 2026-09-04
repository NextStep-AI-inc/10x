import Foundation
import OmpKit

struct TranscriptSearchResolution: Equatable, Sendable {
    let rowID: String
    let groupID: String?
    let messageID: String?
    var excerpt: String? = nil
}

enum TranscriptSearchResolver {
    static func resolve(
        _ request: TranscriptSearchRequest,
        in rows: [TranscriptPresentationRow]
    ) -> TranscriptSearchResolution? {
        for row in rows {
            switch row {
            case .item(.message(let message))
                where message.renderLineageKey.baseMessageID == request.entryID:
                guard !TranscriptTextSegments.matchRanges(
                    in: message.visibleText,
                    query: request.query).isEmpty
                else { continue }
                return TranscriptSearchResolution(
                    rowID: row.id,
                    groupID: nil,
                    messageID: message.id,
                    excerpt: message.role == .user && TranscriptMessage.advisoryContent(from: message.raw) == nil
                        ? nil : excerpt(in: message.visibleText, query: request.query))
            case .item(.tool(let tool)) where tool.id == request.entryID:
                guard let match = excerpt(in: toolText(tool), query: request.query) else { continue }
                return TranscriptSearchResolution(
                    rowID: row.id,
                    groupID: nil,
                    messageID: nil, excerpt: match)
            case .groupedTool(let groupID, let tool) where tool.id == request.entryID:
                guard let match = excerpt(in: toolText(tool), query: request.query) else { continue }
                return TranscriptSearchResolution(
                    rowID: row.id,
                    groupID: groupID,
                    messageID: nil, excerpt: match)
            default:
                continue
            }
        }
        return nil
    }

    private static func excerpt(in text: String, query: String) -> String? {
        guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive],
                                     locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let start = text.index(range.lowerBound, offsetBy: -80, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 100, limitedBy: text.endIndex) ?? text.endIndex
        return (start == text.startIndex ? "" : "…") + String(text[start..<end])
            + (end == text.endIndex ? "" : "…")
    }

    private static func toolText(_ tool: ToolPresentation) -> String {
        ([tool.name] + strings(in: tool.arguments)
            + [tool.result.map { TranscriptMessage.visibleText(from: $0) } ?? ""])
            .joined(separator: " ")
    }

    private static func strings(in value: JSONValue) -> [String] {
        switch value {
        case .string(let text): [text]
        case .array(let values): values.flatMap(strings)
        case .object(let values): values.keys.sorted().flatMap { key in values[key].map(strings) ?? [] }
        default: []
        }
    }
}

import Foundation
import OmpKit

enum SessionSearchDocumentBuilder {
    private static let normalizationLocale = Locale(identifier: "en_US_POSIX")

    static func documents(
        metadata: SessionMetadata,
        parsed: ParsedSessionFile
    ) throws -> [SessionSearchDocument] {
        var documents = [
            SessionSearchDocument(
                sessionPath: metadata.path,
                entryID: nil,
                projectPath: metadata.cwd,
                title: metadata.title ?? "Untitled session",
                excerpt: metadata.cwd,
                kind: .session,
                sessionModified: metadata.modified.timeIntervalSince1970,
                entryOrder: 0,
                normalizedText: normalize(
                    [metadata.title, metadata.cwd, metadata.path]
                        .compactMap { $0 }
                        .joined(separator: " "))),
        ]

        for entry in parsed.entries {
            try Task.checkCancellation()
            guard case .message(let base, let message) = entry else { continue }
            let kind = kind(for: message)
            let displayText = displayText(for: message, kind: kind)
            documents.append(SessionSearchDocument(
                sessionPath: metadata.path,
                entryID: base.id,
                projectPath: metadata.cwd,
                title: title(for: message, kind: kind),
                excerpt: excerpt(from: displayText),
                kind: kind,
                sessionModified: metadata.modified.timeIntervalSince1970,
                entryOrder: documents.count,
                normalizedText: normalize(strings(in: message).joined(separator: " "))))
        }
        return documents
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: normalizationLocale)
            .lowercased(with: normalizationLocale)
    }

    private static func strings(in value: JSONValue) -> [String] {
        switch value {
        case .string(let string):
            [string]
        case .array(let values):
            values.flatMap(strings)
        case .object(let object):
            object.keys.sorted() + object.keys.sorted().flatMap { key in
                object[key].map(strings) ?? []
            }
        case .bool(let value):
            [value ? "true" : "false"]
        case .int(let value):
            [String(value)]
        case .double(let value):
            [String(value)]
        case .null:
            []
        }
    }

    private static func kind(for message: JSONValue) -> SearchResultKind {
        if message["role"]?.stringValue == "toolResult" { return .tool }
        let hasToolCall = message["content"]?.arrayValue?.contains { block in
            block["type"]?.stringValue == "toolCall"
        } == true
        return hasToolCall ? .tool : .message
    }

    private static func title(for message: JSONValue, kind: SearchResultKind) -> String {
        if kind == .tool {
            if let name = message["toolName"]?.stringValue { return name }
            if let block = message["content"]?.arrayValue?.first(where: {
                $0["type"]?.stringValue == "toolCall"
            }), let name = block["name"]?.stringValue {
                return name
            }
            return "Tool activity"
        }
        return message["role"]?.stringValue == "user" ? "You" : "10x"
    }

    private static func displayText(for message: JSONValue, kind: SearchResultKind) -> String {
        let blocks = message["content"]?.arrayValue ?? []
        let blockText = blocks.flatMap { block -> [String] in
            switch block["type"]?.stringValue {
            case "text", "thinking":
                return block["text"]?.stringValue.map { [$0] } ?? []
            case "toolCall":
                let name = block["name"]?.stringValue.map { [$0] } ?? []
                let values = block["arguments"].map(valueStrings) ?? []
                return name + values
            default:
                return block["content"].map(valueStrings) ?? []
            }
        }
        if !blockText.isEmpty { return blockText.joined(separator: " ") }
        if let content = message["content"] {
            return valueStrings(in: content).joined(separator: " ")
        }
        return kind == .tool ? "Tool activity" : "Session message"
    }

    private static func valueStrings(in value: JSONValue) -> [String] {
        switch value {
        case .string(let string): [string]
        case .array(let values): values.flatMap(valueStrings)
        case .object(let object): object.keys.sorted().flatMap { key in
            object[key].map(valueStrings) ?? []
        }
        case .bool(let value): [value ? "true" : "false"]
        case .int(let value): [String(value)]
        case .double(let value): [String(value)]
        case .null: []
        }
    }

    private static func excerpt(from text: String) -> String {
        let compact = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard compact.count > 180 else { return compact }
        return String(compact.prefix(177)) + "…"
    }
}

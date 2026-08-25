import Foundation
import OmpKit

actor SessionSearchService {
    func search(query: String, sessions: [SessionMetadata]) async -> [SearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var results: [SearchResult] = []
        for session in sessions.sorted(by: { $0.modified > $1.modified }) {
            guard !Task.isCancelled, results.count < 200 else { break }

            let sessionText = [session.title, session.cwd, session.path]
                .compactMap { $0 }
                .joined(separator: " ")
            if Self.matches(sessionText, query: query) {
                results.append(SearchResult(
                    sessionPath: session.path,
                    entryID: nil,
                    projectPath: session.cwd,
                    title: session.title ?? "Untitled session",
                    excerpt: session.cwd,
                    kind: .session))
            }

            guard results.count < 200,
                  let data = try? Data(contentsOf: URL(filePath: session.path)),
                  let parsed = try? SessionFileParser.parse(data: data)
            else { continue }

            for entry in parsed.entries {
                guard !Task.isCancelled, results.count < 200 else { break }
                guard case .message(let base, let message) = entry else { continue }
                let searchText = Self.strings(in: message).joined(separator: " ")
                guard Self.matches(searchText, query: query) else { continue }

                let kind = Self.kind(for: message)
                let displayText = Self.displayText(for: message, kind: kind)
                results.append(SearchResult(
                    sessionPath: session.path,
                    entryID: base.id,
                    projectPath: session.cwd,
                    title: Self.title(for: message, kind: kind),
                    excerpt: Self.excerpt(from: displayText),
                    kind: kind))
            }
        }
        return results
    }

    private static func matches(_ value: String, query: String) -> Bool {
        value.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current) != nil
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
        if let content = message["content"] { return valueStrings(in: content).joined(separator: " ") }
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

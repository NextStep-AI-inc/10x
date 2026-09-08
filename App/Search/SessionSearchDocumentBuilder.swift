import Foundation
import OmpKit

enum SessionSearchDocumentBuilder {
    private static let normalizationLocale = Locale(identifier: "en_US_POSIX")

    static func documents(
        metadata: SessionMetadata,
        parsed: ParsedSessionFile
    ) throws -> [SessionSearchDocument] {
        var documents = [sessionDocument(metadata: metadata)]
        var toolDocumentIndices: [String: Int] = [:]

        for entry in SessionTree.activePath(of: parsed) {
            try Task.checkCancellation()
            guard case .message(let base, let message) = entry,
                  TranscriptMessage.isDisplayable(message)
            else { continue }

            if message["role"]?.stringValue == "toolResult" {
                appendToolResult(
                    message,
                    metadata: metadata,
                    documents: &documents,
                    indices: &toolDocumentIndices)
                continue
            }

            let visibleText = TranscriptMessage.visibleText(from: message)
            if !visibleText.isEmpty {
                documents.append(document(
                    metadata: metadata,
                    entryID: base.id,
                    title: message["role"]?.stringValue == "user" ? "You" : "10x",
                    text: visibleText,
                    kind: .message,
                    entryOrder: documents.count))
            }

            for block in message["content"]?.arrayValue ?? [] {
                guard isToolCall(block),
                      let toolID = firstNonEmpty(
                        block["id"]?.stringValue,
                        block["toolCallId"]?.stringValue),
                      let name = firstNonEmpty(
                        block["name"]?.stringValue,
                        block["toolName"]?.stringValue)
                else { continue }
                let text = ([name] + valueStrings(
                    in: block["arguments"] ?? block["args"] ?? .object([:])))
                    .joined(separator: " ")
                appendOrMergeTool(
                    id: toolID,
                    title: name,
                    text: text,
                    metadata: metadata,
                    documents: &documents,
                    indices: &toolDocumentIndices)
            }
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

    private static func sessionDocument(metadata: SessionMetadata) -> SessionSearchDocument {
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
                    .joined(separator: " ")))
    }

    private static func appendToolResult(
        _ message: JSONValue,
        metadata: SessionMetadata,
        documents: inout [SessionSearchDocument],
        indices: inout [String: Int]
    ) {
        guard let toolID = message["toolCallId"]?.stringValue, !toolID.isEmpty else { return }
        let title = message["toolName"]?.stringValue ?? "Tool activity"
        let resultText = TranscriptMessage.visibleText(from: message)
        guard !resultText.isEmpty else { return }
        appendOrMergeTool(
            id: toolID,
            title: title,
            text: resultText,
            metadata: metadata,
            documents: &documents,
            indices: &indices)
    }

    private static func appendOrMergeTool(
        id: String,
        title: String,
        text: String,
        metadata: SessionMetadata,
        documents: inout [SessionSearchDocument],
        indices: inout [String: Int]
    ) {
        if let index = indices[id] {
            let existing = documents[index]
            let combinedExcerpt = [existing.excerpt, text]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            documents[index] = SessionSearchDocument(
                sessionPath: metadata.path,
                entryID: id,
                projectPath: metadata.cwd,
                title: existing.title == "Tool activity" ? title : existing.title,
                excerpt: excerpt(from: combinedExcerpt),
                kind: .tool,
                sessionModified: metadata.modified.timeIntervalSince1970,
                entryOrder: existing.entryOrder,
                normalizedText: [existing.normalizedText, normalize(text)]
                    .filter { !$0.isEmpty }
                    .joined(separator: " "))
            return
        }
        indices[id] = documents.count
        documents.append(document(
            metadata: metadata,
            entryID: id,
            title: title,
            text: text,
            kind: .tool,
            entryOrder: documents.count))
    }

    private static func document(
        metadata: SessionMetadata,
        entryID: String,
        title: String,
        text: String,
        kind: SearchResultKind,
        entryOrder: Int
    ) -> SessionSearchDocument {
        SessionSearchDocument(
            sessionPath: metadata.path,
            entryID: entryID,
            projectPath: metadata.cwd,
            title: title,
            excerpt: excerpt(from: text),
            kind: kind,
            sessionModified: metadata.modified.timeIntervalSince1970,
            entryOrder: entryOrder,
            normalizedText: normalize(text))
    }

    private static func isToolCall(_ block: JSONValue) -> Bool {
        let type = block["type"]?.stringValue?.filter(\.isLetter).lowercased()
        return type == "toolcall" || type == "tooluse"
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

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.isEmpty { return value }
        }
        return nil
    }

    private static func excerpt(from text: String) -> String {
        let compact = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard compact.count > 180 else { return compact }
        return String(compact.prefix(177)) + "…"
    }
}

import Foundation
import OmpKit

enum TranscriptMessageNormalizer {
    static func items(
        id: String,
        raw: JSONValue,
        timestamp: Date? = nil,
        attribution: TranscriptResponseAttribution = .none,
        isFinal: Bool,
        existingTools: [String: ToolPresentation] = [:],
        previousDocuments: [String: ContentDocument] = [:],
        fallbackDate: Date = Date()
    ) -> [TranscriptItem] {
        guard raw["role"]?.stringValue == "assistant",
              let content = raw["content"]?.arrayValue
        else {
            let message = TranscriptMessage(
                id: id,
                raw: raw,
                timestamp: timestamp,
                attribution: attribution,
                isFinal: isFinal,
                previousDocument: previousDocuments[id])
            let retainsPlaceholder = message.role == .assistant && !isFinal
            return shouldEmit(message, raw: raw) || retainsPlaceholder
                ? [.message(message)]
                : []
        }

        var result: [TranscriptItem] = []
        var visibleSegment = 0
        var hasVisibleMessage = false
        var blockRun: [JSONValue] = []
        var emittedToolIDs: Set<String> = []

        for block in content {
            if let tool = toolPresentation(
                from: block,
                raw: raw,
                timestamp: timestamp,
                existingTools: existingTools,
                fallbackDate: fallbackDate) {
                guard emittedToolIDs.insert(tool.id).inserted else { continue }
                flush(
                    blockRun,
                    into: &result,
                    id: id,
                    visibleSegment: &visibleSegment,
                    hasVisibleMessage: &hasVisibleMessage,
                    raw: raw,
                    timestamp: timestamp,
                    attribution: attribution,
                    isFinal: isFinal,
                    previousDocuments: previousDocuments)
                blockRun.removeAll(keepingCapacity: true)
                result.append(.tool(tool))
            } else {
                blockRun.append(block)
            }
        }
        flush(
            blockRun,
            into: &result,
            id: id,
            visibleSegment: &visibleSegment,
            hasVisibleMessage: &hasVisibleMessage,
            raw: raw,
            timestamp: timestamp,
            attribution: attribution,
            isFinal: isFinal,
            previousDocuments: previousDocuments)

        let terminalFailure = isTerminalFailure(raw)
        if !hasVisibleMessage, terminalFailure {
            let failure = TranscriptMessage(
                id: segmentID(base: id, ordinal: visibleSegment),
                raw: raw,
                timestamp: timestamp,
                attribution: attribution,
                isFinal: isFinal,
                showsResponseMetadata: true,
                previousDocument: previousDocuments[segmentID(
                    base: id,
                    ordinal: visibleSegment)])
            result.append(.message(failure))
        } else if result.isEmpty, content.isEmpty, !isFinal {
            let placeholder = TranscriptMessage(
                id: id,
                raw: raw,
                timestamp: timestamp,
                attribution: attribution,
                isFinal: isFinal,
                showsResponseMetadata: true,
                previousDocument: previousDocuments[id])
            result.append(.message(placeholder))
        }
        return result
    }

    private static func flush(
        _ blocks: [JSONValue],
        into result: inout [TranscriptItem],
        id: String,
        visibleSegment: inout Int,
        hasVisibleMessage: inout Bool,
        raw: JSONValue,
        timestamp: Date?,
        attribution: TranscriptResponseAttribution,
        isFinal: Bool,
        previousDocuments: [String: ContentDocument]
    ) {
        guard !blocks.isEmpty else { return }
        guard case .object(var messageObject) = raw else { return }
        messageObject["content"] = .array(blocks)
        let messageRaw = JSONValue.object(messageObject)
        let messageID = segmentID(base: id, ordinal: visibleSegment)
        let candidate = TranscriptMessage(
            id: messageID,
            raw: messageRaw,
            timestamp: timestamp,
            attribution: attribution,
            isFinal: isFinal,
            showsResponseMetadata: !hasVisibleMessage,
            previousDocument: previousDocuments[messageID])
        guard shouldEmitVisible(candidate, raw: messageRaw) else { return }
        result.append(.message(candidate))
        hasVisibleMessage = true
        visibleSegment += 1
    }

    private static func shouldEmit(
        _ message: TranscriptMessage,
        raw: JSONValue
    ) -> Bool {
        guard TranscriptMessage.isDisplayable(raw) else { return false }
        if message.role == .user { return true }
        if !message.visibleText.isEmpty || !message.document.blocks.isEmpty { return true }
        return message.role == .assistant && isTerminalFailure(raw)
    }

    private static func shouldEmitVisible(
        _ message: TranscriptMessage,
        raw: JSONValue
    ) -> Bool {
        guard TranscriptMessage.isDisplayable(raw) else { return false }
        return !TranscriptMessage.visibleText(from: raw).isEmpty
            || !message.document.images.isEmpty
    }

    private static func toolPresentation(
        from block: JSONValue,
        raw: JSONValue,
        timestamp: Date?,
        existingTools: [String: ToolPresentation],
        fallbackDate: Date
    ) -> ToolPresentation? {
        guard let type = block["type"]?.stringValue,
              compact(type) == "toolcall" || compact(type) == "tooluse",
              let id = firstNonEmpty(block["id"]?.stringValue, block["toolCallId"]?.stringValue),
              let name = firstNonEmpty(block["name"]?.stringValue, block["toolName"]?.stringValue)
        else { return nil }

        if let existing = existingTools[id] {
            var refreshed = existing
            refreshed.name = name
            if let arguments = block["arguments"] ?? block["args"] {
                refreshed.arguments = arguments
            }
            return refreshed
        }
        let startDate = TranscriptMessage.messageDate(raw) ?? timestamp ?? fallbackDate
        return ToolPresentation(
            id: id,
            name: name,
            arguments: block["arguments"] ?? block["args"] ?? .object([:]),
            result: nil,
            phase: .running,
            startDate: startDate,
            endDate: nil)
    }

    private static func segmentID(base: String, ordinal: Int) -> String {
        ordinal == 0 ? base : "\(base)-segment-\(ordinal)"
    }

    private static func compact(_ type: String) -> String {
        type.filter(\.isLetter).lowercased()
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.isEmpty { return value }
        }
        return nil
    }

    private static func isTerminalFailure(_ raw: JSONValue) -> Bool {
        guard raw["role"]?.stringValue?.lowercased() == "assistant" else { return false }
        let stopReason = raw["stopReason"]?.stringValue?.lowercased()
        return stopReason == "error" || stopReason == "aborted"
    }
}

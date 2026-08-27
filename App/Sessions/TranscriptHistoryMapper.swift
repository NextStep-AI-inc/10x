import Foundation
import OmpKit

struct TranscriptHistory: Equatable, Sendable {
    let items: [TranscriptItem]
}

enum TranscriptHistoryMapper {
    static func map(header: SessionHeader, path: [SessionEntry]) -> TranscriptHistory {
        var mapper = Mapper()
        mapper.items.append(.threadStart(
            id: "thread-start-\(header.id)",
            date: date(from: header.timestamp)))
        for entry in path {
            mapper.consume(entry)
        }
        return TranscriptHistory(items: mapper.items)
    }

    private struct Mapper {
        var items: [TranscriptItem] = []
        var currentModel: SessionModelSelection?
        var currentMode: String?
        var sessionInit: SessionInitMetadata?
        var hasConversation = false

        mutating func consume(_ entry: SessionEntry) {
            switch entry {
            case .message(let base, let message):
                consumeMessage(base: base, message: message)
            case .modelChange(let base, let selection):
                currentModel = selection
                if hasConversation {
                    appendAnnotation(modelAnnotation(base: base, selection: selection))
                }
            case .thinkingLevelChange(let base, let selection):
                if hasConversation {
                    appendAnnotation(thinkingAnnotation(base: base, selection: selection))
                }
            case .modeChange(let base, let selection):
                currentMode = selection.mode == "none" ? nil : selection.mode
                if hasConversation {
                    appendAnnotation(modeAnnotation(base: base, mode: selection.mode))
                }
            case .sessionInit(_, let metadata):
                sessionInit = metadata
            case .compaction(let base, let compaction):
                appendAnnotation(compactionAnnotation(base: base, compaction: compaction))
            case .branchSummary(let base, let branch):
                appendAnnotation(TranscriptAnnotation(
                    id: base.id,
                    kind: .branch,
                    title: "Branch summarized",
                    detail: branch.summary,
                    timestamp: TranscriptHistoryMapper.date(from: base.timestamp),
                    tone: .neutral))
            case .labelEntry, .resetBoundary, .unknown:
                break
            }
        }

        mutating func consumeMessage(base: SessionEntryBase, message: JSONValue) {
            if let toolResult = toolResultPresentation(
                message,
                fallbackDate: TranscriptHistoryMapper.date(from: base.timestamp)) {
                mergeToolResult(toolResult, message: message)
                return
            }

            let transcriptMessage = TranscriptMessage(
                id: base.id,
                raw: message,
                timestamp: TranscriptHistoryMapper.date(from: base.timestamp),
                attribution: attribution,
                isFinal: true)
            let isTerminalFailure = transcriptMessage.role == .assistant
                && ["error", "aborted"].contains(message["stopReason"]?.stringValue?.lowercased())
            // Tool calls on the entry are still collected below: only the
            // message body is withheld.
            if TranscriptMessage.isDisplayable(message),
               transcriptMessage.role == .user
                || !transcriptMessage.visibleText.isEmpty
                || isTerminalFailure {
                items.append(.message(transcriptMessage))
                hasConversation = true
            }
            items.append(contentsOf: toolCallPresentations(
                message,
                fallbackDate: TranscriptHistoryMapper.date(from: base.timestamp))
                .map(TranscriptItem.tool))
        }

        var attribution: TranscriptResponseAttribution {
            TranscriptResponseAttribution(
                provider: provider(from: currentModel?.model),
                model: modelID(from: currentModel?.model) ?? sessionInit?.resolvedModel,
                mode: currentMode,
                agent: sessionInit?.agent,
                modelRole: sessionInit?.modelRole)
        }

        mutating func mergeToolResult(_ result: ToolPresentation, message: JSONValue) {
            if let index = items.firstIndex(where: { $0.id == result.id }),
               case .tool(var existing) = items[index] {
                existing.result = message
                existing.phase = result.phase
                existing.endDate = result.endDate
                items[index] = .tool(existing)
            } else {
                items.append(.tool(result))
            }
            items.append(contentsOf: SubagentEventReducer.presentations(
                from: message,
                parentToolCallID: result.id).map(TranscriptItem.subagent))
        }

        mutating func appendAnnotation(_ annotation: TranscriptAnnotation) {
            if case .annotation(let previous) = items.last,
               previous.kind == annotation.kind,
               previous.title == annotation.title,
               previous.detail == annotation.detail {
                return
            }
            items.append(.annotation(annotation))
        }
    }

    private static func toolCallPresentations(
        _ message: JSONValue,
        fallbackDate: Date?
    ) -> [ToolPresentation] {
        let timestamp = TranscriptMessage.messageDate(message) ?? fallbackDate ?? Date()
        return message["content"]?.arrayValue?.compactMap { block in
            guard block["type"]?.stringValue == "toolCall",
                  let id = block["id"]?.stringValue ?? block["toolCallId"]?.stringValue,
                  let name = block["name"]?.stringValue ?? block["toolName"]?.stringValue
            else { return nil }
            return ToolPresentation(
                id: id,
                name: name,
                arguments: block["arguments"] ?? block["args"] ?? .object([:]),
                result: nil,
                phase: .running,
                startDate: timestamp,
                endDate: nil)
        } ?? []
    }

    private static func toolResultPresentation(
        _ message: JSONValue,
        fallbackDate: Date?
    ) -> ToolPresentation? {
        guard message["role"]?.stringValue == "toolResult",
              let id = message["toolCallId"]?.stringValue
        else { return nil }
        let timestamp = TranscriptMessage.messageDate(message) ?? fallbackDate ?? Date()
        return ToolPresentation(
            id: id,
            name: message["toolName"]?.stringValue ?? "Unknown tool",
            arguments: .object([:]),
            result: message,
            phase: message["isError"]?.boolValue == true ? .failed : .complete,
            startDate: timestamp,
            endDate: timestamp)
    }

    private static func modelAnnotation(
        base: SessionEntryBase,
        selection: SessionModelSelection
    ) -> TranscriptAnnotation {
        var details: [String] = []
        if let role = selection.role, role != "default" { details.append(role.capitalized) }
        if selection.resolvedModelIsFallback { details.append("fallback") }
        return TranscriptAnnotation(
            id: base.id,
            kind: .model,
            title: "Model changed to \(modelLabel(selection.model))",
            detail: details.isEmpty ? nil : details.joined(separator: " "),
            timestamp: date(from: base.timestamp),
            tone: selection.resolvedModelIsFallback ? .warning : .interactive)
    }

    private static func thinkingAnnotation(
        base: SessionEntryBase,
        selection: SessionThinkingSelection
    ) -> TranscriptAnnotation {
        TranscriptAnnotation(
            id: base.id,
            kind: .thinking,
            title: "Thinking set to \((selection.effective ?? "inherit").capitalized)",
            detail: selection.configured?.capitalized,
            timestamp: date(from: base.timestamp),
            tone: .neutral)
    }

    private static func modeAnnotation(
        base: SessionEntryBase,
        mode: String
    ) -> TranscriptAnnotation {
        TranscriptAnnotation(
            id: base.id,
            kind: .mode,
            title: mode == "none" ? "Mode ended" : "\(mode.capitalized) mode",
            detail: nil,
            timestamp: date(from: base.timestamp),
            tone: .interactive)
    }

    private static func compactionAnnotation(
        base: SessionEntryBase,
        compaction: SessionCompaction
    ) -> TranscriptAnnotation {
        let detail: String?
        if let before = compaction.tokensBefore, let after = compaction.tokensAfter {
            detail = "\(formatted(before)) → \(formatted(after)) tokens"
        } else {
            detail = compaction.shortSummary
        }
        return TranscriptAnnotation(
            id: base.id,
            kind: .compaction,
            title: "Context compacted",
            detail: detail,
            timestamp: date(from: base.timestamp),
            tone: compaction.warning == nil ? .neutral : .warning)
    }

    private static func formatted(_ number: Int) -> String {
        number.formatted(.number.grouping(.automatic))
    }

    private static func provider(from fullModel: String?) -> String? {
        guard let fullModel, let slash = fullModel.firstIndex(of: "/") else { return nil }
        return String(fullModel[..<slash])
    }

    private static func modelID(from fullModel: String?) -> String? {
        guard let fullModel else { return nil }
        guard let slash = fullModel.firstIndex(of: "/") else { return fullModel }
        return String(fullModel[fullModel.index(after: slash)...])
    }

    private static func modelLabel(_ fullModel: String) -> String {
        let model = modelID(from: fullModel) ?? fullModel
        return model.split(separator: "-").map { component in
            let value = String(component)
            if value.lowercased() == "gpt" { return "GPT" }
            return value.capitalized
        }.joined(separator: "-")
        .replacingOccurrences(of: "-Sol", with: " Sol")
    }

    private static func date(from timestamp: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
    }
}

import Foundation
import OmpKit

struct TranscriptReducer {
    var items: [TranscriptItem] = []
    var runtimeState: SessionRuntimeState = .idle

    private var inflightMessageID: String?
    private var pendingPersistenceIDs: Set<String> = []
    private var nextSyntheticID = 1
    private var toolReducer = ToolEventReducer()
    private var subagentReducer = SubagentEventReducer()

    mutating func consume(_ frame: RpcFrame) {
        guard case .event(let type, let payload) = frame else { return }

        switch type {
        case "agent_start", "turn_start":
            runtimeState = .streaming
        case "agent_end":
            if payload["isTerminal"]?.boolValue != false {
                runtimeState = .idle
            }
        case "prompt_result":
            runtimeState = .idle
        case "message_start":
            guard let message = payload["message"] else { return }
            if consumeToolResult(message) { return }
            let id = messageID(message)
            inflightMessageID = id
            replaceOrAppend(.message(TranscriptMessage(
                id: id,
                raw: message,
                isFinal: false)))
        case "message_update":
            guard let message = payload["message"] else { return }
            let id = inflightMessageID ?? messageID(message)
            inflightMessageID = id
            replaceOrAppend(.message(TranscriptMessage(
                id: id,
                raw: message,
                isFinal: false)))
        case "message_end":
            guard let message = payload["message"] else { return }
            if consumeToolResult(message) { return }
            let id = inflightMessageID ?? messageID(message)
            replaceOrAppend(.message(TranscriptMessage(
                id: id,
                raw: message,
                isFinal: true)))
            pendingPersistenceIDs.insert(id)
            inflightMessageID = nil
        case "notice":
            let id = syntheticID(prefix: "notice")
            items.append(.notice(
                id: id,
                level: payload["level"]?.stringValue ?? "info",
                message: payload["message"]?.stringValue ?? ""))
        case "auto_retry_start":
            appendAnnotation(
                kind: .retry,
                title: "Retrying response",
                detail: retryDetail(payload),
                tone: .warning)
        case "auto_retry_end":
            if payload["success"]?.boolValue == false {
                appendAnnotation(
                    kind: .retry,
                    title: "Response retry failed",
                    detail: payload["finalError"]?.stringValue,
                    tone: .error)
            }
        case "retry_fallback_applied":
            appendAnnotation(
                kind: .model,
                title: "Fallback to \(Self.modelLabel(payload["to"]?.stringValue))",
                detail: payload["role"]?.stringValue.flatMap(Self.nonDefaultRole),
                tone: .warning)
        case "retry_fallback_succeeded":
            appendAnnotation(
                kind: .model,
                title: "Fallback succeeded with \(Self.modelLabel(payload["model"]?.stringValue))",
                detail: payload["role"]?.stringValue.flatMap(Self.nonDefaultRole),
                tone: .interactive)
        case "thinking_level_changed":
            let thinking = payload["resolved"]?.stringValue
                ?? payload["thinkingLevel"]?.stringValue
                ?? "inherit"
            appendAnnotation(
                kind: .thinking,
                title: "Thinking set to \(thinking.capitalized)",
                detail: payload["configured"]?.stringValue?.capitalized,
                tone: .neutral)
        case "auto_compaction_end":
            if payload["aborted"]?.boolValue == true {
                appendAnnotation(
                    kind: .compaction,
                    title: "Context compaction stopped",
                    detail: payload["errorMessage"]?.stringValue,
                    tone: payload["willRetry"]?.boolValue == true ? .warning : .error)
            } else if payload["skipped"]?.boolValue != true {
                appendAnnotation(
                    kind: .compaction,
                    title: "Context compacted",
                    detail: Self.compactionDetail(payload["result"]),
                    tone: .neutral)
            }
        case "tool_execution_start", "tool_execution_update", "tool_execution_end":
            toolReducer.consume(type: type, payload: payload)
            guard let id = payload["toolCallId"]?.stringValue,
                  let presentation = toolReducer.presentations.first(where: { $0.id == id })
            else { return }
            replaceOrAppend(.tool(presentation))
            if type == "tool_execution_end", let result = payload["result"] {
                pendingPersistenceIDs.insert(id)
                subagentReducer.attachResult(parentToolCallID: id, result: result)
                for subagent in subagentReducer.presentations where
                    subagent.parentToolCallID == id {
                    replaceOrAppend(.subagent(subagent))
                }
            }
        case "subagent_lifecycle", "subagent_progress":
            subagentReducer.consume(type: type, payload: payload)
            guard let body = payload["payload"],
                  let presentation = Self.subagent(
                    matching: body,
                    in: subagentReducer.presentations)
            else { return }
            replaceOrAppend(.subagent(presentation))
        default:
            items.append(.rawEvent(
                id: syntheticID(prefix: "event"),
                type: type,
                payload: payload))
        }
    }

    mutating func load(messages: [JSONValue]) {
        items = []
        for (index, message) in messages.enumerated() {
            if let result = Self.toolResultPresentation(message) {
                if let itemIndex = items.firstIndex(where: { $0.id == result.id }),
                   case .tool(var existing) = items[itemIndex] {
                    existing.result = message
                    existing.phase = result.phase
                    existing.endDate = result.endDate
                    items[itemIndex] = .tool(existing)
                } else {
                    items.append(.tool(result))
                }
                items.append(contentsOf: SubagentEventReducer.presentations(
                    from: message,
                    parentToolCallID: result.id).map(TranscriptItem.subagent))
                continue
            }

            let visibleText = Self.visibleMessageText(message)
            if Self.shouldKeepMessage(message, visibleText: visibleText) {
                items.append(.message(TranscriptMessage(
                    id: message["id"]?.stringValue ?? "history-\(index)",
                    raw: message,
                    isFinal: true)))
            }
            items.append(contentsOf: Self.toolCallPresentations(message).map(TranscriptItem.tool))
        }
        inflightMessageID = nil
        pendingPersistenceIDs = []
    }

    mutating func load(history: TranscriptHistory) {
        items = history.items
        inflightMessageID = nil
        pendingPersistenceIDs = []
    }

    mutating func ensureThreadStart(date: Date?) {
        guard !items.contains(where: {
            if case .threadStart = $0 { return true }
            return false
        }) else { return }
        items.insert(.threadStart(id: "thread-start-fallback", date: date), at: 0)
    }

    mutating func setReconciliationWarning(isPresented: Bool) {
        items.removeAll { $0.id == "reconciliation-warning" }
        guard isPresented else { return }
        items.append(.annotation(TranscriptAnnotation(
            id: "reconciliation-warning",
            kind: .notice,
            title: "History is catching up",
            detail: "Live updates remain visible.",
            timestamp: nil,
            tone: .warning)))
    }

    mutating func reconcile(history: TranscriptHistory) {
        let persistedIDs = Set(history.items.map(\.id))
        pendingPersistenceIDs.subtract(persistedIDs)
        let transient = items.filter { item in
            guard !persistedIDs.contains(item.id) else { return false }
            if pendingPersistenceIDs.contains(item.id) { return true }
            switch item {
            case .notice, .annotation, .subagent, .extensionUI, .rawEvent:
                return true
            case .tool(let presentation):
                return presentation.phase == .running
            case .message(let message):
                return !message.isFinal
            case .threadStart:
                return false
            }
        }
        items = history.items + transient
        if !items.contains(where: {
            guard case .message(let message) = $0 else { return false }
            return message.id == inflightMessageID
        }) {
            inflightMessageID = nil
        }
    }

    private static func toolCallPresentations(_ message: JSONValue) -> [ToolPresentation] {
        let timestamp = message["timestamp"]?.doubleValue.map {
            Date(timeIntervalSince1970: $0 / 1_000)
        } ?? Date()
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

    private static func subagent(
        matching body: JSONValue,
        in presentations: [SubagentPresentation]
    ) -> SubagentPresentation? {
        let id = body["id"]?.stringValue ?? body["progress"]?["id"]?.stringValue
        if let id { return presentations.first { $0.id == id } }
        guard let index = body["index"]?.intValue else { return nil }
        return presentations.first { $0.index == index }
    }

    private static func visibleMessageText(_ message: JSONValue) -> String {
        if let content = message["content"]?.stringValue { return content }
        return message["content"]?.arrayValue?.compactMap { block in
            guard block["type"]?.stringValue == "text" else { return nil }
            return block["text"]?.stringValue
        }.joined(separator: "\n") ?? ""
    }

    private static func shouldKeepMessage(_ message: JSONValue, visibleText: String) -> Bool {
        if message["role"]?.stringValue == "user" || !visibleText.isEmpty { return true }
        guard message["role"]?.stringValue == "assistant",
              let stopReason = message["stopReason"]?.stringValue?.lowercased()
        else { return false }
        return stopReason == "error" || stopReason == "aborted"
    }

    private mutating func consumeToolResult(_ message: JSONValue) -> Bool {
        guard let incoming = Self.toolResultPresentation(message) else { return false }
        pendingPersistenceIDs.insert(incoming.id)
        if let index = items.firstIndex(where: { $0.id == incoming.id }),
           case .tool(var existing) = items[index] {
            existing.result = message
            existing.phase = incoming.phase
            existing.endDate = incoming.endDate
            items[index] = .tool(existing)
        } else {
            items.append(.tool(incoming))
        }
        return true
    }

    private static func toolResultPresentation(_ message: JSONValue) -> ToolPresentation? {
        guard message["role"]?.stringValue == "toolResult",
              let id = message["toolCallId"]?.stringValue
        else { return nil }
        let timestamp = message["timestamp"]?.doubleValue.map {
            Date(timeIntervalSince1970: $0 / 1_000)
        } ?? Date()
        return ToolPresentation(
            id: id,
            name: message["toolName"]?.stringValue ?? "Unknown tool",
            arguments: .object([:]),
            result: message,
            phase: message["isError"]?.boolValue == true ? .failed : .complete,
            startDate: timestamp,
            endDate: timestamp)
    }

    mutating func upsertExtensionUI(_ state: ExtensionUIState) {
        replaceOrAppend(.extensionUI(state))
    }

    mutating func removeExtensionUI(id: String) {
        items.removeAll { item in
            if case .extensionUI(let state) = item { return state.id == id }
            return false
        }
    }

    mutating func appendNotice(level: String, message: String) {
        items.append(.notice(
            id: syntheticID(prefix: "notice"),
            level: level,
            message: message))
    }

    private mutating func appendAnnotation(
        kind: TranscriptAnnotation.Kind,
        title: String,
        detail: String?,
        tone: TranscriptAnnotation.Tone
    ) {
        items.append(.annotation(TranscriptAnnotation(
            id: syntheticID(prefix: "annotation"),
            kind: kind,
            title: title,
            detail: detail,
            timestamp: Date(),
            tone: tone)))
    }

    private func retryDetail(_ payload: JSONValue) -> String? {
        guard let attempt = payload["attempt"]?.intValue else { return nil }
        var components = ["Attempt \(attempt)"]
        if let maximum = payload["maxAttempts"]?.intValue {
            components[0] += " of \(maximum)"
        }
        if let delay = payload["delayMs"]?.doubleValue {
            components.append(Self.duration(milliseconds: delay))
        }
        return components.joined(separator: " · ")
    }

    private static func duration(milliseconds: Double) -> String {
        let seconds = milliseconds / 1_000
        return seconds == seconds.rounded()
            ? "\(Int(seconds))s"
            : String(format: "%.1fs", seconds)
    }

    private static func compactionDetail(_ result: JSONValue?) -> String? {
        guard let before = result?["tokensBefore"]?.intValue,
              let after = result?["tokensAfter"]?.intValue
        else { return nil }
        return "\(before.formatted()) → \(after.formatted()) tokens"
    }

    private static func nonDefaultRole(_ role: String) -> String? {
        role == "default" ? nil : role.capitalized
    }

    private static func modelLabel(_ fullModel: String?) -> String {
        guard let fullModel else { return "another model" }
        let model = fullModel.split(separator: "/").last.map(String.init) ?? fullModel
        return model.split(separator: "-").map { component in
            component.lowercased() == "gpt" ? "GPT" : component.capitalized
        }.joined(separator: "-")
        .replacingOccurrences(of: "-Sol", with: " Sol")
    }

    private mutating func messageID(_ message: JSONValue) -> String {
        message["id"]?.stringValue ?? syntheticID(prefix: "message")
    }

    private mutating func syntheticID(prefix: String) -> String {
        defer { nextSyntheticID += 1 }
        return "\(prefix)-\(nextSyntheticID)"
    }

    private mutating func replaceOrAppend(_ item: TranscriptItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }
}

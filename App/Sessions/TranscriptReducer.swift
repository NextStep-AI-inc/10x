import Foundation
import OmpKit

enum TranscriptMutation: Equatable, Sendable {
    case none
    case coalesced
    case immediate
}

struct TranscriptReducer {
    var items: [TranscriptItem] = []
    var runtimeState: SessionRuntimeState = .idle

    var hasPendingPersistence: Bool { !pendingPersistenceIDs.isEmpty }

    private var inflightMessageID: String?
    private var pendingPersistenceIDs: Set<String> = []
    private var pendingMessageFingerprints: [String: String] = [:]
    private var nextSyntheticID = 1
    private var toolReducer = ToolEventReducer()
    private var subagentReducer = SubagentEventReducer()

    @discardableResult
    mutating func consume(_ frame: RpcFrame) -> TranscriptMutation {
        guard case .event(let type, let payload) = frame else { return .none }

        switch type {
        case "agent_start", "turn_start":
            runtimeState = .streaming
            return .immediate
        case "agent_end":
            if payload["isTerminal"]?.boolValue != false {
                runtimeState = .idle
            }
            return .immediate
        case "prompt_result":
            runtimeState = .idle
            return .immediate
        case "message_start":
            guard let message = payload["message"] else { return .none }
            guard TranscriptMessage.isDisplayable(message) else { return .none }
            if Self.isMalformedToolResult(message) { return .none }
            if let mutation = consumeToolResult(message) { return mutation }
            let id = messageID(message)
            inflightMessageID = id
            _ = replaceOrAppend(.message(TranscriptMessage(
                id: id,
                raw: message,
                isFinal: false)))
            return .immediate
        case "message_update":
            guard let message = payload["message"] else { return .none }
            guard TranscriptMessage.isDisplayable(message) else { return .none }
            let id = inflightMessageID ?? messageID(message)
            inflightMessageID = id
            return replaceOrAppend(.message(TranscriptMessage(
                id: id,
                raw: message,
                isFinal: false))) ? .coalesced : .none
        case "message_end":
            guard let message = payload["message"] else { return .none }
            guard TranscriptMessage.isDisplayable(message) else { return .none }
            if Self.isMalformedToolResult(message) { return .none }
            if let mutation = consumeToolResult(message) { return mutation }
            let id = inflightMessageID ?? messageID(message)
            let finalMessage = TranscriptMessage(
                id: id,
                raw: message,
                isFinal: true)
            _ = replaceOrAppend(.message(finalMessage))
            pendingPersistenceIDs.insert(id)
            pendingMessageFingerprints[id] = Self.fingerprint(finalMessage)
            inflightMessageID = nil
            return .immediate
        case "notice":
            let id = syntheticID(prefix: "notice")
            items.append(.notice(
                id: id,
                level: payload["level"]?.stringValue ?? "info",
                message: payload["message"]?.stringValue ?? ""))
            return .immediate
        case "auto_retry_start":
            return appendAnnotation(
                kind: .retry,
                title: "Retrying response",
                detail: retryDetail(payload),
                tone: .warning)
        case "auto_retry_end":
            if payload["success"]?.boolValue == false {
                return appendAnnotation(
                    kind: .retry,
                    title: "Response retry failed",
                    detail: payload["finalError"]?.stringValue,
                    tone: .error)
            }
            return .none
        case "retry_fallback_applied":
            return appendAnnotation(
                kind: .model,
                title: "Fallback to \(Self.modelLabel(payload["to"]?.stringValue))",
                detail: payload["role"]?.stringValue.flatMap(Self.nonDefaultRole),
                tone: .warning)
        case "retry_fallback_succeeded":
            return appendAnnotation(
                kind: .model,
                title: "Fallback succeeded with \(Self.modelLabel(payload["model"]?.stringValue))",
                detail: payload["role"]?.stringValue.flatMap(Self.nonDefaultRole),
                tone: .interactive)
        case "thinking_level_changed":
            let thinking = payload["resolved"]?.stringValue
                ?? payload["thinkingLevel"]?.stringValue
                ?? "inherit"
            return appendAnnotation(
                kind: .thinking,
                title: "Thinking set to \(thinking.capitalized)",
                detail: payload["configured"]?.stringValue?.capitalized,
                tone: .neutral)
        case "auto_compaction_end":
            if payload["aborted"]?.boolValue == true {
                return appendAnnotation(
                    kind: .compaction,
                    title: "Context compaction stopped",
                    detail: payload["errorMessage"]?.stringValue,
                    tone: payload["willRetry"]?.boolValue == true ? .warning : .error)
            } else if payload["skipped"]?.boolValue != true {
                return appendAnnotation(
                    kind: .compaction,
                    title: "Context compacted",
                    detail: Self.compactionDetail(payload["result"]),
                    tone: .neutral)
            }
            return .none
        case "tool_execution_start", "tool_execution_update", "tool_execution_end":
            guard payload["toolCallId"]?.stringValue != nil else { return .none }
            toolReducer.consume(type: type, payload: payload)
            guard let id = payload["toolCallId"]?.stringValue,
                  let presentation = toolReducer.presentations.first(where: { $0.id == id })
            else { return .none }
            var changed = replaceOrAppend(.tool(presentation))
            if type == "tool_execution_end", let result = payload["result"] {
                pendingPersistenceIDs.insert(id)
                subagentReducer.attachResult(parentToolCallID: id, result: result)
                for subagent in subagentReducer.presentations where
                    subagent.parentToolCallID == id {
                    changed = replaceOrAppend(.subagent(subagent)) || changed
                }
            }
            if type == "tool_execution_update" {
                return changed ? .coalesced : .none
            }
            if type == "tool_execution_end" {
                return changed ? .immediate : .none
            }
            return .immediate
        case "subagent_lifecycle", "subagent_progress":
            guard let body = payload["payload"] else { return .none }
            if type == "subagent_progress",
               !canConsumeSubagentProgress(body) {
                return .none
            }
            subagentReducer.consume(type: type, payload: payload)
            guard let presentation = Self.subagent(
                    matching: body,
                    in: subagentReducer.presentations)
            else { return .none }
            let changed = replaceOrAppend(.subagent(presentation))
            if type == "subagent_progress" {
                return changed ? .coalesced : .none
            }
            return .immediate
        default:
            return .none
        }
    }

    @discardableResult
    mutating func load(messages: [JSONValue]) -> TranscriptMutation {
        let previous = items
        let previousTools: [String: ToolPresentation] = Dictionary(uniqueKeysWithValues: previous.compactMap { item in
            guard case .tool(let tool) = item else { return nil }
            return (tool.id, tool)
        })
        let fallbackDate = Date()
        items = []
        for (index, message) in messages.enumerated() {
            if let result = Self.toolResultPresentation(
                message,
                existingTool: Self.toolResultID(message).flatMap { previousTools[$0] },
                fallbackDate: fallbackDate) {
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
            items.append(contentsOf: Self.toolCallPresentations(
                message,
                existingTools: previousTools,
                fallbackDate: fallbackDate).map(TranscriptItem.tool))
        }
        inflightMessageID = nil
        pendingPersistenceIDs = []
        pendingMessageFingerprints = [:]
        return previous == items ? .none : .immediate
    }

    @discardableResult
    mutating func load(history: TranscriptHistory) -> TranscriptMutation {
        let previous = items
        items = history.items
        inflightMessageID = nil
        pendingPersistenceIDs = []
        pendingMessageFingerprints = [:]
        return previous == items ? .none : .immediate
    }

    @discardableResult
    mutating func ensureThreadStart(date: Date?) -> TranscriptMutation {
        guard !items.contains(where: {
            if case .threadStart = $0 { return true }
            return false
        }) else { return .none }
        items.insert(.threadStart(id: "thread-start-fallback", date: date), at: 0)
        return .immediate
    }

    @discardableResult
    mutating func setReconciliationWarning(isPresented: Bool) -> TranscriptMutation {
        let previous = items
        items.removeAll { $0.id == "reconciliation-warning" }
        guard isPresented else { return previous == items ? .none : .immediate }
        items.append(.annotation(TranscriptAnnotation(
            id: "reconciliation-warning",
            kind: .notice,
            title: "History is catching up",
            detail: "Live updates remain visible.",
            timestamp: nil,
            tone: .warning)))
        return previous == items ? .none : .immediate
    }

    @discardableResult
    mutating func reconcile(history: TranscriptHistory) -> TranscriptMutation {
        let previous = items
        let persistedIDs = Set(history.items.map(\.id))
        let resolvedMessageIDs = pendingMessageIDsPersisted(in: history)
        let resolvedIDs = persistedIDs.union(resolvedMessageIDs)
        pendingPersistenceIDs.subtract(resolvedIDs)
        for id in resolvedIDs {
            pendingMessageFingerprints.removeValue(forKey: id)
        }
        let transient = items.filter { item in
            guard !persistedIDs.contains(item.id) else { return false }
            if pendingPersistenceIDs.contains(item.id) { return true }
            switch item {
            case .notice, .annotation, .subagent, .extensionUI:
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
        return previous == items ? .none : .immediate
    }

    private static func toolCallPresentations(
        _ message: JSONValue,
        existingTools: [String: ToolPresentation] = [:],
        fallbackDate: Date = Date()
    ) -> [ToolPresentation] {
        let messageTimestamp = message["timestamp"]?.doubleValue.map {
            Date(timeIntervalSince1970: $0 / 1_000)
        }
        return message["content"]?.arrayValue?.compactMap { block in
            guard block["type"]?.stringValue == "toolCall",
                  let id = block["id"]?.stringValue ?? block["toolCallId"]?.stringValue,
                  let name = block["name"]?.stringValue ?? block["toolName"]?.stringValue
            else { return nil }
            let timestamp = messageTimestamp ?? existingTools[id]?.startDate ?? fallbackDate
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

    private func canConsumeSubagentProgress(_ body: JSONValue) -> Bool {
        guard body["progress"] != nil else { return false }
        if body["progress"]?["id"]?.stringValue != nil { return true }
        guard let index = body["index"]?.intValue else { return false }
        return subagentReducer.presentations.contains { $0.index == index }
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

    private mutating func consumeToolResult(_ message: JSONValue) -> TranscriptMutation? {
        let existingTool = Self.toolResultID(message).flatMap { id in
            items.compactMap { item -> ToolPresentation? in
                guard case .tool(let tool) = item, tool.id == id else { return nil }
                return tool
            }.first
        }
        guard let incoming = Self.toolResultPresentation(message, existingTool: existingTool) else { return nil }
        pendingPersistenceIDs.insert(incoming.id)
        let changed: Bool
        if let index = items.firstIndex(where: { $0.id == incoming.id }),
           case .tool(var existing) = items[index] {
            existing.result = message
            existing.phase = incoming.phase
            existing.endDate = incoming.endDate
            changed = items[index] != .tool(existing)
            if changed {
                items[index] = .tool(existing)
            }
        } else {
            items.append(.tool(incoming))
            changed = true
        }
        return changed ? .immediate : TranscriptMutation.none
    }

    private static func toolResultID(_ message: JSONValue) -> String? {
        guard message["role"]?.stringValue == "toolResult",
              let id = message["toolCallId"]?.stringValue
        else { return nil }
        return id
    }

    private static func isMalformedToolResult(_ message: JSONValue) -> Bool {
        message["role"]?.stringValue == "toolResult"
            && message["toolCallId"]?.stringValue == nil
    }

    private static func toolResultPresentation(
        _ message: JSONValue,
        existingTool: ToolPresentation? = nil,
        fallbackDate: Date = Date()
    ) -> ToolPresentation? {
        guard let id = toolResultID(message) else { return nil }
        let timestamp = message["timestamp"]?.doubleValue.map {
            Date(timeIntervalSince1970: $0 / 1_000)
        }
        let startDate = timestamp ?? existingTool?.startDate ?? fallbackDate
        let endDate = timestamp ?? existingTool?.endDate ?? fallbackDate
        return ToolPresentation(
            id: id,
            name: message["toolName"]?.stringValue ?? "Unknown tool",
            arguments: .object([:]),
            result: message,
            phase: message["isError"]?.boolValue == true ? .failed : .complete,
            startDate: startDate,
            endDate: endDate)
    }

    @discardableResult
    mutating func upsertExtensionUI(_ state: ExtensionUIState) -> TranscriptMutation {
        replaceOrAppend(.extensionUI(state)) ? .immediate : .none
    }

    @discardableResult
    mutating func removeExtensionUI(id: String) -> TranscriptMutation {
        let previous = items
        items.removeAll { item in
            if case .extensionUI(let state) = item { return state.id == id }
            return false
        }
        return previous == items ? .none : .immediate
    }

    @discardableResult
    mutating func appendNotice(level: String, message: String) -> TranscriptMutation {
        items.append(.notice(
            id: syntheticID(prefix: "notice"),
            level: level,
            message: message))
        return .immediate
    }

    @discardableResult
    private mutating func appendAnnotation(
        kind: TranscriptAnnotation.Kind,
        title: String,
        detail: String?,
        tone: TranscriptAnnotation.Tone
    ) -> TranscriptMutation {
        items.append(.annotation(TranscriptAnnotation(
            id: syntheticID(prefix: "annotation"),
            kind: kind,
            title: title,
            detail: detail,
            timestamp: Date(),
            tone: tone)))
        return .immediate
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

    private mutating func pendingMessageIDsPersisted(
        in history: TranscriptHistory
    ) -> Set<String> {
        var persistedCounts: [String: Int] = [:]
        for item in history.items {
            guard case .message(let message) = item else { continue }
            persistedCounts[Self.fingerprint(message), default: 0] += 1
        }

        var resolved: Set<String> = []
        for item in items {
            guard case .message = item,
                  let fingerprint = pendingMessageFingerprints[item.id],
                  let count = persistedCounts[fingerprint],
                  count > 0
            else { continue }
            resolved.insert(item.id)
            persistedCounts[fingerprint] = count - 1
        }
        return resolved
    }

    private static func fingerprint(_ message: TranscriptMessage) -> String {
        let timestamp = message.raw["timestamp"]?.doubleValue.map { String($0) } ?? ""
        return [
            message.role.rawValue,
            timestamp,
            message.stopReason ?? "",
            reconciliationText(message.visibleText),
        ].joined(separator: "\u{1F}")
    }

    private static func reconciliationText(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private mutating func messageID(_ message: JSONValue) -> String {
        message["id"]?.stringValue ?? syntheticID(prefix: "message")
    }

    private mutating func syntheticID(prefix: String) -> String {
        defer { nextSyntheticID += 1 }
        return "\(prefix)-\(nextSyntheticID)"
    }

    private mutating func replaceOrAppend(_ item: TranscriptItem) -> Bool {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            guard items[index] != item else { return false }
            items[index] = item
        } else {
            items.append(item)
        }
        return true
    }
}

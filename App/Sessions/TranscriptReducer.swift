import Foundation
import OmpKit

enum TranscriptMutation: Equatable, Sendable {
    case none
    case coalesced
    case immediate
}

struct TranscriptReducer {
    private enum InflightItemIdentity: Hashable {
        case message(String)
        case tool(String)
    }

    var items: [TranscriptItem] = []
    var runtimeState: SessionRuntimeState = .idle

    var hasPendingPersistence: Bool { !pendingPersistenceIDs.isEmpty }

    private var inflightMessageID: String?
    private var inflightGuidanceID: String?
    private var inflightItemIDs: [InflightItemIdentity] = []
    private var pendingPersistenceIDs: Set<InflightItemIdentity> = []
    private var pendingMessageFingerprints: [String: String] = [:]
    private var nextSyntheticID = 1
    private var toolReducer = ToolEventReducer()
    private var subagentReducer = SubagentEventReducer()
    @discardableResult
    mutating func consume(_ frame: RpcFrame, at date: Date = Date()) -> TranscriptMutation {
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
            guard let message = payload["message"] else {
                return recordMalformedPassiveEvent(type: type, payload: payload)
            }
            if let mutation = consumeGuidanceMessage(message, at: date, tracksInflight: true) { return mutation }
            guard TranscriptMessage.isDisplayable(message) else { return .none }
            if Self.isMalformedToolResult(message) { return .none }
            if let mutation = consumeToolResult(message) { return mutation }
            let id = messageID(message)
            if Self.isCompleteAtStart(message) {
                return appendCompleteMessage(id: id, raw: message)
                    ? .immediate
                    : .none
            }
            inflightMessageID = id
            _ = replaceInflightMessage(id: id, raw: message, isFinal: false)
            return .immediate
        case "message_update":
            guard let message = payload["message"] else {
                return recordMalformedPassiveEvent(type: type, payload: payload)
            }
            if let mutation = consumeGuidanceMessage(message, at: date) { return mutation }
            guard TranscriptMessage.isDisplayable(message) else { return .none }
            if Self.isCompleteAtStart(message) {
                return appendCompleteMessage(id: messageID(message), raw: message)
                    ? .immediate
                    : .none
            }
            let id = inflightMessageID ?? messageID(message)
            inflightMessageID = id
            return replaceInflightMessage(id: id, raw: message, isFinal: false) ? .coalesced : .none
        case "message_end":
            guard let message = payload["message"] else {
                return recordMalformedPassiveEvent(type: type, payload: payload)
            }
            if let mutation = consumeGuidanceMessage(message, at: date, clearsInflight: true) {
                return mutation
            }
            guard TranscriptMessage.isDisplayable(message) else { return .none }
            if Self.isMalformedToolResult(message) { return .none }
            if let mutation = consumeToolResult(message) { return mutation }
            if Self.isCompleteAtStart(message) {
                return appendCompleteMessage(id: messageID(message), raw: message)
                    ? .immediate
                    : .none
            }
            let id = inflightMessageID ?? messageID(message)
            _ = replaceInflightMessage(id: id, raw: message, isFinal: true)
            for item in items {
                guard let identity = Self.inflightIdentity(for: item),
                      inflightItemIDs.contains(identity),
                      case .message(let finalMessage) = item
                else { continue }
                pendingPersistenceIDs.insert(.message(finalMessage.id))
                pendingMessageFingerprints[finalMessage.id] = Self.fingerprint(finalMessage)
            }
            inflightMessageID = nil
            inflightItemIDs = []
            if message["stopReason"]?.stringValue?.lowercased() == "aborted" {
                _ = interruptRunningTools(at: date)
            }
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
            guard let id = payload["toolCallId"]?.stringValue else {
                return recordMalformedPassiveEvent(type: type, payload: payload)
            }
            let missingTerminalResult = type == "tool_execution_end"
                && ToolEventReducer.isMissingTerminalResult(payload)
            toolReducer.consume(type: type, payload: payload, at: date)
            guard let presentation = toolReducer.presentations.first(where: { $0.id == id })
            else {
                return missingTerminalResult
                    ? recordMalformedPassiveEvent(type: type, payload: payload)
                    : .none
            }
            var changed = replaceOrAppend(.tool(presentation))
            if missingTerminalResult {
                _ = recordMalformedPassiveEvent(type: type, payload: payload)
                changed = true
            }
            if type == "tool_execution_end", let result = payload["result"] {
                pendingPersistenceIDs.insert(.tool(id))
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
            guard let body = payload["payload"] else {
                return recordMalformedPassiveEvent(type: type, payload: payload)
            }
            if type == "subagent_lifecycle",
               body["id"]?.stringValue == nil,
               Self.isTerminalSubagentStatus(body["status"]?.stringValue) {
                return recordMalformedPassiveEvent(type: type, payload: payload)
            }
            if type == "subagent_lifecycle",
               let id = body["id"]?.stringValue,
               SubagentEventReducer.isMalformedTerminalLifecycle(body) {
                let settled = subagentReducer.settleDisplayError(id: id)
                let mutation = recordMalformedPassiveEvent(type: type, payload: payload)
                if settled,
                   let presentation = subagentReducer.presentations.first(where: { $0.id == id }) {
                    _ = replaceOrAppend(.subagent(presentation))
                    return .immediate
                }
                return mutation
            }
            if type == "subagent_progress",
               !canConsumeSubagentProgress(body) {
                return recordMalformedPassiveEvent(type: type, payload: payload)
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
        case "available_commands_update",
             "turn_end",
             "session_info_update",
             "config_update",
             "model_changed",
             "auto_compaction_start":
            return .none
        default:
            return recordUnknownPassiveEvent(type: type, payload: payload)
        }
    }

    @discardableResult
    mutating func load(messages: [JSONValue]) -> TranscriptMutation {
        let previous = items
        let previousTools: [String: ToolPresentation] = Dictionary(previous.compactMap { item in
            guard case .tool(let tool) = item else { return nil }
            return (tool.id, tool)
        }, uniquingKeysWith: { existing, _ in existing })
        let fallbackDate = Date()
        items = []
        for (index, message) in messages.enumerated() {
            let toolResultID = Self.toolResultID(message)
            let currentToolIndex = toolResultID.flatMap { id in
                items.firstIndex { item in
                    guard case .tool(let tool) = item else { return false }
                    return tool.id == id
                }
            }
            let currentTool = currentToolIndex.flatMap { itemIndex -> ToolPresentation? in
                guard case .tool(let tool) = items[itemIndex] else { return nil }
                return tool
            }
            if let result = Self.toolResultPresentation(
                message,
                existingTool: currentTool
                    ?? toolResultID.flatMap { previousTools[$0] },
                fallbackDate: fallbackDate) {
                if let itemIndex = currentToolIndex {
                    items[itemIndex] = .tool(result)
                } else {
                    items.append(.tool(result))
                }
                items.append(contentsOf: SubagentEventReducer.presentations(
                    from: message,
                    parentToolCallID: result.id).map(TranscriptItem.subagent))
                continue
            }

            let messageID = message["id"]?.stringValue ?? "history-\(index)"
            if let guidance = GuidanceTranscript.classify(id: messageID, message: message) {
                GuidanceTranscript.upsert(guidance, into: &items)
                if message["stopReason"]?.stringValue?.lowercased() == "aborted" {
                    _ = Self.interruptRunningTools(in: &items, at: fallbackDate)
                }
                continue
            }

            items.append(contentsOf: TranscriptMessageNormalizer.items(
                id: messageID,
                raw: message,
                isFinal: true,
                existingTools: previousTools,
                fallbackDate: fallbackDate))
            if message["stopReason"]?.stringValue?.lowercased() == "aborted" {
                _ = Self.interruptRunningTools(in: &items, at: fallbackDate)
            }
        }
        inflightMessageID = nil
        inflightGuidanceID = nil
        inflightItemIDs = []
        pendingPersistenceIDs = []
        pendingMessageFingerprints = [:]
        return previous == items ? .none : .immediate
    }

    @discardableResult
    mutating func interruptRunningTools(at date: Date) -> TranscriptMutation {
        let reducerChanged = toolReducer.interruptRunning(at: date)
        let itemsChanged = Self.interruptRunningTools(in: &items, at: date)
        return reducerChanged || itemsChanged ? .immediate : .none
    }

    @discardableResult
    static func interruptRunningTools(
        in items: inout [TranscriptItem],
        at date: Date
    ) -> Bool {
        var changed = false
        for index in items.indices {
            guard case .tool(var tool) = items[index], tool.phase == .running else { continue }
            tool.update(phase: .interrupted, endDate: .some(date))
            items[index] = .tool(tool)
            changed = true
        }
        return changed
    }

    @discardableResult
    static func settleActiveTurnAfterStop(
        in items: inout [TranscriptItem],
        at date: Date
    ) -> Bool {
        guard let activeTurn = TranscriptTurnProjection.sections(
            from: items,
            runtimeState: .stopped(code: nil, stderrTail: "")).last
        else { return false }
        let activeIDs = Set(activeTurn.items.map(\.viewID))
        let previous = items
        items = items.compactMap { item in
            guard activeIDs.contains(item.viewID) else { return item }
            switch item {
            case .message(let message):
                return .message(message.settledAfterStop(at: date))
            case .tool(var tool) where tool.phase == .running:
                tool.update(phase: .interrupted, endDate: .some(date))
                return .tool(tool)
            case .extensionUI(let state) where state.requiresUserInput:
                return nil
            default:
                return item
            }
        }
        return previous != items
    }

    @discardableResult
    mutating func load(history: TranscriptHistory) -> TranscriptMutation {
        let previous = items
        items = history.items
        inflightMessageID = nil
        inflightGuidanceID = nil
        inflightItemIDs = []
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
        let persistedInflightItemIDs = Set(history.items.compactMap(Self.inflightIdentity))
        let resolvedMessageIDs = pendingMessageIDsPersisted(in: history)
        let resolvedInflightItemIDs = persistedInflightItemIDs.union(resolvedMessageIDs)
        pendingPersistenceIDs.subtract(resolvedInflightItemIDs)
        for identity in resolvedInflightItemIDs {
            guard case .message(let id) = identity else { continue }
            pendingMessageFingerprints.removeValue(forKey: id)
        }
        let persistedAnnotations = Set(history.items.compactMap(Self.annotationSignature))
        var persistedGuidanceFingerprintCounts = Self.persistedGuidanceFingerprintCounts(from: history.items)
        let liveDiagnosticState = Self.diagnosticReconcileState(from: previous)
        let historyDiagnosticOmittedCount = Self.diagnosticOmittedCount(from: history.items)
        var transient: [TranscriptItem] = []
        for item in items {
            if let identity = Self.inflightIdentity(for: item) {
                guard !persistedInflightItemIDs.contains(identity) else { continue }
                if pendingPersistenceIDs.contains(identity) {
                    transient.append(item)
                    continue
                }
            } else if inflightGuidanceID != item.id {
                guard !persistedIDs.contains(item.id) else { continue }
            }
            switch item {
            case .annotation:
                guard let signature = Self.annotationSignature(item) else {
                    transient.append(item)
                    continue
                }
                if !persistedAnnotations.contains(signature) {
                    transient.append(item)
                }
            case .notice, .subagent, .extensionUI:
                transient.append(item)
            case .diagnostic(let diagnostic):
                if Self.shouldKeepDiagnosticTransient(
                    diagnostic,
                    persistedIDs: persistedIDs) {
                    transient.append(item)
                }
            case .guidance(let presentation):
                if Self.shouldKeepGuidanceTransient(
                    presentation,
                    inflightGuidanceID: inflightGuidanceID,
                    counts: &persistedGuidanceFingerprintCounts) {
                    transient.append(item)
                }
            case .tool(let presentation):
                if presentation.phase == .running {
                    transient.append(item)
                }
            case .message(let message):
                if !message.isFinal {
                    transient.append(item)
                }
            case .threadStart:
                break
            }
        }
        items = history.items.compactMap { item in
            if case .diagnostic(let diagnostic) = item,
               diagnostic.omittedEarlierCount != nil,
               liveDiagnosticState.hasOmissionMarker {
                return nil
            }
            guard case .subagent(var persisted) = item,
                  case .subagent(let live)? = previous.first(where: { $0.id == item.id })
            else { return item }
            // Completed task results omit the recent details supplied by live progress.
            if persisted.recentTools.isEmpty {
                persisted.recentTools = live.recentTools
            }
            if persisted.recentOutput.isEmpty {
                persisted.recentOutput = live.recentOutput
            }
            return .subagent(persisted)
        } + transient
        GuidanceTranscript.enforceCap(on: &items)
        EventDiagnosticTranscript.enforceCapAfterReconcile(
            on: &items,
            liveOmitted: liveDiagnosticState.omittedCount,
            historyOmitted: historyDiagnosticOmittedCount)
        if !inflightItemIDs.contains(where: { identity in
            items.contains { Self.inflightIdentity(for: $0) == identity }
        }) {
            inflightMessageID = nil
            inflightItemIDs = []
        }
        if inflightGuidanceID != nil,
           !items.contains(where: { item in
               guard case .guidance(let presentation) = item else { return false }
               return presentation.id == inflightGuidanceID
           }) {
            inflightGuidanceID = nil
        }
        return previous == items ? .none : .immediate
    }

    private static func persistedGuidanceFingerprintCounts(
        from items: [TranscriptItem]
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        for item in items {
            guard case .guidance(let presentation) = item,
                  presentation.omittedEarlierCount == nil
            else { continue }
            counts[presentation.reconcileFingerprint, default: 0] += 1
        }
        return counts
    }

    private static func shouldKeepGuidanceTransient(
        _ presentation: GuidancePresentation,
        inflightGuidanceID: String?,
        counts: inout [String: Int]
    ) -> Bool {
        if presentation.omittedEarlierCount != nil { return false }
        if inflightGuidanceID == presentation.id { return true }
        let fingerprint = presentation.reconcileFingerprint
        if let count = counts[fingerprint], count > 0 {
            counts[fingerprint] = count - 1
            return false
        }
        return true
    }

    /// Identity for the same change arriving twice: once as a live event and
    /// once from the session file, under two different ids.
    private static func annotationSignature(_ item: TranscriptItem) -> String? {
        guard case .annotation(let annotation) = item else { return nil }
        return "\(annotation.kind)|\(annotation.title)"
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

    private mutating func consumeToolResult(_ message: JSONValue) -> TranscriptMutation? {
        let existingIndex = Self.toolResultID(message).flatMap { id in
            items.firstIndex { item in
                guard case .tool(let tool) = item else { return false }
                return tool.id == id
            }
        }
        let existingTool = existingIndex.flatMap { index -> ToolPresentation? in
            guard case .tool(let tool) = items[index] else { return nil }
            return tool
        }
        guard let incoming = Self.toolResultPresentation(message, existingTool: existingTool) else { return nil }
        pendingPersistenceIDs.insert(.tool(incoming.id))
        let changed: Bool
        if let index = existingIndex {
            changed = items[index] != .tool(incoming)
            if changed {
                items[index] = .tool(incoming)
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

    private static func isCompleteAtStart(_ message: JSONValue) -> Bool {
        switch message["role"]?.stringValue {
        case "custom", "hookMessage": true
        default: false
        }
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
        if var existingTool {
            existingTool.update(
                result: .some(message),
                phase: message["isError"]?.boolValue == true ? .failed : .complete,
                endDate: .some(endDate))
            return existingTool
        }
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
        appendNotice(id: syntheticID(prefix: "notice"), level: level, message: message)
    }

    /// Caller-chosen id, so the caller can rewrite the notice in place later
    /// (harness-message notices swap in their summary).
    @discardableResult
    mutating func appendNotice(id: String, level: String, message: String) -> TranscriptMutation {
        items.append(.notice(id: id, level: level, message: message))
        return .immediate
    }

    @discardableResult
    mutating func updateNotice(id: String, message: String) -> TranscriptMutation {
        guard let index = items.firstIndex(where: { $0.id == id }),
              case .notice(let noticeID, let level, _) = items[index]
        else { return .none }
        items[index] = .notice(id: noticeID, level: level, message: message)
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
    ) -> Set<InflightItemIdentity> {
        var persistedCounts: [String: Int] = [:]
        for item in history.items {
            guard case .message(let message) = item else { continue }
            persistedCounts[Self.fingerprint(message), default: 0] += 1
        }

        var resolved: Set<InflightItemIdentity> = []
        for item in items {
            guard case .message = item,
                  let fingerprint = pendingMessageFingerprints[item.id],
                  let count = persistedCounts[fingerprint],
                  count > 0
            else { continue }
            resolved.insert(.message(item.id))
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
        if let id = message["id"]?.stringValue { return id }
        if let inflightMessageID { return inflightMessageID }
        return syntheticID(prefix: "message")
    }

    private mutating func guidanceMessageID(_ message: JSONValue) -> String {
        if let id = message["id"]?.stringValue { return id }
        if let inflightGuidanceID { return inflightGuidanceID }
        return syntheticID(prefix: "guidance")
    }

    private mutating func replaceInflightMessage(
        id: String,
        raw: JSONValue,
        isFinal: Bool
    ) -> Bool {
        if let guidance = GuidanceTranscript.classify(id: id, message: raw) {
            let previous = items
            GuidanceTranscript.upsert(guidance, into: &items)
            if isFinal {
                inflightMessageID = nil
                inflightItemIDs = []
            } else {
                inflightMessageID = id
                inflightItemIDs = []
            }
            return previous != items
        }
        let previous = items
        let existingTools = Dictionary(items.compactMap { item -> (String, ToolPresentation)? in
            guard case .tool(let tool) = item else { return nil }
            return (tool.id, tool)
        }, uniquingKeysWith: { existing, _ in existing })
        let previousDocuments = Dictionary(items.compactMap { item -> (TranscriptRenderLineageKey, ContentDocument)? in
            guard case .message(let message) = item else { return nil }
            return (message.renderLineageKey, message.document)
        }, uniquingKeysWith: { existing, _ in existing })
        let normalized = TranscriptMessageNormalizer.items(
            id: id,
            raw: raw,
            isFinal: isFinal,
            existingTools: existingTools,
            previousDocuments: previousDocuments)
        let normalizedIDs = Set(normalized.compactMap(Self.inflightIdentity))
        let insertionIndex = items.firstIndex { item in
            guard let identity = Self.inflightIdentity(for: item) else { return false }
            return inflightItemIDs.contains(identity)
        } ?? items.endIndex

        items.removeAll { item in
            guard let identity = Self.inflightIdentity(for: item) else { return false }
            return inflightItemIDs.contains(identity) || normalizedIDs.contains(identity)
        }
        items.insert(contentsOf: normalized, at: min(insertionIndex, items.endIndex))
        inflightItemIDs = normalized.compactMap(Self.inflightIdentity)
        return previous != items
    }

    private mutating func appendCompleteMessage(id: String, raw: JSONValue) -> Bool {
        if let guidance = GuidanceTranscript.classify(id: id, message: raw) {
            let previous = items
            GuidanceTranscript.upsert(guidance, into: &items)
            return previous != items
        }
        let normalized = TranscriptMessageNormalizer.items(
            id: id,
            raw: raw,
            isFinal: true)
        var changed = false
        for item in normalized {
            changed = replaceOrAppend(item) || changed
            guard case .message(let message) = item else { continue }
            pendingPersistenceIDs.insert(.message(message.id))
            pendingMessageFingerprints[message.id] = Self.fingerprint(message)
        }
        return changed
    }

    @discardableResult
    private mutating func consumeGuidanceMessage(
        _ message: JSONValue,
        at date: Date,
        tracksInflight: Bool = false,
        clearsInflight: Bool = false
    ) -> TranscriptMutation? {
        let id = guidanceMessageID(message)
        guard let guidance = GuidanceTranscript.classify(id: id, message: message) else { return nil }
        let previous = items
        if let inflightGuidanceID,
           inflightGuidanceID != id,
           message["id"]?.stringValue != nil {
            items.removeAll { item in
                guard case .guidance(let presentation) = item else { return false }
                return presentation.id == inflightGuidanceID
            }
            if !clearsInflight {
                self.inflightGuidanceID = id
            }
        }
        GuidanceTranscript.upsert(guidance, into: &items)
        if tracksInflight {
            inflightGuidanceID = id
        }
        if clearsInflight {
            inflightGuidanceID = nil
        }
        var changed = previous != items
        if clearsInflight,
           message["stopReason"]?.stringValue?.lowercased() == "aborted" {
            changed = interruptRunningTools(at: date) != .none || changed
        }
        return changed ? .immediate : .none
    }

    private mutating func syntheticID(prefix: String) -> String {
        defer { nextSyntheticID += 1 }
        return "\(prefix)-\(nextSyntheticID)"
    }

    private mutating func replaceOrAppend(_ item: TranscriptItem) -> Bool {
        if let index = items.firstIndex(where: { Self.hasSameKindIdentity($0, item) }) {
            guard items[index] != item else { return false }
            items[index] = item
        } else {
            items.append(item)
        }
        return true
    }

    private static func inflightIdentity(for item: TranscriptItem) -> InflightItemIdentity? {
        switch item {
        case .message(let message):
            return .message(message.id)
        case .tool(let tool):
            return .tool(tool.id)
        case .threadStart, .annotation, .subagent, .notice, .extensionUI, .guidance, .diagnostic:
            return nil
        }
    }

    private static func hasSameKindIdentity(_ lhs: TranscriptItem, _ rhs: TranscriptItem) -> Bool {
        switch (lhs, rhs) {
        case (.threadStart(let lhsID, _), .threadStart(let rhsID, _)),
             (.notice(let lhsID, _, _), .notice(let rhsID, _, _)):
            return lhsID == rhsID
        case (.message(let lhsMessage), .message(let rhsMessage)):
            return lhsMessage.id == rhsMessage.id
        case (.annotation(let lhsAnnotation), .annotation(let rhsAnnotation)):
            return lhsAnnotation.id == rhsAnnotation.id
        case (.subagent(let lhsSubagent), .subagent(let rhsSubagent)):
            return lhsSubagent.id == rhsSubagent.id
        case (.tool(let lhsTool), .tool(let rhsTool)):
            return lhsTool.id == rhsTool.id
        case (.extensionUI(let lhsState), .extensionUI(let rhsState)):
            return lhsState.id == rhsState.id
        case (.guidance(let lhsGuidance), .guidance(let rhsGuidance)):
            return lhsGuidance.id == rhsGuidance.id
        case (.diagnostic(let lhsDiagnostic), .diagnostic(let rhsDiagnostic)):
            return lhsDiagnostic.id == rhsDiagnostic.id
        default:
            return false
        }
    }

    private mutating func recordUnknownPassiveEvent(
        type: String,
        payload: JSONValue
    ) -> TranscriptMutation {
        let id = diagnosticEventID(type: type, payload: payload)
        let previous = items
        EventDiagnosticTranscript.upsert(
            EventDiagnostic.make(id: id, type: type, payload: payload),
            into: &items)
        return previous == items ? .none : .immediate
    }

    private mutating func recordMalformedPassiveEvent(
        type: String,
        payload: JSONValue
    ) -> TranscriptMutation {
        recordUnknownPassiveEvent(type: type, payload: payload)
    }

    private mutating func diagnosticEventID(type: String, payload: JSONValue) -> String {
        if let id = payload["id"]?.stringValue { return id }
        return syntheticID(prefix: "diagnostic-\(type)")
    }

    private struct DiagnosticReconcileState: Equatable {
        let omittedCount: Int
        let retainedIDs: Set<String>
        let hasOmissionMarker: Bool
    }

    private static func diagnosticReconcileState(from items: [TranscriptItem]) -> DiagnosticReconcileState {
        let diagnostics = diagnosticItems(from: items)
        return DiagnosticReconcileState(
            omittedCount: diagnostics.compactMap(\.omittedEarlierCount).first ?? 0,
            retainedIDs: Set(diagnostics.compactMap { diagnostic in
                diagnostic.omittedEarlierCount == nil ? diagnostic.id : nil
            }),
            hasOmissionMarker: diagnostics.contains { $0.omittedEarlierCount != nil })
    }

    private static func diagnosticOmittedCount(from items: [TranscriptItem]) -> Int {
        diagnosticItems(from: items).compactMap(\.omittedEarlierCount).first ?? 0
    }

    private static func diagnosticItems(from items: [TranscriptItem]) -> [EventDiagnostic] {
        items.compactMap { item in
            guard case .diagnostic(let diagnostic) = item else { return nil }
            return diagnostic
        }
    }

    private static func shouldKeepDiagnosticTransient(
        _ diagnostic: EventDiagnostic,
        persistedIDs: Set<String>
    ) -> Bool {
        if diagnostic.omittedEarlierCount != nil { return false }
        if persistedIDs.contains(diagnostic.id) { return false }
        return true
    }

    private static func isTerminalSubagentStatus(_ status: String?) -> Bool {
        switch status?.lowercased() {
        case "completed", "complete", "failed", "aborted", "done":
            return true
        default:
            return false
        }
    }
}

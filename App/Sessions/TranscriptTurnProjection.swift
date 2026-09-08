import Foundation

enum TranscriptTurnState: Equatable, Sendable {
    case completed
    case stopped
    case failed
    case interrupted
    case working
    case pendingInput
    case unknown
}

struct TranscriptTurnSection: Identifiable, Equatable, Sendable {
    let id: String
    let items: [TranscriptItem]
    let state: TranscriptTurnState?
    let duration: TimeInterval?
}

enum TranscriptTurnProjection {
    nonisolated static func sections(
        from items: [TranscriptItem],
        runtimeState: SessionRuntimeState
    ) -> [TranscriptTurnSection] {
        var result: [TranscriptTurnSection] = []
        var preamble: [TranscriptItem] = []
        var turnItems: [TranscriptItem] = []
        var turnID: String?
        var hasResponseEvidence = false

        func appendTurn(closedByNextInput: Bool) {
            guard let turnID else { return }
            result.append(section(
                id: turnID,
                items: turnItems,
                runtimeState: runtimeState,
                isFinal: !closedByNextInput,
                closedByNextInput: closedByNextInput))
        }

        for item in items {
            if case .message(let message) = item, message.role == .user {
                if turnID == nil {
                    if !preamble.isEmpty {
                        result.append(TranscriptTurnSection(
                            id: "transcript-preamble",
                            items: preamble,
                            state: nil,
                            duration: nil))
                    }
                    turnID = "turn:\(message.renderLineageKey.baseMessageID)"
                } else if hasResponseEvidence {
                    appendTurn(closedByNextInput: true)
                    turnItems.removeAll(keepingCapacity: true)
                    turnID = "turn:\(message.renderLineageKey.baseMessageID)"
                    hasResponseEvidence = false
                }
                turnItems.append(item)
            } else if turnID == nil {
                preamble.append(item)
            } else {
                turnItems.append(item)
                hasResponseEvidence = hasResponseEvidence || isResponseEvidence(item)
            }
        }

        if turnID != nil {
            appendTurn(closedByNextInput: false)
        } else if !preamble.isEmpty {
            result.append(TranscriptTurnSection(
                id: "transcript-preamble", items: preamble, state: nil, duration: nil))
        }
        return result
    }

    private nonisolated static func section(
        id: String,
        items: [TranscriptItem],
        runtimeState: SessionRuntimeState,
        isFinal: Bool,
        closedByNextInput: Bool
    ) -> TranscriptTurnSection {
        TranscriptTurnSection(
            id: id,
            items: items,
            state: state(
                for: items,
                runtimeState: runtimeState,
                isFinal: isFinal,
                closedByNextInput: closedByNextInput),
            duration: duration(for: items))
    }

    private nonisolated static func state(
        for items: [TranscriptItem],
        runtimeState: SessionRuntimeState,
        isFinal: Bool,
        closedByNextInput: Bool
    ) -> TranscriptTurnState {
        if isFinal, items.contains(where: requiresUserInput) { return .pendingInput }
        if isFinal, runtimeState == .streaming || items.contains(where: isActive) { return .working }

        if let terminal = items.reversed().compactMap(terminalAssistantState).first {
            return terminal
        }
        if isFinal {
            switch runtimeState {
            case .failed: return .failed
            case .stopped: return .stopped
            case .loading, .idle, .streaming: break
            }
        }
        if items.contains(where: isFailed) { return .failed }
        if closedByNextInput { return .interrupted }
        return .unknown
    }

    private nonisolated static func terminalAssistantState(
        _ item: TranscriptItem
    ) -> TranscriptTurnState? {
        guard case .message(let message) = item,
              message.role == .assistant,
              message.isFinal else { return nil }
        return switch message.stopReason?.lowercased() {
        case "error": .failed
        case "aborted": .stopped
        default: .completed
        }
    }

    private nonisolated static func isResponseEvidence(_ item: TranscriptItem) -> Bool {
        switch item {
        case .message(let message): message.role == .assistant
        case .tool, .subagent, .extensionUI: true
        case .threadStart, .annotation, .notice: false
        }
    }

    private nonisolated static func requiresUserInput(_ item: TranscriptItem) -> Bool {
        guard case .extensionUI(let state) = item else { return false }
        return state.requiresUserInput
    }

    private nonisolated static func isActive(_ item: TranscriptItem) -> Bool {
        switch item {
        case .message(let message):
            message.role == .assistant && !message.isFinal && !message.document.blocks.isEmpty
        case .tool(let tool): tool.phase == .running
        case .subagent(let subagent): subagent.status.isActive
        case .threadStart, .annotation, .notice, .extensionUI: false
        }
    }

    private nonisolated static func isFailed(_ item: TranscriptItem) -> Bool {
        switch item {
        case .tool(let tool): tool.phase == .failed
        case .subagent(let subagent): subagent.status == .failed
        case .threadStart, .message, .annotation, .notice, .extensionUI: false
        }
    }

    private nonisolated static func duration(for items: [TranscriptItem]) -> TimeInterval? {
        var starts: [Date] = []
        var ends: [Date] = []
        var assistantEnds: [String: Date] = [:]
        var lastResponseHasEnd = false

        for item in items {
            switch item {
            case .message(let message) where message.role == .assistant:
                if let timestamp = message.timestamp { starts.append(timestamp) }
                let key = message.renderLineageKey.baseMessageID
                if let completedAt = completedAt(for: message) {
                    if let existing = assistantEnds[key] {
                        assistantEnds[key] = max(existing, completedAt)
                    } else {
                        assistantEnds[key] = completedAt
                    }
                }
                lastResponseHasEnd = assistantEnds[key] != nil
            case .tool(let tool):
                starts.append(tool.startDate)
                if let endDate = tool.endDate { ends.append(endDate) }
                lastResponseHasEnd = tool.endDate != nil
            case .subagent:
                lastResponseHasEnd = false
            case .extensionUI:
                lastResponseHasEnd = false
            case .threadStart, .message, .annotation, .notice:
                break
            }
        }
        ends.append(contentsOf: assistantEnds.values)
        guard lastResponseHasEnd, let start = starts.min(), let end = ends.max(), end >= start else {
            return nil
        }
        return end.timeIntervalSince(start)
    }

    private nonisolated static func completedAt(for message: TranscriptMessage) -> Date? {
        guard let value = message.raw["completedAt"] else { return nil }
        if let milliseconds = value.doubleValue {
            return Date(timeIntervalSince1970: milliseconds / 1_000)
        }
        guard let string = value.stringValue else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }
}

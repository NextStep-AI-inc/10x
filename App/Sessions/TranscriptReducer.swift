import Foundation
import OmpKit

struct TranscriptReducer {
    var items: [TranscriptItem] = []
    var runtimeState: SessionRuntimeState = .idle

    private var inflightMessageID: String?
    private var nextSyntheticID = 1
    private var toolReducer = ToolEventReducer()

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
            replaceOrAppend(.message(id: id, message: message, isFinal: false))
        case "message_update":
            guard let message = payload["message"] else { return }
            let id = inflightMessageID ?? messageID(message)
            inflightMessageID = id
            replaceOrAppend(.message(id: id, message: message, isFinal: false))
        case "message_end":
            guard let message = payload["message"] else { return }
            if consumeToolResult(message) { return }
            let id = inflightMessageID ?? messageID(message)
            replaceOrAppend(.message(id: id, message: message, isFinal: true))
            inflightMessageID = nil
        case "notice":
            let id = syntheticID(prefix: "notice")
            items.append(.notice(
                id: id,
                level: payload["level"]?.stringValue ?? "info",
                message: payload["message"]?.stringValue ?? ""))
        case "tool_execution_start", "tool_execution_update", "tool_execution_end":
            toolReducer.consume(type: type, payload: payload)
            guard let id = payload["toolCallId"]?.stringValue,
                  let presentation = toolReducer.presentations.first(where: { $0.id == id })
            else { return }
            replaceOrAppend(.tool(presentation))
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
                continue
            }

            let visibleText = Self.visibleMessageText(message)
            if message["role"]?.stringValue == "user" || !visibleText.isEmpty {
                items.append(.message(
                    id: message["id"]?.stringValue ?? "history-\(index)",
                    message: message,
                    isFinal: true))
            }
            items.append(contentsOf: Self.toolCallPresentations(message).map(TranscriptItem.tool))
        }
        inflightMessageID = nil
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

    private static func visibleMessageText(_ message: JSONValue) -> String {
        if let content = message["content"]?.stringValue { return content }
        return message["content"]?.arrayValue?.compactMap { block in
            guard block["type"]?.stringValue == "text" else { return nil }
            return block["text"]?.stringValue
        }.joined(separator: "\n") ?? ""
    }

    private mutating func consumeToolResult(_ message: JSONValue) -> Bool {
        guard let incoming = Self.toolResultPresentation(message) else { return false }
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

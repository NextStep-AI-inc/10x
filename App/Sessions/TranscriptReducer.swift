import OmpKit

struct TranscriptReducer {
    var items: [TranscriptItem] = []
    var runtimeState: SessionRuntimeState = .idle

    private var inflightMessageID: String?
    private var nextSyntheticID = 1

    mutating func consume(_ frame: RpcFrame) {
        guard case .event(let type, let payload) = frame else { return }

        switch type {
        case "agent_start", "turn_start":
            runtimeState = .streaming
        case "agent_end":
            if payload["isTerminal"]?.boolValue != false {
                runtimeState = .idle
            }
        case "message_start":
            guard let message = payload["message"] else { return }
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
            let id = inflightMessageID ?? messageID(message)
            replaceOrAppend(.message(id: id, message: message, isFinal: true))
            inflightMessageID = nil
        case "notice":
            let id = syntheticID(prefix: "notice")
            items.append(.notice(
                id: id,
                level: payload["level"]?.stringValue ?? "info",
                message: payload["message"]?.stringValue ?? ""))
        default:
            items.append(.rawEvent(
                id: syntheticID(prefix: "event"),
                type: type,
                payload: payload))
        }
    }

    mutating func load(messages: [JSONValue]) {
        items = messages.enumerated().map { index, message in
            .message(
                id: message["id"]?.stringValue ?? "history-\(index)",
                message: message,
                isFinal: true)
        }
        inflightMessageID = nil
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

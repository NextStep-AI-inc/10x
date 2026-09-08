import Foundation

/// Where a session left off, derived from its last message entry.
public enum SessionStatus: String, Sendable, Equatable {
    case complete
    case error
    case aborted
    case interrupted
    case pending
    case unknown
}

public struct SessionMetadata: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public let sessionId: String
    /// Read from the header. Bucket directory names collapse `/`, `\`, and `:`
    /// to `-`, so they cannot be decoded back into a path.
    public let cwd: String
    public let title: String?
    public let created: Date
    public let modified: Date
    public let sizeBytes: Int
    public let status: SessionStatus

    public init(
        path: String, sessionId: String, cwd: String, title: String?,
        created: Date, modified: Date, sizeBytes: Int, status: SessionStatus
    ) {
        self.path = path
        self.sessionId = sessionId
        self.cwd = cwd
        self.title = title
        self.created = created
        self.modified = modified
        self.sizeBytes = sizeBytes
        self.status = status
    }
}

enum SessionStatusClassifier {
    /// Walks the tail backwards for the last message entry and classifies it.
    /// Lines not starting with `{` are skipped: the window usually opens
    /// mid-line, and a crash can leave a partial final line.
    static func classify(tail: Data) -> SessionStatus {
        let lines = tail.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        var trailingToolResultIDs: Set<String> = []
        var hasUnidentifiedTrailingToolResult = false
        for line in lines.reversed() {
            guard line.first == UInt8(ascii: "{") else { continue }
            guard let object = try? JSONValue.decode(from: Data(line)),
                  object["type"]?.stringValue == "message",
                  let message = object["message"]
            else { continue }

            if message["role"]?.stringValue == "toolResult" {
                if let id = message["toolCallId"]?.stringValue, !id.isEmpty {
                    trailingToolResultIDs.insert(id)
                } else {
                    hasUnidentifiedTrailingToolResult = true
                }
                continue
            }

            if !trailingToolResultIDs.isEmpty || hasUnidentifiedTrailingToolResult {
                guard message["role"]?.stringValue == "assistant" else { return .interrupted }
                return classify(
                    assistant: message,
                    trailingToolResultIDs: trailingToolResultIDs,
                    hasUnidentifiedTrailingToolResult: hasUnidentifiedTrailingToolResult)
            }
            return classify(message: message)
        }
        return trailingToolResultIDs.isEmpty && !hasUnidentifiedTrailingToolResult
            ? .unknown
            : .interrupted
    }

    static func classify(message: JSONValue) -> SessionStatus {
        switch message["role"]?.stringValue {
        case "assistant":
            switch message["stopReason"]?.stringValue {
            case "error": return .error
            case "aborted": return .aborted
            case "length": return .interrupted
            default:
                // Tool calls with no results after them mean the turn was cut off.
                let blocks = message["content"]?.arrayValue ?? []
                let hasToolCall = blocks.contains { $0["type"]?.stringValue == "toolCall" }
                return hasToolCall ? .interrupted : .complete
            }
        case "toolResult": return .interrupted
        case "user": return .pending
        default: return .unknown
        }
    }

    private static func classify(
        assistant message: JSONValue,
        trailingToolResultIDs: Set<String>,
        hasUnidentifiedTrailingToolResult: Bool
    ) -> SessionStatus {
        guard message["stopReason"]?.stringValue == "stop" else {
            return classify(message: message)
        }
        let toolCalls = (message["content"]?.arrayValue ?? []).filter {
            $0["type"]?.stringValue == "toolCall"
        }
        let toolCallIDs = toolCalls.compactMap { block -> String? in
            let id = block["id"]?.stringValue ?? block["toolCallId"]?.stringValue
            return id.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard !toolCallIDs.isEmpty,
              toolCallIDs.count == toolCalls.count,
              Set(toolCallIDs).count == toolCallIDs.count,
              !hasUnidentifiedTrailingToolResult,
              Set(toolCallIDs).isSubset(of: trailingToolResultIDs)
        else { return .interrupted }
        return .complete
    }
}

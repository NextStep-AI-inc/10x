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
        for line in lines.reversed() {
            guard line.first == UInt8(ascii: "{") else { continue }
            guard let object = try? JSONDecoder().decode(JSONValue.self, from: Data(line)),
                  object["type"]?.stringValue == "message",
                  let message = object["message"]
            else { continue }
            return classify(message: message)
        }
        return .unknown
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
}

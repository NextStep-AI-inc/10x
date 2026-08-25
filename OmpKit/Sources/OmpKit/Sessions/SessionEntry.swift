import Foundation

/// The mutable 256-byte first line carrying a session's current title.
public struct SessionTitleSlot: Sendable, Equatable {
    public let title: String
    public let source: String?
    public let updatedAt: String

    public init(title: String, source: String?, updatedAt: String) {
        self.title = title
        self.source = source
        self.updatedAt = updatedAt
    }
}

/// The `type: "session"` line. `title` is reported after slot folding: the slot
/// wins when present, and an empty slot title means the session has none.
public struct SessionHeader: Sendable, Equatable {
    public let id: String
    public let cwd: String
    public let timestamp: String
    public let version: Int?
    public let title: String?
    public let titleSource: String?
    public let parentSession: String?

    public init(
        id: String, cwd: String, timestamp: String, version: Int?,
        title: String?, titleSource: String?, parentSession: String?
    ) {
        self.id = id
        self.cwd = cwd
        self.timestamp = timestamp
        self.version = version
        self.title = title
        self.titleSource = titleSource
        self.parentSession = parentSession
    }
}

public struct SessionEntryBase: Sendable, Equatable {
    public let id: String
    public let parentId: String?
    public let timestamp: String

    public init(id: String, parentId: String?, timestamp: String) {
        self.id = id
        self.parentId = parentId
        self.timestamp = timestamp
    }
}

/// One entry line. Variants the transcript needs are typed; the rest keep their
/// raw payload so an unfamiliar or newer entry kind is still positioned
/// correctly in the tree.
public enum SessionEntry: Sendable, Equatable {
    case message(base: SessionEntryBase, message: JSONValue)
    case modelChange(base: SessionEntryBase, model: String)
    case thinkingLevelChange(base: SessionEntryBase, thinkingLevel: String?)
    case compaction(base: SessionEntryBase, summary: String, firstKeptEntryId: String)
    case labelEntry(base: SessionEntryBase, targetId: String, label: String?)
    case resetBoundary(base: SessionEntryBase)
    case unknown(type: String, base: SessionEntryBase, raw: JSONValue)

    public var base: SessionEntryBase {
        switch self {
        case .message(let base, _),
             .modelChange(let base, _),
             .thinkingLevelChange(let base, _),
             .resetBoundary(let base):
            return base
        case .compaction(let base, _, _):
            return base
        case .labelEntry(let base, _, _):
            return base
        case .unknown(_, let base, _):
            return base
        }
    }

    public var typeName: String {
        switch self {
        case .message: return "message"
        case .modelChange: return "model_change"
        case .thinkingLevelChange: return "thinking_level_change"
        case .compaction: return "compaction"
        case .labelEntry: return "label"
        case .resetBoundary: return "reset_boundary"
        case .unknown(let type, _, _): return type
        }
    }
}

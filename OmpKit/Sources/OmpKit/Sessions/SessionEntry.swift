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

public struct SessionModelSelection: Sendable, Equatable {
    public let model: String
    public let role: String?
    public let resolvedModelIsFallback: Bool

    public init(model: String, role: String?, resolvedModelIsFallback: Bool) {
        self.model = model
        self.role = role
        self.resolvedModelIsFallback = resolvedModelIsFallback
    }
}

public struct SessionThinkingSelection: Sendable, Equatable {
    public let effective: String?
    public let configured: String?

    public init(effective: String?, configured: String?) {
        self.effective = effective
        self.configured = configured
    }
}

public struct SessionCompaction: Sendable, Equatable {
    public let summary: String
    public let shortSummary: String?
    public let firstKeptEntryId: String
    public let tokensBefore: Int?
    public let tokensAfter: Int?
    public let method: String?
    public let warning: String?

    public init(
        summary: String,
        shortSummary: String?,
        firstKeptEntryId: String,
        tokensBefore: Int?,
        tokensAfter: Int?,
        method: String?,
        warning: String?
    ) {
        self.summary = summary
        self.shortSummary = shortSummary
        self.firstKeptEntryId = firstKeptEntryId
        self.tokensBefore = tokensBefore
        self.tokensAfter = tokensAfter
        self.method = method
        self.warning = warning
    }
}

public struct SessionBranchSummary: Sendable, Equatable {
    public let fromId: String
    public let summary: String

    public init(fromId: String, summary: String) {
        self.fromId = fromId
        self.summary = summary
    }
}

public struct SessionModeSelection: Sendable, Equatable {
    public let mode: String
    public let data: JSONValue?

    public init(mode: String, data: JSONValue?) {
        self.mode = mode
        self.data = data
    }
}

/// Display-safe subagent metadata. Deliberately excludes `systemPrompt` and
/// schemas because those are execution context, not transcript content.
public struct SessionInitMetadata: Sendable, Equatable {
    public let task: String
    public let agent: String?
    public let modelRole: String?
    public let resolvedModel: String?
    public let isReadOnly: Bool
    public let advisor: String?

    public init(
        task: String,
        agent: String?,
        modelRole: String?,
        resolvedModel: String?,
        isReadOnly: Bool,
        advisor: String?
    ) {
        self.task = task
        self.agent = agent
        self.modelRole = modelRole
        self.resolvedModel = resolvedModel
        self.isReadOnly = isReadOnly
        self.advisor = advisor
    }
}

/// One entry line. Variants the transcript needs are typed; the rest keep their
/// raw payload so an unfamiliar or newer entry kind is still positioned
/// correctly in the tree.
public enum SessionEntry: Sendable, Equatable {
    case message(base: SessionEntryBase, message: JSONValue)
    case modelChange(base: SessionEntryBase, selection: SessionModelSelection)
    case thinkingLevelChange(base: SessionEntryBase, selection: SessionThinkingSelection)
    case compaction(base: SessionEntryBase, value: SessionCompaction)
    case branchSummary(base: SessionEntryBase, value: SessionBranchSummary)
    case modeChange(base: SessionEntryBase, selection: SessionModeSelection)
    case sessionInit(base: SessionEntryBase, metadata: SessionInitMetadata)
    case labelEntry(base: SessionEntryBase, targetId: String, label: String?)
    case resetBoundary(base: SessionEntryBase)
    case unknown(type: String, base: SessionEntryBase, raw: JSONValue)

    public var base: SessionEntryBase {
        switch self {
        case .message(let base, _),
             .modelChange(let base, _),
             .thinkingLevelChange(let base, _),
             .compaction(let base, _),
             .branchSummary(let base, _),
             .modeChange(let base, _),
             .sessionInit(let base, _),
             .resetBoundary(let base):
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
        case .branchSummary: return "branch_summary"
        case .modeChange: return "mode_change"
        case .sessionInit: return "session_init"
        case .labelEntry: return "label"
        case .resetBoundary: return "reset_boundary"
        case .unknown(let type, _, _): return type
        }
    }
}

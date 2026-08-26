enum ResolutionToolAction: Equatable, Sendable {
    case resolve
    case reject
    case propose
}

enum VibeToolAction: Equatable, Sendable {
    case spawn
    case send
    case wait
    case kill
    case list
}

enum ToolCardKind: Equatable, Sendable {
    case read
    case bash
    case edit
    case astGrep
    case astEdit
    case ask
    case debug
    case eval
    case github
    case glob
    case grep
    case lsp
    case inspectImage
    case browser
    case computer
    case checkpoint
    case rewind
    case securityScan
    case task
    case hub
    case todo
    case webSearch
    case write
    case memoryEdit
    case retain
    case recall
    case reflect
    case learn
    case manageSkill
    case `yield`
    case goal
    case think
    case resolution(ResolutionToolAction)
    case vibe(VibeToolAction)
    case mcp(server: String, tool: String)
    case custom(name: String)

    var isExplicit: Bool {
        if case .custom = self { return false }
        return true
    }

    var startsExpandedWhenComplete: Bool {
        switch self {
        case .edit, .astEdit, .resolution:
            true
        default:
            false
        }
    }
}

enum ToolCardRegistry {
    static func kind(for name: String) -> ToolCardKind {
        switch name.lowercased() {
        case "read": .read
        case "bash": .bash
        case "edit", "apply_patch": .edit
        case "ast_grep": .astGrep
        case "ast_edit": .astEdit
        case "ask": .ask
        case "debug": .debug
        case "eval": .eval
        case "github": .github
        case "glob", "find": .glob
        case "grep", "search": .grep
        case "lsp": .lsp
        case "inspect_image": .inspectImage
        case "browser": .browser
        case "computer": .computer
        case "checkpoint": .checkpoint
        case "rewind": .rewind
        case "security_scan": .securityScan
        case "task": .task
        case "hub": .hub
        case "todo": .todo
        case "web_search": .webSearch
        case "write": .write
        case "memory_edit": .memoryEdit
        case "retain": .retain
        case "recall": .recall
        case "reflect": .reflect
        case "learn": .learn
        case "manage_skill": .manageSkill
        case "yield": .yield
        case "goal": .goal
        case "think": .think
        case "resolve": .resolution(.resolve)
        case "reject": .resolution(.reject)
        case "propose": .resolution(.propose)
        case "vibe_spawn": .vibe(.spawn)
        case "vibe_send": .vibe(.send)
        case "vibe_wait": .vibe(.wait)
        case "vibe_kill": .vibe(.kill)
        case "vibe_list": .vibe(.list)
        default:
            mcpKind(for: name) ?? .custom(name: name)
        }
    }

    private static func mcpKind(for name: String) -> ToolCardKind? {
        guard name.lowercased().hasPrefix("mcp__") else { return nil }
        let remainder = String(name.dropFirst("mcp__".count))
        let separator = remainder.range(of: "__") ?? remainder.range(of: "_")
        guard let separator else {
            return .mcp(server: remainder, tool: "Tool")
        }
        let server = String(remainder[..<separator.lowerBound])
        let tool = String(remainder[separator.upperBound...])
        return .mcp(
            server: server.isEmpty ? "MCP" : server,
            tool: tool.isEmpty ? "Tool" : tool)
    }
}

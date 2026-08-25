enum ToolCardKind: Equatable {
    case read
    case bash
    case edit
    case write
    case search
    case task
    case todo
    case web
    case generic
}

enum ToolCardRegistry {
    static func kind(for name: String) -> ToolCardKind {
        switch name.lowercased() {
        case "read": .read
        case "bash": .bash
        case "edit": .edit
        case "write": .write
        case "grep", "glob": .search
        case "task": .task
        case "todo": .todo
        case "web_search", "browser": .web
        default: .generic
        }
    }
}

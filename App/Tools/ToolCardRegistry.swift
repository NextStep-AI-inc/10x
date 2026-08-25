enum ToolCardKind: Equatable {
    case generic
}

enum ToolCardRegistry {
    static func kind(for name: String) -> ToolCardKind {
        .generic
    }
}

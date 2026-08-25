enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case appearance
    case models
    case agent
    case tools
    case subagents
    case memory
    case integrations
    case safety
    case advanced

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

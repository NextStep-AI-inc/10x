enum RailAccessibility {
    static func sessionLabel(
        title: String,
        project: String,
        state: String,
        hasComputerUse: Bool = false
    ) -> String {
        var parts = [title, project, state]
        if hasComputerUse { parts.append("Computer use active") }
        return parts.joined(separator: ", ")
    }
}

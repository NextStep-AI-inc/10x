enum RailAccessibility {
    static func sessionLabel(title: String, project: String, state: String) -> String {
        [title, project, state].joined(separator: ", ")
    }
}

enum RailAccessibility {
    static func sessionLabel(title: String, project: String, state: String) -> String {
        [title, project, state].joined(separator: ", ")
    }

    static func projectHint(_ displayName: String) -> String {
        "Starts a new session in \(displayName)"
    }

    static func disclosureLabel(hiddenCount: Int, isExpanded: Bool) -> String {
        isExpanded ? "Show recent 5 sessions" : "Show \(hiddenCount) more sessions"
    }

    static func hiddenSessionsLabel(_ hiddenCount: Int) -> String {
        "\(hiddenCount) more sessions"
    }

    static func scrollLabel(_ direction: RailScrollDirection) -> String {
        direction == .up ? "Show earlier rail items" : "Show later rail items"
    }
}

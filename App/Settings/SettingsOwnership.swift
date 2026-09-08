import Foundation

enum SettingsOwner: String {
    case omp = "OMP"
    case tenX = "10x"
}

enum TenXSettingsCategory: String, CaseIterable, Identifiable {
    case general
    case composer
    case computerUse

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general, .composer: rawValue.capitalized
        case .computerUse: "Computer Use"
        }
    }

    func matches(query: String, preferredIDEName: String?) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return switch self {
        case .general:
            PreferredIDESettingRowView.matches(
                query: query,
                applicationName: preferredIDEName)
            || HarnessNoticeSettingRowView.matches(query: query)
        case .composer:
            [
                "Composer", "default send action", "Steer", "Follow up",
                "keyboard shortcuts", "Enter", "Command-Enter", "Shift-Enter", "New line",
            ].contains { $0.localizedCaseInsensitiveContains(query) }
        case .computerUse:
            [
                "Computer", "Computer Use", "MCP", "daemon", "install", "selfcheck",
                "Claude Code", "Codex",
            ].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}

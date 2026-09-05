import Foundation

enum SettingsOwner: String {
    case omp = "OMP"
    case tenX = "10x"
}

enum TenXSettingsCategory: String, CaseIterable, Identifiable {
    case general
    case composer

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    func matches(query: String, preferredIDEName: String?) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return switch self {
        case .general:
            PreferredIDESettingRowView.matches(
                query: query,
                applicationName: preferredIDEName)
        case .composer:
            [
                "Composer", "default send action", "Steer", "Follow up",
                "keyboard shortcuts", "Enter", "Command-Enter", "Shift-Enter", "New line",
            ].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}

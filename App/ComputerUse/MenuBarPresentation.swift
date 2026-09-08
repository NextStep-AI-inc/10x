import Foundation

struct HarnessSessionGroup: Equatable {
    let harness: String
    let sessions: [ComputerSessionState]
}

enum MenuBarPresentation {
    /// Groups sessions with at least one claimed window by harness.
    /// "10x" sorts first (own sessions are the ones you can open in-app);
    /// the rest sort alphabetically.
    static func groups(sessions: [Int: ComputerSessionState]) -> [HarnessSessionGroup] {
        let active = sessions.values.filter { !$0.windows.isEmpty }
        let grouped = Dictionary(grouping: active, by: \.harness)
        return grouped
            .map { HarnessSessionGroup(harness: $0.key, sessions: $0.value.sorted { $0.id < $1.id }) }
            .sorted { lhs, rhs in
                if lhs.harness == "10x" { return true }
                if rhs.harness == "10x" { return false }
                return lhs.harness.localizedCaseInsensitiveCompare(rhs.harness) == .orderedAscending
            }
    }
}

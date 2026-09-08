import Observation

enum RailSessionActivity: Equatable {
    case neutral
    case working
    case completed
    case needsInput
    case failed
    case stopped
}

enum RailSessionIndicator: Equatable {
    case neutral
    case working
    case completed
    case needsInput
    case failed
}

@MainActor
@Observable
final class RailSessionReadState {
    private var lastActivityByPath: [String: RailSessionActivity] = [:]
    private var unreadCompletionPaths: Set<String> = []

    func observe(path: String, activity: RailSessionActivity, isSelected: Bool) {
        let previous = lastActivityByPath[path]
        lastActivityByPath[path] = activity

        if isSelected {
            unreadCompletionPaths.remove(path)
        } else if activity == .completed, previous == .working {
            unreadCompletionPaths.insert(path)
        } else if activity != .completed {
            unreadCompletionPaths.remove(path)
        }
    }

    func indicator(for path: String, activity: RailSessionActivity) -> RailSessionIndicator {
        switch activity {
        case .working: .working
        case .completed where unreadCompletionPaths.contains(path): .completed
        case .needsInput: .needsInput
        case .failed: .failed
        case .neutral, .completed, .stopped: .neutral
        }
    }
}

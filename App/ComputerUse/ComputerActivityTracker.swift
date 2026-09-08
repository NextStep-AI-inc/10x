import Foundation

enum ComputerActivityPhase: Equatable {
    case off
    case ready        // holds claims, no input action yet / lately
    case controlling  // an act call is in flight or just completed
}

/// Reduces one session's MCP tool stream into computer-use activity.
/// Tool names arrive as mcp__tenx-computer_<tool>; inputs carry window_id.
struct ComputerActivityTracker {
    static let toolPrefix = "mcp__tenx-computer_computer_"

    private(set) var claimedWindowIDs: Set<Int> = []
    private(set) var phase: ComputerActivityPhase = .off
    private var pendingActCount = 0

    var isActive: Bool { !claimedWindowIDs.isEmpty }

    /// Returns true when the tool is one of ours.
    @discardableResult
    mutating func toolStarted(name: String, input: [String: Any]?) -> Bool {
        guard name.hasPrefix(Self.toolPrefix) else { return false }
        let tool = String(name.dropFirst(Self.toolPrefix.count))
        switch tool {
        case "claim":
            if let id = input?["window_id"] as? Int { claimedWindowIDs.insert(id) }
        case "release":
            if let id = input?["window_id"] as? Int { claimedWindowIDs.remove(id) }
        case "act":
            pendingActCount += 1
        default:
            break // windows/screenshot/status/launch: no state change at start
        }
        recompute()
        return true
    }

    /// `claimedWindowID` is parsed from the tool result text for computer_launch
    /// ("launched X; claimed window N …") by the caller.
    mutating func toolCompleted(name: String, claimedWindowID: Int? = nil) {
        guard name.hasPrefix(Self.toolPrefix) else { return }
        let tool = String(name.dropFirst(Self.toolPrefix.count))
        switch tool {
        case "act": pendingActCount = max(0, pendingActCount - 1)
        case "launch": if let claimedWindowID { claimedWindowIDs.insert(claimedWindowID) }
        default: break
        }
        recompute()
    }

    private mutating func recompute() {
        if claimedWindowIDs.isEmpty { phase = .off }
        else if pendingActCount > 0 { phase = .controlling }
        else { phase = .ready }
    }
}

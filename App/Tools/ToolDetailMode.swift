import Foundation

/// What an activity row needs to say about itself for a mode to place it.
struct ToolDisclosureTraits: Equatable, Sendable {
    let isActive: Bool
    let isError: Bool
    /// True for the kinds worth reading once they finish, such as edits.
    let opensWhenComplete: Bool
}

enum ToolDetailMode: String, CaseIterable, Identifiable, Sendable {
    /// Tool-call group open, and every tool open.
    case expanded
    /// Tool-call group open, tools closed.
    case standard
    /// Tool-call group closed. The group line carries the tool call and its info.
    case slim

    var id: String { rawValue }

    /// Chips read capitalized, matching the effort row they share a style with.
    var title: String { rawValue.capitalized }

    var accessibilityTitle: String { rawValue.capitalized }

    var opensToolsByDefault: Bool { self == .expanded }

    var opensGroupsByDefault: Bool { self != .slim }

    func isExpandedByDefault(_: ToolDisclosureTraits) -> Bool {
        opensToolsByDefault
    }

    /// Older raw values keep their nearest density instead of jumping to Standard.
    static func resolving(_ rawValue: String?) -> Self {
        switch rawValue {
        case "expanded": .expanded
        case "standard": .standard
        case "slim", "compact": .slim
        case "auto": .standard
        default: .standard
        }
    }
}

extension ToolPresentation {
    var disclosureTraits: ToolDisclosureTraits {
        ToolDisclosureTraits(
            isActive: phase == .running,
            isError: phase == .failed,
            opensWhenComplete: ToolCardRegistry.kind(for: name).startsExpandedWhenComplete)
    }
}

extension SubagentPresentation {
    var disclosureTraits: ToolDisclosureTraits {
        ToolDisclosureTraits(
            isActive: status.isActive,
            isError: status.isError,
            opensWhenComplete: false)
    }
}

import Foundation

/// What an activity row needs to say about itself for a mode to place it.
struct ToolDisclosureTraits: Equatable, Sendable {
    let isActive: Bool
    let isError: Bool
    /// True for the kinds worth reading once they finish, such as edits.
    let opensWhenComplete: Bool
}

enum ToolDetailMode: String, CaseIterable, Identifiable, Sendable {
    /// Open while the work is live or failed, and for the kinds worth reading
    /// once they land. Everything else stays closed.
    case auto
    case expanded
    case compact

    var id: String { rawValue }

    /// Chips read lowercase, matching the effort row they share a style with.
    var title: String { rawValue }

    var accessibilityTitle: String { rawValue.capitalized }

    func isExpandedByDefault(_ traits: ToolDisclosureTraits) -> Bool {
        switch self {
        case .auto: traits.isActive || traits.isError || traits.opensWhenComplete
        case .expanded: true
        case .compact: false
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

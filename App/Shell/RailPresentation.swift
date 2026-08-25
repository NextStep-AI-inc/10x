import Foundation
import OmpKit

struct RailProjectDisclosure: Equatable {
    let projectID: String
    let hiddenCount: Int
    let isExpanded: Bool
}

struct RailPresentationItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case project
        case session
        case disclosure
    }

    enum Content: Equatable {
        case project(ProjectSessionGroup)
        case session(SessionMetadata)
        case disclosure(RailProjectDisclosure)
    }

    enum TreePosition: Equatable {
        case root
        case child
        case terminalChild
    }

    let content: Content
    let isSelected: Bool
    let markerLabel: String
    let treePosition: TreePosition

    var kind: Kind {
        switch content {
        case .project: .project
        case .session: .session
        case .disclosure: .disclosure
        }
    }

    var disclosure: RailProjectDisclosure? {
        guard case .disclosure(let disclosure) = content else { return nil }
        return disclosure
    }

    var id: String {
        switch content {
        case .project(let group): "project:\(group.id)"
        case .session(let metadata): "session:\(metadata.path)"
        case .disclosure(let disclosure): "disclosure:\(disclosure.projectID)"
        }
    }
}

enum RailPresentation {
    static let recentSessionLimit = 5

    static func items(
        groups: [ProjectSessionGroup],
        selectedSessionPath: String?,
        expandedProjectIDs: Set<String> = []
    ) -> [RailPresentationItem] {
        groups.flatMap { group in
            let hasDisclosure = group.sessions.count > recentSessionLimit
            let isExpanded = expandedProjectIDs.contains(group.id)
            let visibleSessions = isExpanded
                ? group.sessions
                : Array(group.sessions.prefix(recentSessionLimit))

            return [RailPresentationItem(
                content: .project(group),
                isSelected: false,
                markerLabel: markerLabel(for: group.displayName),
                treePosition: .root,
            )]
                + visibleSessions.enumerated().map { index, metadata in
                    RailPresentationItem(
                        content: .session(metadata),
                        isSelected: metadata.path == selectedSessionPath,
                        markerLabel: String(format: "%02d", index + 1),
                        treePosition: !hasDisclosure && index == visibleSessions.count - 1
                            ? .terminalChild
                            : .child,
                    )
                }
                + (hasDisclosure
                    ? [RailPresentationItem(
                        content: .disclosure(RailProjectDisclosure(
                            projectID: group.id,
                            hiddenCount: group.sessions.count - recentSessionLimit,
                            isExpanded: isExpanded)),
                        isSelected: false,
                        markerLabel: "...",
                        treePosition: .terminalChild,
                    )]
                    : [])
        }
    }

    private static func markerLabel(for displayName: String) -> String {
        let words = displayName.split { character in
            !character.isLetter && !character.isNumber
        }
        guard let first = words.first else { return "??" }
        if words.count > 1, let second = words.dropFirst().first {
            return String(first.prefix(1) + second.prefix(1)).uppercased()
        }
        return String(first.prefix(2)).uppercased()
    }
}

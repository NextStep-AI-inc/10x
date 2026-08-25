import Foundation
import OmpKit

struct RailPresentationItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case project
        case session
    }

    enum Content: Equatable {
        case project(ProjectSessionGroup)
        case session(SessionMetadata)
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
        }
    }

    var id: String {
        switch content {
        case .project(let group): "project:\(group.id)"
        case .session(let metadata): "session:\(metadata.path)"
        }
    }
}

enum RailPresentation {
    static func items(
        groups: [ProjectSessionGroup],
        selectedSessionPath: String?
    ) -> [RailPresentationItem] {
        groups.flatMap { group in
            [RailPresentationItem(
                content: .project(group),
                isSelected: false,
                markerLabel: markerLabel(for: group.displayName),
                treePosition: .root,
            )]
                + group.sessions.enumerated().map { index, metadata in
                    RailPresentationItem(
                        content: .session(metadata),
                        isSelected: metadata.path == selectedSessionPath,
                        markerLabel: String(format: "%02d", index + 1),
                        treePosition: index == group.sessions.count - 1 ? .terminalChild : .child,
                    )
                }
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

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

    let content: Content
    let isSelected: Bool

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
            [RailPresentationItem(content: .project(group), isSelected: false)]
                + group.sessions.map { metadata in
                    RailPresentationItem(
                        content: .session(metadata),
                        isSelected: metadata.path == selectedSessionPath)
                }
        }
    }
}

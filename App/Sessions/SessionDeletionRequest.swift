import OmpKit

enum SessionDeletionRequest: Identifiable, Equatable {
    case session(SessionMetadata)
    case project(ProjectSessionGroup)

    var id: String {
        switch self {
        case .session(let metadata):
            "session:\(metadata.path)"
        case .project(let group):
            "project:\(group.id)"
        }
    }

    var paths: [String] {
        switch self {
        case .session(let metadata):
            [metadata.path]
        case .project(let group):
            group.sessions.map(\.path)
        }
    }

    var title: String {
        switch self {
        case .session(let metadata):
            "Delete \(sessionDisplayName(metadata))?"
        case .project(let group):
            "Delete sessions for \(group.displayName)?"
        }
    }

    var message: String {
        switch self {
        case .session:
            return "This permanently deletes the session transcript. Project files are not changed."
        case .project(let group):
            let count = group.sessions.count
            let noun = count == 1 ? "transcript" : "transcripts"
            return "This permanently deletes \(count) session \(noun). Project files are not changed."
        }
    }

    var errorSubject: String {
        switch self {
        case .session(let metadata):
            sessionDisplayName(metadata)
        case .project(let group):
            "\(group.displayName) sessions"
        }
    }

    private func sessionDisplayName(_ metadata: SessionMetadata) -> String {
        metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session"
    }
}

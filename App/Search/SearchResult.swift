import Foundation

enum SearchResultKind: String, CaseIterable, Hashable {
    case session
    case message
    case tool

    var label: String {
        switch self {
        case .session: "Session"
        case .message: "Message"
        case .tool: "Tool"
        }
    }
}

struct SearchResult: Identifiable, Equatable {
    let sessionPath: String
    let entryID: String?
    let projectPath: String
    let title: String
    let excerpt: String
    let kind: SearchResultKind
    let query: String

    init(
        sessionPath: String,
        entryID: String?,
        projectPath: String,
        title: String,
        excerpt: String,
        kind: SearchResultKind,
        query: String = ""
    ) {
        self.sessionPath = sessionPath
        self.entryID = entryID
        self.projectPath = projectPath
        self.title = title
        self.excerpt = excerpt
        self.kind = kind
        self.query = query
    }

    var id: String {
        "\(sessionPath)#\(entryID ?? "session")#\(kind.rawValue)"
    }

    func withOpeningQuery(_ query: String) -> Self {
        Self(
            sessionPath: sessionPath,
            entryID: entryID,
            projectPath: projectPath,
            title: title,
            excerpt: excerpt,
            kind: kind,
            query: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

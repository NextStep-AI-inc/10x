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

    var id: String {
        "\(sessionPath)#\(entryID ?? "session")#\(kind.rawValue)"
    }
}

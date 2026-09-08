import Foundation

struct IDEApplication: Identifiable, Equatable {
    enum Source: Equatable {
        case known(bundleIdentifier: String)
        case custom
    }

    let displayName: String
    let url: URL
    let source: Source

    var id: String {
        switch source {
        case .known(let bundleIdentifier):
            bundleIdentifier
        case .custom:
            url.standardizedFileURL.path
        }
    }
}

enum IDESelection: Codable, Equatable {
    case known(bundleIdentifier: String, displayName: String)
    case custom(bookmarkData: Data, displayName: String)

    var displayName: String {
        switch self {
        case .known(_, let displayName), .custom(_, let displayName):
            displayName
        }
    }
}

enum IDEPreferenceState: Equatable {
    case none
    case available(IDEApplication)
    case unavailable(displayName: String)
}

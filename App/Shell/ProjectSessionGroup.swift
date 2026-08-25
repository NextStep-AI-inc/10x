import Foundation
import OmpKit

struct ProjectSessionGroup: Identifiable, Equatable {
    static let unknownProjectURL = URL(filePath: "/Unknown Project", directoryHint: .isDirectory)

    let projectURL: URL
    let sessions: [SessionMetadata]

    var id: String { projectURL.standardizedFileURL.path }
    var displayName: String {
        projectURL == Self.unknownProjectURL ? "Unknown Project" : projectURL.lastPathComponent
    }
}

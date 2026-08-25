import Foundation
import OmpKit

enum ProjectSessionGrouper {
    static func groups(_ sessions: [SessionMetadata]) -> [ProjectSessionGroup] {
        let grouped = Dictionary(grouping: sessions) { metadata in
            guard !metadata.cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ProjectSessionGroup.unknownProjectURL
            }
            return URL(filePath: metadata.cwd, directoryHint: .isDirectory).standardizedFileURL
        }

        return grouped.map { projectURL, sessions in
            ProjectSessionGroup(
                projectURL: projectURL,
                sessions: sessions.sorted { $0.modified > $1.modified })
        }
        .sorted { left, right in
            guard let leftDate = left.sessions.first?.modified else { return false }
            guard let rightDate = right.sessions.first?.modified else { return true }
            return leftDate > rightDate
        }
    }
}

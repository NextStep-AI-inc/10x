import Foundation
import OmpKit

enum ProjectSessionGrouper {
    /// - Parameter knownProjectURLs: Projects the app remembers even without
    ///   a session yet, most recently added first (see
    ///   `RecentProjectStore.knownProjects`). Each one not already covered
    ///   by a session-derived group gets its own group with no sessions, so
    ///   it can still show up wherever groups are listed (e.g. the rail).
    ///   Defaults to empty so existing callers are unaffected.
    static func groups(
        _ sessions: [SessionMetadata],
        knownProjectURLs: [URL] = []
    ) -> [ProjectSessionGroup] {
        let grouped = Dictionary(grouping: sessions) { metadata in
            guard !metadata.cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ProjectSessionGroup.unknownProjectURL
            }
            return URL(filePath: metadata.cwd, directoryHint: .isDirectory).standardizedFileURL
        }

        let sessionGroups = grouped.map { projectURL, sessions in
            ProjectSessionGroup(
                projectURL: projectURL,
                sessions: sessions.sorted { $0.modified > $1.modified })
        }
        .sorted { left, right in
            guard let leftDate = left.sessions.first?.modified else { return false }
            guard let rightDate = right.sessions.first?.modified else { return true }
            return leftDate > rightDate
        }

        // Session-bearing groups first (already ordered above, newest
        // first); sessionless known projects after, most recently added
        // first — the order `knownProjectURLs` already arrives in.
        var seenPaths = Set(sessionGroups.map(\.id))
        var sessionlessGroups: [ProjectSessionGroup] = []
        for url in knownProjectURLs {
            let standardized = url.standardizedFileURL
            guard standardized != ProjectSessionGroup.unknownProjectURL,
                  seenPaths.insert(standardized.path).inserted
            else { continue }
            sessionlessGroups.append(ProjectSessionGroup(projectURL: standardized, sessions: []))
        }

        return sessionGroups + sessionlessGroups
    }

    static func choosableProjectURLs(
        from sessions: [SessionMetadata],
        including selected: URL? = nil,
        knownProjectURLs: [URL] = []
    ) -> [URL] {
        var urls = groups(sessions, knownProjectURLs: knownProjectURLs)
            .map(\.projectURL)
            .filter { $0 != ProjectSessionGroup.unknownProjectURL }
        if let selected {
            let standardized = selected.standardizedFileURL
            if !urls.contains(where: { $0.path == standardized.path }) {
                urls.insert(standardized, at: 0)
            }
        }
        return urls
    }
}

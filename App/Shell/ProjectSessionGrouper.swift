import Foundation
import OmpKit

enum ProjectSessionGrouper {
    /// - Parameter knownProjectURLs: Projects the app remembers even without
    ///   a session yet, most recently added first (see
    ///   `RecentProjectStore.knownProjects`). Each one not already covered by
    ///   a session-derived group gets its own group with no sessions, so it
    ///   still shows up wherever groups are listed, such as the rail.
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

        // Newest created first, never newest modified: omp rewrites a session
        // file on every streamed token, and the library reloads on that write.
        // Ordering by modification date makes the rail resort itself under the
        // pointer mid-turn, so a click lands on whichever session slid into the
        // row. Creation order is fixed for the life of a session, so rows only
        // move when one is genuinely added or removed.
        let sessionGroups = grouped.map { projectURL, sessions in
            ProjectSessionGroup(
                projectURL: projectURL,
                sessions: sessions.sorted(by: isNewer))
        }
        .sorted { left, right in
            guard let leftSession = left.sessions.first else { return false }
            guard let rightSession = right.sessions.first else { return true }
            return isNewer(leftSession, rightSession)
        }

        // Session-bearing groups first, in the creation order established
        // above; sessionless known projects after, most recently added first,
        // which is the order `knownProjectURLs` already arrives in.
        var seenPaths = Set(sessionGroups.map(\.id))
        var sessionlessGroups: [ProjectSessionGroup] = []
        for url in knownProjectURLs {
            let standardized = url.standardizedFileURL
            guard standardized != ProjectSessionGroup.unknownProjectURL,
                  seenPaths.insert(standardized.path).inserted
            else { continue }
            sessionlessGroups.append(
                ProjectSessionGroup(projectURL: standardized, sessions: []))
        }

        return sessionGroups + sessionlessGroups
    }

    /// Path breaks ties so two sessions created in the same millisecond keep a
    /// fixed order rather than swapping between reloads.
    private static func isNewer(_ left: SessionMetadata, _ right: SessionMetadata) -> Bool {
        guard left.created == right.created else { return left.created > right.created }
        return left.path < right.path
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

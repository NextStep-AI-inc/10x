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

        // Newest created first, never newest modified: omp rewrites a session
        // file on every streamed token, and the library reloads on that write.
        // Ordering by modification date makes the rail resort itself under the
        // pointer mid-turn, so a click lands on whichever session slid into the
        // row. Creation order is fixed for the life of a session, so rows only
        // move when one is genuinely added or removed.
        return grouped.map { projectURL, sessions in
            ProjectSessionGroup(
                projectURL: projectURL,
                sessions: sessions.sorted(by: isNewer))
        }
        .sorted { left, right in
            guard let leftSession = left.sessions.first else { return false }
            guard let rightSession = right.sessions.first else { return true }
            return isNewer(leftSession, rightSession)
        }
    }

    /// Path breaks ties so two sessions created in the same millisecond keep a
    /// fixed order rather than swapping between reloads.
    private static func isNewer(_ left: SessionMetadata, _ right: SessionMetadata) -> Bool {
        guard left.created == right.created else { return left.created > right.created }
        return left.path < right.path
    }

    static func choosableProjectURLs(
        from sessions: [SessionMetadata],
        including selected: URL? = nil
    ) -> [URL] {
        var urls = groups(sessions)
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

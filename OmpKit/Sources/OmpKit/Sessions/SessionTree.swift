import Foundation

/// Resolves the conversation actually on screen out of a session's entry tree.
///
/// Entries form a tree via `parentId`; branching happens when a new entry is
/// appended under an earlier parent. There is no leaf marker on disk — the
/// persisted leaf is simply the last entry in file order.
public enum SessionTree {
    /// The active path, root first. Returns an empty array for a header-only file.
    public static func activePath(of file: ParsedSessionFile) -> [SessionEntry] {
        activePath(entries: file.entries, leafId: nil)
    }

    public static func activePath(
        entries: [SessionEntry], leafId: String?
    ) -> [SessionEntry] {
        guard !entries.isEmpty else { return [] }
        var byId: [String: SessionEntry] = [:]
        for entry in entries { byId[entry.base.id] = entry }

        let leaf: SessionEntry?
        if let leafId {
            leaf = byId[leafId] ?? entries.last
        } else {
            leaf = entries.last
        }
        guard let leaf else { return [] }

        // A corrupt file can contain a parent cycle; the guard keeps the walk finite.
        var path: [SessionEntry] = []
        var seen: Set<String> = []
        var cursor: SessionEntry? = leaf
        while let current = cursor, !seen.contains(current.base.id) {
            seen.insert(current.base.id)
            path.append(current)
            cursor = current.base.parentId.flatMap { byId[$0] }
        }
        return path.reversed()
    }

    /// Entries the newest compaction on the path replaced with a summary, so a
    /// transcript can collapse them behind it.
    public static func compactedPrefix(
        of path: [SessionEntry]
    ) -> (hidden: ArraySlice<SessionEntry>, summary: String)? {
        guard let compactionIndex = path.lastIndex(where: {
            if case .compaction = $0 { return true }
            return false
        }) else { return nil }
        guard case .compaction(_, let summary, let firstKeptEntryId) = path[compactionIndex] else {
            return nil
        }
        let cutoff = path.firstIndex { $0.base.id == firstKeptEntryId } ?? compactionIndex
        guard cutoff > 0 else { return (path[0..<0], summary) }
        return (path[0..<cutoff], summary)
    }
}

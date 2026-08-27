import Foundation

/// A Git repository offered as a project suggestion during onboarding.
struct GitRepositorySuggestion: Equatable, Sendable, Identifiable {
    var id: String { url.path }
    let url: URL
    let modified: Date
}

/// Finds Git repositories under the user's home folder to suggest as projects.
///
/// Spotlight cannot answer this: it does not index dot-directories, so a query
/// for `.git` returns nothing. A bounded walk is the only option, and it is
/// cheap once `Library` is skipped and the walk stops at each repository.
struct GitRepositoryScanner: Sendable {
    /// Skipped by name below the home folder. The first four are the folders
    /// macOS gates behind a consent prompt, which onboarding must not trigger.
    /// `.Trash` is also covered by `.skipsHiddenFiles`.
    static let excludedNames: Set<String> = [
        "Library", "Desktop", "Documents", "Downloads", ".Trash",
    ]

    /// Directory levels below the home folder. Results saturate here: a
    /// development machine found 40 repositories at 3 and 55 at both 4 and 5.
    static let maximumDepth = 4
    static let maximumResults = 12

    private let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func scan() async throws -> [GitRepositorySuggestion] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: homeDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }

        var found: [GitRepositorySuggestion] = []
        // `for case let url as URL in enumerator` desugars to `NSEnumerator`'s
        // `Sequence` conformance, whose `makeIterator()` is unavailable from
        // asynchronous contexts. Driving `nextObject()` directly avoids that
        // restriction without changing the walk's behavior.
        while let next = enumerator.nextObject() {
            try Task.checkCancellation()
            guard let url = next as? URL else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))

            // Resource values resolve symlinks, so a link to a directory reads
            // as one. Checking the link itself is what stops a cycle.
            guard values?.isDirectory == true, values?.isSymbolicLink != true else {
                enumerator.skipDescendants()
                continue
            }
            guard !Self.excludedNames.contains(url.lastPathComponent) else {
                enumerator.skipDescendants()
                continue
            }
            if Self.isRepository(url) {
                found.append(GitRepositorySuggestion(
                    url: url.standardizedFileURL,
                    modified: values?.contentModificationDate ?? .distantPast))
                // Nothing inside a repository is a separate project, and this
                // is what keeps the walk cheap.
                enumerator.skipDescendants()
                continue
            }
            if enumerator.level >= Self.maximumDepth {
                enumerator.skipDescendants()
            }
        }

        return Array(
            found.sorted { $0.modified > $1.modified }
                .prefix(Self.maximumResults))
    }

    /// A worktree's `.git` is a file, not a directory, so requiring a directory
    /// excludes worktrees without a special case.
    private static func isRepository(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let git = url.appending(path: ".git").path
        guard FileManager.default.fileExists(atPath: git, isDirectory: &isDirectory)
        else { return false }
        return isDirectory.boolValue
    }
}

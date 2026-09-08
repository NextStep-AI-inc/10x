import Foundation
import OmpKit

@MainActor
struct RecentProjectStore: Sendable {
    static let defaultKey = "recent-project-paths"

    /// How many projects the store remembers for listing (the rail, the
    /// composer's project flyout, onboarding). Wider than `rankedProjects`,
    /// which stays capped to the startup warming budget.
    static let knownProjectsLimit = 10

    /// How many projects `rankedProjects` warms an OMP client for at
    /// startup. Not a listing limit: see `knownProjects`.
    static let rankedProjectsLimit = 2

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = Self.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func recordSelection(_ url: URL) {
        guard let project = canonicalDirectory(url) else { return }
        let prior = defaults.stringArray(forKey: key) ?? []
        let paths = [project.path] + prior.filter { path in
            URL(filePath: path).resolvingSymlinksInPath().standardizedFileURL.path != project.path
        }
        defaults.set(Array(paths.prefix(Self.knownProjectsLimit)), forKey: key)
    }

    /// Every project 10x remembers, most recently added first, for listing.
    /// Unlike `rankedProjects`, this never falls back to session history and
    /// is not capped to the warming budget.
    func knownProjects() -> [URL] {
        let explicitPaths = defaults.stringArray(forKey: key) ?? []
        var seen = Set<String>()
        var projects: [URL] = []

        for path in explicitPaths {
            guard let project = canonicalDirectory(URL(filePath: path, directoryHint: .isDirectory)),
                  seen.insert(project.path).inserted
            else { continue }
            projects.append(project)
        }
        return projects
    }

    func rankedProjects(sessions: [SessionMetadata]) -> [URL] {
        let explicitPaths = defaults.stringArray(forKey: key) ?? []
        let sessionPaths = sessions
            .sorted { $0.modified > $1.modified }
            .map(\.cwd)
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        var projects: [URL] = []

        for path in explicitPaths + sessionPaths {
            guard projects.count < Self.rankedProjectsLimit,
                  let project = canonicalDirectory(URL(filePath: path, directoryHint: .isDirectory)),
                  seen.insert(project.path).inserted
            else { continue }
            projects.append(project)
        }
        return projects
    }

    private func canonicalDirectory(_ url: URL) -> URL? {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isReadableKey]
        guard let values = try? canonical.resourceValues(forKeys: keys),
              values.isDirectory == true,
              values.isReadable == true
        else { return nil }
        return canonical
    }
}

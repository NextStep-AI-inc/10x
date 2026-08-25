import Foundation
import OmpKit

@MainActor
struct RecentProjectStore: Sendable {
    static let defaultKey = "recent-project-paths"

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
        defaults.set(Array(paths.prefix(2)), forKey: key)
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
            guard projects.count < 2,
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

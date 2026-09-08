import Foundation

/// Why setup did or did not get a runtime. `unrunnable` is kept distinct from
/// `notFound` because they need different things from the user: one is a
/// missing install, the other an install that cannot execute.
enum OmpLocation: Equatable, Sendable {
    case found(OmpInstallation)
    /// An executable is at this path, but it could not report a version.
    case unrunnable(URL)
    case notFound

    var installation: OmpInstallation? {
        guard case .found(let installation) = self else { return nil }
        return installation
    }
}

protocol OmpLocating: Sendable {
    func locate(preferredURL: URL?) async throws -> OmpLocation
}

struct OmpExecutableLocator: OmpLocating {
    /// Display strings for the setup screen, derived from the same directories
    /// `candidates(preferredURL:)` probes so the two cannot drift.
    static let knownPaths = OmpProcessEnvironment.toolDirectories.map { "\($0)/omp" }

    private let homeDirectory: URL
    private let pathDirectories: [String]

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        path: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) {
        self.homeDirectory = homeDirectory
        self.pathDirectories = path.split(separator: ":").map(String.init)
    }

    func locate(preferredURL: URL?) async throws -> OmpLocation {
        var firstUnrunnable: URL?
        for candidate in candidates(preferredURL: preferredURL) {
            try Task.checkCancellation()
            guard FileManager.default.isExecutableFile(atPath: candidate.path) else { continue }
            let installation = try await inspect(candidate)
            try Task.checkCancellation()
            if let installation {
                return .found(installation)
            }
            // Present and executable but silent: remember it so setup can say so
            // rather than claiming nothing is installed.
            if firstUnrunnable == nil { firstUnrunnable = candidate }
        }
        if let firstUnrunnable { return .unrunnable(firstUnrunnable) }
        return .notFound
    }

    private func candidates(preferredURL: URL?) -> [URL] {
        let known = OmpProcessEnvironment
            .resolvedToolDirectories(homeDirectory: homeDirectory)
            .map { $0.appending(path: "omp") }
        let fromPath = pathDirectories
            .filter { $0.hasPrefix("/") }
            .map { URL(filePath: $0).appending(path: "omp") }

        var seen = Set<String>()
        return ([preferredURL].compactMap { $0 } + known + fromPath).compactMap { url in
            let standardized = url.standardizedFileURL
            return seen.insert(standardized.path).inserted ? standardized : nil
        }
    }

    private func inspect(_ candidate: URL) async throws -> OmpInstallation? {
        let data: Data
        do {
            // Deliberately no `-e <extension path>` here. This probe never
            // reaches `session_start` (the extension's only hook) — a plain
            // `--version` invocation isn't an RPC session, so loading the
            // extension would buy nothing. It would only add risk: OMP
            // discovery itself would then depend on the extension parsing
            // correctly, and a broken extension would make the app unable to
            // find `omp` at all (Setup screen) instead of only losing account
            // routing.
            data = try await OmpCommandRunner().run(
                executableURL: candidate,
                arguments: ["--version"])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }

        guard let text = String(data: data, encoding: .utf8),
              let firstLine = text.split(whereSeparator: \Character.isNewline).first
        else { return nil }

        let version = firstLine.trimmingCharacters(in: .whitespaces)
        guard !version.isEmpty else { return nil }
        return OmpInstallation(executableURL: candidate, version: version)
    }

}

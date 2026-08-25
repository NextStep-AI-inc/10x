import Foundation

protocol OmpLocating: Sendable {
    func locate(preferredURL: URL?) async -> OmpInstallation?
}

struct OmpExecutableLocator: OmpLocating {
    static let knownPaths = [
        "~/.bun/bin/omp",
        "/opt/homebrew/bin/omp",
        "/usr/local/bin/omp",
    ]

    private let homeDirectory: URL
    private let pathDirectories: [String]

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        path: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) {
        self.homeDirectory = homeDirectory
        self.pathDirectories = path.split(separator: ":").map(String.init)
    }

    func locate(preferredURL: URL?) async -> OmpInstallation? {
        for candidate in candidates(preferredURL: preferredURL) {
            if let installation = inspect(candidate) {
                return installation
            }
        }
        return nil
    }

    private func candidates(preferredURL: URL?) -> [URL] {
        let known = [
            homeDirectory.appending(path: ".bun/bin/omp"),
            URL(filePath: "/opt/homebrew/bin/omp"),
            URL(filePath: "/usr/local/bin/omp"),
        ]
        let fromPath = pathDirectories
            .filter { $0.hasPrefix("/") }
            .map { URL(filePath: $0).appending(path: "omp") }

        var seen = Set<String>()
        return ([preferredURL].compactMap { $0 } + known + fromPath).compactMap { url in
            let standardized = url.standardizedFileURL
            return seen.insert(standardized.path).inserted ? standardized : nil
        }
    }

    private func inspect(_ candidate: URL) -> OmpInstallation? {
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else { return nil }

        let output = Pipe()
        let process = Process()
        process.executableURL = candidate
        process.arguments = ["--version"]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8),
              let firstLine = text.split(whereSeparator: \Character.isNewline).first
        else { return nil }

        let version = firstLine.trimmingCharacters(in: .whitespaces)
        guard !version.isEmpty else { return nil }
        return OmpInstallation(executableURL: candidate, version: version)
    }

    static func inspectionErrorDescription(for url: URL) -> String {
        "[Setup:OmpExecutableLocator] Unable to inspect OMP — \(url.path)"
    }
}

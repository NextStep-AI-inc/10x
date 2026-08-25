import Foundation

struct SessionHeaderMetadata: Sendable, Equatable {
    let branch: String
    let repo: String
    let worktreePath: String?

    var displayLine: String {
        [branch, repo, worktreePath]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " | ")
    }

    static func resolve(projectURL: URL) async -> SessionHeaderMetadata {
        await Task.detached(priority: .userInitiated) {
            let topLevel = git(["rev-parse", "--show-toplevel"], at: projectURL)
                .map { URL(filePath: $0, directoryHint: .isDirectory).standardizedFileURL }
            let commonDirectory = git(
                ["rev-parse", "--path-format=absolute", "--git-common-dir"],
                at: projectURL)
                .map { URL(filePath: $0, directoryHint: .isDirectory).standardizedFileURL }
            let repositoryRoot = commonDirectory?.lastPathComponent == ".git"
                ? commonDirectory?.deletingLastPathComponent()
                : topLevel

            return SessionHeaderMetadata(
                branch: git(["branch", "--show-current"], at: projectURL) ?? "detached",
                repo: repositoryRoot?.lastPathComponent ?? projectURL.lastPathComponent,
                worktreePath: relativeWorktreePath(topLevel: topLevel, repositoryRoot: repositoryRoot))
        }.value
    }

    private static func relativeWorktreePath(topLevel: URL?, repositoryRoot: URL?) -> String? {
        guard let topLevel, let repositoryRoot, topLevel != repositoryRoot else { return nil }
        let prefix = repositoryRoot.path.hasSuffix("/")
            ? repositoryRoot.path
            : repositoryRoot.path + "/"
        guard topLevel.path.hasPrefix(prefix) else { return topLevel.path }
        return String(topLevel.path.dropFirst(prefix.count))
    }

    private static func git(_ arguments: [String], at projectURL: URL) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", projectURL.path] + arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let value = String(
                decoding: output.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        } catch {
            return nil
        }
    }
}

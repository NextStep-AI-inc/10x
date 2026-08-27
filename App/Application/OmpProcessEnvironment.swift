import Foundation

/// The environment OMP subprocesses are spawned with.
///
/// `omp` ships as a `#!/usr/bin/env bun` script, so spawning it resolves `bun`
/// through PATH. A GUI launch inherits LaunchServices' PATH
/// (`/usr/bin:/bin:/usr/sbin:/sbin`), which contains neither Homebrew nor
/// `~/.bun/bin`, so `env` fails and the app reports OMP as missing even though
/// it is installed. Launching from a terminal masks this: the shell's PATH is
/// inherited and everything resolves.
enum OmpProcessEnvironment {
    /// Where `omp` and its interpreter are installed. Same set the setup screen
    /// lists, so the paths it claims to check are the paths a spawn can reach.
    static let toolDirectories = ["~/.bun/bin", "/opt/homebrew/bin", "/usr/local/bin"]

    /// Appends any missing tool directory to PATH. Appends rather than prepends
    /// so an explicitly configured PATH still wins.
    // ponytail: static directory list, not the login shell's PATH. Reading that
    // means `zsh -ilc 'echo $PATH'`, which sources rc files and can hang on a
    // slow profile. Switch to it only if installs outside these three appear.
    static func resolved(
        base: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: String] {
        var environment = base
        var entries = (base["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
        var seen = Set(entries)

        for directory in toolDirectories.map({ expand($0, homeDirectory: homeDirectory) })
        where seen.insert(directory).inserted {
            entries.append(directory)
        }

        environment["PATH"] = entries.joined(separator: ":")
        return environment
    }

    /// Applies the resolved PATH to this process, so children that inherit the
    /// environment rather than being handed one explicitly — `Process` with a nil
    /// `environment`, which is every spawn in OmpKit — also resolve `bun`.
    /// Call once at launch, before anything spawns.
    static func install() {
        guard let path = resolved()["PATH"] else { return }
        setenv("PATH", path, 1)
    }

    private static func expand(_ directory: String, homeDirectory: URL) -> String {
        guard directory.hasPrefix("~/") else { return directory }
        return homeDirectory
            .appending(path: String(directory.dropFirst(2)))
            .standardizedFileURL
            .path
    }
}

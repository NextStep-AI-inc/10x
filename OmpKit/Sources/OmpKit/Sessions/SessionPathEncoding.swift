import Foundation

/// Maps a working directory to its session bucket directory name.
///
/// Encode-only by design: `/`, `\`, and `:` all collapse to `-`, so a bucket
/// name cannot be turned back into a path. omp itself never decodes — it
/// re-encodes a known cwd and compares. Read a session's real cwd from its
/// header instead.
public enum SessionPathEncoding {
    public static func bucketName(
        forCwd cwd: String,
        home: String = NSHomeDirectory(),
        tmp: String = NSTemporaryDirectory()
    ) -> String {
        // Symlink aliases must resolve to the same bucket as their target.
        let canonicalCwd = canonical(cwd)
        let canonicalHome = canonical(home)
        let canonicalTmp = canonical(tmp)

        if let relative = relativePath(of: canonicalCwd, under: canonicalHome) {
            return encodeRelative(prefix: "-", relative: relative)
        }
        if let relative = relativePath(of: canonicalCwd, under: canonicalTmp) {
            return encodeRelative(prefix: "-tmp", relative: relative)
        }
        let trimmed = canonicalCwd.hasPrefix("/") ? String(canonicalCwd.dropFirst()) : canonicalCwd
        return "--\(replaceSeparators(trimmed))--"
    }

    private static func canonical(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        let resolved = URL(fileURLWithPath: standardized).resolvingSymlinksInPath().path
        // Trailing slashes would produce an empty final component.
        return resolved.count > 1 && resolved.hasSuffix("/")
            ? String(resolved.dropLast()) : resolved
    }

    /// The path of `path` relative to `base`, or nil when it is not underneath.
    private static func relativePath(of path: String, under base: String) -> String? {
        if path == base { return "" }
        let prefix = base.hasSuffix("/") ? base : base + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }

    private static func encodeRelative(prefix: String, relative: String) -> String {
        let encoded = replaceSeparators(relative)
        guard !encoded.isEmpty else { return prefix }
        return prefix.hasSuffix("-") ? "\(prefix)\(encoded)" : "\(prefix)-\(encoded)"
    }

    private static func replaceSeparators(_ value: String) -> String {
        String(value.map { $0 == "/" || $0 == "\\" || $0 == ":" ? "-" : $0 })
    }
}

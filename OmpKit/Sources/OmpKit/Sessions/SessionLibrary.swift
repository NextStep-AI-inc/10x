import Foundation

/// Lists omp's on-disk sessions without spawning anything.
///
/// Reads only a 4 KB head (metadata) and a 32 KB tail (status) per file, and
/// memoizes on `(mtime, size)`. Both must match to reuse an entry: omp rewrites
/// the title slot in place, which changes mtime while leaving size identical.
public actor SessionLibrary {
    public static let prefixBytes = 4096
    public static let suffixBytes = 32_768

    private struct CacheKey: Hashable {
        let path: String
        let mtime: TimeInterval
        let size: Int
    }

    private enum CacheValue {
        case metadata(SessionMetadata)
        case missing
    }

    private let root: URL
    private var cache: [CacheKey: CacheValue] = [:]
    private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    private var watching = false
    private var debounceTask: Task<Void, Never>?

    private let changeStream: AsyncStream<Void>
    private let changeContinuation: AsyncStream<Void>.Continuation

    /// omp writes fractional seconds, which the default options reject.
    /// Actor-isolated: ISO8601DateFormatter is not Sendable.
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(
        root: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".omp/agent/sessions")
    ) {
        self.root = root
        (changeStream, changeContinuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
    }

    deinit {
        debounceTask?.cancel()
        for watcher in watchers.values { watcher.cancel() }
        changeContinuation.finish()
    }

    /// Signals that the session tree changed. Starts watching on first use.
    public nonisolated var changes: AsyncStream<Void> {
        Task { await startWatchingIfNeeded() }
        return changeStream
    }

    /// Every session, newest modification first.
    ///
    /// Scans exactly `<root>/<bucket>/*.jsonl`. Subagent transcripts live one
    /// level deeper and are deliberately not listed, matching omp's own listing.
    public func listAll() -> [SessionMetadata] {
        let fileManager = FileManager.default
        guard let buckets = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ) else { return [] }

        var results: [SessionMetadata] = []
        for bucket in buckets {
            guard (try? bucket.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            guard let files = try? fileManager.contentsOfDirectory(
                at: bucket, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: []
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                if let metadata = scan(file) { results.append(metadata) }
            }
        }
        results.sort { $0.modified > $1.modified }
        return results
    }

    private func scan(_ url: URL) -> SessionMetadata? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? Int
        else { return nil }

        let key = CacheKey(
            path: url.path, mtime: modified.timeIntervalSince1970, size: size)
        if let cached = cache[key] {
            switch cached {
            case .metadata(let metadata): return metadata
            case .missing: return nil
            }
        }

        let metadata = read(url, modified: modified, size: size)
        cache = cache.filter { $0.key.path != url.path }
        cache[key] = metadata.map(CacheValue.metadata) ?? .missing
        if cache.count > 4096 {
            cache.removeValue(forKey: cache.keys.first!)
        }
        return metadata
    }

    private func read(_ url: URL, modified: Date, size: Int) -> SessionMetadata? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let prefix = try? handle.read(upToCount: Self.prefixBytes), !prefix.isEmpty,
              let parsed = try? SessionFileParser.parseHeader(prefix: prefix)
        else { return nil }

        var status: SessionStatus = .unknown
        let tailOffset = max(0, size - Self.suffixBytes)
        if (try? handle.seek(toOffset: UInt64(tailOffset))) != nil,
           let tail = try? handle.readToEnd(), !tail.isEmpty {
            status = SessionStatusClassifier.classify(tail: tail)
        }

        let created = timestampFormatter.date(from: parsed.header.timestamp) ?? modified
        return SessionMetadata(
            path: url.path,
            sessionId: parsed.header.id,
            cwd: parsed.header.cwd,
            title: parsed.header.title,
            created: created,
            modified: modified,
            sizeBytes: size,
            status: status)
    }

    // MARK: - Watching

    private func startWatchingIfNeeded() {
        guard !watching else { return }
        watching = true
        refreshWatchers()
    }

    private func refreshWatchers() {
        let fileManager = FileManager.default
        var desired: [URL] = []
        if fileManager.fileExists(atPath: root.path) { desired.append(root) }
        if let buckets = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            for bucket in buckets where
                (try? bucket.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                desired.append(bucket)
                if let files = try? fileManager.contentsOfDirectory(
                    at: bucket, includingPropertiesForKeys: [.isRegularFileKey], options: []) {
                    desired += files.filter { $0.pathExtension == "jsonl" }
                }
            }
        }

        let desiredPaths = Set(desired.map(\.path))
        for path in watchers.keys where !desiredPaths.contains(path) {
            watchers.removeValue(forKey: path)?.cancel()
        }
        for url in desired where watchers[url.path] == nil { watch(url) }
    }

    private func watch(_ url: URL) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global())
        source.setEventHandler { [weak self] in
            Task { await self?.handleWatchEvent() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watchers[url.path] = source
    }

    private func handleWatchEvent() {
        refreshWatchers()
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return }
            await self?.emitChange()
        }
    }

    private func emitChange() {
        changeContinuation.yield(())
    }
}

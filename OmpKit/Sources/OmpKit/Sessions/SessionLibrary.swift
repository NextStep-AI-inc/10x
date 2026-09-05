import Foundation
import Darwin

public enum SessionMutationFailureReason: Sendable, Equatable {
    case invalidPath
    case missingSource
    case destinationExists
    case fileOperationFailed
}

public struct SessionMutationFailure: Sendable, Equatable {
    public let path: String
    public let reason: SessionMutationFailureReason

    public init(path: String, reason: SessionMutationFailureReason) {
        self.path = path
        self.reason = reason
    }
}

public struct SessionMutationReport: Sendable, Equatable {
    public let succeededPaths: [String]
    public let failures: [SessionMutationFailure]

    public init(succeededPaths: [String], failures: [SessionMutationFailure]) {
        self.succeededPaths = succeededPaths
        self.failures = failures
    }
}

/// Lists omp's on-disk sessions without spawning anything.
///
/// Reads only a 4 KB head (metadata) and a 32 KB tail (status) per file, and
/// memoizes on `(mtime, size)`. Both must match to reuse an entry: omp rewrites
/// the title slot in place, which changes mtime while leaving size identical.
public actor SessionLibrary {
    typealias DirectoryContents = @Sendable (URL, [URLResourceKey]) throws -> [URL]

    public static let prefixBytes = 4096
    public static let suffixBytes = 32_768

    private struct CacheKey: Hashable {
        let path: String
        let mtime: TimeInterval
        let size: Int
    }

    private struct WatchedURL {
        let url: URL
        let isDirectory: Bool
    }

    private enum CacheValue {
        case metadata(SessionMetadata)
        case missing
    }

    private struct ValidatedSessionPath {
        let url: URL
        let relativePath: String
    }

    private enum SessionPathValidation {
        case valid(ValidatedSessionPath)
        case missing
        case invalid
    }

    private enum DestinationValidation {
        case available(URL)
        case exists
        case invalid
    }

    private let root: URL
    private let archiveRoot: URL
    private let unlinkItem: @Sendable (String) -> Int32
    private let watcherContentsOfDirectory: DirectoryContents
    private var cache: [CacheKey: CacheValue] = [:]
    private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    private var watching = false
    private var topologyRefreshPending = false
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
            .appendingPathComponent(".omp/agent/sessions"),
        archiveRoot: URL? = nil
    ) {
        self.init(root: root, archiveRoot: archiveRoot, unlinkItem: { unlink($0) })
    }

    init(
        root: URL,
        archiveRoot: URL?,
        unlinkItem: @escaping @Sendable (String) -> Int32,
        watcherContentsOfDirectory: @escaping DirectoryContents = { url, keys in
            try FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: keys, options: [])
        }
    ) {
        self.root = root.standardizedFileURL
        self.archiveRoot = (archiveRoot ?? root.deletingLastPathComponent()
            .appendingPathComponent("archived-sessions")).standardizedFileURL
        self.unlinkItem = unlinkItem
        self.watcherContentsOfDirectory = watcherContentsOfDirectory
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

    /// Installs the directory watchers before a caller begins relying on
    /// `changes`. Reading `changes` also starts them lazily, but callers that
    /// load state and then hand off to live updates need an awaitable barrier
    /// so a write cannot land between those two steps.
    public func startWatching() {
        startWatchingIfNeeded()
    }

    /// Every session, newest modification first.
    ///
    /// Scans exactly `<root>/<bucket>/*.jsonl`. Subagent transcripts live one
    /// level deeper and are deliberately not listed, matching omp's own listing.
    public func listAll() -> [SessionMetadata] {
        list(in: root)
    }

    public func listArchived() -> [SessionMetadata] {
        list(in: archiveRoot)
    }

    private func list(in collectionRoot: URL) -> [SessionMetadata] {
        let fileManager = FileManager.default
        guard let buckets = try? fileManager.contentsOfDirectory(
            at: collectionRoot, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ) else { return [] }

        var results: [SessionMetadata] = []
        for bucket in buckets {
            guard (try? bucket.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            guard let files = try? fileManager.contentsOfDirectory(
                at: bucket, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: []
            ) else { continue }
            for file in files {
                guard let transcript = listableTranscriptURL(file, under: collectionRoot) else {
                    continue
                }
                if let metadata = scan(transcript) { results.append(metadata) }
            }
        }
        results.sort { $0.modified > $1.modified }
        return results
    }

    public func archive(paths: [String]) -> SessionMutationReport {
        move(paths: paths, from: root, to: archiveRoot)
    }

    public func restore(paths: [String]) -> SessionMutationReport {
        move(paths: paths, from: archiveRoot, to: root)
    }

    public func delete(paths: [String]) -> SessionMutationReport {
        var succeeded: [String] = []
        var failures: [SessionMutationFailure] = []

        for path in paths {
            let validation = validateSessionPathUnderEitherRoot(path)
            guard case .valid(let source) = validation else {
                let reason: SessionMutationFailureReason = switch validation {
                case .missing: .missingSource
                case .invalid, .valid: .invalidPath
                }
                failures.append(SessionMutationFailure(path: path, reason: reason))
                continue
            }
            if unlinkItem(source.url.path) == 0 {
                succeeded.append(path)
                invalidateCache(paths: [source.url.path])
            } else {
                let reason: SessionMutationFailureReason = errno == ENOENT
                    ? .missingSource
                    : .fileOperationFailed
                failures.append(SessionMutationFailure(path: path, reason: reason))
            }
        }
        refreshWatchers()
        emitChange()
        return SessionMutationReport(succeededPaths: succeeded, failures: failures)
    }

    private func validateSessionPathUnderEitherRoot(_ path: String) -> SessionPathValidation {
        let activeValidation = validateSessionPath(path, under: root)
        let archivedValidation = validateSessionPath(path, under: archiveRoot)
        switch (activeValidation, archivedValidation) {
        case (.valid(let source), _), (_, .valid(let source)):
            return .valid(source)
        case (.missing, _), (_, .missing):
            return .missing
        case (.invalid, .invalid):
            return .invalid
        }
    }

    private func move(paths: [String], from sourceRoot: URL, to destinationRoot: URL)
        -> SessionMutationReport {
        var succeeded: [String] = []
        var failures: [SessionMutationFailure] = []
        let fileManager = FileManager.default

        for path in paths {
            let sourceValidation = validateSessionPath(path, under: sourceRoot)
            guard case .valid(let source) = sourceValidation else {
                let reason: SessionMutationFailureReason = switch sourceValidation {
                case .missing: .missingSource
                case .invalid, .valid: .invalidPath
                }
                failures.append(SessionMutationFailure(path: path, reason: reason))
                continue
            }
            let destinationValidation = validateDestination(
                relativePath: source.relativePath,
                under: destinationRoot)
            guard case .available(let destination) = destinationValidation else {
                let reason: SessionMutationFailureReason = switch destinationValidation {
                case .exists: .destinationExists
                case .invalid, .available: .invalidPath
                }
                failures.append(SessionMutationFailure(path: path, reason: reason))
                continue
            }
            do {
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try fileManager.moveItem(at: source.url, to: destination)
                succeeded.append(path)
                invalidateCache(paths: [source.url.path, destination.path])
            } catch {
                failures.append(SessionMutationFailure(path: path, reason: .fileOperationFailed))
            }
        }
        refreshWatchers()
        emitChange()
        return SessionMutationReport(succeededPaths: succeeded, failures: failures)
    }

    private func validateSessionPath(
        _ path: String,
        under collectionRoot: URL
    ) -> SessionPathValidation {
        let lexicalRoot = collectionRoot.standardizedFileURL
        let candidate = URL(filePath: path).standardizedFileURL
        let rootComponents = lexicalRoot.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidate.pathExtension == "jsonl",
              candidateComponents.starts(with: rootComponents),
              candidateComponents.count == rootComponents.count + 2
        else { return .invalid }

        let fileKeys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let fileValues = try? candidate.resourceValues(forKeys: fileKeys) else {
            return .missing
        }
        guard fileValues.isRegularFile == true, fileValues.isSymbolicLink != true else {
            return .invalid
        }

        let bucket = candidate.deletingLastPathComponent()
        let bucketKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let bucketValues = try? bucket.resourceValues(forKeys: bucketKeys),
              bucketValues.isDirectory == true,
              bucketValues.isSymbolicLink != true
        else { return .invalid }

        let resolvedRoot = lexicalRoot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRootComponents = resolvedRoot.pathComponents
        let resolvedCandidateComponents = resolvedCandidate.pathComponents
        guard resolvedCandidateComponents.starts(with: resolvedRootComponents),
              resolvedCandidateComponents.count == resolvedRootComponents.count + 2
        else { return .invalid }

        let relativePath = resolvedCandidateComponents
            .dropFirst(resolvedRootComponents.count)
            .joined(separator: "/")
        return .valid(ValidatedSessionPath(
            url: resolvedCandidate,
            relativePath: relativePath))
    }

    private func validateDestination(
        relativePath: String,
        under collectionRoot: URL
    ) -> DestinationValidation {
        let resolvedRoot = collectionRoot.resolvingSymlinksInPath().standardizedFileURL
        let destination = resolvedRoot.appending(path: relativePath).standardizedFileURL
        let rootComponents = resolvedRoot.pathComponents
        let destinationComponents = destination.pathComponents
        guard destination.pathExtension == "jsonl",
              destinationComponents.starts(with: rootComponents),
              destinationComponents.count == rootComponents.count + 2
        else { return .invalid }

        if (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey])) != nil {
            return .exists
        }

        let bucket = destination.deletingLastPathComponent()
        if let bucketValues = try? bucket.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ), bucketValues.isDirectory != true || bucketValues.isSymbolicLink == true {
            return .invalid
        }
        let resolvedBucket = bucket.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedBucket.pathComponents.starts(with: rootComponents),
              resolvedBucket.pathComponents.count == rootComponents.count + 1
        else { return .invalid }
        return .available(destination)
    }

    private func listableTranscriptURL(_ url: URL, under collectionRoot: URL) -> URL? {
        guard case .valid(let transcript) = validateSessionPath(url.path, under: collectionRoot)
        else { return nil }
        return transcript.url
    }

    private func invalidateCache(paths: [String]) {
        let changedPaths = Set(paths)
        cache = cache.filter { !changedPaths.contains($0.key.path) }
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
        // A cancelled caller learned nothing about the file; caching `.missing`
        // for it would hide the session from every later listing.
        guard metadata != nil || !Task.isCancelled else { return nil }
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
        let desired = [root, archiveRoot].flatMap(watchedURLs)
        let desiredPaths = Set(desired.map(\.url.path))
        for path in watchers.keys where !desiredPaths.contains(path) {
            watchers.removeValue(forKey: path)?.cancel()
        }
        for target in desired where watchers[target.url.path] == nil { watch(target) }
    }

    private func watchedURLs(in collectionRoot: URL) -> [WatchedURL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: collectionRoot.path) else { return [] }
        var desired = [WatchedURL(url: collectionRoot, isDirectory: true)]
        guard let buckets = try? watcherContentsOfDirectory(
            collectionRoot, [.isDirectoryKey])
        else { return desired }
        for bucket in buckets where
            (try? bucket.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            desired.append(WatchedURL(url: bucket, isDirectory: true))
            if let files = try? watcherContentsOfDirectory(
                bucket, [.isRegularFileKey]) {
                desired += files.compactMap { file in
                    listableTranscriptURL(file, under: collectionRoot).map {
                        WatchedURL(url: $0, isDirectory: false)
                    }
                }
            }
        }
        return desired
    }

    private func watch(_ target: WatchedURL) {
        let descriptor = open(target.url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global())
        source.setEventHandler { [weak self] in
            // Resolve the weak reference before creating the Task rather than
            // optional-chaining inside it. `self?` in the Task body keeps the weak
            // binding inside the region the isolation checker is tracking, which
            // Swift 6.2 rejects as a sending violation; a resolved actor reference is
            // plainly Sendable. Also means a live event cannot spawn a Task that finds
            // the library already gone.
            guard let self else { return }
            let event = source.data
            let isStructural = !event.intersection([.rename, .delete]).isEmpty
            let requiresTopologyRefresh = target.isDirectory || isStructural
            let staleFilePath = !target.isDirectory && isStructural ? target.url.path : nil
            Task { await self.handleWatchEvent(
                requiresTopologyRefresh: requiresTopologyRefresh,
                staleFilePath: staleFilePath) }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watchers[target.url.path] = source
    }

    private func handleWatchEvent(requiresTopologyRefresh: Bool, staleFilePath: String? = nil) {
        if let staleFilePath {
            // The descriptor follows the old inode. Drop it now, so a file
            // recreated before the deferred refresh runs is reopened rather
            // than watched through a descriptor that will never fire again.
            watchers.removeValue(forKey: staleFilePath)?.cancel()
        }
        topologyRefreshPending = topologyRefreshPending || requiresTopologyRefresh
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return }
            await self?.flushWatchEvents()
        }
    }

    private func flushWatchEvents() {
        if topologyRefreshPending {
            topologyRefreshPending = false
            refreshWatchers()
        }
        emitChange()
    }

    private func emitChange() {
        changeContinuation.yield(())
    }
}

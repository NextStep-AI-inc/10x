import Foundation
import OmpKit
import Darwin

actor SessionTimelineLoader {
    typealias DataReader = @Sendable (URL) async throws -> Data

    private struct SourceFingerprint: Equatable, Sendable {
        let path: String
        let modificationSeconds: Int64
        let modificationNanoseconds: Int64
        let size: UInt64
        let systemNumber: UInt64
        let fileNumber: UInt64
    }

    private struct Cache: Sendable {
        let fingerprint: SourceFingerprint
        let history: TranscriptHistory
    }

    private let readData: DataReader
    private var cache: Cache?

    init(readData: @escaping DataReader = { try Data(contentsOf: $0) }) {
        self.readData = readData
    }

    func load(path: String) async throws -> TranscriptHistory? {
        try Task.checkCancellation()
        let url = URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let before = try fingerprint(for: url)
        if cache?.fingerprint == before { return cache?.history }

        let file = try SessionFileParser.parse(data: try await readData(url))
        let history = try TranscriptHistoryMapper.mapCancellable(
            header: file.header,
            path: SessionTree.cancellableActivePath(of: file))
        try Task.checkCancellation()

        if let after = try? fingerprint(for: url), after == before {
            cache = Cache(fingerprint: before, history: history)
        } else {
            cache = nil
        }
        return history
    }

    private func fingerprint(for url: URL) throws -> SourceFingerprint {
        var status = stat()
        guard lstat(url.path, &status) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return SourceFingerprint(
            path: url.path,
            modificationSeconds: Int64(status.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(status.st_mtimespec.tv_nsec),
            size: UInt64(status.st_size),
            systemNumber: UInt64(status.st_dev),
            fileNumber: UInt64(status.st_ino))
    }
}

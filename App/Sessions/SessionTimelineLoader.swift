import CryptoKit
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
    private let imageBlobResolver: SessionImageBlobResolver
    private var cache: Cache?

    init(
        blobDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".omp", directoryHint: .isDirectory)
            .appending(path: "agent", directoryHint: .isDirectory)
            .appending(path: "blobs", directoryHint: .isDirectory),
        readData: @escaping DataReader = { try Data(contentsOf: $0) }
    ) {
        imageBlobResolver = SessionImageBlobResolver(directory: blobDirectory)
        self.readData = readData
    }

    func load(path: String) async throws -> TranscriptHistory? {
        try Task.checkCancellation()
        let url = URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let before = try fingerprint(for: url)
        if cache?.fingerprint == before { return cache?.history }

        let file = try SessionFileParser.parse(data: try await readData(url))
        let resolved = try imageBlobResolver.resolve(
            entries: SessionTree.cancellableActivePath(of: file))
        let history = try TranscriptHistoryMapper.mapCancellable(
            header: file.header,
            path: resolved.entries)
        try Task.checkCancellation()

        if !resolved.hasUnresolvedReference,
           let after = try? fingerprint(for: url), after == before {
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

private struct SessionImageBlobResolver: Sendable {
    struct Result: Sendable {
        let entries: [SessionEntry]
        let hasUnresolvedReference: Bool
    }

    private static let referencePrefix = "blob:sha256:"
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func resolve(entries: [SessionEntry]) throws -> Result {
        var hasUnresolvedReference = false
        let resolved = try entries.enumerated().map { index, entry in
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            guard case .message(let base, .object(var message)) = entry,
                  case .array(let content) = message["content"]
            else { return entry }

            message["content"] = .array(try content.map { block in
                guard case .object(var object) = block,
                      object["type"]?.stringValue?.lowercased() == "image",
                      let reference = object["data"]?.stringValue,
                      let hash = blobHash(from: reference)
                else { return block }
                try Task.checkCancellation()
                guard let data = verifiedBlob(hash: hash) else {
                    hasUnresolvedReference = true
                    return block
                }
                object["data"] = .string(data.base64EncodedString())
                return .object(object)
            })
            return .message(base: base, message: .object(message))
        }
        try Task.checkCancellation()
        return Result(
            entries: resolved,
            hasUnresolvedReference: hasUnresolvedReference)
    }

    private func blobHash(from reference: String) -> String? {
        guard reference.hasPrefix(Self.referencePrefix) else { return nil }
        let hash = String(reference.dropFirst(Self.referencePrefix.count))
        guard hash.utf8.count == 64,
              hash.utf8.allSatisfy({ byte in
                  (0x30...0x39).contains(byte) || (0x61...0x66).contains(byte)
              })
        else { return nil }
        return hash
    }

    private func verifiedBlob(hash: String) -> Data? {
        let url = directory.appending(path: hash)
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG
        else { return nil }

        let data: Data
        do {
            data = try FileHandle(
                fileDescriptor: descriptor,
                closeOnDealloc: false).readToEnd() ?? Data()
        } catch {
            return nil
        }
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return digest == hash ? data : nil
    }
}

import Foundation
import OmpKit

protocol SessionSearching: Sendable {
    func search(query: String, sessions: [SessionMetadata]) async -> [SearchResult]
}

actor SessionSearchService: SessionSearching {
    typealias DataLoader = @Sendable (URL) throws -> Data

    private let databaseURL: URL
    private let loadData: DataLoader
    private var database: SessionSearchDatabase?

    init(
        databaseURL: URL? = nil,
        loadData: @escaping DataLoader = { try Data(contentsOf: $0) }
    ) {
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL()
        self.loadData = loadData
    }

    func search(query: String, sessions: [SessionMetadata]) async -> [SearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let normalizedQuery = SessionSearchDocumentBuilder.normalize(query)

        do {
            return try indexedSearch(normalizedQuery: normalizedQuery, sessions: sessions)
        } catch is CancellationError {
            return []
        } catch let error as SessionSearchDatabaseError {
            guard error.canResetDerivedIndex else {
                logUnavailable(error)
                return []
            }
            do {
                try resetDerivedIndex()
                return try indexedSearch(normalizedQuery: normalizedQuery, sessions: sessions)
            } catch is CancellationError {
                return []
            } catch let retryError as SessionSearchDatabaseError {
                logUnavailable(retryError)
                return []
            } catch {
                logUnavailable(SessionSearchDatabaseError(
                    operation: "rebuild",
                    message: error.localizedDescription))
                return []
            }
        } catch {
            logUnavailable(SessionSearchDatabaseError(
                operation: "search",
                message: error.localizedDescription))
            return []
        }
    }

    private func indexedSearch(
        normalizedQuery: String,
        sessions: [SessionMetadata]
    ) throws -> [SearchResult] {
        try Task.checkCancellation()
        let database = try openDatabaseIfNeeded()
        try synchronize(sessions, in: database)
        try Task.checkCancellation()
        return try database.search(normalizedQuery: normalizedQuery, limit: 200)
    }

    private func synchronize(
        _ sessions: [SessionMetadata],
        in database: SessionSearchDatabase
    ) throws {
        var indexedFingerprints = try database.fingerprints()
        let currentPaths = Set(sessions.map(\.path))
        let removedPaths = Set(indexedFingerprints.keys).subtracting(currentPaths)
        try database.remove(sessionPaths: removedPaths)
        for path in removedPaths {
            indexedFingerprints.removeValue(forKey: path)
        }

        for metadata in sessions {
            try Task.checkCancellation()
            let fingerprint = SessionSearchFingerprint(
                path: metadata.path,
                modified: metadata.modified.timeIntervalSince1970,
                sizeBytes: metadata.sizeBytes)
            guard indexedFingerprints[metadata.path] != fingerprint else { continue }
            guard let documents = try documentsForStableSource(
                metadata: metadata,
                fingerprint: fingerprint)
            else { continue }

            try Task.checkCancellation()
            try database.replace(fingerprint: fingerprint, documents: documents)
            indexedFingerprints[metadata.path] = fingerprint
        }
    }

    private func documentsForStableSource(
        metadata: SessionMetadata,
        fingerprint: SessionSearchFingerprint
    ) throws -> [SessionSearchDocument]? {
        do {
            try Task.checkCancellation()
            let sourceURL = URL(filePath: metadata.path)
            let data = try loadData(sourceURL)
            try Task.checkCancellation()
            let parsed = try SessionFileParser.parse(data: data)
            let documents = try SessionSearchDocumentBuilder.documents(
                metadata: metadata,
                parsed: parsed)
            let values = try sourceURL.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard values.contentModificationDate?.timeIntervalSince1970 == fingerprint.modified,
                  values.fileSize == fingerprint.sizeBytes
            else { return nil }
            return documents
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private func openDatabaseIfNeeded() throws -> SessionSearchDatabase {
        if let database { return database }
        let database = try SessionSearchDatabase(url: databaseURL)
        self.database = database
        return database
    }

    private func resetDerivedIndex() throws {
        database = nil
        let fileManager = FileManager.default
        let derivedURLs = [
            databaseURL,
            URL(filePath: databaseURL.path + "-wal"),
            URL(filePath: databaseURL.path + "-shm"),
        ]
        for url in derivedURLs where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw SessionSearchDatabaseError(
                    operation: "reset",
                    message: error.localizedDescription)
            }
        }
    }

    private func logUnavailable(_ error: SessionSearchDatabaseError) {
        let message = Self.sanitized(error.message)
        let line = "[SearchIndex:\(error.operation)] Search index unavailable — \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private static func sanitized(_ message: String) -> String {
        let sanitizedScalars = message.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }.joined()
        let compact = sanitizedScalars
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return compact.isEmpty ? "Unknown database error" : String(compact.prefix(500))
    }

    private static func defaultDatabaseURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return applicationSupport
            .appending(path: "10x", directoryHint: .isDirectory)
            .appending(path: "SearchIndex-v2.sqlite")
    }
}

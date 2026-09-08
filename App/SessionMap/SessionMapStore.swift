import CryptoKit
import Foundation

struct SessionMapCaughtUpGraph: Codable, Equatable, Sendable {
    let nodeFingerprints: [String: String]
    let edgeFingerprints: [String: String]
}

enum SessionMapCheckOutcome: String, Codable, Equatable, Sendable {
    case off, skipped, passed, failed, rewrittenUnchecked, unavailable
}

struct SessionMapRecord: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let xml: String
    let cacheKey: String
    let generatedThrough: SessionMapCursor
    let sourceManifest: [String: String]
    let caughtUpAt: Date?
    let caughtUpCursor: SessionMapCursor?
    let caughtUpGraph: SessionMapCaughtUpGraph?
    let firstSeenOrder: [String]
    let updatedAt: Date
    let writerConfiguration: SessionMapResolvedModel
    let checkerConfiguration: SessionMapResolvedModel?
    let checkOutcome: SessionMapCheckOutcome
    let dismissedThrough: SessionMapCursor?

    var sourceFingerprintManifest: [String: String] { sourceManifest }

    init(
        xml: String,
        cacheKey: String,
        generatedThrough: SessionMapCursor,
        sourceManifest: [String: String],
        caughtUpAt: Date?,
        caughtUpCursor: SessionMapCursor?,
        caughtUpGraph: SessionMapCaughtUpGraph?,
        firstSeenOrder: [String],
        updatedAt: Date,
        writerConfiguration: SessionMapResolvedModel,
        checkerConfiguration: SessionMapResolvedModel?,
        checkOutcome: SessionMapCheckOutcome,
        dismissedThrough: SessionMapCursor?
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.xml = xml
        self.cacheKey = cacheKey
        self.generatedThrough = generatedThrough
        self.sourceManifest = sourceManifest
        self.caughtUpAt = caughtUpAt
        self.caughtUpCursor = caughtUpCursor
        self.caughtUpGraph = caughtUpGraph
        self.firstSeenOrder = firstSeenOrder
        self.updatedAt = updatedAt
        self.writerConfiguration = writerConfiguration
        self.checkerConfiguration = checkerConfiguration
        self.checkOutcome = checkOutcome
        self.dismissedThrough = dismissedThrough
    }
}

actor SessionMapStore {
    typealias AtomicWrite = @Sendable (Data, URL) throws -> Void

    private let directory: URL
    private let atomicWrite: AtomicWrite
    private let fileManager: FileManager

    init(
        directory: URL,
        fileManager: FileManager = .default,
        atomicWrite: @escaping AtomicWrite = { data, destination in
            try data.write(to: destination, options: .atomic)
        }
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.atomicWrite = atomicWrite
    }

    func load(sessionKey: String) throws -> SessionMapRecord? {
        let destination = recordURL(sessionKey: sessionKey)
        guard fileManager.fileExists(atPath: destination.path) else { return nil }
        let data = try Data(contentsOf: destination)
        guard let record = try? JSONDecoder().decode(SessionMapRecord.self, from: data),
              record.schemaVersion == SessionMapRecord.currentSchemaVersion,
              isValidXML(record)
        else { return nil }
        return record
    }

    func save(_ record: SessionMapRecord, sessionKey: String) throws {
        guard record.schemaVersion == SessionMapRecord.currentSchemaVersion,
              isValidXML(record)
        else { throw SessionMapStoreError.invalidRecord }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try atomicWrite(JSONEncoder().encode(record), recordURL(sessionKey: sessionKey))
    }

    func remove(sessionKey: String) throws {
        let destination = recordURL(sessionKey: sessionKey)
        guard fileManager.fileExists(atPath: destination.path) else { return }
        try fileManager.removeItem(at: destination)
    }

    func migrate(from temporarySessionKey: String, to canonicalSessionKey: String) throws {
        guard temporarySessionKey.hasPrefix("new:") else {
            throw SessionMapStoreError.invalidTemporaryKey
        }
        let source = recordURL(sessionKey: temporarySessionKey)
        guard fileManager.fileExists(atPath: source.path) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = recordURL(sessionKey: canonicalSessionKey)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: source)
        } else {
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    private func recordURL(sessionKey: String) -> URL {
        let key = SHA256.hash(data: Data(sessionKey.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key).appendingPathExtension("json")
    }

    private func isValidXML(_ record: SessionMapRecord) -> Bool {
        let validation = SessionMapDocumentParser.parse(
            Data(record.xml.utf8),
            context: SessionMapValidationContext(
                knownRefs: Set(record.sourceManifest.keys),
                facts: [:],
                previous: nil,
                projectURL: nil))
        return validation.document != nil && validation.fatal.isEmpty
    }
}

enum SessionMapStoreError: Error {
    case invalidRecord
    case invalidTemporaryKey
}

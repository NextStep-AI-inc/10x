import CryptoKit
import Foundation
import Testing
@testable import TenXApp

@Test func sessionMapStoreIsolatesSessionsAndKeepsLastGoodRecord() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "TenXAppTests.SessionMapStore.\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SessionMapStore(directory: directory)
    let first = record(cacheKey: "first")
    let second = record(cacheKey: "second")

    try await store.save(first, sessionKey: "one")
    try await store.save(second, sessionKey: "two")
    #expect(try await store.load(sessionKey: "one")?.cacheKey == "first")
    #expect(try await store.load(sessionKey: "two")?.cacheKey == "second")

    let invalid = record(cacheKey: "invalid", xml: "<sessionmap>")
    await #expect(throws: (any Error).self) {
        try await store.save(invalid, sessionKey: "one")
    }
    #expect(try await store.load(sessionKey: "one")?.cacheKey == "first")
}

@Test func sessionMapStoreTreatsCorruptJSONAsMissing() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "TenXAppTests.SessionMapStore.Corrupt.\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SessionMapStore(directory: directory)
    try await store.save(record(cacheKey: "good"), sessionKey: "session")
    let url = recordURL(directory: directory, sessionKey: "session")
    try Data("not json".utf8).write(to: url)
    #expect(try await store.load(sessionKey: "session") == nil)
}

@Test func sessionMapStoreTreatsUnsupportedSchemaVersionAsMissing() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "TenXAppTests.SessionMapStore.Schema.\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SessionMapStore(directory: directory)
    try await store.save(record(cacheKey: "good"), sessionKey: "session")
    let url = recordURL(directory: directory, sessionKey: "session")
    let json = try #require(String(data: Data(contentsOf: url), encoding: .utf8))
    let unsupported = json.replacingOccurrences(
        of: "\"schemaVersion\":1",
        with: "\"schemaVersion\":2")
    #expect(unsupported != json)
    try Data(unsupported.utf8).write(to: url)

    #expect(try await store.load(sessionKey: "session") == nil)
}

@Test func sessionMapStoreAtomicWriteFailureKeepsLastGoodRecord() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "TenXAppTests.SessionMapStore.Atomic.\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SessionMapStore(directory: directory) { data, destination in
        let decoded = try JSONDecoder().decode(SessionMapRecord.self, from: data)
        if decoded.cacheKey == "failure" { throw SessionMapStoreTestError.writeFailed }
        try data.write(to: destination, options: .atomic)
    }
    try await store.save(record(cacheKey: "good"), sessionKey: "session")

    await #expect(throws: SessionMapStoreTestError.self) {
        try await store.save(record(cacheKey: "failure"), sessionKey: "session")
    }

    #expect(try await store.load(sessionKey: "session")?.cacheKey == "good")
}

@Test func sessionMapStoreMigratesTemporaryKeyToEmptyCanonicalKey() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "TenXAppTests.SessionMapStore.Migrate.\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SessionMapStore(directory: directory)
    try await store.save(record(cacheKey: "temporary"), sessionKey: "new:ABC")
    try await store.migrate(from: "new:ABC", to: "/sessions/one.jsonl")

    #expect(try await store.load(sessionKey: "new:ABC") == nil)
    #expect(try await store.load(sessionKey: "/sessions/one.jsonl")?.cacheKey == "temporary")
}

@Test func sessionMapStoreMigrationKeepsExistingCanonicalRecord() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "TenXAppTests.SessionMapStore.MigrateExisting.\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SessionMapStore(directory: directory)
    try await store.save(record(cacheKey: "temporary"), sessionKey: "new:ABC")
    try await store.save(record(cacheKey: "canonical"), sessionKey: "/sessions/one.jsonl")
    try await store.migrate(from: "new:ABC", to: "/sessions/one.jsonl")

    #expect(try await store.load(sessionKey: "new:ABC") == nil)
    #expect(try await store.load(sessionKey: "/sessions/one.jsonl")?.cacheKey == "canonical")
}

private func record(
    cacheKey: String,
    xml: String = "<sessionmap headline=\"Stored\" phase=\"planning\"><summary>Stored.</summary></sessionmap>"
) -> SessionMapRecord {
    SessionMapRecord(
        xml: xml,
        cacheKey: cacheKey,
        generatedThrough: SessionMapCursor(lineage: "lineage", entryID: "entry"),
        sourceManifest: ["entry": "fingerprint"],
        caughtUpAt: nil,
        caughtUpCursor: nil,
        caughtUpGraph: nil,
        firstSeenOrder: ["node"],
        updatedAt: Date(timeIntervalSince1970: 100),
        writerConfiguration: SessionMapResolvedModel(
            provider: "provider", modelID: "writer", effort: nil, acceptsImages: false),
        checkerConfiguration: nil,
        checkOutcome: .off,
        dismissedThrough: nil)
}

private enum SessionMapStoreTestError: Error {
    case writeFailed
}

private func recordURL(directory: URL, sessionKey: String) -> URL {
    let key = SHA256.hash(data: Data(sessionKey.utf8))
        .map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(key).appendingPathExtension("json")
}

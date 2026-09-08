import Darwin
import Foundation
import Testing
@testable import TenXApp

@Test func sessionSearchDatabaseMatchesStoredMetadata() throws {
    try withTemporarySearchDatabase { database in
        let sessionPath = "/tmp/Prime Radiant/Session With Spaces.jsonl"
        let fingerprint = SessionSearchFingerprint(
            path: sessionPath,
            modified: 1_787_601_600,
            sizeBytes: 4_096)
        let documents = [
            searchDocument(
                sessionPath: sessionPath,
                projectPath: "/tmp/Prime Radiant",
                title: "Migration work",
                excerpt: "/tmp/Prime Radiant",
                kind: .session,
                normalizedText: "migration work /tmp/prime radiant session with spaces.jsonl",
                modified: fingerprint.modified,
                order: 0),
            searchDocument(
                sessionPath: sessionPath,
                entryID: "message-1",
                projectPath: "/tmp/Prime Radiant",
                title: "You",
                excerpt: "Summarize the release notes",
                kind: .message,
                normalizedText: "user text summarize the release notes",
                modified: fingerprint.modified,
                order: 1),
            searchDocument(
                sessionPath: sessionPath,
                entryID: "tool-1",
                projectPath: "/tmp/Prime Radiant",
                title: "read",
                excerpt: "read /tmp/README.md",
                kind: .tool,
                normalizedText: "toolcall read absolutepath /tmp/readme.md",
                modified: fingerprint.modified,
                order: 2),
        ]

        try database.replace(fingerprint: fingerprint, documents: documents)

        #expect(try database.fingerprints() == [sessionPath: fingerprint])
        #expect(try database.search(normalizedQuery: "prime radiant", limit: 200) == [
            SearchResult(
                sessionPath: sessionPath,
                entryID: nil,
                projectPath: "/tmp/Prime Radiant",
                title: "Migration work",
                excerpt: "/tmp/Prime Radiant",
                kind: .session),
        ])
        #expect(try database.search(normalizedQuery: "release notes", limit: 200).map(\.entryID) == [
            "message-1",
        ])
        #expect(try database.search(normalizedQuery: "absolutepath", limit: 200).map(\.entryID) == [
            "tool-1",
        ])
        #expect(try database.search(normalizedQuery: "/tmp/readme.md", limit: 200).map(\.entryID) == [
            "tool-1",
        ])
    }
}

@Test func sessionSearchDatabaseSupportsCaseDiacriticsSubstringsAndShortQueries() throws {
    try withTemporarySearchDatabase { database in
        let fingerprint = SessionSearchFingerprint(path: "/tmp/accent.jsonl", modified: 20, sizeBytes: 200)
        try database.replace(
            fingerprint: fingerprint,
            documents: [
                searchDocument(
                    sessionPath: fingerprint.path,
                    entryID: "accent",
                    normalizedText: "Prepared the résumé draft inside foxtrot foobar",
                    modified: fingerprint.modified),
            ])

        #expect(try database.search(normalizedQuery: "RESUME", limit: 200).map(\.entryID) == ["accent"])
        #expect(try database.search(normalizedQuery: "obar", limit: 200).map(\.entryID) == ["accent"])
        #expect(try database.search(normalizedQuery: "x", limit: 200).map(\.entryID) == ["accent"])
        #expect(try database.search(normalizedQuery: "ox", limit: 200).map(\.entryID) == ["accent"])
    }
}

@Test func sessionSearchDatabaseBindsQuotesAndPunctuationSafely() throws {
    try withTemporarySearchDatabase { database in
        let fingerprint = SessionSearchFingerprint(path: "/tmp/punctuation.jsonl", modified: 30, sizeBytes: 300)
        try database.replace(
            fingerprint: fingerprint,
            documents: [
                searchDocument(
                    sessionPath: fingerprint.path,
                    entryID: "punctuation",
                    normalizedText: "The user said \"ship-it\" with C++ from /tmp/a,b?.swift",
                    modified: fingerprint.modified),
            ])

        #expect(try database.search(normalizedQuery: "said \"ship-it\"", limit: 200).map(\.entryID) == [
            "punctuation",
        ])
        #expect(try database.search(normalizedQuery: "C++", limit: 200).map(\.entryID) == ["punctuation"])
        #expect(try database.search(normalizedQuery: "/tmp/a,b?", limit: 200).map(\.entryID) == [
            "punctuation",
        ])
        #expect(try database.search(normalizedQuery: "\" OR search_document MATCH \"*", limit: 200).isEmpty)
    }
}

@Test func sessionSearchDatabaseReplacesAndDeletesSessions() throws {
    try withTemporarySearchDatabase { database in
        let firstPath = "/tmp/first.jsonl"
        let secondPath = "/tmp/second.jsonl"
        try database.replace(
            fingerprint: SessionSearchFingerprint(path: firstPath, modified: 100, sizeBytes: 100),
            documents: [
                searchDocument(
                    sessionPath: firstPath,
                    entryID: "old",
                    normalizedText: "obsolete marker",
                    modified: 100),
            ])
        try database.replace(
            fingerprint: SessionSearchFingerprint(path: secondPath, modified: 300, sizeBytes: 300),
            documents: (0..<3).map { order in
                searchDocument(
                    sessionPath: secondPath,
                    entryID: "second-\(order)",
                    normalizedText: "common ordering token other-session",
                    modified: 300,
                    order: order)
            })

        let replacementFingerprint = SessionSearchFingerprint(path: firstPath, modified: 400, sizeBytes: 400)
        try database.replace(
            fingerprint: replacementFingerprint,
            documents: (0..<198).map { order in
                searchDocument(
                    sessionPath: firstPath,
                    entryID: "first-\(order)",
                    normalizedText: "common ordering token replacement",
                    modified: replacementFingerprint.modified,
                    order: order)
            })

        #expect(try database.search(normalizedQuery: "obsolete", limit: 200).isEmpty)
        #expect(try database.search(normalizedQuery: "other-session", limit: 200).count == 3)
        let ordered = try database.search(normalizedQuery: "common ordering token", limit: 200)
        #expect(ordered.count == 200)
        #expect(ordered.prefix(198).map(\.entryID) == (0..<198).map { "first-\($0)" })
        #expect(ordered.suffix(2).map(\.entryID) == ["second-0", "second-1"])
        #expect(try database.fingerprints()[firstPath] == replacementFingerprint)

        try database.remove(sessionPaths: [firstPath])

        #expect(try database.fingerprints() == [
            secondPath: SessionSearchFingerprint(path: secondPath, modified: 300, sizeBytes: 300),
        ])
        #expect(try database.search(normalizedQuery: "replacement", limit: 200).isEmpty)
        #expect(try database.search(normalizedQuery: "common ordering token", limit: 200).map(\.entryID) == [
            "second-0", "second-1", "second-2",
        ])
    }
}

@Test func sessionSearchDatabaseHardensWALFiles() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "tenx-search-database-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appending(path: "SearchIndex-v1.sqlite")
    let database = try SessionSearchDatabase(url: databaseURL)
    let fingerprint = SessionSearchFingerprint(path: "/tmp/privacy.jsonl", modified: 10, sizeBytes: 20)
    try database.replace(
        fingerprint: fingerprint,
        documents: [
            searchDocument(
                sessionPath: fingerprint.path,
                entryID: "privacy",
                normalizedText: "private transcript",
                modified: fingerprint.modified),
        ])

    let writeAheadLogURL = URL(filePath: databaseURL.path + "-wal")
    let sharedMemoryURL = URL(filePath: databaseURL.path + "-shm")
    #expect(FileManager.default.fileExists(atPath: writeAheadLogURL.path))
    #expect(FileManager.default.fileExists(atPath: sharedMemoryURL.path))
    #expect(try permissions(at: directory) == 0o700)
    for indexURL in [databaseURL, writeAheadLogURL, sharedMemoryURL]
        where FileManager.default.fileExists(atPath: indexURL.path)
    {
        #expect(try permissions(at: indexURL) == 0o600)
        let values = try indexURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }
    #expect(try database.fingerprints()[fingerprint.path] == fingerprint)
}

private func withTemporarySearchDatabase(_ body: (SessionSearchDatabase) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "tenx-search-database-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = try SessionSearchDatabase(url: directory.appending(path: "SearchIndex-v1.sqlite"))
    try body(database)
}

private func searchDocument(
    sessionPath: String,
    entryID: String? = nil,
    projectPath: String = "/tmp/project",
    title: String = "Result",
    excerpt: String = "Result excerpt",
    kind: SearchResultKind = .message,
    normalizedText: String,
    modified: TimeInterval,
    order: Int = 0
) -> SessionSearchDocument {
    SessionSearchDocument(
        sessionPath: sessionPath,
        entryID: entryID,
        projectPath: projectPath,
        title: title,
        excerpt: excerpt,
        kind: kind,
        sessionModified: modified,
        entryOrder: order,
        normalizedText: normalizedText)
}

private func permissions(at url: URL) throws -> mode_t {
    var information = stat()
    guard url.path.withCString({ lstat($0, &information) }) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return information.st_mode & mode_t(0o777)
}

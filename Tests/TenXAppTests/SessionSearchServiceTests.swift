import Foundation
import OmpKit
import Synchronization
import Testing
@testable import TenXApp

@Test func searchFindsSessionMessagesAndToolArguments() async throws {
    let directory = try makeSearchTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sessionURL = directory.appending(path: "session.jsonl")
    let fixture = completeSearchFixture(
        sessionID: "session-1",
        title: "Migration work",
        messageID: "user-1",
        messageText: "Summarize the release notes",
        toolID: "tool-1")
    let metadata = try writeSession(fixture, to: sessionURL, title: "Migration work")
    let service = SessionSearchService(
        databaseURL: directory.appending(path: "SearchIndex-v1.sqlite"))

    let sessionResults = await service.search(query: "migration", sessions: [metadata])
    #expect(sessionResults.map(\.kind) == [.session])

    let messageResults = await service.search(query: "release notes", sessions: [metadata])
    #expect(messageResults.map(\.kind) == [.message])
    #expect(messageResults.first?.entryID == "user-1")
    #expect(messageResults.first?.excerpt == "Summarize the release notes")

    let toolResults = await service.search(query: "absolutePath", sessions: [metadata])
    #expect(toolResults.map(\.kind) == [.tool])
    #expect(toolResults.first?.entryID == "tool-1")
    #expect(toolResults.first?.excerpt == "read /tmp/README.md 80")
}

@Test func searchIsCaseAndDiacriticInsensitive() async throws {
    let directory = try makeSearchTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sessionURL = directory.appending(path: "session.jsonl")
    let fixture = messageSearchFixture(
        sessionID: "session-2",
        messageID: "message-1",
        messageText: "Prepared the résumé draft")
    let metadata = try writeSession(fixture, to: sessionURL)
    let service = SessionSearchService(
        databaseURL: directory.appending(path: "SearchIndex-v1.sqlite"))

    let results = await service.search(query: "RESUME", sessions: [metadata])
    #expect(results.map(\.entryID) == ["message-1"])
}

@Test func searchPreservesSessionMessageToolPathAndSubstringResults() async throws {
    let directory = try makeSearchTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sessionURL = directory.appending(path: "searchable-session-path.jsonl")
    let fixture = completeSearchFixture(
        sessionID: "shape-session",
        title: "Migration work",
        messageID: "shape-message",
        messageText: "Summarize the release notes",
        toolID: "shape-tool")
    let metadata = try writeSession(fixture, to: sessionURL, title: "Migration work")
    let service = SessionSearchService(
        databaseURL: directory.appending(path: "SearchIndex-v1.sqlite"))

    let expectations: [(query: String, kind: SearchResultKind, entryID: String?)] = [
        ("Migration work", .session, nil),
        ("searchable-session-path", .session, nil),
        ("release notes", .message, "shape-message"),
        ("lease not", .message, "shape-message"),
        ("toolCall", .tool, "shape-tool"),
        ("lineLimit", .tool, "shape-tool"),
        ("README.md", .tool, "shape-tool"),
    ]

    for expectation in expectations {
        let results = await service.search(query: expectation.query, sessions: [metadata])
        #expect(results.map(\.kind) == [expectation.kind])
        #expect(results.first?.entryID == expectation.entryID)
    }
}

@Test func unchangedSessionsAreParsedOnlyOnceAcrossQueries() async throws {
    let directory = try makeSearchTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sessionURL = directory.appending(path: "unchanged.jsonl")
    let fixture = messageSearchFixture(
        sessionID: "unchanged-session",
        messageID: "unchanged-message",
        messageText: "persistent constellation marker")
    let metadata = try writeSession(fixture, to: sessionURL, title: "Indexed once")
    let loader = CountingDataLoader()
    let service = SessionSearchService(
        databaseURL: directory.appending(path: "SearchIndex-v1.sqlite"),
        loadData: { url in try loader.load(url) })

    #expect(await service.search(query: "Indexed once", sessions: [metadata]).count == 1)
    #expect(await service.search(query: "constellation", sessions: [metadata]).count == 1)
    #expect(loader.readCount == 1)
}

@Test func unchangedSessionsSurviveServiceRecreationWithoutParsing() async throws {
    let directory = try makeSearchTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sessionURL = directory.appending(path: "recreation.jsonl")
    let databaseURL = directory.appending(path: "SearchIndex-v1.sqlite")
    let fixture = messageSearchFixture(
        sessionID: "recreation-session",
        messageID: "recreation-message",
        messageText: "warm persistence marker")
    let metadata = try writeSession(fixture, to: sessionURL)
    let loader = CountingDataLoader()

    do {
        let service = SessionSearchService(
            databaseURL: databaseURL,
            loadData: { url in try loader.load(url) })
        #expect(await service.search(query: "warm persistence", sessions: [metadata]).count == 1)
    }
    #expect(loader.readCount == 1)

    let recreatedService = SessionSearchService(
        databaseURL: databaseURL,
        loadData: { url in try loader.load(url) })
    #expect(await recreatedService.search(query: "persistence marker", sessions: [metadata]).count == 1)
    #expect(loader.readCount == 1)
}

@Test func changedSessionsReplaceTheirIndexedDocuments() async throws {
    let directory = try makeSearchTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sessionURL = directory.appending(path: "changed.jsonl")
    let databaseURL = directory.appending(path: "SearchIndex-v1.sqlite")
    let original = messageSearchFixture(
        sessionID: "changed-session",
        messageID: "changed-message",
        messageText: "obsolete graphite marker")
    let originalMetadata = try writeSession(original, to: sessionURL)
    let loader = CountingDataLoader()
    let service = SessionSearchService(
        databaseURL: databaseURL,
        loadData: { url in try loader.load(url) })

    #expect(await service.search(query: "obsolete graphite", sessions: [originalMetadata]).count == 1)

    let replacement = messageSearchFixture(
        sessionID: "changed-session",
        messageID: "changed-message",
        messageText: "replacement vermilion marker with a different byte count")
    let replacementMetadata = try writeSession(replacement, to: sessionURL)
    #expect(await service.search(query: "replacement vermilion", sessions: [replacementMetadata]).count == 1)
    #expect(await service.search(query: "obsolete graphite", sessions: [replacementMetadata]).isEmpty)
    #expect(loader.readCount == 2)
}

@Test func invalidChangedSessionKeepsPriorIndexedRows() async throws {
    let directory = try makeSearchTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sessionURL = directory.appending(path: "invalid-change.jsonl")
    let original = messageSearchFixture(
        sessionID: "invalid-change-session",
        messageID: "invalid-change-message",
        messageText: "durable cobalt marker")
    let originalMetadata = try writeSession(original, to: sessionURL)
    let loader = CountingDataLoader()
    let service = SessionSearchService(
        databaseURL: directory.appending(path: "SearchIndex-v1.sqlite"),
        loadData: { url in try loader.load(url) })

    #expect(await service.search(query: "durable cobalt", sessions: [originalMetadata]).count == 1)

    let invalidMetadata = try writeSession("this is not a session file", to: sessionURL)
    let preserved = await service.search(query: "durable cobalt", sessions: [invalidMetadata])
    #expect(preserved.map(\.entryID) == ["invalid-change-message"])
    #expect(loader.readCount == 2)
}

@Test func removedSessionsLoseTheirIndexedDocuments() async throws {
    let directory = try makeSearchTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let removedURL = directory.appending(path: "removed.jsonl")
    let retainedURL = directory.appending(path: "retained.jsonl")
    let removedMetadata = try writeSession(
        messageSearchFixture(
            sessionID: "removed-session",
            messageID: "removed-message",
            messageText: "disappearing heliotrope marker"),
        to: removedURL)
    let retainedMetadata = try writeSession(
        messageSearchFixture(
            sessionID: "retained-session",
            messageID: "retained-message",
            messageText: "remaining saffron marker"),
        to: retainedURL)
    let service = SessionSearchService(
        databaseURL: directory.appending(path: "SearchIndex-v1.sqlite"))

    #expect(await service.search(
        query: "disappearing heliotrope",
        sessions: [removedMetadata, retainedMetadata]
    ).count == 1)
    #expect(await service.search(
        query: "disappearing heliotrope",
        sessions: [retainedMetadata]
    ).isEmpty)
    #expect(await service.search(query: "remaining saffron", sessions: [retainedMetadata]).count == 1)
}

@Test func changingSourceDuringParseKeepsPriorRows() async throws {
    let directory = try makeSearchTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sessionURL = directory.appending(path: "drifting.jsonl")
    let original = messageSearchFixture(
        sessionID: "drifting-session",
        messageID: "drifting-message",
        messageText: "stable indigo marker")
    let originalMetadata = try writeSession(original, to: sessionURL)
    let initialLoader = CountingDataLoader()
    let databaseURL = directory.appending(path: "SearchIndex-v1.sqlite")
    let service = SessionSearchService(
        databaseURL: databaseURL,
        loadData: { url in try initialLoader.load(url) })
    #expect(await service.search(query: "stable indigo", sessions: [originalMetadata]).count == 1)

    let candidate = messageSearchFixture(
        sessionID: "drifting-session",
        messageID: "drifting-message",
        messageText: "candidate azure marker with changed bytes")
    let candidateMetadata = try writeSession(candidate, to: sessionURL)
    let drifted = messageSearchFixture(
        sessionID: "drifting-session",
        messageID: "drifting-message",
        messageText: "drifted magenta marker with substantially more changed bytes than the candidate")
    let driftingLoader = CountingDataLoader(replacementAfterFirstRead: Data(drifted.utf8))
    let changedService = SessionSearchService(
        databaseURL: databaseURL,
        loadData: { url in try driftingLoader.load(url) })

    let preserved = await changedService.search(query: "stable indigo", sessions: [candidateMetadata])
    #expect(preserved.map(\.entryID) == ["drifting-message"])
    #expect(driftingLoader.readCount == 1)
}

@Test func corruptIndexRebuildsOnceFromSources() async throws {
    let directory = try makeSearchTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sessionURL = directory.appending(path: "corrupt-recovery.jsonl")
    let databaseURL = directory.appending(path: "SearchIndex-v1.sqlite")
    let fixture = messageSearchFixture(
        sessionID: "corrupt-session",
        messageID: "corrupt-message",
        messageText: "recoverable turquoise marker")
    let metadata = try writeSession(fixture, to: sessionURL)
    let sourceBefore = try Data(contentsOf: sessionURL)
    try Data("definitely not a sqlite database".utf8).write(to: databaseURL)
    let loader = CountingDataLoader()
    let service = SessionSearchService(
        databaseURL: databaseURL,
        loadData: { url in try loader.load(url) })

    let results = await service.search(query: "recoverable turquoise", sessions: [metadata])

    #expect(results.map(\.entryID) == ["corrupt-message"])
    #expect(loader.readCount == 1)
    #expect(try Data(contentsOf: sessionURL) == sourceBefore)
    #expect(try Data(contentsOf: databaseURL).starts(with: Data("SQLite format 3\0".utf8)))
}

private final class CountingDataLoader: Sendable {
    private struct State: Sendable {
        var readCount = 0
        var hasReplacedSource = false
    }

    private let state = Mutex(State())
    private let replacementAfterFirstRead: Data?

    init(replacementAfterFirstRead: Data? = nil) {
        self.replacementAfterFirstRead = replacementAfterFirstRead
    }

    var readCount: Int {
        state.withLock { $0.readCount }
    }

    func load(_ url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        let shouldReplace = state.withLock { state in
            state.readCount += 1
            guard replacementAfterFirstRead != nil, !state.hasReplacedSource else { return false }
            state.hasReplacedSource = true
            return true
        }
        if shouldReplace, let replacementAfterFirstRead {
            try replacementAfterFirstRead.write(to: url)
        }
        return data
    }
}

private func makeSearchTestDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "tenx-search-service-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func writeSession(
    _ fixture: String,
    to url: URL,
    title: String? = nil
) throws -> SessionMetadata {
    try Data(fixture.utf8).write(to: url)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return SessionMetadata(
        path: url.path,
        sessionId: url.deletingPathExtension().lastPathComponent,
        cwd: "/tmp/Prime Radiant",
        title: title,
        created: .distantPast,
        modified: try #require(attributes[.modificationDate] as? Date),
        sizeBytes: try #require(attributes[.size] as? Int),
        status: .complete)
}

private func messageSearchFixture(
    sessionID: String,
    messageID: String,
    messageText: String
) -> String {
    """
    {"type":"session","id":"\(sessionID)","cwd":"/tmp/Prime Radiant","timestamp":"2026-08-24T12:00:00Z","version":3}
    {"type":"message","id":"\(messageID)","timestamp":"2026-08-24T12:01:00Z","message":{"role":"assistant","content":[{"type":"text","text":"\(messageText)"}]}}
    """
}

private func completeSearchFixture(
    sessionID: String,
    title: String,
    messageID: String,
    messageText: String,
    toolID: String
) -> String {
    """
    {"type":"session","id":"\(sessionID)","cwd":"/tmp/Prime Radiant","timestamp":"2026-08-24T12:00:00Z","version":3,"title":"\(title)"}
    {"type":"message","id":"\(messageID)","timestamp":"2026-08-24T12:01:00Z","message":{"role":"user","content":[{"type":"text","text":"\(messageText)"}]}}
    {"type":"message","id":"\(toolID)","timestamp":"2026-08-24T12:02:00Z","message":{"role":"assistant","content":[{"type":"toolCall","name":"read","arguments":{"absolutePath":"/tmp/README.md","lineLimit":80}}]}}
    """
}

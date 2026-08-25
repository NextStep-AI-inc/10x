import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func searchFindsSessionMessagesAndToolArguments() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sessionURL = directory.appending(path: "session.jsonl")
    let fixture = """
    {"type":"session","id":"session-1","cwd":"/tmp/Prime Radiant","timestamp":"2026-08-24T12:00:00Z","version":3,"title":"Migration work"}
    {"type":"message","id":"user-1","timestamp":"2026-08-24T12:01:00Z","message":{"role":"user","content":[{"type":"text","text":"Summarize the release notes"}]}}
    {"type":"message","id":"tool-1","timestamp":"2026-08-24T12:02:00Z","message":{"role":"assistant","content":[{"type":"toolCall","name":"read","arguments":{"absolutePath":"/tmp/README.md"}}]}}
    """
    try Data(fixture.utf8).write(to: sessionURL)

    let metadata = SessionMetadata(
        path: sessionURL.path,
        sessionId: "session-1",
        cwd: "/tmp/Prime Radiant",
        title: "Migration work",
        created: .distantPast,
        modified: .now,
        sizeBytes: fixture.utf8.count,
        status: .complete)
    let service = SessionSearchService()

    let sessionResults = await service.search(query: "migration", sessions: [metadata])
    #expect(sessionResults.map(\.kind) == [.session])

    let messageResults = await service.search(query: "release notes", sessions: [metadata])
    #expect(messageResults.map(\.kind) == [.message])
    #expect(messageResults.first?.entryID == "user-1")
    #expect(messageResults.first?.excerpt == "Summarize the release notes")

    let toolResults = await service.search(query: "absolutePath", sessions: [metadata])
    #expect(toolResults.map(\.kind) == [.tool])
    #expect(toolResults.first?.entryID == "tool-1")
    #expect(toolResults.first?.excerpt == "read /tmp/README.md")
}

@Test func searchIsCaseAndDiacriticInsensitive() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sessionURL = directory.appending(path: "session.jsonl")
    let fixture = """
    {"type":"session","id":"session-2","cwd":"/tmp","timestamp":"2026-08-24T12:00:00Z","version":3}
    {"type":"message","id":"message-1","timestamp":"2026-08-24T12:01:00Z","message":{"role":"assistant","content":[{"type":"text","text":"Prepared the résumé draft"}]}}
    """
    try Data(fixture.utf8).write(to: sessionURL)

    let metadata = SessionMetadata(
        path: sessionURL.path,
        sessionId: "session-2",
        cwd: "/tmp",
        title: nil,
        created: .distantPast,
        modified: .now,
        sizeBytes: fixture.utf8.count,
        status: .complete)

    let results = await SessionSearchService().search(query: "RESUME", sessions: [metadata])
    #expect(results.map(\.entryID) == ["message-1"])
}

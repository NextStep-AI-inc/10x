import Foundation
import Testing
@testable import TenXApp

@Test func timelineLoaderMapsTheActivePersistedPath() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "session.jsonl")
    let data = Data("""
    {"type":"session","version":3,"id":"s","timestamp":"2026-08-24T20:00:00.000Z","cwd":"/tmp"}
    {"type":"message","id":"a","parentId":null,"timestamp":"2026-08-24T20:00:01.000Z","message":{"role":"user","content":"Root","timestamp":1787601601000}}
    {"type":"message","id":"old","parentId":"a","timestamp":"2026-08-24T20:00:02.000Z","message":{"role":"assistant","content":"Old branch","timestamp":1787601602000}}
    {"type":"message","id":"active","parentId":"a","timestamp":"2026-08-24T20:00:03.000Z","message":{"role":"assistant","content":"Active branch","timestamp":1787601603000}}
    """.utf8)
    try data.write(to: file)

    let history = try await SessionTimelineLoader().load(path: file.path)

    #expect(history?.items.contains { item in
        guard case .message(let message) = item else { return false }
        return message.visibleText == "Active branch"
    } == true)
    #expect(history?.items.contains { item in
        guard case .message(let message) = item else { return false }
        return message.visibleText == "Old branch"
    } == false)
}

@Test func timelineLoaderReturnsNilForAFileThatDoesNotExist() async throws {
    let history = try await SessionTimelineLoader().load(
        path: "/tmp/tenx-missing-\(UUID().uuidString).jsonl")
    #expect(history == nil)
}


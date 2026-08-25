import Testing
import Foundation
@testable import OmpKit

/// Writes a minimal session file whose LAST message line drives the classifier.
func writeSession(at url: URL, id: String, cwd: String, lastMessage: String) throws {
    let content = """
    {"type":"session","version":3,"id":"\(id)","timestamp":"2026-01-01T00:00:00.000Z","cwd":"\(cwd)"}
    \(lastMessage)
    """
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(content.utf8).write(to: url)
}

let userLast = #"{"type":"message","id":"m1","parentId":null,"timestamp":"t","message":{"role":"user","content":"q"}}"#
let abortedLast = #"{"type":"message","id":"m1","parentId":null,"timestamp":"t","message":{"role":"assistant","stopReason":"aborted","content":"x"}}"#
let completeLast = #"{"type":"message","id":"m1","parentId":null,"timestamp":"t","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}"#
let toolCallLast = #"{"type":"message","id":"m1","parentId":null,"timestamp":"t","message":{"role":"assistant","content":[{"type":"toolCall","id":"tc"}]}}"#

private func makeTempRoot(_ label: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(label)-\(UUID().uuidString)")
}

@Test func listsSortsAndClassifies() async throws {
    let root = makeTempRoot("lib")
    defer { try? FileManager.default.removeItem(at: root) }
    let b1 = root.appendingPathComponent("-proj-a")
    let b2 = root.appendingPathComponent("-proj-b")
    try writeSession(at: b1.appendingPathComponent("2026-01-01T00-00-00-000Z_s1.jsonl"),
                     id: "s1", cwd: "/tmp/a", lastMessage: userLast)
    try writeSession(at: b1.appendingPathComponent("2026-01-02T00-00-00-000Z_s2.jsonl"),
                     id: "s2", cwd: "/tmp/a", lastMessage: abortedLast)
    try writeSession(at: b2.appendingPathComponent("2026-01-03T00-00-00-000Z_s3.jsonl"),
                     id: "s3", cwd: "/tmp/b", lastMessage: completeLast)
    // A nested subagent transcript is one level deeper and must NOT be listed.
    try writeSession(at: b1.appendingPathComponent("2026-01-01T00-00-00-000Z_s1/sub.jsonl"),
                     id: "sub", cwd: "/tmp/a", lastMessage: userLast)

    let library = SessionLibrary(root: root)
    let all = await library.listAll()
    #expect(all.count == 3)
    #expect(all.contains { $0.sessionId == "sub" } == false)
    #expect(all.map(\.modified) == all.map(\.modified).sorted(by: >))

    let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.sessionId, $0) })
    #expect(byId["s1"]?.status == .pending)
    #expect(byId["s2"]?.status == .aborted)
    #expect(byId["s3"]?.status == .complete)
    #expect(byId["s1"]?.cwd == "/tmp/a")   // from the header, not the bucket name
}

@Test func classifiesTrailingToolCallAsInterrupted() {
    let message = try! JSONDecoder().decode(
        JSONValue.self,
        from: Data(#"{"role":"assistant","content":[{"type":"toolCall","id":"tc"}]}"#.utf8))
    #expect(SessionStatusClassifier.classify(message: message) == .interrupted)
}

@Test func classifierSkipsPartialLeadingLine() {
    // The 32 KB window usually opens mid-line; that fragment must be ignored.
    let tail = Data(("garbage-fragment-no-brace\n" + completeLast + "\n").utf8)
    #expect(SessionStatusClassifier.classify(tail: tail) == .complete)
}

@Test func cacheInvalidatesOnTitleSlotRewrite() async throws {
    let root = makeTempRoot("cache")
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("-p/2026-01-01T00-00-00-000Z_c1.jsonl")
    let body = """
    {"type":"session","version":3,"id":"c1","timestamp":"2026-01-01T00:00:00.000Z","cwd":"/tmp/c"}
    \(completeLast)
    """
    try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data((makeTitleSlotLine(title: "Before") + "\n" + body).utf8).write(to: file)

    let library = SessionLibrary(root: root)
    let first = await library.listAll()
    #expect(first.first?.title == "Before")

    // Rewrite only the 256-byte slot: same size, new mtime.
    let sizeBefore = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int
    let handle = try FileHandle(forWritingTo: file)
    try handle.seek(toOffset: 0)
    try handle.write(contentsOf: Data((makeTitleSlotLine(title: "After_") + "\n").utf8))
    try handle.close()
    let sizeAfter = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int
    #expect(sizeBefore == sizeAfter)

    let second = await library.listAll()
    #expect(second.first?.title == "After_")
}

@Test func watcherSignalsOnNewFile() async throws {
    let root = makeTempRoot("watch")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let library = SessionLibrary(root: root)
    _ = await library.listAll()
    let stream = library.changes

    // The write happens on a detached task so the stream is already being
    // consumed when it lands.
    let writer = Task {
        try? await Task.sleep(for: .milliseconds(200))
        try? writeSession(
            at: root.appendingPathComponent("-x/2026-01-01T00-00-00-000Z_n1.jsonl"),
            id: "n1", cwd: "/x", lastMessage: userLast)
    }
    defer { writer.cancel() }

    // Iterate inside the timeout: `for await` on an AsyncStream honors
    // cancellation, so this cannot outlive the deadline.
    let fired = await withTimeout(.seconds(5)) {
        for await _ in stream { return true }
        return false
    } ?? false
    #expect(fired)
}

@Test func missingRootYieldsEmptyList() async {
    let library = SessionLibrary(root: makeTempRoot("absent"))
    #expect(await library.listAll().isEmpty)
}

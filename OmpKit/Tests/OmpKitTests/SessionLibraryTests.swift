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

@Test func classifierCoversEveryContractStatusAndTrailingPartialLine() {
    let cases: [(String, SessionStatus)] = [
        (#"{"role":"assistant","stopReason":"error","content":"x"}"#, .error),
        (#"{"role":"assistant","stopReason":"length","content":"x"}"#, .interrupted),
        (#"{"role":"toolResult","content":"x"}"#, .interrupted),
        (#"{"role":"custom","content":"x"}"#, .unknown),
    ]
    for (json, expected) in cases {
        let message = try? JSONValue.decode(from: Data(json.utf8))
        #expect(message.map { SessionStatusClassifier.classify(message: $0) } == expected)
    }

    let tail = Data((completeLast + "\n" + #"{"type":"message","message":{"role":"assistant""#).utf8)
    #expect(SessionStatusClassifier.classify(tail: tail) == .complete)
    let headerOnly = Data(#"{"type":"session","id":"x"}"#.utf8)
    #expect(SessionStatusClassifier.classify(tail: headerOnly) == .unknown)
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

@Test func watcherSignalsWhenAnExistingSessionIsAppended() async throws {
    let root = makeTempRoot("append-watch")
    let file = root.appendingPathComponent("-x/2026-01-01T00-00-00-000Z_n1.jsonl")
    try writeSession(at: file, id: "n1", cwd: "/x", lastMessage: userLast)
    defer { try? FileManager.default.removeItem(at: root) }

    let library = SessionLibrary(root: root)
    _ = await library.listAll()
    let stream = library.changes
    let writer = Task {
        try? await Task.sleep(for: .milliseconds(200))
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(("\n" + completeLast + "\n").utf8))
        try? handle.close()
    }
    defer { writer.cancel() }

    let fired = await withTimeout(.seconds(5)) {
        for await _ in stream { return true }
        return false
    } ?? false
    #expect(fired)
}

@Test func corruptFilesAreSkippedThenRescannedAfterChanging() async throws {
    let root = makeTempRoot("negative-cache")
    let bucket = root.appendingPathComponent("-x")
    try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let corrupt = bucket.appendingPathComponent("broken.jsonl")
    try Data("not json\n".utf8).write(to: corrupt)
    try Data("ignored\n".utf8).write(to: bucket.appendingPathComponent("x.jsonl.bak"))
    try Data("ignored\n".utf8).write(to: bucket.appendingPathComponent("x.jsonl.gz"))

    let library = SessionLibrary(root: root)
    #expect(await library.listAll().isEmpty)
    try await Task.sleep(for: .milliseconds(20))
    try writeSession(at: corrupt, id: "repaired", cwd: "/x", lastMessage: completeLast)
    let repaired = await library.listAll()
    #expect(repaired.map(\.sessionId) == ["repaired"])
}

@Test func missingRootYieldsEmptyList() async {
    let library = SessionLibrary(root: makeTempRoot("absent"))
    #expect(await library.listAll().isEmpty)
}

@Test func archivesAndRestoresAResultWithoutChangingItsRelativePath() async throws {
    let container = makeTempRoot("archive-restore")
    defer { try? FileManager.default.removeItem(at: container) }
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    let activeFile = activeRoot.appendingPathComponent("-tmp-project/session.jsonl")
    try writeSession(
        at: activeFile,
        id: "archive-me",
        cwd: "/tmp/project",
        lastMessage: completeLast)
    let library = SessionLibrary(root: activeRoot, archiveRoot: archiveRoot)

    let archiveReport = await library.archive(paths: [activeFile.path])
    #expect(archiveReport.failures.isEmpty)
    #expect(await library.listAll().isEmpty)
    let archived = await library.listArchived()
    #expect(archived.map(\.sessionId) == ["archive-me"])
    #expect(archived.map { Array(URL(filePath: $0.path).pathComponents.suffix(2)) }
        == [["-tmp-project", "session.jsonl"]])

    let restoreReport = await library.restore(paths: archived.map(\.path))
    #expect(restoreReport.failures.isEmpty)
    #expect(await library.listArchived().isEmpty)
    let restored = await library.listAll()
    #expect(restored.map { Array(URL(filePath: $0.path).pathComponents.suffix(2)) }
        == [["-tmp-project", "session.jsonl"]])
}

@Test func restoreNeverOverwritesAnActiveTranscript() async throws {
    let container = makeTempRoot("restore-conflict")
    defer { try? FileManager.default.removeItem(at: container) }
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    let relativePath = "-tmp-project/session.jsonl"
    let activeFile = activeRoot.appendingPathComponent(relativePath)
    let archivedFile = archiveRoot.appendingPathComponent(relativePath)
    try writeSession(at: activeFile, id: "active", cwd: "/tmp/project", lastMessage: completeLast)
    try writeSession(at: archivedFile, id: "archived", cwd: "/tmp/project", lastMessage: completeLast)
    let library = SessionLibrary(root: activeRoot, archiveRoot: archiveRoot)

    let report = await library.restore(paths: [archivedFile.path])

    #expect(report.succeededPaths.isEmpty)
    #expect(report.failures == [SessionMutationFailure(
        path: archivedFile.path,
        reason: .destinationExists)])
    #expect(FileManager.default.fileExists(atPath: activeFile.path))
    #expect(FileManager.default.fileExists(atPath: archivedFile.path))
}

@Test func deleteRemovesOnlySuppliedTranscriptsAndNeverTheProjectDirectory() async throws {
    let container = makeTempRoot("delete-safety")
    defer { try? FileManager.default.removeItem(at: container) }
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    let projectRoot = container.appendingPathComponent("source-project")
    let keptSource = projectRoot.appendingPathComponent("Keep.swift")
    try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    try Data("struct Keep {}".utf8).write(to: keptSource)
    let first = activeRoot.appendingPathComponent("-source-project/first.jsonl")
    let second = activeRoot.appendingPathComponent("-source-project/second.jsonl")
    try writeSession(at: first, id: "first", cwd: projectRoot.path, lastMessage: completeLast)
    try writeSession(at: second, id: "second", cwd: projectRoot.path, lastMessage: completeLast)
    let library = SessionLibrary(root: activeRoot, archiveRoot: archiveRoot)

    let report = await library.delete(paths: [first.path])

    #expect(report.succeededPaths == [first.path])
    #expect(report.failures.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: first.path))
    #expect(FileManager.default.fileExists(atPath: second.path))
    #expect(FileManager.default.fileExists(atPath: keptSource.path))
}

@Test func deleteReportsInvalidAndMissingTranscriptPaths() async throws {
    let container = makeTempRoot("delete-failures")
    defer { try? FileManager.default.removeItem(at: container) }
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    let sourceFile = container.appendingPathComponent("source-project/keep.jsonl")
    let missingTranscript = activeRoot.appendingPathComponent("-source-project/missing.jsonl")
    try FileManager.default.createDirectory(
        at: sourceFile.deletingLastPathComponent(),
        withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: sourceFile)
    let library = SessionLibrary(root: activeRoot, archiveRoot: archiveRoot)

    let report = await library.delete(paths: [sourceFile.path, missingTranscript.path])

    #expect(report.succeededPaths.isEmpty)
    #expect(report.failures == [
        SessionMutationFailure(path: sourceFile.path, reason: .invalidPath),
        SessionMutationFailure(path: missingTranscript.path, reason: .missingSource),
    ])
    #expect(FileManager.default.fileExists(atPath: sourceFile.path))
}

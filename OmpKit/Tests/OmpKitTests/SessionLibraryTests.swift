import Testing
import Foundation
import Darwin
import Synchronization
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

private final class DirectoryEnumerationRecorder: Sendable {
    private let enumerationCount = Mutex(0)

    func contents(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]
    ) throws -> [URL] {
        enumerationCount.withLock { $0 += 1 }
        return try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: [])
    }

    func reset() {
        enumerationCount.withLock { $0 = 0 }
    }

    var count: Int {
        enumerationCount.withLock { $0 }
    }
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

@Test func classifierTreatsTerminalStopWithAllTrailingToolResultsAsComplete() {
    let assistant = #"{"type":"message","id":"assistant","message":{"role":"assistant","stopReason":"stop","content":[{"type":"toolCall","id":"read-call"},{"type":"toolCall","id":"test-call"}]}}"#
    let readResult = #"{"type":"message","id":"read-result","message":{"role":"toolResult","toolCallId":"read-call","isError":true,"content":"expected failure"}}"#
    let testResult = #"{"type":"message","id":"test-result","message":{"role":"toolResult","toolCallId":"test-call","isError":false,"content":"passed"}}"#
    let tail = Data(([assistant, readResult, testResult].joined(separator: "\n") + "\n").utf8)

    #expect(SessionStatusClassifier.classify(tail: tail) == .complete)
}

@Test func classifierKeepsUnresolvedAndNonterminalToolTurnsInterrupted() {
    let stoppedWithTwoCalls = #"{"type":"message","id":"assistant","message":{"role":"assistant","stopReason":"stop","content":[{"type":"toolCall","id":"one"},{"type":"toolCall","id":"two"}]}}"#
    let toolUse = #"{"type":"message","id":"assistant","message":{"role":"assistant","stopReason":"toolUse","content":[{"type":"toolCall","id":"one"}]}}"#
    let oneResult = #"{"type":"message","id":"result","message":{"role":"toolResult","toolCallId":"one","isError":false,"content":"done"}}"#

    for assistant in [stoppedWithTwoCalls, toolUse] {
        let tail = Data((assistant + "\n" + oneResult + "\n").utf8)
        #expect(SessionStatusClassifier.classify(tail: tail) == .interrupted)
    }
}

@Test func classifierRejectsUnidentifiedCallsAndResultOnlyTailWindows() {
    let malformedStop = #"{"type":"message","id":"assistant","message":{"role":"assistant","stopReason":"stop","content":[{"type":"toolCall","id":"one"},{"type":"toolCall"}]}}"#
    let oneResult = #"{"type":"message","id":"result","message":{"role":"toolResult","toolCallId":"one","isError":false,"content":"done"}}"#

    #expect(SessionStatusClassifier.classify(
        tail: Data((malformedStop + "\n" + oneResult + "\n").utf8)) == .interrupted)
    #expect(SessionStatusClassifier.classify(
        tail: Data((oneResult + "\n").utf8)) == .interrupted)
}

@Test func classifierUsesTerminalSessionOutcomeInsteadOfRecoveredToolError() {
    let toolUse = #"{"type":"message","id":"tool-use","message":{"role":"assistant","stopReason":"toolUse","content":[{"type":"toolCall","id":"test-call"}]}}"#
    let failedTest = #"{"type":"message","id":"failed-test","message":{"role":"toolResult","toolCallId":"test-call","isError":true,"content":"expected TDD failure"}}"#
    let success = #"{"type":"message","id":"success","message":{"role":"assistant","stopReason":"stop","content":"Implemented and verified."}}"#
    let tail = Data(([toolUse, failedTest, success].joined(separator: "\n") + "\n").utf8)

    #expect(SessionStatusClassifier.classify(tail: tail) == .complete)
}

@Test func classifierPreservesExplicitTerminalFailureStatusesAfterToolActivity() {
    let result = #"{"type":"message","id":"result","message":{"role":"toolResult","toolCallId":"call","isError":false,"content":"done"}}"#
    let terminalMessages: [(String, SessionStatus)] = [
        (#"{"type":"message","id":"error","message":{"role":"assistant","stopReason":"error","content":[{"type":"toolCall","id":"call"}]}}"#, .error),
        (#"{"type":"message","id":"aborted","message":{"role":"assistant","stopReason":"aborted","content":[{"type":"toolCall","id":"call"}]}}"#, .aborted),
        (#"{"type":"message","id":"length","message":{"role":"assistant","stopReason":"length","content":[{"type":"toolCall","id":"call"}]}}"#, .interrupted),
    ]

    for (terminal, expected) in terminalMessages {
        let tail = Data((terminal + "\n" + result + "\n").utf8)
        #expect(SessionStatusClassifier.classify(tail: tail) == expected)
    }
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
    #expect(await library.listAll().first?.status == .complete)
}

@Test func repeatedSessionWritesDoNotReenumerateWatcherTopology() async throws {
    let root = makeTempRoot("bounded-watch-enumeration")
    let file = root.appendingPathComponent("-x/session.jsonl")
    try writeSession(at: file, id: "session", cwd: "/x", lastMessage: userLast)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = DirectoryEnumerationRecorder()
    let library = SessionLibrary(
        root: root,
        archiveRoot: nil,
        unlinkItem: { unlink($0) },
        watcherContentsOfDirectory: recorder.contents)
    await library.startWatching()
    recorder.reset()
    let stream = library.changes
    let writer = Task {
        try? await Task.sleep(for: .milliseconds(200))
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        _ = try? handle.seekToEnd()
        for _ in 0..<20 {
            try? handle.write(contentsOf: Data("\n".utf8))
            try? await Task.sleep(for: .milliseconds(20))
        }
        try? handle.close()
    }
    defer { writer.cancel() }

    let fired = await withTimeout(.seconds(5)) {
        for await _ in stream { return true }
        return false
    } ?? false

    #expect(fired)
    #expect(recorder.count == 0)
}

@Test func watcherTracksCreatedRenamedAndDeletedSessions() async throws {
    let root = makeTempRoot("structural-watch")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = SessionLibrary(root: root)
    let stream = library.changes
    await library.startWatching()
    let original = root.appendingPathComponent("-x/original.jsonl")
    let renamed = root.appendingPathComponent("-x/renamed.jsonl")

    let creator = Task {
        try? await Task.sleep(for: .milliseconds(200))
        try? writeSession(at: original, id: "created", cwd: "/x", lastMessage: userLast)
    }
    defer { creator.cancel() }
    let createSignal = await withTimeout(.seconds(5)) {
        for await _ in stream { return true }
        return false
    } ?? false
    #expect(createSignal)
    #expect(await eventuallyLists(library, [original.path]))

    let renamer = Task {
        try? await Task.sleep(for: .milliseconds(200))
        try? FileManager.default.moveItem(at: original, to: renamed)
    }
    defer { renamer.cancel() }
    let renameSignal = await withTimeout(.seconds(5)) {
        for await _ in stream { return true }
        return false
    } ?? false
    #expect(renameSignal)
    // A signal left over from the previous phase can satisfy the wait early,
    // so the listing is polled rather than read once.
    #expect(await eventuallyLists(library, [renamed.path]))

    let deleter = Task {
        try? await Task.sleep(for: .milliseconds(200))
        try? FileManager.default.removeItem(at: renamed)
    }
    defer { deleter.cancel() }
    let deleteSignal = await withTimeout(.seconds(5)) {
        for await _ in stream { return true }
        return false
    } ?? false
    #expect(deleteSignal)
    #expect(await eventuallyLists(library, []))
}

/// Polls the library until it lists exactly `paths`, bounded so a missed
/// structural event fails instead of hanging.
private func eventuallyLists(_ library: SessionLibrary, _ paths: [String]) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if await library.listAll().map(\.path) == paths { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await library.listAll().map(\.path) == paths
}

@Test func watcherSignalsOnNewArchivedFile() async throws {
    let container = makeTempRoot("archive-watch")
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: container) }

    let library = SessionLibrary(root: activeRoot, archiveRoot: archiveRoot)
    let stream = library.changes
    let writer = Task {
        try? await Task.sleep(for: .milliseconds(200))
        try? writeSession(
            at: archiveRoot.appendingPathComponent("-x/archived.jsonl"),
            id: "archived", cwd: "/x", lastMessage: userLast)
    }
    defer { writer.cancel() }

    let fired = await withTimeout(.seconds(5)) {
        for await _ in stream { return true }
        return false
    } ?? false
    #expect(fired)
}

@Test func watcherSignalsWhenAnArchivedSessionIsAppended() async throws {
    let container = makeTempRoot("archive-append-watch")
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    let file = archiveRoot.appendingPathComponent("-x/archived.jsonl")
    try writeSession(at: file, id: "archived", cwd: "/x", lastMessage: userLast)
    defer { try? FileManager.default.removeItem(at: container) }

    let library = SessionLibrary(root: activeRoot, archiveRoot: archiveRoot)
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

@Test func archiveRefreshesWatchersForItsNewDestination() async throws {
    let container = makeTempRoot("post-archive-watch")
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    let activeFile = activeRoot.appendingPathComponent("-x/session.jsonl")
    try writeSession(at: activeFile, id: "session", cwd: "/x", lastMessage: userLast)
    defer { try? FileManager.default.removeItem(at: container) }

    let library = SessionLibrary(root: activeRoot, archiveRoot: archiveRoot)
    let stream = library.changes
    let report = await library.archive(paths: [activeFile.path])
    #expect(report.failures.isEmpty)
    let archiveSignal = await withTimeout(.seconds(5)) {
        for await _ in stream { return true }
        return false
    } ?? false
    #expect(archiveSignal)
    let archivedFile = try #require(await library.listArchived().first).path

    let writer = Task {
        try? await Task.sleep(for: .milliseconds(200))
        guard let handle = try? FileHandle(forWritingTo: URL(filePath: archivedFile)) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(("\n" + completeLast + "\n").utf8))
        try? handle.close()
    }
    defer { writer.cancel() }
    let appendSignal = await withTimeout(.seconds(5)) {
        for await _ in stream { return true }
        return false
    } ?? false
    #expect(appendSignal)
}

@Test func listingExcludesSymlinkedTranscriptFiles() async throws {
    let container = makeTempRoot("symlink-listing")
    defer { try? FileManager.default.removeItem(at: container) }
    let activeRoot = container.appendingPathComponent("sessions")
    let outsideFile = container.appendingPathComponent("outside/session.jsonl")
    let linkedFile = activeRoot.appendingPathComponent("-x/linked.jsonl")
    try writeSession(at: outsideFile, id: "outside", cwd: "/outside", lastMessage: completeLast)
    try FileManager.default.createDirectory(
        at: linkedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: linkedFile, withDestinationURL: outsideFile)

    let library = SessionLibrary(root: activeRoot)

    #expect(await library.listAll().isEmpty)
}

@Test func watcherIgnoresOutsideTargetOfSymlinkedTranscript() async throws {
    let container = makeTempRoot("symlink-watch")
    defer { try? FileManager.default.removeItem(at: container) }
    let activeRoot = container.appendingPathComponent("sessions")
    let outsideFile = container.appendingPathComponent("outside/session.jsonl")
    let linkedFile = activeRoot.appendingPathComponent("-x/linked.jsonl")
    try writeSession(at: outsideFile, id: "outside", cwd: "/outside", lastMessage: userLast)
    try FileManager.default.createDirectory(
        at: linkedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: linkedFile, withDestinationURL: outsideFile)

    let library = SessionLibrary(root: activeRoot)
    let stream = library.changes
    let writer = Task {
        try? await Task.sleep(for: .milliseconds(200))
        guard let handle = try? FileHandle(forWritingTo: outsideFile) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(("\n" + completeLast + "\n").utf8))
        try? handle.close()
    }
    defer { writer.cancel() }

    let fired = await withTimeout(.seconds(1)) {
        for await _ in stream { return true }
        return false
    } ?? false
    #expect(!fired)
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

@Test func mutationsRejectJSONLDirectories() async throws {
    let container = makeTempRoot("directory-safety")
    defer { try? FileManager.default.removeItem(at: container) }
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    let archiveDirectory = activeRoot.appendingPathComponent("-bucket/archive.jsonl")
    let restoreDirectory = archiveRoot.appendingPathComponent("-bucket/restore.jsonl")
    let deleteDirectory = activeRoot.appendingPathComponent("-bucket/delete.jsonl")
    for directory in [archiveDirectory, restoreDirectory, deleteDirectory] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: directory.appendingPathComponent("sentinel"))
    }
    let library = SessionLibrary(root: activeRoot, archiveRoot: archiveRoot)

    let archiveReport = await library.archive(paths: [archiveDirectory.path])
    let restoreReport = await library.restore(paths: [restoreDirectory.path])
    let deleteReport = await library.delete(paths: [deleteDirectory.path])

    #expect(archiveReport.failures == [SessionMutationFailure(
        path: archiveDirectory.path, reason: .invalidPath)])
    #expect(restoreReport.failures == [SessionMutationFailure(
        path: restoreDirectory.path, reason: .invalidPath)])
    #expect(deleteReport.failures == [SessionMutationFailure(
        path: deleteDirectory.path, reason: .invalidPath)])
    for directory in [archiveDirectory, restoreDirectory, deleteDirectory] {
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("sentinel").path))
    }
}

@Test func mutationsRejectSymlinkedBucketsThatEscapeCollectionRoots() async throws {
    let container = makeTempRoot("bucket-symlink-safety")
    defer { try? FileManager.default.removeItem(at: container) }
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    let outsideRoot = container.appendingPathComponent("outside")
    let archiveTarget = outsideRoot.appendingPathComponent("archive-source/session.jsonl")
    let restoreTarget = outsideRoot.appendingPathComponent("restore-source/session.jsonl")
    let deleteTarget = outsideRoot.appendingPathComponent("delete-source/session.jsonl")
    try writeSession(at: archiveTarget, id: "archive", cwd: "/outside", lastMessage: completeLast)
    try writeSession(at: restoreTarget, id: "restore", cwd: "/outside", lastMessage: completeLast)
    try writeSession(at: deleteTarget, id: "delete", cwd: "/outside", lastMessage: completeLast)
    try FileManager.default.createDirectory(at: activeRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
    let archiveBucket = activeRoot.appendingPathComponent("-archive-link")
    let restoreBucket = archiveRoot.appendingPathComponent("-restore-link")
    let deleteBucket = activeRoot.appendingPathComponent("-delete-link")
    try FileManager.default.createSymbolicLink(
        at: archiveBucket, withDestinationURL: archiveTarget.deletingLastPathComponent())
    try FileManager.default.createSymbolicLink(
        at: restoreBucket, withDestinationURL: restoreTarget.deletingLastPathComponent())
    try FileManager.default.createSymbolicLink(
        at: deleteBucket, withDestinationURL: deleteTarget.deletingLastPathComponent())
    let archivePath = archiveBucket.appendingPathComponent("session.jsonl").path
    let restorePath = restoreBucket.appendingPathComponent("session.jsonl").path
    let deletePath = deleteBucket.appendingPathComponent("session.jsonl").path
    let library = SessionLibrary(root: activeRoot, archiveRoot: archiveRoot)

    let archiveReport = await library.archive(paths: [archivePath])
    let restoreReport = await library.restore(paths: [restorePath])
    let deleteReport = await library.delete(paths: [deletePath])

    #expect(archiveReport.failures == [SessionMutationFailure(
        path: archivePath, reason: .invalidPath)])
    #expect(restoreReport.failures == [SessionMutationFailure(
        path: restorePath, reason: .invalidPath)])
    #expect(deleteReport.failures == [SessionMutationFailure(
        path: deletePath, reason: .invalidPath)])
    #expect(FileManager.default.fileExists(atPath: archiveTarget.path))
    #expect(FileManager.default.fileExists(atPath: restoreTarget.path))
    #expect(FileManager.default.fileExists(atPath: deleteTarget.path))
}

@Test func mutationsRejectSymlinkedTranscriptFiles() async throws {
    let container = makeTempRoot("file-symlink-safety")
    defer { try? FileManager.default.removeItem(at: container) }
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    let outsideRoot = container.appendingPathComponent("outside")
    let archiveTarget = outsideRoot.appendingPathComponent("archive.jsonl")
    let restoreTarget = outsideRoot.appendingPathComponent("restore.jsonl")
    let deleteTarget = outsideRoot.appendingPathComponent("delete.jsonl")
    try writeSession(at: archiveTarget, id: "archive", cwd: "/outside", lastMessage: completeLast)
    try writeSession(at: restoreTarget, id: "restore", cwd: "/outside", lastMessage: completeLast)
    try writeSession(at: deleteTarget, id: "delete", cwd: "/outside", lastMessage: completeLast)
    let archiveLink = activeRoot.appendingPathComponent("-bucket/archive.jsonl")
    let restoreLink = archiveRoot.appendingPathComponent("-bucket/restore.jsonl")
    let deleteLink = activeRoot.appendingPathComponent("-bucket/delete.jsonl")
    for link in [archiveLink, restoreLink, deleteLink] {
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
    try FileManager.default.createSymbolicLink(at: archiveLink, withDestinationURL: archiveTarget)
    try FileManager.default.createSymbolicLink(at: restoreLink, withDestinationURL: restoreTarget)
    try FileManager.default.createSymbolicLink(at: deleteLink, withDestinationURL: deleteTarget)
    let library = SessionLibrary(root: activeRoot, archiveRoot: archiveRoot)

    let archiveReport = await library.archive(paths: [archiveLink.path])
    let restoreReport = await library.restore(paths: [restoreLink.path])
    let deleteReport = await library.delete(paths: [deleteLink.path])

    #expect(archiveReport.failures == [SessionMutationFailure(
        path: archiveLink.path, reason: .invalidPath)])
    #expect(restoreReport.failures == [SessionMutationFailure(
        path: restoreLink.path, reason: .invalidPath)])
    #expect(deleteReport.failures == [SessionMutationFailure(
        path: deleteLink.path, reason: .invalidPath)])
    for path in [archiveLink.path, restoreLink.path, deleteLink.path,
                 archiveTarget.path, restoreTarget.path, deleteTarget.path] {
        #expect(FileManager.default.fileExists(atPath: path))
    }
}

@Test func deleteNeverRecursivelyRemovesADirectorySwappedAfterValidation() async throws {
    let container = makeTempRoot("delete-swap-safety")
    defer { try? FileManager.default.removeItem(at: container) }
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    let bucket = activeRoot.appendingPathComponent("-bucket")
    try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
    let transcript = bucket.appendingPathComponent("session.jsonl")
    let swapDirectory = bucket.appendingPathComponent("swap")
    let sentinel = swapDirectory.appendingPathComponent("sentinel")
    try Data("transcript".utf8).write(to: transcript)
    try FileManager.default.createDirectory(at: swapDirectory, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: sentinel)
    let library = SessionLibrary(
        root: activeRoot,
        archiveRoot: archiveRoot,
        unlinkItem: { path in
            guard renamex_np(path, swapDirectory.path, UInt32(RENAME_SWAP)) == 0 else { return -1 }
            return unlink(path)
        })

    let report = await library.delete(paths: [transcript.path])

    #expect(report.failures == [SessionMutationFailure(
        path: transcript.path,
        reason: .fileOperationFailed)])
    #expect(FileManager.default.fileExists(
        atPath: transcript.appendingPathComponent("sentinel").path))
}

@Test func listingFromACancelledTaskDoesNotHideTheSessionAfterwards() async throws {
    let root = makeTempRoot("cancelled-listing")
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("-x/session.jsonl")
    try writeSession(at: file, id: "cancelled", cwd: "/x", lastMessage: userLast)
    let library = SessionLibrary(root: root)

    // A cancelled caller must not poison the metadata cache for everyone else.
    let cancelled = Task { () -> [SessionMetadata] in
        withUnsafeCurrentTask { $0?.cancel() }
        return await library.listAll()
    }
    _ = await cancelled.value

    #expect(await library.listAll().map(\.path) == [file.path])
}

@Test func watcherFollowsAFileDeletedAndRecreatedWithinOneDebounce() async throws {
    let root = makeTempRoot("recreate-watch")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("-x/session.jsonl")
    try writeSession(at: file, id: "recreated", cwd: "/x", lastMessage: userLast)
    let library = SessionLibrary(root: root)
    let stream = library.changes
    await library.startWatching()
    #expect(await eventuallyLists(library, [file.path]))

    // Delete and recreate faster than the 100 ms debounce, then let it settle.
    try FileManager.default.removeItem(at: file)
    try writeSession(at: file, id: "recreated", cwd: "/x", lastMessage: userLast)
    try await Task.sleep(for: .milliseconds(400))

    // Directory watchers never fire for in-file writes, so a signal after the
    // second append can only come from a watcher on the recreated inode. Two
    // appends and two waits, because the stream may still hold the signal
    // from the recreate itself; the iterator is never cancelled, which would
    // terminate the shared stream.
    func append() throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n".utf8))
    }
    try append()
    let firstSignal = await withTimeout(.seconds(5)) {
        for await _ in stream { return true }
        return false
    } ?? false
    #expect(firstSignal)
    try append()
    let secondSignal = await withTimeout(.seconds(5)) {
        for await _ in stream { return true }
        return false
    } ?? false
    #expect(secondSignal)
}

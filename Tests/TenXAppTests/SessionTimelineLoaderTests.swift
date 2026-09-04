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

@Test func timelineLoaderReadsAndMapsUnchangedHistoryOnce() async throws {
    let fixture = try TimelineLoaderFixture(message: "First")
    defer { fixture.remove() }
    let reader = CountingTimelineReader()
    let loader = SessionTimelineLoader(readData: { url in try reader.read(url) })

    let first = try await loader.load(path: fixture.file.path)
    let second = try await loader.load(path: fixture.file.path)

    #expect(first == second)
    #expect(reader.count == 1)
}

@Test func timelineLoaderReloadsChangedAndReplacedFiles() async throws {
    let fixture = try TimelineLoaderFixture(message: "First")
    defer { fixture.remove() }
    let reader = CountingTimelineReader()
    let loader = SessionTimelineLoader(readData: { url in try reader.read(url) })

    _ = try await loader.load(path: fixture.file.path)
    try fixture.write(message: "Changed value")
    try fixture.setModificationDate(Date(timeIntervalSince1970: 1_800_000_000))
    let changed = try await loader.load(path: fixture.file.path)

    let modificationDate = try fixture.modificationDate()
    let size = try fixture.size()
    try fixture.replace(message: "Replaced text", modificationDate: modificationDate)
    #expect(try fixture.modificationDate() == modificationDate)
    #expect(try fixture.size() == size)
    let replaced = try await loader.load(path: fixture.file.path)

    #expect(changed?.visibleText == "Changed value")
    #expect(replaced?.visibleText == "Replaced text")
    #expect(reader.count == 3)
}

@Test func canceledTimelineLoadThrowsAndDoesNotInstallAStaleCacheEntry() async throws {
    let fixture = try TimelineLoaderFixture(message: "Stale")
    defer { fixture.remove() }
    let reader = BlockingTimelineReader()
    let loader = SessionTimelineLoader(readData: { url in try reader.read(url) })

    let canceledLoad = Task { try await loader.load(path: fixture.file.path) }
    #expect(reader.waitUntilBlocked())
    canceledLoad.cancel()
    reader.resume()
    await #expect(throws: CancellationError.self) {
        _ = try await canceledLoad.value
    }

    try fixture.write(message: "Fresh")
    let fresh = try await loader.load(path: fixture.file.path)

    #expect(fresh?.visibleText == "Fresh")
    #expect(reader.count == 2)
}

@Test func timelineLoaderDoesNotCacheAHistoryThatChangesDuringItsRead() async throws {
    let fixture = try TimelineLoaderFixture(message: "Stale")
    defer { fixture.remove() }
    let reader = ChangingTimelineReader(
        replacement: TimelineLoaderFixture.data(message: "Fresh history"))
    let loader = SessionTimelineLoader(readData: { url in try reader.read(url) })

    let stale = try await loader.load(path: fixture.file.path)
    let fresh = try await loader.load(path: fixture.file.path)

    #expect(stale?.visibleText == "Stale")
    #expect(fresh?.visibleText == "Fresh history")
    #expect(reader.count == 2)
}

private final class CountingTimelineReader: @unchecked Sendable {
    private let lock = NSLock()
    private var readCount = 0

    var count: Int { lock.withLock { readCount } }

    func read(_ url: URL) throws -> Data {
        lock.withLock { readCount += 1 }
        return try Data(contentsOf: url)
    }
}

private final class BlockingTimelineReader: @unchecked Sendable {
    private let lock = NSLock()
    private let didStart = DispatchSemaphore(value: 0)
    private let canFinish = DispatchSemaphore(value: 0)
    private var readCount = 0

    var count: Int { lock.withLock { readCount } }

    func read(_ url: URL) throws -> Data {
        lock.withLock { readCount += 1 }
        let data = try Data(contentsOf: url)
        if count == 1 {
            didStart.signal()
            canFinish.wait()
        }
        return data
    }

    func waitUntilBlocked() -> Bool {
        didStart.wait(timeout: .now() + 5) == .success
    }

    func resume() {
        canFinish.signal()
    }
}

private final class ChangingTimelineReader: @unchecked Sendable {
    private let lock = NSLock()
    private let replacement: Data
    private var readCount = 0

    init(replacement: Data) {
        self.replacement = replacement
    }

    var count: Int { lock.withLock { readCount } }

    func read(_ url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        let shouldReplace = lock.withLock {
            readCount += 1
            return readCount == 1
        }
        if shouldReplace { try replacement.write(to: url) }
        return data
    }
}

private struct TimelineLoaderFixture: Sendable {
    let directory: URL
    let file: URL

    init(message: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        file = directory.appending(path: "session.jsonl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(message: message)
    }

    func write(message: String) throws {
        try data(message: message).write(to: file)
    }

    func replace(message: String, modificationDate: Date) throws {
        let replacement = directory.appending(path: "replacement.jsonl")
        try data(message: message).write(to: replacement)
        try FileManager.default.setAttributes(
            [.modificationDate: modificationDate],
            ofItemAtPath: replacement.path)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: replacement, to: file)
    }

    func modificationDate() throws -> Date {
        let values = try file.resourceValues(forKeys: [.contentModificationDateKey])
        return try #require(values.contentModificationDate)
    }

    func size() throws -> UInt64 {
        let values = try file.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(try #require(values.fileSize))
    }

    func setModificationDate(_ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func data(message: String) -> Data {
        Data("""
        {"type":"session","version":3,"id":"s","timestamp":"2026-08-24T20:00:00.000Z","cwd":"/tmp"}
        {"type":"message","id":"a","parentId":null,"timestamp":"2026-08-24T20:00:01.000Z","message":{"role":"assistant","content":"\(message)","timestamp":1787601601000}}
        """.utf8)
    }

    private func data(message: String) -> Data {
        Self.data(message: message)
    }
}

private extension TranscriptHistory {
    var visibleText: String? {
        items.compactMap { item -> TranscriptMessage? in
            guard case .message(let message) = item else { return nil }
            return message
        }.first?.visibleText
    }
}

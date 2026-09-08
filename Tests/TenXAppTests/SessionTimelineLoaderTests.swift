import CryptoKit
import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func timelineLoaderHydratesPersistedImageAndReconcilesItsReceiptOnce() async throws {
    let image = try #require(Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
    let fixture = try TimelineImageFixture(reference: blobReference(for: image))
    defer { fixture.remove() }
    try fixture.writeBlob(image)
    let reader = CountingTimelineReader()
    let loader = SessionTimelineLoader(
        blobDirectory: fixture.blobDirectory,
        readData: { url in try reader.read(url) })

    let first = try #require(try await loader.load(path: fixture.file.path))
    let second = try #require(try await loader.load(path: fixture.file.path))
    let messages = first.items.compactMap { item -> TranscriptMessage? in
        guard case .message(let message) = item else { return nil }
        return message
    }
    let message = try #require(messages.first)

    #expect(message.id == "user-1")
    #expect(message.timestamp == Date(timeIntervalSince1970: 1_787_601_601))
    #expect(message.document.images.map(\.data) == [image, Data([1, 2, 3])])
    #expect(message.visibleText == "Inspect blob:sha256:not-an-image")
    #expect(message.raw["provider"]?.stringValue == "preserve-me")
    #expect(message.raw["content"]?.arrayValue?.first?["data"]?.stringValue
        == blobReference(for: image))
    #expect(first == second)
    #expect(reader.count == 1)

    let firstReceipt = pendingWithImages(image)
    let secondReceipt = pendingWithImages(image)
    var consumedIndices: Set<Int> = []

    let afterFirstReconcile = PendingUserSubmission.reconcile(
        [firstReceipt, secondReceipt],
        messages: messages,
        consumedIndices: &consumedIndices)
    let afterSecondReconcile = PendingUserSubmission.reconcile(
        afterFirstReconcile,
        messages: messages,
        consumedIndices: &consumedIndices)

    #expect(afterFirstReconcile == [secondReceipt])
    #expect(afterSecondReconcile == [secondReceipt])
    #expect(consumedIndices == [0])
}

@Test func timelineLoaderRetriesAValidMissingBlobWhenItAppears() async throws {
    let image = Data("late image bytes".utf8)
    let reference = blobReference(for: image)
    let fixture = try TimelineImageFixture(reference: reference)
    defer { fixture.remove() }
    let reader = CountingTimelineReader()
    let loader = SessionTimelineLoader(
        blobDirectory: fixture.blobDirectory,
        readData: { url in try reader.read(url) })

    let missing = try #require(try await loader.load(path: fixture.file.path))
    #expect(missing.firstMessage?.raw.firstImageData == reference)
    #expect(missing.firstMessage?.document.images.map(\.data) == [Data([1, 2, 3])])

    try fixture.writeBlob(image)
    let restored = try #require(try await loader.load(path: fixture.file.path))

    #expect(restored.firstMessage?.document.images.map(\.data) == [image, Data([1, 2, 3])])
    #expect(reader.count == 2)
}

@Test func timelineLoaderPreservesUnresolvableImageReferences() async throws {
    let bytes = Data("expected bytes".utf8)
    let validReference = blobReference(for: bytes)
    let hash = String(validReference.dropFirst("blob:sha256:".count))
    let cases: [(name: String, reference: String, prepare: (TimelineImageFixture) throws -> Void)] = [
        ("invalid", "blob:md5:\(hash)", { _ in }),
        ("malformed", "blob:sha256:1234", { _ in }),
        ("uppercase", "blob:sha256:\(hash.uppercased())", { _ in }),
        ("traversal", "blob:sha256:../\(hash)", { _ in }),
        ("wrong hash", validReference, { fixture in
            try fixture.writeBlob(Data("different bytes".utf8))
        }),
        ("directory", validReference, { fixture in
            try FileManager.default.createDirectory(
                at: fixture.blobURL(for: validReference),
                withIntermediateDirectories: false)
        }),
        ("symlink", validReference, { fixture in
            let target = fixture.directory.appending(path: "target")
            try bytes.write(to: target)
            try FileManager.default.createSymbolicLink(
                at: fixture.blobURL(for: validReference),
                withDestinationURL: target)
        }),
    ]

    for testCase in cases {
        let fixture = try TimelineImageFixture(reference: testCase.reference)
        defer { fixture.remove() }
        try testCase.prepare(fixture)

        let history = try #require(try await SessionTimelineLoader(
            blobDirectory: fixture.blobDirectory).load(path: fixture.file.path))

        #expect(history.firstMessage?.raw.firstImageData == testCase.reference,
                "\(testCase.name) reference changed")
        #expect(history.firstMessage?.document.images.map(\.data) == [Data([1, 2, 3])],
                "\(testCase.name) produced an image")
    }
}

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
    let loader = SessionTimelineLoader(readData: { url in try await reader.read(url) })

    let canceledLoad = Task { try await loader.load(path: fixture.file.path) }
    await reader.waitUntilBlocked()
    canceledLoad.cancel()
    await reader.resume()
    await #expect(throws: CancellationError.self) {
        _ = try await canceledLoad.value
    }

    try fixture.write(message: "Fresh")
    let fresh = try await loader.load(path: fixture.file.path)

    #expect(fresh?.visibleText == "Fresh")
    #expect(await reader.count == 2)
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

/// Holds the first read open until released. Suspends instead of blocking, so
/// neither the loader's actor nor the test occupies a cooperative thread while
/// waiting, which a semaphore would under a saturated pool.
private actor BlockingTimelineReader {
    private var readCount = 0
    private var hasStarted = false
    private var isReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    var count: Int { readCount }

    func read(_ url: URL) async throws -> Data {
        readCount += 1
        let data = try Data(contentsOf: url)
        if readCount == 1 {
            hasStarted = true
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
            if !isReleased {
                await withCheckedContinuation { releaseWaiters.append($0) }
            }
        }
        return data
    }

    func waitUntilBlocked() async {
        if hasStarted { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func resume() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
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

private struct TimelineImageFixture: Sendable {
    let directory: URL
    let blobDirectory: URL
    let file: URL
    let reference: String

    init(reference: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        blobDirectory = directory.appending(path: "blobs", directoryHint: .isDirectory)
        file = directory.appending(path: "session.jsonl")
        self.reference = reference
        try FileManager.default.createDirectory(
            at: blobDirectory,
            withIntermediateDirectories: true)
        try Data("""
        {"type":"session","version":3,"id":"s","timestamp":"2026-08-24T20:00:00.000Z","cwd":"/tmp"}
        {"type":"message","id":"user-1","parentId":null,"timestamp":"2026-08-24T20:00:01.000Z","message":{"role":"user","provider":"preserve-me","content":[{"type":"text","text":"Inspect blob:sha256:not-an-image","data":"\(reference)"},{"type":"image","data":"\(reference)","mimeType":"image/png","name":"proof.png"},{"type":"image","data":"AQID","mimeType":"image/png"}],"timestamp":1787601601000}}
        """.utf8).write(to: file)
    }

    func blobURL(for reference: String? = nil) -> URL {
        let value = reference ?? self.reference
        let hash = String(value.dropFirst("blob:sha256:".count))
        return blobDirectory.appending(path: hash)
    }

    func writeBlob(_ data: Data) throws {
        try data.write(to: blobURL())
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func blobReference(for data: Data) -> String {
    "blob:sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func pendingWithImages(_ image: Data) -> PendingUserSubmission {
    PendingUserSubmission(
        text: "Inspect blob:sha256:not-an-image",
        attachments: [
            ComposerAttachment(
                name: "proof.png",
                data: image,
                mimeType: "image/png",
                pixelWidth: 1,
                pixelHeight: 1),
            ComposerAttachment(
                name: "inline.png",
                data: Data([1, 2, 3]),
                mimeType: "image/png",
                pixelWidth: 1,
                pixelHeight: 1),
        ],
        minimumUserIndex: 0,
        state: .sending)
}

private extension TranscriptHistory {
    var visibleText: String? {
        items.compactMap { item -> TranscriptMessage? in
            guard case .message(let message) = item else { return nil }
            return message
        }.first?.visibleText
    }

    var firstMessage: TranscriptMessage? {
        items.compactMap { item -> TranscriptMessage? in
            guard case .message(let message) = item else { return nil }
            return message
        }.first
    }
}

private extension JSONValue {
    var firstImageData: String? {
        self["content"]?.arrayValue?.first {
            $0["type"]?.stringValue == "image"
        }?["data"]?.stringValue
    }
}

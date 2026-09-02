import AppKit
import Foundation
import Testing
@testable import TenXApp

@Suite struct ToolMediaLoaderTests {
    @MainActor @Test func mediaLoaderDecodesOneImmutableItemOnce() async {
        let calls = MediaDecodeCounter()
        let loader = ToolMediaLoader(decode: { item in
            calls.increment()
            return .loaded(DecodedToolMedia(data: Data(item.id.utf8), image: nil))
        })
        let item = mediaItem(id: "image-1")

        await loader.load(item)
        await loader.load(item)

        #expect(calls.value == 1)
    }

    @MainActor @Test func mediaLoaderReusesCompletedResultForTheSameID() async {
        let loader = ToolMediaLoader(decode: { item in
            .loaded(DecodedToolMedia(data: Data((item.name ?? "").utf8), image: nil))
        })
        let contentID = UUID()
        let original = mediaItem(id: "image-1", name: "original.png", contentID: contentID)
        let replacement = mediaItem(id: "image-1", name: "replacement.png", contentID: contentID)

        await loader.load(original)
        await loader.load(replacement)

        #expect(loader.decodedData == Data("original.png".utf8))
    }

    @Test func mediaItemSemanticEqualityIgnoresItsGenerationToken() {
        let original = mediaItem(id: "image-1", data: "same")
        let equivalent = mediaItem(id: "image-1", data: "same")
        let replacement = mediaItem(id: "image-1", data: "different")

        #expect(original.contentID != equivalent.contentID)
        #expect(original == equivalent)
        #expect(original != replacement)
    }

    @MainActor @Test func mediaLoaderReloadsDifferentPayloadWithTheSameVisibleID() async {
        let calls = MediaDecodeCounter()
        let loader = ToolMediaLoader(decode: { item in
            calls.increment()
            return .loaded(DecodedToolMedia(data: Data((item.data ?? "").utf8), image: nil))
        })
        let original = mediaItem(id: "image-1", data: "first")
        let replacement = mediaItem(id: "image-1", data: "second")

        await loader.load(original)
        await loader.load(replacement)

        #expect(calls.value == 2)
        #expect(loader.decodedData == Data("second".utf8))
    }

    @MainActor @Test func mediaLoaderRejectsAnObsoleteResult() async {
        let gate = MediaDecodeGate()
        let loader = ToolMediaLoader(decode: { item in
            if item.id == "slow" { await gate.wait() }
            return .loaded(DecodedToolMedia(data: Data(item.id.utf8), image: nil))
        })

        let slow = Task { await loader.load(mediaItem(id: "slow")) }
        await gate.waitForStart()
        await loader.load(mediaItem(id: "new"))
        await gate.open()
        await slow.value

        #expect(loader.loadedItemID == "new")
        #expect(loader.decodedData == Data("new".utf8))
    }

    @MainActor @Test func mediaLoaderCancellationCannotPublishALateResult() async {
        let gate = MediaDecodeGate()
        let loader = ToolMediaLoader(decode: { item in
            await gate.wait()
            return .loaded(DecodedToolMedia(data: Data(item.id.utf8), image: nil))
        })
        let work = Task { await loader.load(mediaItem(id: "slow")) }
        await gate.waitForStart()

        loader.cancel()
        await gate.open()
        await work.value

        #expect(loader.loadedItemID == nil)
        #expect(loader.decodedData == nil)
    }

    @MainActor @Test func cancelledCallerCanReloadTheSameItem() async {
        let gate = MediaDecodeGate()
        let cancellation = MediaCancellationRecorder()
        let calls = MediaDecodeCounter()
        let loader = ToolMediaLoader(decode: { item in
            calls.increment()
            if calls.value == 1 {
                await gate.wait()
                cancellation.record(Task.isCancelled)
            }
            return .loaded(DecodedToolMedia(data: Data(item.id.utf8), image: nil))
        })
        let item = mediaItem(id: "slow")
        let caller = Task { await loader.load(item) }
        await gate.waitForStart()

        caller.cancel()
        await gate.open()
        await caller.value
        await loader.load(item)

        #expect(cancellation.wasCancelled)
        #expect(calls.value == 2)
        #expect(loader.loadedItemID == item.id)
    }

    @MainActor @Test func mediaLoaderMarksInvalidInlineDataUnavailable() async {
        let loader = ToolMediaLoader()

        await loader.load(mediaItem(id: "invalid", data: "not base64"))

        guard case .unavailable = loader.state else {
            Issue.record("Invalid base64 should be unavailable")
            return
        }
    }

    @MainActor @Test func mediaLoaderRetainsDecodedDataForSave() async {
        let data = Data([0, 1, 2, 3])
        let loader = ToolMediaLoader()

        await loader.load(mediaItem(id: "bytes", data: data.base64EncodedString()))

        #expect(loader.decodedData == data)
        guard case .loaded(let media) = loader.state else {
            Issue.record("Valid non-image data should load")
            return
        }
        #expect(media.data == data)
        #expect(media.image == nil)
    }

    @MainActor @Test func defaultDecoderEagerlyLoadsAnInlinePNG() async throws {
        let data = try #require(testPNGData())
        let loader = ToolMediaLoader()
        let item = mediaItem(id: "inline-png", data: data.base64EncodedString())

        await loader.load(item)

        guard case .loaded(let media) = loader.state else {
            Issue.record("Valid inline PNG should load")
            return
        }
        #expect(media.data == data)
        #expect(media.image?.width == 1)
        #expect(media.image?.height == 1)
    }

    @MainActor @Test func defaultDecoderLoadsALocalPNG() async throws {
        let data = try #require(testPNGData())
        let url = URL.temporaryDirectory.appending(path: "tool-media-\(UUID().uuidString).png")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let loader = ToolMediaLoader()
        let item = localMediaItem(id: "local-png", url: url)

        await loader.load(item)

        guard case .loaded(let media) = loader.state else {
            Issue.record("Valid local PNG should load")
            return
        }
        #expect(media.data == data)
        #expect(media.image?.width == 1)
    }

    @MainActor @Test func defaultDecoderFailsForAMissingLocalFile() async {
        let loader = ToolMediaLoader()
        let item = localMediaItem(
            id: "missing-file",
            url: URL.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).png"))

        await loader.load(item)

        guard case .failed = loader.state else {
            Issue.record("Missing local file should fail")
            return
        }
    }
}

private final class MediaDecodeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() { lock.withLock { count += 1 } }
}

private final class MediaCancellationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var wasCancelled: Bool { lock.withLock { value } }

    func record(_ isCancelled: Bool) { lock.withLock { value = isCancelled } }
}

private actor MediaDecodeGate {
    private var isOpen = false
    private var isStarted = false
    private var waitContinuation: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        isStarted = true
        startContinuation?.resume()
        startContinuation = nil
        guard !isOpen else { return }
        await withCheckedContinuation { waitContinuation = $0 }
    }

    func waitForStart() async {
        guard !isStarted else { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func open() {
        isOpen = true
        waitContinuation?.resume()
        waitContinuation = nil
    }
}

private func mediaItem(
    id: String,
    name: String? = nil,
    data: String? = nil,
    contentID: UUID = UUID()
) -> ToolMediaItem {
    ToolMediaItem(
        id: id,
        kind: .image,
        name: name ?? "\(id).png",
        mimeType: "image/png",
        data: data ?? Data(id.utf8).base64EncodedString(),
        url: nil,
        contentID: contentID)
}

private func localMediaItem(id: String, url: URL) -> ToolMediaItem {
    ToolMediaItem(
        id: id,
        kind: .image,
        name: url.lastPathComponent,
        mimeType: "image/png",
        data: nil,
        url: url.path,
        contentID: UUID())
}

private func testPNGData() -> Data? {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 1,
        pixelsHigh: 1,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0)
    bitmap?.setColor(.systemCyan, atX: 0, y: 0)
    return bitmap?.representation(using: .png, properties: [:])
}

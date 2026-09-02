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
        let original = mediaItem(id: "image-1", name: "original.png")
        let replacement = mediaItem(id: "image-1", name: "replacement.png")

        await loader.load(original)
        await loader.load(replacement)

        #expect(loader.decodedData == Data("original.png".utf8))
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
}

private final class MediaDecodeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() { lock.withLock { count += 1 } }
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
    data: String? = nil
) -> ToolMediaItem {
    ToolMediaItem(
        id: id,
        kind: .image,
        name: name ?? "\(id).png",
        mimeType: "image/png",
        data: data ?? Data(id.utf8).base64EncodedString(),
        url: nil)
}

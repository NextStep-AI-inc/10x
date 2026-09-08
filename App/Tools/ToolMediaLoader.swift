import Combine
import CoreGraphics
import Foundation
import ImageIO

enum ToolMediaLoadState: Sendable {
    case idle
    case loading
    case loaded(DecodedToolMedia)
    case unavailable
    case failed
}

struct DecodedToolMedia: @unchecked Sendable {
    let data: Data?
    let image: CGImage?
}

@MainActor final class ToolMediaLoader: ObservableObject {
    typealias Decoder = @Sendable (ToolMediaItem) async -> ToolMediaLoadState

    @Published private(set) var state: ToolMediaLoadState = .idle

    private let decode: Decoder
    private var decodeTask: Task<Void, Never>?
    private var activeContentID: UUID?
    private var completedResult: (contentID: UUID, itemID: String, state: ToolMediaLoadState)?

    init() {
        decode = Self.decodeMedia
    }

    init(decode: @escaping Decoder) {
        self.decode = decode
    }

    convenience init(preloaded item: ToolMediaItem, media: DecodedToolMedia) {
        self.init(preloaded: item, state: .loaded(media))
    }

    init(preloaded item: ToolMediaItem, state: ToolMediaLoadState) {
        decode = Self.decodeMedia
        self.state = state
        completedResult = (item.contentID, item.id, state)
    }

    var decodedData: Data? {
        guard case .loaded(let media) = state else { return nil }
        return media.data
    }

    var loadedItemID: String? {
        guard case .loaded = state else { return nil }
        return completedResult?.itemID
    }

    func load(_ item: ToolMediaItem) async {
        if completedResult?.contentID == item.contentID { return }
        guard activeContentID != item.contentID else { return }

        cancel()
        activeContentID = item.contentID
        state = .loading

        let contentID = item.contentID
        let decode = decode
        let work = Task { [weak self] in
            let result = await decode(item)
            guard !Task.isCancelled else { return }
            self?.publish(result, for: item, contentID: contentID)
        }
        decodeTask = work
        await withTaskCancellationHandler(
            operation: { await work.value },
            onCancel: { work.cancel() })
        if Task.isCancelled {
            cancelLoad(for: contentID)
        }
    }

    func cancel() {
        cancelLoad(for: activeContentID)
    }

    private func cancelLoad(for contentID: UUID?) {
        guard let contentID, activeContentID == contentID else { return }
        decodeTask?.cancel()
        decodeTask = nil
        activeContentID = nil
        if case .loading = state {
            state = .idle
        }
    }

    private func publish(
        _ result: ToolMediaLoadState,
        for item: ToolMediaItem,
        contentID: UUID
    ) {
        guard activeContentID == contentID else { return }
        activeContentID = nil
        decodeTask = nil
        state = result
        completedResult = (contentID, item.id, result)
    }

    private static func decodeMedia(_ item: ToolMediaItem) async -> ToolMediaLoadState {
        let work: Task<ToolMediaLoadState, Never> = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return .idle }
            let data: Data?

            if let encoded = item.data {
                let payload = encoded.split(separator: ",", maxSplits: 1).last.map(String.init) ?? encoded
                guard let decoded = Data(base64Encoded: payload) else { return .unavailable }
                data = decoded
            } else if let url = fileURL(for: item) {
                do {
                    data = try Data(contentsOf: url)
                } catch {
                    return .failed
                }
            } else {
                return .unavailable
            }

            guard !Task.isCancelled, let data else { return .idle }
            let image: CGImage?
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               CGImageSourceGetType(source) != nil {
                image = CGImageSourceCreateImageAtIndex(
                    source,
                    0,
                    [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
            } else {
                image = nil
            }
            return .loaded(DecodedToolMedia(data: data, image: image))
        }
        return await withTaskCancellationHandler(
            operation: { await work.value },
            onCancel: { work.cancel() })
    }

    nonisolated private static func fileURL(for item: ToolMediaItem) -> URL? {
        guard let value = item.url, !value.isEmpty else { return nil }
        let url = value.hasPrefix("/") ? URL(filePath: value) : URL(string: value)
        guard url?.isFileURL == true else { return nil }
        return url
    }
}

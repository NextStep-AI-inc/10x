import Combine
import CoreGraphics
import Foundation
import ImageIO

enum ToolMediaLoadState: @unchecked Sendable {
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
    private var activeItemID: String?
    private var completedResult: (itemID: String, state: ToolMediaLoadState)?

    init() {
        decode = Self.decodeMedia
    }

    init(decode: @escaping Decoder) {
        self.decode = decode
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
        if completedResult?.itemID == item.id { return }
        guard activeItemID != item.id else { return }

        cancel()
        activeItemID = item.id
        state = .loading

        let itemID = item.id
        let decode = decode
        let work = Task { [weak self] in
            let result = await decode(item)
            guard !Task.isCancelled else { return }
            self?.publish(result, for: itemID)
        }
        decodeTask = work
        await withTaskCancellationHandler(
            operation: { await work.value },
            onCancel: { work.cancel() })
    }

    func cancel() {
        decodeTask?.cancel()
        decodeTask = nil
        activeItemID = nil
        if case .loading = state {
            state = .idle
        }
    }

    private func publish(_ result: ToolMediaLoadState, for itemID: String) {
        guard activeItemID == itemID else { return }
        activeItemID = nil
        decodeTask = nil
        state = result
        completedResult = (itemID, result)
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
                image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            } else {
                image = nil
            }
            return .loaded(DecodedToolMedia(data: data, image: image))
        }
        return await work.value
    }

    nonisolated private static func fileURL(for item: ToolMediaItem) -> URL? {
        guard let value = item.url, !value.isEmpty else { return nil }
        let url = value.hasPrefix("/") ? URL(filePath: value) : URL(string: value)
        guard url?.isFileURL == true else { return nil }
        return url
    }
}

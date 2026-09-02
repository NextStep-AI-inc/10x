import Foundation
import OmpKit

enum ToolPhase: Equatable, Sendable {
    case running
    case complete
    case failed
}

extension ToolPhase {
    var label: String {
        switch self {
        case .running: "Running"
        case .complete: "Complete"
        case .failed: "Error"
        }
    }
}

struct ToolPresentation: Identifiable, Equatable, Sendable {
    let id: String
    var name: String { didSet { refreshContent() } }
    var arguments: JSONValue { didSet { refreshContent() } }
    var result: JSONValue? { didSet { refreshContent() } }
    var phase: ToolPhase { didSet { refreshContent() } }
    let startDate: Date
    var endDate: Date?
    private(set) var content: ToolCardContent

    init(
        id: String,
        name: String,
        arguments: JSONValue,
        result: JSONValue?,
        phase: ToolPhase,
        startDate: Date,
        endDate: Date?
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.result = result
        self.phase = phase
        self.startDate = startDate
        self.endDate = endDate
        content = ToolContentExtractor.card(
            name: name,
            arguments: arguments,
            result: result,
            phase: phase)
    }

    var isError: Bool { phase == .failed }

    var durationLabel: String {
        let end = endDate ?? Date()
        return String(format: "%.1fs", max(0, end.timeIntervalSince(startDate)))
    }

    private mutating func refreshContent() {
        let refreshed = ToolContentExtractor.card(
            name: name,
            arguments: arguments,
            result: result,
            phase: phase)
        content = refreshed.reusingMediaContentIDs(from: content)
    }
}

private extension ToolCardContent {
    func reusingMediaContentIDs(from previous: ToolCardContent) -> ToolCardContent {
        var previousMedia = previous.body.mediaItems
        return ToolCardContent(
            title: title,
            verb: verb,
            primary: primary,
            outcome: outcome,
            reference: reference,
            body: body.reusingMediaContentIDs(from: &previousMedia))
    }
}

private extension ToolBody {
    var mediaItems: [ToolMediaItem] {
        switch self {
        case .media(let items, _): items
        case .stack(let bodies): bodies.flatMap(\.mediaItems)
        default: []
        }
    }

    func reusingMediaContentIDs(from previousMedia: inout [ToolMediaItem]) -> ToolBody {
        switch self {
        case .media(let items, let caption):
            return .media(items.map { item in
                guard let index = previousMedia.firstIndex(of: item) else { return item }
                let previous = previousMedia.remove(at: index)
                return ToolMediaItem(
                    id: item.id,
                    kind: item.kind,
                    name: item.name,
                    mimeType: item.mimeType,
                    data: item.data,
                    url: item.url,
                    contentID: previous.contentID)
            }, caption: caption)
        case .stack(let bodies):
            return .stack(bodies.map { $0.reusingMediaContentIDs(from: &previousMedia) })
        default:
            return self
        }
    }
}

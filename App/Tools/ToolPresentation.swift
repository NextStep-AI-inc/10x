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
        content = refreshed.reusingRenderContentIDs(from: content)
    }
}

private extension ToolCardContent {
    func reusingRenderContentIDs(from previous: ToolCardContent) -> ToolCardContent {
        var previousMedia = previous.body.mediaItems
        var previousSources = previous.body.sourceItems
        var previousDiffs = previous.body.diffItems
        return ToolCardContent(
            title: title,
            verb: verb,
            primary: primary,
            outcome: outcome,
            reference: reference,
            body: body.reusingRenderContentIDs(
                from: &previousMedia,
                previousSources: &previousSources,
                previousDiffs: &previousDiffs))
    }
}

private struct SourceRenderItem: Equatable {
    let presentation: SourcePresentation
    let previewLines: Int?
}

private struct DiffRenderItem: Equatable {
    let diff: UnifiedDiff
    let fallbackPath: String?
}

private extension ToolBody {
    var mediaItems: [ToolMediaItem] {
        switch self {
        case .media(let items, _): items
        case .stack(let bodies): bodies.flatMap(\.mediaItems)
        default: []
        }
    }

    var sourceItems: [SourceRenderItem] {
        switch self {
        case .source(let presentation, let previewLines):
            [SourceRenderItem(presentation: presentation, previewLines: previewLines)]
        case .stack(let bodies):
            bodies.flatMap(\.sourceItems)
        default:
            []
        }
    }

    var diffItems: [DiffRenderItem] {
        switch self {
        case .diff(let diff, let fallbackPath):
            [DiffRenderItem(diff: diff, fallbackPath: fallbackPath)]
        case .stack(let bodies):
            bodies.flatMap(\.diffItems)
        default:
            []
        }
    }

    func reusingRenderContentIDs(
        from previousMedia: inout [ToolMediaItem],
        previousSources: inout [SourceRenderItem],
        previousDiffs: inout [DiffRenderItem]
    ) -> ToolBody {
        switch self {
        case .source(let presentation, let previewLines):
            let item = SourceRenderItem(
                presentation: presentation,
                previewLines: previewLines)
            guard let index = previousSources.firstIndex(of: item) else { return self }
            let previous = previousSources.remove(at: index).presentation
            return .source(SourcePresentation(
                language: presentation.language,
                text: presentation.text,
                lines: presentation.lines,
                contentID: previous.contentID), previewLines: previewLines)
        case .diff(let diff, let fallbackPath):
            let item = DiffRenderItem(diff: diff, fallbackPath: fallbackPath)
            guard let index = previousDiffs.firstIndex(of: item) else { return self }
            let previous = previousDiffs.remove(at: index).diff
            return .diff(UnifiedDiff(
                raw: diff.raw,
                files: diff.files,
                renderID: previous.renderID), fallbackPath: fallbackPath)
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
            return .stack(bodies.map {
                $0.reusingRenderContentIDs(
                    from: &previousMedia,
                    previousSources: &previousSources,
                    previousDiffs: &previousDiffs)
            })
        default:
            return self
        }
    }
}

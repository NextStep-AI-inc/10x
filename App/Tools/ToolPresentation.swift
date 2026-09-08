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
    private var storedName: String
    private var storedArguments: JSONValue
    private var storedResult: JSONValue?
    private var storedPhase: ToolPhase
    let startDate: Date
    var endDate: Date?
    private(set) var content: ToolCardContent

    var name: String {
        get { storedName }
        set { update(name: newValue) }
    }

    var arguments: JSONValue {
        get { storedArguments }
        set { update(arguments: newValue) }
    }

    var result: JSONValue? {
        get { storedResult }
        set { update(result: .some(newValue)) }
    }

    var phase: ToolPhase {
        get { storedPhase }
        set { update(phase: newValue) }
    }

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
        self.storedName = name
        self.storedArguments = arguments
        self.storedResult = result
        self.storedPhase = phase
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

    /// Applies one event/history mutation and extracts card content from the final state once.
    mutating func update(
        name: String? = nil,
        arguments: JSONValue? = nil,
        result: JSONValue?? = nil,
        phase: ToolPhase? = nil,
        endDate: Date?? = nil,
        normalizationObserver: (() -> Void)? = nil
    ) {
        var hasSemanticChange = false
        if let name, name != storedName {
            storedName = name
            hasSemanticChange = true
        }
        if let arguments, arguments != storedArguments {
            storedArguments = arguments
            hasSemanticChange = true
        }
        if let result, result != storedResult {
            storedResult = result
            hasSemanticChange = true
        }
        if let phase, phase != storedPhase {
            storedPhase = phase
            hasSemanticChange = true
        }
        if let endDate, endDate != self.endDate {
            self.endDate = endDate
        }
        guard hasSemanticChange else { return }
        normalizationObserver?()
        refreshContent()
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

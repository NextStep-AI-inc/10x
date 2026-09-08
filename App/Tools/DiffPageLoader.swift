import Combine
import Foundation

@MainActor final class DiffPageLoader: ObservableObject {
    typealias Tokenizer = @Sendable (String, String?) -> [SourceSpan]
    private static let initialRowLimit = 200
    private static let initialCharacterLimit = 16_384
    private static let initialLineCharacterLimit = 2_048

    @Published private(set) var cachedSpans: [DiffRenderRow.ID: [SourceSpan]] = [:]
    private let tokenize: Tokenizer
    private var contentID: UUID?
    private var tokenizationTask: Task<[DiffRenderRow.ID: [SourceSpan]], Never>?
    private var activeTokenizationID: UUID?

    init(
        contentID: UUID? = nil,
        initialRows: [DiffRenderRow] = [],
        tokenize: @escaping Tokenizer = { text, language in
            SourceTokenizer.spans(text, language: language)
        }
    ) {
        self.contentID = contentID
        self.tokenize = tokenize
        cache(initialRows)
    }

    func reset(contentID: UUID, initialRows: [DiffRenderRow]) {
        guard self.contentID != contentID else { return }
        tokenizationTask?.cancel()
        activeTokenizationID = nil
        cachedSpans = [:]
        self.contentID = contentID
        cache(initialRows)
    }

    private func cache(_ rows: [DiffRenderRow]) {
        var cachedCharacterCount = 0
        for row in rows.lazy.filter(\.isLine).prefix(Self.initialRowLimit) {
            guard let line = row.line else { continue }
            let text = line.line.text
            let lineLimitIndex = text.index(
                text.startIndex,
                offsetBy: Self.initialLineCharacterLimit,
                limitedBy: text.endIndex
            )
            guard lineLimitIndex == nil || lineLimitIndex == text.endIndex else { return }
            let characterCount = text.count
            guard characterCount <= Self.initialCharacterLimit - cachedCharacterCount else { return }
            cachedSpans[row.id] = tokenize(text, line.language)
            cachedCharacterCount += characterCount
        }
    }

    var cachedLineCount: Int { cachedSpans.count }

    func spans(for rowID: DiffRenderRow.ID, contentID: UUID) -> [SourceSpan]? {
        guard self.contentID == contentID else { return nil }
        return cachedSpans[rowID]
    }

    func load(rows: [DiffRenderRow], contentID: UUID? = nil) async {
        let requestedContentID = contentID ?? self.contentID
        guard requestedContentID == self.contentID else { return }
        var characterCount = 0
        var missingRows: [(DiffRenderRow.ID, DiffRenderLine)] = []
        for row in rows where cachedSpans[row.id] == nil {
            guard missingRows.count < Self.initialRowLimit else { break }
            guard let line = row.line else { continue }
            let lineCharacterCount = line.line.text.prefix(
                Self.initialLineCharacterLimit + 1).count
            guard lineCharacterCount <= Self.initialLineCharacterLimit else { continue }
            guard lineCharacterCount <= Self.initialCharacterLimit - characterCount else { break }
            missingRows.append((row.id, line))
            characterCount += lineCharacterCount
        }
        guard !missingRows.isEmpty else { return }

        tokenizationTask?.cancel()
        let tokenize = tokenize
        let id = UUID()
        let work: Task<[DiffRenderRow.ID: [SourceSpan]], Never> = Task.detached(priority: .userInitiated) {
            var spans: [DiffRenderRow.ID: [SourceSpan]] = [:]
            for (id, line) in missingRows {
                guard !Task.isCancelled else { return [:] }
                spans[id] = tokenize(line.line.text, line.language)
            }
            return spans
        }
        tokenizationTask = work
        activeTokenizationID = id
        let spans = await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
        guard !Task.isCancelled,
              activeTokenizationID == id,
              self.contentID == requestedContentID
        else { return }
        cachedSpans.merge(spans) { _, latest in latest }
    }
}

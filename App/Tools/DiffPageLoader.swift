import Combine
import Foundation

@MainActor final class DiffPageLoader: ObservableObject {
    typealias Tokenizer = @Sendable (String, String?) -> [SourceSpan]

    @Published private(set) var cachedSpans: [DiffRenderRow.ID: [SourceSpan]] = [:]
    private let tokenize: Tokenizer
    private var tokenizationTask: Task<[DiffRenderRow.ID: [SourceSpan]], Never>?
    private var activeTokenizationID: UUID?

    init(
        initialRows: [DiffRenderRow] = [],
        tokenize: @escaping Tokenizer = { text, language in
            SourceTokenizer.spans(text, language: language)
        }
    ) {
        self.tokenize = tokenize
        for row in initialRows.lazy.filter(\.isLine).prefix(200) {
            guard let line = row.line else { continue }
            cachedSpans[row.id] = tokenize(line.line.text, line.language)
        }
    }

    var cachedLineCount: Int { cachedSpans.count }

    func spans(for rowID: DiffRenderRow.ID) -> [SourceSpan]? {
        cachedSpans[rowID]
    }

    func load(rows: [DiffRenderRow]) async {
        let missingRows = rows.compactMap { row -> (DiffRenderRow.ID, DiffRenderLine)? in
            guard let line = row.line, cachedSpans[row.id] == nil else { return nil }
            return (row.id, line)
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
        guard !Task.isCancelled, activeTokenizationID == id else { return }
        cachedSpans.merge(spans) { _, latest in latest }
    }
}

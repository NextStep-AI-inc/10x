import Combine
import Foundation

@MainActor final class SourcePageLoader: ObservableObject {
    typealias Tokenizer = @Sendable (String, String?) -> [SourceSpan]

    private static let initialRowLimit = 200
    private static let initialCharacterLimit = 16_384
    private static let initialLineCharacterLimit = 2_048

    @Published private(set) var cachedSpans: [Int: [SourceSpan]] = [:]
    private let tokenize: Tokenizer
    private var contentID: UUID?
    private var tokenizationTask: Task<[Int: [SourceSpan]], Never>?
    private var activeTokenizationID: UUID?

    init(
        contentID: UUID? = nil,
        initialLines: [SourceLine] = [],
        language: String? = nil,
        tokenize: @escaping Tokenizer = { text, language in
            SourceTokenizer.spans(text, language: language)
        }
    ) {
        self.contentID = contentID
        self.tokenize = tokenize
        cache(initialLines, language: language)
    }

    func reset(contentID: UUID, initialLines: [SourceLine], language: String?) {
        guard self.contentID != contentID else { return }
        tokenizationTask?.cancel()
        activeTokenizationID = nil
        cachedSpans = [:]
        self.contentID = contentID
        cache(initialLines, language: language)
    }

    var cachedLineCount: Int { cachedSpans.count }

    func spans(for line: SourceLine, contentID: UUID) -> [SourceSpan]? {
        guard self.contentID == contentID else { return nil }
        return cachedSpans[line.number]
    }

    func load(lines: [SourceLine], language: String?, contentID: UUID? = nil) async {
        let requestedContentID = contentID ?? self.contentID
        guard requestedContentID == self.contentID else { return }
        let missingLines = lines.filter { cachedSpans[$0.number] == nil }
        guard !missingLines.isEmpty else { return }

        tokenizationTask?.cancel()
        let tokenize = tokenize
        let id = UUID()
        let work: Task<[Int: [SourceSpan]], Never> = Task.detached(priority: .userInitiated) {
            var spans: [Int: [SourceSpan]] = [:]
            for line in missingLines {
                guard !Task.isCancelled else { return [:] }
                spans[line.number] = tokenize(line.rawText, language)
            }
            return spans
        }
        tokenizationTask = work
        activeTokenizationID = id
        let spans = await withTaskCancellationHandler(
            operation: { await work.value },
            onCancel: { work.cancel() })
        guard !Task.isCancelled,
              activeTokenizationID == id,
              self.contentID == requestedContentID
        else { return }
        cachedSpans.merge(spans) { _, latest in latest }
    }

    private func cache(_ lines: [SourceLine], language: String?) {
        var characterCount = 0
        for line in lines.prefix(Self.initialRowLimit) {
            let lineCharacterCount = line.characterCount(
                cappedAt: Self.initialLineCharacterLimit + 1)
            guard lineCharacterCount <= Self.initialLineCharacterLimit else { return }
            guard lineCharacterCount <= Self.initialCharacterLimit - characterCount else { return }
            cachedSpans[line.number] = tokenize(line.rawText, language)
            characterCount += lineCharacterCount
        }
    }
}

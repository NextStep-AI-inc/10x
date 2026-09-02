import SwiftUI

struct ProgressiveTextPresentation: Equatable, Sendable {
    static let initialReveal = ProgressiveReveal(initialLimit: 2_048, pageSize: 4_000)

    let spans: [SourceSpan]
    let visibleText: String
    let accessibilityText: String
    let hasMore: Bool
    let progressiveTotal: Int

    init(
        text: String,
        spans: [SourceSpan]? = nil,
        characterLimit: Int
    ) {
        let limit = max(0, characterLimit)
        let pageSize = Self.initialReveal.pageSize
        let probeLimit = limit + pageSize + 1
        let probeCount = text.prefix(probeLimit).count
        let visibleText = String(text.prefix(limit))

        self.visibleText = visibleText
        accessibilityText = visibleText
        self.spans = spans.map {
            Self.prefix($0, characterLimit: limit)
        } ?? []
        hasMore = probeCount > limit
        progressiveTotal = probeCount < probeLimit ? probeCount : limit + pageSize
    }

    private static func prefix(
        _ spans: [SourceSpan],
        characterLimit: Int
    ) -> [SourceSpan] {
        var remaining = characterLimit
        var result: [SourceSpan] = []
        for span in spans where remaining > 0 {
            let text = String(span.text.prefix(remaining))
            guard !text.isEmpty else { continue }
            result.append(SourceSpan(text: text, role: span.role))
            remaining -= text.count
        }
        return result
    }
}

struct ProgressiveTextView<Content: View>: View {
    let text: String
    let accessibilityNoun: String
    private let content: (String) -> Content
    @State private var reveal = ProgressiveTextPresentation.initialReveal

    init(
        text: String,
        accessibilityNoun: String,
        @ViewBuilder content: @escaping (String) -> Content
    ) {
        self.text = text
        self.accessibilityNoun = accessibilityNoun
        self.content = content
    }

    var body: some View {
        let presentation = ProgressiveTextPresentation(
            text: text,
            characterLimit: reveal.limit)
        VStack(alignment: .leading, spacing: 4) {
            content(presentation.visibleText)
                .accessibilityLabel(presentation.accessibilityText)
            ProgressiveRevealButton(
                reveal: $reveal,
                total: presentation.progressiveTotal,
                noun: "characters",
                accessibilityNoun: accessibilityNoun)
        }
    }
}

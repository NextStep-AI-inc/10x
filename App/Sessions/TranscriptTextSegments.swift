import SwiftUI

struct TranscriptTextSegment: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
}

enum TranscriptTextSegments {
    static let defaultMaximumCharacters = 1_024

    static func make(
        _ source: String,
        maximumCharacters: Int = defaultMaximumCharacters,
        avoidingSplit query: String? = nil
    ) -> [TranscriptTextSegment] {
        guard !source.isEmpty else { return [] }
        precondition(maximumCharacters > 0)

        var segments: [TranscriptTextSegment] = []
        var start = source.startIndex
        var offset = 0
        let protectedRanges = query.map { matchRanges(in: source, query: $0) } ?? []

        while start < source.endIndex {
            var hardEnd = source.index(
                start,
                offsetBy: maximumCharacters,
                limitedBy: source.endIndex) ?? source.endIndex
            if let crossingMatch = protectedRanges.first(where: {
                   $0.lowerBound < hardEnd && $0.upperBound > hardEnd
               }) {
                hardEnd = crossingMatch.upperBound
            }
            let end = hardEnd == source.endIndex
                ? hardEnd
                : preferredEnd(in: source, from: start, through: hardEnd)
            let text = String(source[start..<end])
            segments.append(TranscriptTextSegment(id: offset, text: text))
            offset += text.count
            start = end
        }

        return segments
    }

    static func matchRanges(in source: String, query: String) -> [Range<String.Index>] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !query.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var remaining = source.startIndex..<source.endIndex
        while let match = source.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: remaining,
            locale: Locale(identifier: "en_US_POSIX")) {
            ranges.append(match)
            guard match.upperBound < source.endIndex else { break }
            remaining = match.upperBound..<source.endIndex
        }
        return ranges
    }

    private static func preferredEnd(
        in source: String,
        from start: String.Index,
        through hardEnd: String.Index
    ) -> String.Index {
        var cursor = hardEnd
        while cursor > start {
            let previous = source.index(before: cursor)
            if source[previous] == "\n" { return cursor }
            cursor = previous
        }

        cursor = hardEnd
        while cursor > start {
            let previous = source.index(before: cursor)
            if source[previous].isWhitespace { return cursor }
            cursor = previous
        }
        return hardEnd
    }
}

struct TranscriptPlainTextView: View {
    let text: String
    let font: Font
    let color: Color
    let highlightedQuery: String?

    init(
        text: String,
        font: Font,
        color: Color,
        highlightedQuery: String? = nil
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.highlightedQuery = highlightedQuery
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(TranscriptTextSegments.make(
                text,
                avoidingSplit: highlightedQuery)) { segment in
                Text(attributedText(segment.text))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(font)
        .foregroundStyle(color)
        .textSelection(.enabled)
    }

    private func attributedText(_ text: String) -> AttributedString {
        guard let highlightedQuery else { return AttributedString(text) }
        var attributed = AttributedString(text)
        for sourceRange in TranscriptTextSegments.matchRanges(
            in: text,
            query: highlightedQuery) {
            guard let range = Range(sourceRange, in: attributed) else { continue }
            attributed[range].backgroundColor = TenXPalette.color(TenXPalette.yellowHex)
            attributed[range].foregroundColor = TenXPalette.color(TenXPalette.nearBlackHex)
        }
        return attributed
    }
}

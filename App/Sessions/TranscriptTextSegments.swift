import SwiftUI

struct TranscriptTextSegment: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
}

enum TranscriptTextSegments {
    static let defaultMaximumCharacters = 1_024

    static func make(
        _ source: String,
        maximumCharacters: Int = defaultMaximumCharacters
    ) -> [TranscriptTextSegment] {
        guard !source.isEmpty else { return [] }
        precondition(maximumCharacters > 0)

        var segments: [TranscriptTextSegment] = []
        var start = source.startIndex
        var offset = 0

        while start < source.endIndex {
            let hardEnd = source.index(
                start,
                offsetBy: maximumCharacters,
                limitedBy: source.endIndex) ?? source.endIndex
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(TranscriptTextSegments.make(text)) { segment in
                Text(segment.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(font)
        .foregroundStyle(color)
        .textSelection(.enabled)
    }
}

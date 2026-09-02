import AppKit
import SwiftUI
import Testing
@testable import TenXApp

@Suite struct SourceSurfaceTests {
    @Test func sourceLinePresentationSlicesAtSpanBoundaries() {
        let line = SourceLine(number: 7, spans: [
            SourceSpan(text: "let", role: .keyword),
            SourceSpan(text: " value", role: .plain),
            SourceSpan(text: " = 1", role: .number)
        ])

        let presentation = SourceLineRenderPresentation(
            line: line,
            spans: line.spans,
            characterLimit: 5)

        #expect(presentation.spans == [
            SourceSpan(text: "let", role: .keyword),
            SourceSpan(text: " v", role: .plain)
        ])
        #expect(presentation.visibleText == "let v")
        #expect(presentation.hasMore)
    }

    @Test func hugeSourceLineUsesOneFiniteDisplayPageAtATime() {
        let line = SourceLine(number: 1, text: String(repeating: "x", count: 4_000_000))
        var reveal = ProgressiveReveal(initialLimit: 2_048, pageSize: 2_048)

        let initial = SourceLineRenderPresentation(
            line: line,
            spans: line.spans,
            characterLimit: reveal.limit)

        #expect(initial.visibleText.count <= 2_048)
        #expect(initial.accessibilityText.count <= 2_048)
        #expect(initial.hasMore)
        #expect(initial.progressiveTotal == 4_096)
        #expect(reveal.nextPageCount(total: initial.progressiveTotal) == 2_048)

        reveal.revealNextPage(total: initial.progressiveTotal)
        let next = SourceLineRenderPresentation(
            line: line,
            spans: line.spans,
            characterLimit: reveal.limit)

        #expect(next.visibleText.count <= 4_096)
        #expect(next.accessibilityText.count <= 4_096)
        #expect(next.hasMore)
        #expect(next.progressiveTotal == 6_144)
        #expect(reveal.nextPageCount(total: next.progressiveTotal) == 2_048)
    }

    @MainActor @Test func sourceCardMountsHugeLineWithFiniteRowAndDisclosure() throws {
        let source = SourcePresentation(
            language: "swift",
            text: String(repeating: "x", count: 100_000))

        let bitmap = try #require(renderSnapshotBitmap(
            SourceCard(presentation: source, lines: source.lines),
            size: CGSize(width: 640, height: 220)))
        let presentation = SourceLineRenderPresentation(
            line: source.lines[0],
            spans: source.lines[0].spans,
            characterLimit: 2_048)

        #expect(bitmap.pixelsHigh > 0)
        #expect(presentation.visibleText.count == 2_048)
        #expect(presentation.accessibilityText.count == 2_048)
        #expect(presentation.progressiveTotal == 4_096)
    }
}

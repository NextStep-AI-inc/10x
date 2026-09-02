import AppKit
import SwiftUI
import Testing
@testable import TenXApp

@Suite struct SourceSurfaceTests {
    @Test func sourceReplacementReturnsToItsInitialVisiblePage() {
        let original = SourcePresentation(language: "swift", text: sourceLines(prefix: "original"))
        let replacement = SourcePresentation(language: "swift", text: sourceLines(prefix: "replacement"))
        var state = SourceRenderState(contentID: original.contentID, initialLimit: 200)
        state.reveal.revealNextPage(total: original.lines.count)

        let effective = state.effective(
            for: replacement.contentID,
            initialLimit: 200)

        #expect(state.reveal.limit == 400)
        #expect(effective.reveal.limit == 200)
        #expect(SourceSurface.visibleLineCount(
            total: replacement.lines.count,
            previewLineLimit: nil,
            reveal: effective.reveal) == 200)
    }

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

    @Test func finalSourceLinePageAdvertisesItsExactSingleCharacter() {
        let line = SourceLine(number: 1, text: String(repeating: "x", count: 2_049))
        let presentation = SourceLineRenderPresentation(
            line: line,
            spans: line.spans,
            characterLimit: 2_048)
        let reveal = ProgressiveReveal(initialLimit: 2_048, pageSize: 2_048)

        #expect(presentation.progressiveTotal == 2_049)
        #expect(reveal.nextPageCount(total: presentation.progressiveTotal) == 1)
    }

    @Test func sourceLineLookaheadNeverAdvertisesBeyondTheNextPage() {
        let line = SourceLine(number: 1, text: String(repeating: "x", count: 100_000))
        let presentation = SourceLineRenderPresentation(
            line: line,
            spans: line.spans,
            characterLimit: 2_048)
        let reveal = ProgressiveReveal(initialLimit: 2_048, pageSize: 2_048)

        #expect(presentation.progressiveTotal == 4_096)
        #expect(reveal.nextPageCount(total: presentation.progressiveTotal) == 2_048)
    }

    @Test func sourceLineAccessibilityPresentationIsFiniteAndQuantitySpecific() {
        let line = SourceLine(number: 7, text: String(repeating: "x", count: 2_049))
        let presentation = SourceLineRenderPresentation(
            line: line,
            spans: line.spans,
            characterLimit: 2_048)
        let reveal = ProgressiveReveal(initialLimit: 2_048, pageSize: 2_048)
        let disclosureLabel = ProgressiveRevealCopy.label(
            count: reveal.nextPageCount(total: presentation.progressiveTotal),
            noun: SourceLineRenderPresentation.disclosureAccessibilityNoun)

        #expect(presentation.accessibilityLabel(lineNumber: 7)
            == "Line 7, \(String(repeating: "x", count: 2_048)). Truncated. Show more characters to continue.")
        #expect(disclosureLabel == "Show 1 more source line character")
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

private func sourceLines(prefix: String) -> String {
    (1...500).map { "let \(prefix)\($0) = \($0)" }.joined(separator: "\n")
}

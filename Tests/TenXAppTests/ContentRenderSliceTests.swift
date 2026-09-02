import Foundation
import Testing
@testable import TenXApp

@Suite struct ContentRenderSliceTests {
    @Test func nestedDocumentUsesOneGlobalBudget() {
        let source = (0..<20).map { parent in
            (["- parent \(parent)"] + (0..<20).map { "  - child \($0)" })
                .joined(separator: "\n")
        }.joined(separator: "\n")
        let document = MessageContentParser.parse(source)

        let slice = ContentRenderSlicer.slice(document, limit: 160)

        #expect(slice.consumedUnits == 160)
        #expect(slice.hasMore)
        #expect(ContentRenderSlicer.unitCount(slice.document) == 160)
    }

    @Test func partialTableKeepsItsHeader() {
        let rows = (0..<500).map { "| row \($0) | value \($0) |" }
            .joined(separator: "\n")
        let document = MessageContentParser.parse("""
        | Name | Value |
        | --- | --- |
        \(rows)
        """)

        let slice = ContentRenderSlicer.slice(document, limit: 20)

        guard case .table(let table) = slice.document.blocks.first else {
            Issue.record("Expected a sliced table")
            return
        }
        #expect(!table.headers.isEmpty)
        #expect(table.rows.count == 19)
    }

    @Test func partialSourcePreservesOriginalLineNumbers() {
        let lines = (0..<500).map { "let value\($0) = \($0)" }
            .joined(separator: "\n")
        let document = MessageContentParser.parse("""
        ```swift
        \(lines)
        ```
        """)

        let slice = ContentRenderSlicer.slice(document, limit: 30)

        guard case .source(let source) = slice.document.blocks.first else {
            Issue.record("Expected sliced source")
            return
        }
        #expect(source.lines.map(\.number) == Array(1...30))
        guard case .source(let original) = document.blocks.first else {
            Issue.record("Expected an original source")
            return
        }
        #expect(source.lines == Array(original.lines.prefix(30)))
        #expect(source.contentID == original.contentID)
        #expect(slice.document.renderVersion == document.renderVersion)
    }

    @Test func sourceAppendKeepsTheExistingDocumentRevealLimit() {
        let original = largeDocument(prefix: "original")
        let appended = MessageContentParser.parse(original.source + "\n\nappended")
        var state = ContentDocumentRenderState()
        state = state.effective(for: original)
        state.reveal.revealNextPage(total: ContentRenderSlicer.unitCount(original))

        let continued = state.effective(for: appended)

        #expect(continued.reveal.limit == 320)
        #expect(ContentRenderSlicer.slice(
            appended,
            limit: continued.reveal.limit).consumedUnits == 320)
    }

    @Test func sameDocumentVersionKeepsTheExistingRevealLimit() {
        let document = largeDocument(prefix: "same")
        var state = ContentDocumentRenderState()
        state = state.effective(for: document)
        state.reveal.revealNextPage(total: ContentRenderSlicer.unitCount(document))

        let continued = state.effective(for: document)

        #expect(continued.reveal.limit == 320)
    }

    @Test func reconstructedSameSourceResetsTheRevealLimit() {
        let original = largeDocument(prefix: "same")
        let reconstructed = ContentDocument(source: original.source, blocks: original.blocks)
        var state = ContentDocumentRenderState()
        state = state.effective(for: original)
        state.reveal.revealNextPage(total: ContentRenderSlicer.unitCount(original))

        let replacement = state.effective(for: reconstructed)

        #expect(original.renderVersion != reconstructed.renderVersion)
        #expect(replacement.reveal.limit == 160)
    }

    @Test func sourceReplacementDerivesAnInitialSliceBeforeStateMutation() {
        let original = largeDocument(prefix: "original")
        let replacement = largeDocument(prefix: "replacement")
        var state = ContentDocumentRenderState()
        state = state.effective(for: original)
        state.reveal.revealNextPage(total: ContentRenderSlicer.unitCount(original))

        let replacementState = state.effective(for: replacement)
        let replacementSlice = ContentRenderSlicer.slice(
            replacement,
            limit: replacementState.reveal.limit)

        #expect(state.reveal.limit == 320)
        #expect(replacementState.reveal.limit == 160)
        #expect(replacementSlice.consumedUnits == 160)
        #expect(replacementSlice.hasMore)
    }

    @Test func imageOnlyReplacementResetsTheRevealLimit() {
        let original = ContentDocument(
            source: "",
            blocks: Array(repeating: .image(ContentImage(data: Data([1]), mimeType: "image/png")), count: 500))
        let replacement = ContentDocument(
            source: "",
            blocks: Array(repeating: .image(ContentImage(data: Data([2]), mimeType: "image/png")), count: 500))
        var state = ContentDocumentRenderState()
        state = state.effective(for: original)
        state.reveal.revealNextPage(total: ContentRenderSlicer.unitCount(original))

        let replacementState = state.effective(for: replacement)

        #expect(replacementState.reveal.limit == 160)
        #expect(ContentRenderSlicer.slice(replacement, limit: replacementState.reveal.limit).consumedUnits == 160)
    }

    @Test func sameSourceStructuralReplacementResetsTheRevealLimit() {
        let original = ContentDocument(
            source: "shared",
            blocks: Array(repeating: .unsupported(label: "old"), count: 500))
        let replacement = ContentDocument(
            source: "shared",
            blocks: Array(repeating: .unsupported(label: "new"), count: 500))
        var state = ContentDocumentRenderState()
        state = state.effective(for: original)
        state.reveal.revealNextPage(total: ContentRenderSlicer.unitCount(original))

        let replacementState = state.effective(for: replacement)

        #expect(replacementState.reveal.limit == 160)
        #expect(ContentRenderSlicer.slice(replacement, limit: replacementState.reveal.limit).consumedUnits == 160)
    }
}

private func largeDocument(prefix: String) -> ContentDocument {
    MessageContentParser.parse((0..<500).map { "\(prefix) paragraph \($0)" }
        .joined(separator: "\n\n"))
}

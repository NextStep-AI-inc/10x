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
    }
}

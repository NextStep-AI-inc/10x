import Testing
import OmpKit
import SwiftUI
@testable import TenXApp

@Suite struct RendererPaginationTests {
    @Test func rendererPaginationPreservesExistingPreviews() {
        #expect(ToolSurfacePagination.console.visibleCount(total: 10_000) == 10)
        #expect(ToolSurfacePagination.collection.visibleCount(total: 10_000) == 8)
        #expect(ToolSurfacePagination.jsonChildren.visibleCount(total: 10_000) == 12)
    }

    @Test func sourceExpansionAddsOnePageAfterAnExtractorPreview() {
        var reveal = ProgressiveReveal(initialLimit: 12, pageSize: 200)
        #expect(SourceSurface.visibleLineCount(
            total: 2_000,
            previewLineLimit: 12,
            reveal: reveal) == 12)
        reveal.revealNextPage(total: 2_000)
        #expect(SourceSurface.visibleLineCount(
            total: 2_000,
            previewLineLimit: 12,
            reveal: reveal) == 212)
    }

    @Test func jsonChildrenNeverJumpFromPreviewToTotal() {
        var reveal = ToolSurfacePagination.jsonChildren
        reveal.revealNextPage(total: 10_000)
        #expect(reveal.visibleCount(total: 10_000) == 62)
    }

    @MainActor
    @Test func oversizedRendererSurfacesSnapshotInitialPages() throws {
        let console = (1...500).map { "console line \($0)" }.joined(separator: "\n")
        let collection = (1...150).map { index in
            ToolCollectionItem(
                id: "item-\(index)",
                label: "Collection item \(index)",
                detail: "Deterministic detail \(index)",
                reference: nil,
                state: nil)
        }
        let source = SourcePresentation(
            language: "swift",
            text: (1...500).map { "let value\($0) = \($0)" }.joined(separator: "\n"))
        let children = Dictionary(uniqueKeysWithValues: (1...200).map { index in
            ("field-\(index)", JSONValue.int(index))
        })
        let scalar = String(repeating: "scalar value ", count: 1_538) + "scalar"
        #expect(scalar.count == 20_000)

        try assertSnapshot(
            VStack(alignment: .leading, spacing: 16) {
                ToolSurfaceView(body: .console(command: "generate fixtures", output: console, exitCode: 0))
                ToolSurfaceView(body: .collection(collection))
                ToolSurfaceView(body: .source(source, previewLines: 20))
                ToolSurfaceView(body: .data(label: "JSON children", value: .object(children)))
                ToolSurfaceView(body: .data(label: "JSON scalar", value: .string(scalar)))
            }
            .frame(width: 720, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading),
            name: "renderer-pagination-initial",
            size: CGSize(width: 800, height: 2_400))
    }
}

import Foundation
import Testing
@testable import TenXApp

@Suite struct DiffRenderPresentationTests {
    @Test func diffSliceUsesOneBudgetAcrossFilesAndHunks() throws {
        let diff = try #require(largeDiff(fileCount: 4, changedLinesPerFile: 150))
        let presentation = DiffRenderPresentation(diff: diff)
        let slice = presentation.slice(limit: 200)

        #expect(slice.lines.count == 200)
        #expect(slice.hasMore)
        #expect(Set(slice.lines.map(\.fileID)).count > 1)
    }

    @Test func hiddenDiffRowsAreNotRequestedForTokenization() async throws {
        let source = DiffRenderPresentation(diff: try #require(
            largeDiff(fileCount: 1, changedLinesPerFile: 1_000)))
        let loader = await DiffPageLoader(tokenize: { text, _ in
            [SourceSpan(text: text, role: .plain)]
        })

        await loader.load(rows: Array(source.rows.prefix(200)))
        #expect(await loader.cachedLineCount == 200)
    }

    @Test func initialDiffCacheTokenizesOnlyTheFirstVisiblePage() async throws {
        let source = DiffRenderPresentation(diff: try #require(
            largeDiff(fileCount: 1, changedLinesPerFile: 1_000)))
        let initialRows = source.slice(limit: 1_000).rows
        let recorder = TokenizationRecorder()
        let loader = await DiffPageLoader(initialRows: initialRows, tokenize: { text, _ in
            recorder.record(text)
            return [SourceSpan(text: text, role: .plain)]
        })

        #expect(await loader.cachedLineCount == 200)
        #expect(recorder.count == 200)
        #expect(!recorder.contains("let value999 = 999"))
    }

    @Test func expandingCollapsedContextUsesOnlyOneFinitePage() throws {
        let context = (0..<500).map { " context\($0)" }.joined(separator: "\n")
        let diff = try #require(UnifiedDiffParser.parse("""
        --- a/App.swift
        +++ b/App.swift
        @@ -1,500 +1,500 @@
        \(context)
        """))
        let presentation = DiffRenderPresentation(diff: diff)
        let collapsed = try #require(presentation.rows.first { $0.collapsedContext != nil })
        let rows = presentation.rows(revealing: [collapsed.id: 200])

        #expect(rows.filter(\.isLine).count == 206)
        #expect(rows.first { $0.id == collapsed.id }?.collapsedContext?.count == 294)
    }
}

private final class TokenizationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []

    var count: Int {
        lock.withLock { texts.count }
    }

    func contains(_ text: String) -> Bool {
        lock.withLock { texts.contains(text) }
    }

    func record(_ text: String) {
        lock.withLock { texts.append(text) }
    }
}

private func largeDiff(fileCount: Int, changedLinesPerFile: Int) -> UnifiedDiff? {
    let raw = (0..<fileCount).map { file in
        let changes = (0..<changedLinesPerFile).map { line in
            "+let value\(line) = \(line)"
        }.joined(separator: "\n")
        return """
        diff --git a/File\(file).swift b/File\(file).swift
        --- a/File\(file).swift
        +++ b/File\(file).swift
        @@ -0,0 +1,\(changedLinesPerFile) @@
        \(changes)
        """
    }.joined(separator: "\n")
    return UnifiedDiffParser.parse(raw)
}

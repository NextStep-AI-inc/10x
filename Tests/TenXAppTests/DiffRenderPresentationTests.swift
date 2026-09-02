import Dispatch
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

    @Test func contextPageKeepsItsContinuationInTheFinalGlobalSlice() throws {
        let context = (0..<500).map { " context\($0)" }.joined(separator: "\n")
        let diff = try #require(UnifiedDiffParser.parse("""
        --- a/App.swift
        +++ b/App.swift
        @@ -1,500 +1,500 @@
        \(context)
        """))
        let presentation = DiffRenderPresentation(diff: diff)
        let collapsed = try #require(presentation.rows.first { $0.collapsedContext != nil })
        let expandedRows = presentation.rows(revealing: [collapsed.id: 200])
        let finalSlice = presentation.slice(rows: expandedRows, limit: 203)

        #expect(finalSlice.lines.count == 203)
        #expect(finalSlice.rows.first { $0.id == collapsed.id }?.collapsedContext?.visibleCount == 200)
        #expect(finalSlice.rows.first { $0.id == collapsed.id }?.collapsedContext?.count == 294)
    }

    @Test func contentReplacementResetsAndReprimesSameShapedRows() async throws {
        let original = DiffRenderPresentation(diff: try #require(singleLineDiff(text: "original")))
        let replacement = DiffRenderPresentation(diff: try #require(singleLineDiff(text: "replacement")))
        let originalRows = original.slice(limit: 200).rows
        let replacementRows = replacement.slice(limit: 200).rows
        let loader = await DiffPageLoader(
            contentID: original.contentID,
            initialRows: originalRows,
            tokenize: { text, _ in [SourceSpan(text: text, role: .plain)] })

        await loader.reset(contentID: replacement.contentID, initialRows: replacementRows)

        guard let replacementLine = replacementRows.first(where: { $0.isLine }) else {
            Issue.record("Expected replacement line")
            return
        }
        #expect(original.contentID != replacement.contentID)
        #expect(await loader.spans(for: replacementLine.id, contentID: replacement.contentID) == [
            SourceSpan(text: "replacement", role: .plain),
        ])
    }

    @Test func initialCacheDefersEveryRowAfterAnOversizedFirstLine() async throws {
        let source = DiffRenderPresentation(diff: try #require(additionsDiff(lines: [
            String(repeating: "a", count: 2_049),
            "deferred",
        ])))
        let recorder = TokenizationRecorder()
        let loader = await DiffPageLoader(initialRows: source.slice(limit: 200).rows, tokenize: { text, _ in
            recorder.record(text)
            return [SourceSpan(text: text, role: .plain)]
        })

        #expect(await loader.cachedLineCount == 0)
        #expect(recorder.count == 0)
    }

    @Test func initialCacheStopsAtTheTotalCharacterCeiling() async throws {
        let ceilingLine = String(repeating: "b", count: 2_048)
        let source = DiffRenderPresentation(diff: try #require(additionsDiff(lines: Array(
            repeating: ceilingLine,
            count: 8) + ["deferred"])))
        let recorder = TokenizationRecorder()
        let loader = await DiffPageLoader(initialRows: source.slice(limit: 200).rows, tokenize: { text, _ in
            recorder.record(text)
            return [SourceSpan(text: text, role: .plain)]
        })

        #expect(await loader.cachedLineCount == 8)
        #expect(recorder.count == 8)
        #expect(!recorder.contains("deferred"))
    }

    @Test func finalContextPageDoesNotRevealOrTokenizeTheChangedTail() async throws {
        let context = (0..<500).map { " context\($0)" }
        let tail = (0..<1_000).map { "tail\($0)" }
        let presentation = DiffRenderPresentation(diff: try #require(additionsAndContextDiff(
            context: context,
            additions: tail)))
        let collapsed = try #require(presentation.rows.first { $0.collapsedContext != nil })
        let visibleCount = try #require(collapsed.collapsedContext?.totalCount)
        let lineLimit = try #require(presentation.lineLimit(
            throughContext: collapsed.id,
            visibleCount: visibleCount))
        let rows = presentation.rows(revealing: [collapsed.id: visibleCount])
        let slice = presentation.slice(rows: rows, limit: lineLimit)
        let recorder = TokenizationRecorder()
        let loader = await DiffPageLoader(tokenize: { text, _ in
            recorder.record(text)
            return [SourceSpan(text: text, role: .plain)]
        })

        await loader.load(rows: slice.rows)

        #expect(lineLimit == 497)
        #expect(slice.lines.count == 497)
        #expect(!slice.lines.contains { $0.line.text == "tail0" })
        #expect(!recorder.contains("tail0"))
    }

    @Test func replacementAfterFullExpansionReturnsToTheInitialPage() throws {
        let original = DiffRenderPresentation(diff: try #require(additionsAndContextDiff(
            context: (0..<500).map { "context\($0)" },
            additions: (0..<1_000).map { "original\($0)" })))
        let replacement = DiffRenderPresentation(diff: try #require(additionsAndContextDiff(
            context: (0..<500).map { "context\($0)" },
            additions: (0..<1_000).map { "replacement\($0)" })))
        let collapsed = try #require(original.rows.first { $0.collapsedContext != nil })
        let contextCount = try #require(collapsed.collapsedContext?.totalCount)
        var state = DiffRenderState()
        state.reset(contentID: original.contentID)
        var contextReveal = ProgressiveReveal(initialLimit: 200, pageSize: 200)
        while contextReveal.canRevealMore(total: contextCount) {
            contextReveal.revealNextPage(total: contextCount)
        }
        state.contextReveals[collapsed.id] = contextReveal
        let expandedRows = original.rows(revealing: state.contextReveals.mapValues(\.limit))
        while state.reveal.canRevealMore(total: expandedRows.filter(\.isLine).count) {
            state.reveal.revealNextPage(total: expandedRows.filter(\.isLine).count)
        }

        state.reset(contentID: replacement.contentID)
        let replacementSlice = replacement.slice(
            rows: replacement.rows(revealing: state.contextReveals.mapValues(\.limit)),
            limit: state.reveal.limit)

        #expect(replacementSlice.lines.count == 200)
        #expect(replacementSlice.hasMore)
        #expect(state.contextReveals.isEmpty)
    }

    @Test func replacementDerivesItsInitialPageBeforeStateReset() throws {
        let original = DiffRenderPresentation(diff: try #require(additionsAndContextDiff(
            context: (0..<500).map { "context\($0)" },
            additions: (0..<1_000).map { "original\($0)" })))
        let replacement = DiffRenderPresentation(diff: try #require(additionsAndContextDiff(
            context: (0..<500).map { "context\($0)" },
            additions: (0..<1_000).map { "replacement\($0)" })))
        let collapsed = try #require(original.rows.first { $0.collapsedContext != nil })
        let contextCount = try #require(collapsed.collapsedContext?.totalCount)
        var state = DiffRenderState()
        state.reset(contentID: original.contentID)
        var contextReveal = ProgressiveReveal(initialLimit: 200, pageSize: 200)
        while contextReveal.canRevealMore(total: contextCount) {
            contextReveal.revealNextPage(total: contextCount)
        }
        state.contextReveals[collapsed.id] = contextReveal
        let expandedRows = original.rows(revealing: state.contextReveals.mapValues(\.limit))
        while state.reveal.canRevealMore(total: expandedRows.filter(\.isLine).count) {
            state.reveal.revealNextPage(total: expandedRows.filter(\.isLine).count)
        }

        let firstReplacementSlice = replacement.slice(using: state)

        #expect(state.contentID == original.contentID)
        #expect(firstReplacementSlice.lines.count == 200)
        #expect(firstReplacementSlice.hasMore)
        #expect(firstReplacementSlice.rows.first { $0.collapsedContext != nil }?.collapsedContext?.visibleCount == 0)
        #expect(!firstReplacementSlice.lines.contains { $0.line.text == "replacement194" })
    }

    @Test func cancelledOldTokenizationCannotPublishIntoReplacementContent() async throws {
        let original = DiffRenderPresentation(diff: try #require(singleLineDiff(text: "original")))
        let replacement = DiffRenderPresentation(diff: try #require(singleLineDiff(text: "replacement")))
        let originalRows = original.slice(limit: 200).rows
        let replacementRows = replacement.slice(limit: 200).rows
        guard let originalRow = originalRows.first(where: { $0.isLine }),
              let replacementRow = replacementRows.first(where: { $0.isLine }) else {
            Issue.record("Expected line rows for both diff contents")
            return
        }
        let gate = TokenizationGate()
        let loader = await DiffPageLoader(contentID: original.contentID, tokenize: { text, _ in
            if text == "original" {
                gate.block()
            }
            return [SourceSpan(text: text, role: .plain)]
        })
        let oldWork = Task {
            await loader.load(rows: [originalRow], contentID: original.contentID)
        }
        defer { gate.resume() }

        await waitUntil("old diff tokenization to start") { gate.hasStarted }
        await loader.reset(
            contentID: replacement.contentID,
            initialRows: [replacementRow])
        gate.resume()
        await oldWork.value

        #expect(await loader.spans(for: replacementRow.id, contentID: replacement.contentID) == [
            SourceSpan(text: "replacement", role: .plain),
        ])
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

private final class TokenizationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isStarted = false
    private let continuation = DispatchSemaphore(value: 0)

    var hasStarted: Bool { lock.withLock { isStarted } }

    func block() {
        lock.withLock { isStarted = true }
        continuation.wait()
    }

    func resume() {
        continuation.signal()
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

private func singleLineDiff(text: String) -> UnifiedDiff? {
    UnifiedDiffParser.parse("""
    --- a/App.swift
    +++ b/App.swift
    @@ -0,0 +1 @@
    +\(text)
    """)
}

private func additionsDiff(lines: [String]) -> UnifiedDiff? {
    UnifiedDiffParser.parse("""
    --- a/App.swift
    +++ b/App.swift
    @@ -0,0 +1,\(lines.count) @@
    \(lines.map { "+\($0)" }.joined(separator: "\n"))
    """)
}

private func additionsAndContextDiff(context: [String], additions: [String]) -> UnifiedDiff? {
    UnifiedDiffParser.parse("""
    --- a/App.swift
    +++ b/App.swift
    @@ -1,\(context.count) +1,\(context.count + additions.count) @@
    \(context.map { " \($0)" }.joined(separator: "\n"))
    \(additions.map { "+\($0)" }.joined(separator: "\n"))
    """)
}

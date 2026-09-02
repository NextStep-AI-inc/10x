import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Suite(.serialized)
struct RendererSaturationFixtureTests {
    @Test
    func tenThousandLineDiffKeepsSlicesAndTokenizationFinite() async throws {
        let raw = oversizedDiff(fileCount: 10, linesPerFile: 1_000)
        let diff = try #require(UnifiedDiffParser.parse(raw))
        let presentation = DiffRenderPresentation(diff: diff)
        var state = DiffRenderState(contentID: presentation.contentID)
        let initialSlice = presentation.slice(using: state)
        let work = RendererWorkRecorder()
        let loader = await DiffPageLoader(
            contentID: presentation.contentID,
            initialRows: initialSlice.rows,
            tokenize: { text, _ in
                work.record(text)
                return [SourceSpan(text: text, role: .plain)]
            })

        #expect(diff.files.count == 10)
        #expect(presentation.rows.filter(\.isLine).count == 10_000)
        #expect(diff.raw == raw)
        #expect(initialSlice.lines.count == 200)
        #expect(initialSlice.hasMore)
        #expect(await loader.cachedLineCount == 0)
        #expect(work.count == 0)

        await loader.load(rows: initialSlice.rows, contentID: presentation.contentID)

        #expect(await loader.cachedLineCount == 200)
        #expect(work.count == 200)
        #expect(work.mainThreadCount == 0)
        #expect(!work.contains("let file0Value200"))

        state.reveal.revealNextPage(total: 10_000)
        let expandedSlice = presentation.slice(using: state)
        await loader.load(rows: expandedSlice.rows, contentID: presentation.contentID)

        #expect(expandedSlice.lines.count == 400)
        #expect(expandedSlice.hasMore)
        #expect(await loader.cachedLineCount == 400)
        #expect(work.count == 400)
        #expect(work.mainThreadCount == 0)
        #expect(!work.contains("let file0Value400"))
        #expect(!work.contains("let file9Value999"))
    }

    @Test
    func tenThousandLineConsoleKeepsOneFinitePageAndFullCopyPayload() {
        let output = (0..<10_000).map { "console line \($0)" }.joined(separator: "\n")
        var lineReveal = ToolSurfacePagination.console
        let characterReveal = ProgressiveTextPresentation.initialReveal
        let initial = ConsoleRenderPresentation(
            output: output,
            lineLimit: lineReveal.limit,
            characterLimit: characterReveal.limit)

        #expect(initial.visibleText.hasSuffix("console line 9"))
        #expect(!initial.visibleText.contains("console line 10"))
        #expect(initial.accessibilityText == initial.visibleText)
        #expect(initial.lineProgressiveTotal == 110)
        #expect(initial.inspectedCharacterCount <= 6_049)
        #expect(initial.inspectedLineCount <= 111)
        #expect(initial.materializedCharacterCount <= 6_049)
        #expect(initial.copyText == output)

        lineReveal.revealNextPage(total: initial.lineProgressiveTotal)
        let expanded = ConsoleRenderPresentation(
            output: output,
            lineLimit: lineReveal.limit,
            characterLimit: characterReveal.limit)

        #expect(lineReveal.limit == 110)
        #expect(expanded.visibleText.hasSuffix("console line 109"))
        #expect(!expanded.visibleText.contains("console line 110"))
        #expect(expanded.lineProgressiveTotal == 210)
        #expect(expanded.inspectedCharacterCount <= 6_049)
        #expect(expanded.inspectedLineCount <= 211)
        #expect(output.hasPrefix("console line 0\n"))
        #expect(output.hasSuffix("console line 9999"))
    }

    @Test
    func hundredThousandCharacterConsoleLineScansAndRevealsFinitePrefixes() {
        let output = String(repeating: "x", count: 100_000)
        let lineReveal = ToolSurfacePagination.console
        var characterReveal = ProgressiveTextPresentation.initialReveal
        let initial = ConsoleRenderPresentation(
            output: output,
            lineLimit: lineReveal.limit,
            characterLimit: characterReveal.limit)

        #expect(initial.visibleText.count == 2_048)
        #expect(initial.accessibilityText.count == 2_048)
        #expect(initial.characterProgressiveTotal == 6_048)
        #expect(initial.lineProgressiveTotal == 1)
        #expect(initial.inspectedCharacterCount == 6_049)
        #expect(initial.inspectedLineCount == 1)
        #expect(initial.materializedCharacterCount == 6_049)

        characterReveal.revealNextPage(total: initial.characterProgressiveTotal)
        let expanded = ConsoleRenderPresentation(
            output: output,
            lineLimit: lineReveal.limit,
            characterLimit: characterReveal.limit)

        #expect(expanded.visibleText.count == 6_048)
        #expect(expanded.accessibilityText.count == 6_048)
        #expect(expanded.characterProgressiveTotal == 10_048)
        #expect(expanded.inspectedCharacterCount == 10_049)
        #expect(expanded.inspectedLineCount == 1)
        #expect(expanded.materializedCharacterCount == 10_049)
        #expect(expanded.copyText == output)
        #expect(output.count == 100_000)
        #expect(output.last == "x")
    }

    @Test
    func hundredThousandCharacterDiffSpanBoundsVisibleAndAccessibilityText() {
        let payload = String(repeating: "d", count: 100_000)
        let presentation = ProgressiveTextPresentation(
            text: payload,
            spans: [SourceSpan(text: payload, role: .plain)],
            characterLimit: ProgressiveTextPresentation.initialReveal.limit)

        #expect(presentation.spans.map(\.text).joined().count == 2_048)
        #expect(presentation.visibleText.count == 2_048)
        #expect(presentation.accessibilityText.count == 2_048)
        #expect(presentation.hasMore)
        #expect(payload.count == 100_000)
    }

    @Test
    func finalTextPageAdvertisesOnlyItsRemainingCharacters() {
        let payload = String(repeating: "f", count: 3_000)
        let presentation = ProgressiveTextPresentation(
            text: payload,
            characterLimit: ProgressiveTextPresentation.initialReveal.limit)

        #expect(presentation.visibleText.count == 2_048)
        #expect(presentation.progressiveTotal == 3_000)
        #expect(presentation.hasMore)
    }

    @Test
    func thousandItemCollectionKeepsOneFinitePageAndAllItems() {
        let items = (0..<1_000).map { index in
            ToolCollectionItem(
                id: "item-\(index)",
                label: "Item \(index)",
                detail: "Detail \(index)",
                reference: nil,
                state: nil)
        }
        var reveal = ToolSurfacePagination.collection

        #expect(items.count == 1_000)
        #expect(reveal.visibleCount(total: items.count) == 8)
        #expect(items.prefix(8).last?.id == "item-7")

        reveal.revealNextPage(total: items.count)

        #expect(reveal.visibleCount(total: items.count) == 58)
        #expect(items.prefix(58).last?.id == "item-57")
        #expect(items.last?.id == "item-999")
    }

    @Test
    func thousandEntryProgressHistoryKeepsOneFinitePageAndAllEntries() {
        let history = (0..<1_000).map { "Progress entry \($0)" }
        var reveal = ToolSurfacePagination.progressHistory

        #expect(reveal.visibleCount(total: history.count) == 8)
        #expect(history.prefix(8).last == "Progress entry 7")

        reveal.revealNextPage(total: history.count)

        #expect(reveal.visibleCount(total: history.count) == 58)
        #expect(history.prefix(58).last == "Progress entry 57")
        #expect(history.last == "Progress entry 999")
    }

    @Test
    func largeJSONKeepsChildrenAndScalarTextOnIndependentFinitePages() {
        let scalar = String(repeating: "s", count: 100_000)
        let children = Dictionary(uniqueKeysWithValues: (0..<5_000).map { index in
            (String(format: "field-%04d", index), JSONValue.int(index))
        })
        let value = JSONValue.object(children)
        var childReveal = ToolSurfacePagination.jsonChildren
        var scalarReveal = ToolSurfacePagination.jsonScalar

        #expect(children.count == 5_000)
        #expect(childReveal.visibleCount(total: children.count) == 12)
        #expect(scalar.count == 100_000)
        #expect(scalarReveal.visibleCount(total: scalar.count) == 2_000)

        childReveal.revealNextPage(total: children.count)
        scalarReveal.revealNextPage(total: scalar.count)

        #expect(childReveal.visibleCount(total: children.count) == 62)
        #expect(scalarReveal.visibleCount(total: scalar.count) == 6_000)
        #expect(String(scalar.prefix(6_000)).count == 6_000)
        #expect(value["field-4999"]?.intValue == 4_999)
        #expect(scalar.last == "s")
        #expect(DataTreeSurfaceLayout.maximumDepth == 6)
    }

    @Test
    func fiveThousandUnitDocumentKeepsGlobalAndSourceWorkFinite() async throws {
        let markdown = oversizedMarkdownDocument(unitsPerKind: 1_250)
        let document = MessageContentParser.parse(markdown)
        let source = try #require(document.blocks.first?.sourcePresentation)
        var state = ContentDocumentRenderState(document: document)
        let initialSlice = ContentRenderSlicer.slice(
            document,
            limit: state.reveal.visibleCount(total: ContentRenderSlicer.unitCount(document)))
        let initialSource = try #require(initialSlice.document.blocks.first?.sourcePresentation)
        let work = RendererWorkRecorder()
        let loader = await SourcePageLoader(
            contentID: source.contentID,
            initialLines: initialSource.lines,
            language: source.language,
            tokenize: { text, _ in
                work.record(text)
                return [SourceSpan(text: text, role: .plain)]
            })

        #expect(ContentRenderSlicer.unitCount(document) == 5_000)
        #expect(initialSlice.consumedUnits == 160)
        #expect(initialSlice.hasMore)
        #expect(initialSource.lines.count == 160)
        #expect(source.lines.count == 1_250)
        #expect(source.lines[0].rawText.count == 10_000)
        #expect(await loader.cachedLineCount == 0)
        #expect(work.count == 0)

        var lineReveal = ProgressiveReveal(initialLimit: 2_048, pageSize: 2_048)
        #expect(lineReveal.visibleCount(total: source.lines[0].rawText.count) == 2_048)
        lineReveal.revealNextPage(total: source.lines[0].rawText.count)
        #expect(lineReveal.visibleCount(total: source.lines[0].rawText.count) == 4_096)
        #expect(source.text.hasPrefix(source.lines[0].rawText))

        await loader.load(
            lines: initialSource.lines,
            language: source.language,
            contentID: source.contentID)
        #expect(await loader.cachedLineCount == 160)
        #expect(work.count == 160)
        #expect(work.mainThreadCount == 0)
        #expect(!work.contains("let sourceLine160"))

        state.reveal.revealNextPage(total: ContentRenderSlicer.unitCount(document))
        let expandedSlice = ContentRenderSlicer.slice(document, limit: state.reveal.limit)
        let expandedSource = try #require(expandedSlice.document.blocks.first?.sourcePresentation)
        await loader.load(
            lines: expandedSource.lines,
            language: source.language,
            contentID: source.contentID)

        #expect(expandedSlice.consumedUnits == 320)
        #expect(expandedSlice.hasMore)
        #expect(expandedSource.lines.count == 320)
        #expect(await loader.cachedLineCount == 320)
        #expect(work.count == 320)
        #expect(work.mainThreadCount == 0)
        #expect(!work.contains("let sourceLine320"))
    }

    @MainActor
    @Test
    func fiveMegabyteInlineMediaLoadsOnceOffMainAndKeepsDecodedPayload() async {
        let data = Data(repeating: 0xA5, count: 5 * 1_024 * 1_024)
        let encoded = data.base64EncodedString()
        let item = ToolMediaItem(
            id: "five-megabyte-inline",
            kind: .image,
            name: "fixture.bin",
            mimeType: "application/octet-stream",
            data: encoded,
            url: nil)
        let work = RendererWorkRecorder()
        let loader = ToolMediaLoader(decode: { item in
            await Task.detached {
                work.record("media")
                guard let encoded = item.data,
                      let decoded = Data(base64Encoded: encoded)
                else { return ToolMediaLoadState.unavailable }
                return .loaded(DecodedToolMedia(data: decoded, image: nil))
            }.value
        })

        #expect(work.count == 0)
        await loader.load(item)
        await loader.load(item)

        #expect(item.data == encoded)
        #expect(work.count == 1)
        #expect(work.mainThreadCount == 0)
        #expect(loader.loadedItemID == item.id)
        #expect(loader.decodedData?.count == 5 * 1_024 * 1_024)
        #expect(loader.decodedData == data)
    }

    @MainActor
    @Test
    func tenThousandInstallerLinesPublishOneBatchAndRevealOneOlderPage() {
        let scheduler = RendererLogFlushScheduler()
        let buffer = OnboardingInstallLogBuffer(scheduleFlush: scheduler.schedule)
        for index in 0..<10_000 {
            buffer.append("installer line \(index)")
        }

        #expect(buffer.totalCount == 0)
        #expect(scheduler.scheduledCount == 1)

        scheduler.fire()
        var reveal = ProgressiveReveal(initialLimit: 200, pageSize: 200)
        let initialTail = buffer.visibleTail(limit: reveal.visibleCount(total: buffer.totalCount))

        #expect(buffer.totalCount == 10_000)
        #expect(initialTail.count == 200)
        #expect(initialTail.first?.id == 9_800)
        #expect(initialTail.last?.id == 9_999)

        reveal.revealNextPage(total: buffer.totalCount)
        let expandedTail = buffer.visibleTail(limit: reveal.visibleCount(total: buffer.totalCount))

        #expect(expandedTail.count == 400)
        #expect(expandedTail.first?.id == 9_600)
        #expect(expandedTail.suffix(200).map(\.id) == initialTail.map(\.id))
        #expect(buffer.completeText.split(separator: "\n").count == 10_000)
        #expect(buffer.completeText.hasPrefix("installer line 0\n"))
        #expect(buffer.completeText.hasSuffix("installer line 9999"))
    }
}

private extension ContentBlock {
    var sourcePresentation: SourcePresentation? {
        guard case .source(let source) = self else { return nil }
        return source
    }
}

private final class RendererWorkRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var prefixes: [String] = []
    private var mainThreadCalls = 0

    var count: Int { lock.withLock { prefixes.count } }
    var mainThreadCount: Int { lock.withLock { mainThreadCalls } }

    func contains(_ prefix: String) -> Bool {
        lock.withLock { prefixes.contains(where: { $0.hasPrefix(prefix) }) }
    }

    func record(_ text: String) {
        let prefix = String(text.prefix(64))
        let isMainThread = Thread.isMainThread
        lock.withLock {
            prefixes.append(prefix)
            if isMainThread { mainThreadCalls += 1 }
        }
    }
}

@MainActor
private final class RendererLogFlushScheduler {
    private var action: (@MainActor () -> Void)?
    private(set) var scheduledCount = 0

    func schedule(_ action: @escaping @MainActor () -> Void) {
        scheduledCount += 1
        self.action = action
    }

    func fire() {
        let action = action
        self.action = nil
        action?()
    }
}

private func oversizedDiff(fileCount: Int, linesPerFile: Int) -> String {
    (0..<fileCount).map { file in
        let lines = (0..<linesPerFile).map { line in
            if file == 0, line == 0 {
                return "+" + String(repeating: "x", count: 2_049)
            }
            return "+let file\(file)Value\(line) = \(line)"
        }.joined(separator: "\n")
        return """
        diff --git a/File\(file).swift b/File\(file).swift
        --- a/File\(file).swift
        +++ b/File\(file).swift
        @@ -0,0 +1,\(linesPerFile) @@
        \(lines)
        """
    }.joined(separator: "\n")
}

private func oversizedMarkdownDocument(unitsPerKind: Int) -> String {
    let sourceLines = ([String(repeating: "x", count: 10_000)] +
        (1..<unitsPerKind).map { "let sourceLine\($0) = \($0)" })
        .joined(separator: "\n")
    let list = (0..<unitsPerKind).map { "- list item \($0)" }
        .joined(separator: "\n")
    let quote = (0..<unitsPerKind).map { "> # quote item \($0)" }
        .joined(separator: "\n")
    let tableRows = (0..<(unitsPerKind - 1)).map { "| row \($0) | value \($0) |" }
        .joined(separator: "\n")
    return """
    ```swift
    \(sourceLines)
    ```

    \(list)

    \(quote)

    | Name | Value |
    | --- | --- |
    \(tableRows)
    """
}

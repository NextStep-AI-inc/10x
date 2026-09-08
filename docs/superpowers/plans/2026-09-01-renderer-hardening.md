# Renderer Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure every untrusted renderer surface performs bounded work per publication and per user expansion while retaining complete copyable or saveable content.

**Architecture:** A pure `ProgressiveReveal` value supplies finite initial and page budgets to tool, source, diff, JSON, Markdown, and installer views. Expensive diff tokenization and media decoding move to cancellable page/item loaders, installer output publishes in batches, and provider activity uses a state-driven animation rather than a wall-clock timeline.

**Tech Stack:** Swift 6, SwiftUI, Observation, AppKit/ImageIO, Swift Testing, Xcode 17, macOS 15+

**Spec:** `docs/superpowers/specs/2026-09-01-renderer-hardening-design.md`

## Global Constraints

- This branch remains stacked on PR #18 until PR #18 merges; do not change PR #18.
- Never discard source payloads. Pagination changes rendered children only.
- Copy and Save always operate on the complete original payload.
- One activation reveals at most one finite page.
- Preserve the existing 10-line console and 8-item collection previews.
- Diff and Markdown use one global budget per surface, not one budget per nested section.
- Do not add dependencies.
- Do not hand-edit `10x.xcodeproj`; run `bundle exec ruby scripts/generate_xcodeproj.rb` after adding Swift files.
- Use existing typography, palette, `GhostActionStyle`, and accessibility patterns.

---

### Task 1: Shared Progressive Reveal Policy

**Files:**
- Create: `App/Design/ProgressiveReveal.swift`
- Create: `App/Design/ProgressiveRevealButton.swift`
- Create: `Tests/TenXAppTests/ProgressiveRevealTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` through the generator only

**Interfaces:**
- Produces: `ProgressiveReveal.init(initialLimit:pageSize:)`
- Produces: `visibleCount(total:)`, `remainingCount(total:)`, `nextPageCount(total:)`, `canRevealMore(total:)`, `revealNextPage(total:)`, and `collapse()`
- Produces: `ProgressiveRevealButton(reveal:total:noun:accessibilityNoun:)`

- [ ] **Step 1: Write failing policy tests**

```swift
import Testing
@testable import TenXApp

@Suite struct ProgressiveRevealTests {
@Test func progressiveRevealAddsOnlyOneFinitePage() {
    var reveal = ProgressiveReveal(initialLimit: 10, pageSize: 100)
    #expect(reveal.visibleCount(total: 10_000) == 10)
    #expect(reveal.nextPageCount(total: 10_000) == 100)
    reveal.revealNextPage(total: 10_000)
    #expect(reveal.visibleCount(total: 10_000) == 110)
}

@Test func progressiveRevealClampsTheFinalPageAndCollapses() {
    var reveal = ProgressiveReveal(initialLimit: 8, pageSize: 50)
    reveal.revealNextPage(total: 30)
    #expect(reveal.visibleCount(total: 30) == 30)
    #expect(!reveal.canRevealMore(total: 30))
    reveal.collapse()
    #expect(reveal.visibleCount(total: 30) == 8)
}

@Test func progressiveRevealClampsInvalidTotals() {
    let reveal = ProgressiveReveal(initialLimit: 10, pageSize: 20)
    #expect(reveal.visibleCount(total: -5) == 0)
    #expect(reveal.remainingCount(total: -5) == 0)
}
}
```

- [ ] **Step 2: Run the new tests and confirm the type is missing**

Run:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/progressiveRevealAddsOnlyOneFinitePage()'
```

Expected: compilation fails because `ProgressiveReveal` does not exist.

- [ ] **Step 3: Implement the pure policy**

```swift
struct ProgressiveReveal: Equatable, Sendable {
    let initialLimit: Int
    let pageSize: Int
    private(set) var limit: Int

    init(initialLimit: Int, pageSize: Int) {
        precondition(initialLimit > 0 && pageSize > 0)
        self.initialLimit = initialLimit
        self.pageSize = pageSize
        limit = initialLimit
    }

    func visibleCount(total: Int) -> Int {
        min(max(0, total), limit)
    }

    func remainingCount(total: Int) -> Int {
        max(0, total - visibleCount(total: total))
    }

    func nextPageCount(total: Int) -> Int {
        min(pageSize, remainingCount(total: total))
    }

    func canRevealMore(total: Int) -> Bool {
        remainingCount(total: total) > 0
    }

    mutating func revealNextPage(total: Int) {
        limit = visibleCount(total: total) + nextPageCount(total: total)
    }

    mutating func collapse() {
        limit = initialLimit
    }
}
```

Implement `ProgressiveRevealButton` as the one reusable control. Its primary label is `Show \(reveal.nextPageCount(total: total)) more \(noun)`; when fully expanded it offers `Show fewer`. Its accessibility label includes the surface-specific `accessibilityNoun`.

- [ ] **Step 4: Regenerate the project and run the policy tests**

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/ProgressiveRevealTests'
```

Expected: the three policy tests pass and project generation changes only generated file entries.

- [ ] **Step 5: Commit the shared policy**

```bash
git add App/Design/ProgressiveReveal.swift App/Design/ProgressiveRevealButton.swift Tests/TenXAppTests/ProgressiveRevealTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat(rendering): add progressive reveal policy"
```

---

### Task 2: Paginate Existing Tool, Source, and JSON Expansions

**Files:**
- Modify: `App/Tools/ToolSurfaceView.swift`
- Modify: `App/Design/SourceSurface.swift`
- Modify: `Tests/TenXAppTests/ToolContentExtractorTests.swift`
- Create: `Tests/TenXAppTests/RendererPaginationTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` through the generator only

**Interfaces:**
- Consumes: `ProgressiveReveal`
- Produces: `ToolSurfacePagination.console`, `.collection`, `.jsonChildren`, and `.jsonScalar` policies for testable constants
- Produces: `SourceSurface.visibleLineCount(total:previewLineLimit:reveal:)`
- Changes: console, collections, source, JSON children, and JSON scalars reveal one page per action

- [ ] **Step 1: Write failing pagination tests**

```swift
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
}
```

- [ ] **Step 2: Run the focused tests and confirm missing policies fail**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/rendererPaginationPreservesExistingPreviews()'
```

Expected: compilation fails because `ToolSurfacePagination` is missing.

- [ ] **Step 3: Replace Boolean expansion state with reveal counts**

Add testable constants:

```swift
enum ToolSurfacePagination {
    static let console = ProgressiveReveal(initialLimit: 10, pageSize: 100)
    static let collection = ProgressiveReveal(initialLimit: 8, pageSize: 50)
    static let jsonChildren = ProgressiveReveal(initialLimit: 12, pageSize: 50)
    static let jsonScalar = ProgressiveReveal(initialLimit: 2_000, pageSize: 4_000)
}
```

For console and collection views, replace `@State private var isShowingAll` with the matching reveal value and render `prefix(reveal.visibleCount(total:))`. Copy continues using `output` or `items`, not the visible slice.

For `SourceSurface`, initialize its reveal policy with `previewLineLimit ?? 200` and a 200-line page. Preserve the caller-provided smaller preview. Render only the visible prefix and use `ProgressiveRevealButton`.

For JSON children, each explicit node owns its own 12/50 reveal value. For long scalar strings, render a prefix bounded by the character reveal and keep `Copy value` bound to the full string. Use labels `Show 4,000 more characters` and `Show fewer`.

- [ ] **Step 4: Add oversized surface snapshots**

Add deterministic snapshot fixtures containing 500 console lines, 150 collection entries, 500 source lines, 200 JSON children, and a 20,000-character scalar. Snapshot the initial state only; behavior tests prove page increments.

- [ ] **Step 5: Regenerate and run focused tests and snapshots**

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/RendererPaginationTests'
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/ViewSnapshotTests'
```

Expected: all pagination and snapshot tests pass.

- [ ] **Step 6: Commit bounded tool expansions**

```bash
git add App/Tools/ToolSurfaceView.swift App/Design/SourceSurface.swift Tests/TenXAppTests/ToolContentExtractorTests.swift Tests/TenXAppTests/RendererPaginationTests.swift Tests/TenXAppTests/__Snapshots__ 10x.xcodeproj/project.pbxproj
git commit -m "perf(tools): paginate expanded output"
```

---

### Task 3: Page and Cache Diff Rendering

**Files:**
- Create: `App/Tools/DiffRenderPresentation.swift`
- Create: `App/Tools/DiffPageLoader.swift`
- Modify: `App/Tools/DiffView.swift`
- Create: `Tests/TenXAppTests/DiffRenderPresentationTests.swift`
- Modify: `Tests/TenXAppTests/UnifiedDiffParserTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` through the generator only

**Interfaces:**
- Consumes: `ProgressiveReveal(initialLimit: 200, pageSize: 200)`
- Produces: `DiffRenderPresentation.init(diff:)`, stable flattened `rows`, and `slice(limit:)`
- Produces: `@MainActor DiffPageLoader.load(rows:)` with cached `[DiffRenderRow.ID: [SourceSpan]]`
- Changes: `DiffView.body` consumes cached spans and never calls `SourceTokenizer.spans`

- [ ] **Step 1: Write failing global-budget tests**

```swift
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
```

- [ ] **Step 2: Run the focused tests and confirm missing presentation types fail**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/diffSliceUsesOneBudgetAcrossFilesAndHunks()'
```

Expected: compilation fails because `DiffRenderPresentation` is missing.

- [ ] **Step 3: Implement stable flattened rows and slicing**

Define a sendable row identity containing file index, hunk index, and source line index. The presentation flattens only display rows and section metadata; it does not tokenize them. `slice(limit:)` returns the first bounded line rows plus the file and hunk headers needed to render those rows.

Collapsed context remains one row. Revealing context uses its own 200-line `ProgressiveReveal`; one click appends at most 200 context lines.

- [ ] **Step 4: Implement cancellable page tokenization**

`DiffPageLoader` keeps a cache keyed by stable row ID. `load(rows:)` filters already cached rows, then uses `Task.detached` to tokenize only the missing page. Publish the complete page result on the main actor only if the task was not cancelled. Expose a deterministic tokenizer closure in the initializer for tests.

In `DiffView`, request tokenization when the visible row IDs change. Until a row is tokenized, render one plain span for that row; replace it with cached colored spans when the page completes. Remove the direct tokenizer call from `lineView`.

- [ ] **Step 5: Prove the old body path is gone and run tests**

```bash
! rg -n 'SourceTokenizer\.spans' App/Tools/DiffView.swift
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/DiffRenderPresentationTests'
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/UnifiedDiffParserTests'
```

Expected: grep finds no body tokenization and all diff tests pass.

- [ ] **Step 6: Commit paged diff rendering**

```bash
git add App/Tools/DiffRenderPresentation.swift App/Tools/DiffPageLoader.swift App/Tools/DiffView.swift Tests/TenXAppTests/DiffRenderPresentationTests.swift Tests/TenXAppTests/UnifiedDiffParserTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "perf(diff): tokenize one visible page at a time"
```

---

### Task 4: Apply One Global Budget to Assistant Documents

**Files:**
- Create: `App/Sessions/ContentRenderSlice.swift`
- Modify: `App/Sessions/ContentDocument.swift`
- Modify: `App/Sessions/MessageBlockView.swift`
- Modify: `App/Sessions/CodeBlockView.swift`
- Modify: `App/Design/SourceSurface.swift`
- Create: `Tests/TenXAppTests/ContentRenderSliceTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` through the generator only

**Interfaces:**
- Consumes: `ProgressiveReveal(initialLimit: 160, pageSize: 160)`
- Produces: `ContentRenderSlice(document:consumedUnits:hasMore:)`
- Produces: `ContentRenderSlicer.slice(_ document: ContentDocument, limit: Int)`
- Produces: `ContentRenderSlicer.unitCount(_ document: ContentDocument)` for the reveal total and deterministic tests
- Produces: `SourcePresentation.init(language:text:lines:)` so sliced source preserves token spans and original line numbers

- [ ] **Step 1: Write failing structure and global-budget tests**

```swift
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
}
}
```

- [ ] **Step 2: Run a focused test and confirm the slicer is missing**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/nestedDocumentUsesOneGlobalBudget()'
```

Expected: compilation fails because `ContentRenderSlicer` is missing.

- [ ] **Step 3: Implement the depth-first structure-preserving slicer**

Walk blocks in display order with one mutable remaining-unit count. Each visible paragraph, heading, list item, quote child, table header/body row, source line, divider, image, or unsupported block consumes one unit.

When the limit ends inside:

- a list, retain the current item and only the child-list prefixes already visited;
- a quote, retain the visible child-block prefix;
- a table, retain headers and the visible row prefix;
- a source block, construct a `SourcePresentation` from the visible original `SourceLine` values without re-tokenizing.

Return `hasMore` whenever any original unit was omitted. Empty structural shells are not emitted.

- [ ] **Step 4: Mount one reveal control at `ContentDocumentView`**

`ContentDocumentView` owns the 160/160 reveal state, obtains one slice, renders only `slice.document.blocks`, and shows `ProgressiveRevealButton` when `slice.hasMore`. Nested `ContentListView`, quote, table, and code views receive already sliced values and do not own independent reveal budgets.

Use the original document unit count as the button total. Streaming changes append hidden units without automatically changing the current reveal limit.

- [ ] **Step 5: Add a large mixed-document snapshot and run tests**

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/ContentRenderSliceTests'
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/ViewSnapshotTests'
```

Expected: all slicing tests pass and the snapshot ends with one bounded `Show more` control.

- [ ] **Step 6: Commit document budgeting**

```bash
git add App/Sessions/ContentRenderSlice.swift App/Sessions/ContentDocument.swift App/Sessions/MessageBlockView.swift App/Sessions/CodeBlockView.swift App/Design/SourceSurface.swift Tests/TenXAppTests/ContentRenderSliceTests.swift Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/__Snapshots__ 10x.xcodeproj/project.pbxproj
git commit -m "perf(markdown): bound nested document rendering"
```

---

### Task 5: Decode Tool Media Once Off the Main Actor

**Files:**
- Create: `App/Tools/ToolMediaLoader.swift`
- Modify: `App/Tools/ToolSurfaceView.swift`
- Create: `Tests/TenXAppTests/ToolMediaLoaderTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` through the generator only

**Interfaces:**
- Produces: `ToolMediaLoadState` with `.idle`, `.loading`, `.loaded(DecodedToolMedia)`, `.unavailable`, `.failed`
- Produces: `DecodedToolMedia(data: Data?, image: CGImage?)`
- Produces: `@MainActor ToolMediaLoader.load(_ item: ToolMediaItem)` and `cancel()`
- Changes: `MediaItemView` reads loader state; body does not decode base64 or construct an image from raw data

- [ ] **Step 1: Write failing one-load and cancellation tests**

```swift
@Suite struct ToolMediaLoaderTests {
@MainActor @Test func mediaLoaderDecodesOneImmutableItemOnce() async {
    let calls = ThreadSafeCounter()
    let loader = ToolMediaLoader(decode: { item in
        calls.increment()
        return .loaded(DecodedToolMedia(data: Data(item.id.utf8), image: nil))
    })
    let item = mediaItem(id: "image-1")

    await loader.load(item)
    await loader.load(item)
    #expect(calls.value == 1)
}

@MainActor @Test func mediaLoaderRejectsAnObsoleteResult() async {
    let gate = AsyncGate()
    let loader = ToolMediaLoader(decode: { item in
        if item.id == "slow" { await gate.wait() }
        return .loaded(DecodedToolMedia(data: Data(item.id.utf8), image: nil))
    })

    let slow = Task { await loader.load(mediaItem(id: "slow")) }
    await loader.load(mediaItem(id: "new"))
    await gate.open()
    await slow.value
    #expect(loader.loadedItemID == "new")
}
}

private final class ThreadSafeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private func mediaItem(id: String) -> ToolMediaItem {
    ToolMediaItem(
        id: id,
        kind: .image,
        name: "\(id).png",
        mimeType: "image/png",
        data: Data(id.utf8).base64EncodedString(),
        url: nil)
}
```

- [ ] **Step 2: Run the focused test and confirm loader types are missing**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/mediaLoaderDecodesOneImmutableItemOnce()'
```

Expected: compilation fails because `ToolMediaLoader` is missing.

- [ ] **Step 3: Implement the cancellable loader**

For inline base64 and local file URLs, use `Task.detached` to produce decoded `Data` and a `CGImage` through ImageIO. Keep the full decoded data for Save. Treat unsupported non-image data as loaded data with no image. Remote HTTP URLs continue through `AsyncImage` and bypass the loader.

Cache the last completed item ID and result. Calling `load` with that ID is a no-op. Starting a different ID cancels the prior task. Check cancellation and current identity before publishing state.

- [ ] **Step 4: Replace computed decoding in `MediaItemView`**

Store the loader with `@State`, start it with `.task(id: item.id)`, and render from `loader.state`. Delete `decodedData` and `localImage` computed properties. Save reads `loader.decodedData`; it never decodes again.

Keep unavailable, Open, Save, and error copy unchanged.

- [ ] **Step 5: Run media tests and verify no body decode remains**

```bash
! rg -n 'Data\(base64Encoded|NSImage\(data: decodedData' App/Tools/ToolSurfaceView.swift
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/ToolMediaLoaderTests'
```

Expected: grep finds no computed decode path and loader tests pass.

- [ ] **Step 6: Commit cached media loading**

```bash
git add App/Tools/ToolMediaLoader.swift App/Tools/ToolSurfaceView.swift Tests/TenXAppTests/ToolMediaLoaderTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "perf(media): decode tool previews once"
```

---

### Task 6: Remove Wall-Clock Provider Wheel Rendering

**Files:**
- Modify: `App/Providers/ProviderUsageWheelView.swift`
- Modify: `Tests/TenXAppTests/ProviderUsageRingGeometryTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`

**Interfaces:**
- Produces: `ProviderActivityAnimation.shouldPulse(activeCount:reduceMotion:isSceneActive:)`
- Changes: provider wheels use a one-second state animation and contain no `TimelineView`

- [ ] **Step 1: Write failing animation-gate tests**

```swift
@Test(arguments: [
    (3, false, true, true),
    (0, false, true, false),
    (3, true, true, false),
    (3, false, false, false),
])
func providerPulseRunsOnlyWhenUseful(
    activeCount: Int,
    reduceMotion: Bool,
    isSceneActive: Bool,
    expected: Bool
) {
    #expect(ProviderActivityAnimation.shouldPulse(
        activeCount: activeCount,
        reduceMotion: reduceMotion,
        isSceneActive: isSceneActive) == expected)
}
```

- [ ] **Step 2: Run the focused test and confirm the gate is missing**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/providerPulseRunsOnlyWhenUseful()'
```

Expected: compilation fails because `ProviderActivityAnimation` is missing.

- [ ] **Step 3: Replace `TimelineView` with a state-driven pulse**

Add `@Environment(\.scenePhase)` and `@State private var isPulseExpanded = false`. Compute the pure gate from activity, Reduce Motion, and `scenePhase == .active`. When enabled, set the state true under `.easeInOut(duration: 1).repeatForever(autoreverses: true)`; when disabled, set it false without a repeating animation.

Apply scale and opacity directly from `isPulseExpanded`. Reduce Motion retains the stable outline.

- [ ] **Step 4: Verify the timeline is gone and run wheel tests**

```bash
! rg -n 'TimelineView' App/Providers/ProviderUsageWheelView.swift
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/ProviderUsageRingGeometryTests'
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/providerUsageWheelSnapshot()'
```

Expected: no `TimelineView` remains in the provider wheel and tests pass.

- [ ] **Step 5: Commit the animation change**

```bash
git add App/Providers/ProviderUsageWheelView.swift Tests/TenXAppTests/ProviderUsageRingGeometryTests.swift Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/__Snapshots__
git commit -m "perf(providers): stop continuous wheel evaluation"
```

---

### Task 7: Batch and Paginate Installer Logs

**Files:**
- Create: `App/Onboarding/OnboardingInstallLogBuffer.swift`
- Modify: `App/Onboarding/OnboardingInstallStepView.swift`
- Create: `Tests/TenXAppTests/OnboardingInstallLogBufferTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` through the generator only

**Interfaces:**
- Produces: `@MainActor OnboardingInstallLogBuffer`
- Produces: `append(_:)`, `flush()`, `reset()`, `visibleTail(limit:)`, `completeText`, and `totalCount`
- Changes: output publishes no more than once per 100 ms during a burst and renders through `LazyVStack`

- [ ] **Step 1: Write failing retention and batching tests**

```swift
@Suite struct OnboardingInstallLogBufferTests {
@MainActor @Test func installerBufferRetainsAllLinesButPublishesInBatches() async {
    let scheduler = ManualLogFlushScheduler()
    let buffer = OnboardingInstallLogBuffer(scheduleFlush: scheduler.schedule)
    for index in 0..<1_000 { buffer.append("line \(index)") }

    #expect(buffer.totalCount == 0)
    #expect(scheduler.scheduledCount == 1)
    scheduler.fire()
    #expect(buffer.totalCount == 1_000)
    #expect(buffer.completeText.split(separator: "\n").count == 1_000)
}

@MainActor @Test func installerTailRevealsOlderLinesOnePageAtATime() {
    let scheduler = ManualLogFlushScheduler()
    let buffer = OnboardingInstallLogBuffer(scheduleFlush: scheduler.schedule)
    for index in 0..<1_000 { buffer.append("line \(index)") }
    scheduler.fire()

    #expect(buffer.visibleTail(limit: 200).first?.text == "line 800")
    #expect(buffer.visibleTail(limit: 400).first?.text == "line 600")
}
}

@MainActor private final class ManualLogFlushScheduler {
    private var action: (@MainActor () -> Void)?
    private(set) var scheduledCount = 0

    func schedule(_ action: @escaping @MainActor () -> Void) {
        scheduledCount += 1
        self.action = action
    }

    func fire() {
        action?()
        action = nil
    }
}
```

- [ ] **Step 2: Run a focused test and confirm the buffer is missing**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/installerBufferRetainsAllLinesButPublishesInBatches()'
```

Expected: compilation fails because `OnboardingInstallLogBuffer` is missing.

- [ ] **Step 3: Implement the observable buffer**

Retain all lines in an observation-ignored array. Expose only `totalCount` and a flush revision as observed state. The first append in an empty pending batch schedules one 100 ms flush; later appends join that batch. `flush()` cancels the scheduled handle, publishes the current count once, and preserves all text. `reset()` clears both retained and published state.

Use stable line IDs based on their absolute offset so adding older pages does not invalidate newer rows.

- [ ] **Step 4: Mount the buffer in onboarding**

Replace `[String]` state with the buffer and a 200/200 reveal. The scroll view uses `LazyVStack` over `visibleTail(limit:)`. The first page is the newest 200 lines; `Show 200 older lines` increases the tail count by one page. Add a Copy button bound to `completeText`.

Preserve the existing `initialLog` initializer used by snapshots by seeding and immediately flushing the buffer during initialization.

During install, append every raw line to the buffer but let the buffer publish batches. Call `flush()` before phase transitions on success, thrown failure, and cancellation. Scroll to the newest line when the published count changes and the user remains at the live tail.

- [ ] **Step 5: Run buffer tests and onboarding snapshots**

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/OnboardingInstallLogBufferTests'
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/onboardingInstallStepVerifyingSnapshot()'
```

Expected: all 1,000 lines remain copyable, only bounded tails render, and snapshots pass.

- [ ] **Step 6: Commit batched installer logs**

```bash
git add App/Onboarding/OnboardingInstallLogBuffer.swift App/Onboarding/OnboardingInstallStepView.swift Tests/TenXAppTests/OnboardingInstallLogBufferTests.swift Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/__Snapshots__ 10x.xcodeproj/project.pbxproj
git commit -m "perf(onboarding): batch and paginate install logs"
```

---

### Task 8: Integrated Oversized Fixtures and Release Verification

**Files:**
- Create: `Tests/TenXAppTests/RendererSaturationFixtureTests.swift`
- Modify: `docs/performance/2026-09-01-renderer-saturation-audit.md`
- Modify: `10x.xcodeproj/project.pbxproj` through the generator only

**Interfaces:**
- Consumes: every bounded renderer policy and loader from Tasks 1–7
- Produces: deterministic fixtures that assert each initial tree and each single expansion remain finite
- Produces: final verification evidence in the audit and PR body

- [ ] **Step 1: Add one integrated oversized fixture test per surface**

Create local values with at least:

- 10,000 diff lines across ten files;
- 10,000 console lines;
- 1,000 collection items;
- 5,000 JSON children plus a 100,000-character scalar;
- a Markdown document with 5,000 combined list, quote, table, and source units;
- a 5 MB inline media payload;
- 10,000 installer log lines.

Each test asserts the initial visible count and the visible count after exactly one expansion. No test asserts elapsed wall time; deterministic bounded-work assertions are the regression gate.

- [ ] **Step 2: Run the integrated fixture tests**

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/RendererSaturationFixtureTests'
```

Expected: all oversized fixtures pass without exposing the full total.

- [ ] **Step 3: Run formatting and the complete suite**

```bash
git diff --check origin/codex/fix-large-skill-freeze...HEAD
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
```

Expected: no whitespace errors and every test in every suite passes.

- [ ] **Step 4: Build the signed Release artifact**

```bash
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-renderer-hardening-release
codesign --verify --deep --strict /private/tmp/tenx-renderer-hardening-release/Build/Products/Release/10x.app
```

Expected: `** BUILD SUCCEEDED **` and codesign exits zero.

- [ ] **Step 5: Launch and profile the exact artifact**

Launch with:

```bash
open -n /private/tmp/tenx-renderer-hardening-release/Build/Products/Release/10x.app
```

Confirm the exact binary path, visible window, and oversized local fixtures. Sample CPU five times after each surface settles. Any surface that remains materially active gets a 10-second `sample` capture before further changes.

- [ ] **Step 6: Update audit evidence and commit verification fixtures**

Record exact suite count, Release path, CPU samples, residual limitations, and whether any main-thread sample was required in `docs/performance/2026-09-01-renderer-saturation-audit.md`.

```bash
git add Tests/TenXAppTests/RendererSaturationFixtureTests.swift docs/performance/2026-09-01-renderer-saturation-audit.md 10x.xcodeproj/project.pbxproj
git commit -m "test(rendering): cover oversized renderer fixtures"
```

- [ ] **Step 7: Push and update draft PR #19**

```bash
git push origin codex/harden-renderer-surfaces
gh api repos/NextStep-AI-inc/10x/pulls/19 -X PATCH -f body='## Summary
- paginate every previously unbounded renderer expansion
- cache diff tokenization and tool-media decoding
- batch installer output and stop continuous provider-wheel evaluation

## Verification
- [x] oversized renderer fixtures
- [x] full macOS test suite; exact count recorded in the audit
- [x] signed Release build and codesign verification
- [x] packaged-app CPU sampling; exact samples recorded in the audit

## Design and evidence
- docs/superpowers/specs/2026-09-01-renderer-hardening-design.md
- docs/performance/2026-09-01-renderer-saturation-audit.md

Stacked on PR #18. Do not merge until PR #18 lands and this PR is retargeted to main.'
```

Keep PR #19 draft until packaged UI verification and one review pass are complete. Do not merge or retarget it without Tanner's instruction.

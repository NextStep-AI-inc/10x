# Rich Chat and OMP Tool Surfaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved semantic assistant transcript and exhaustive reusable OMP tool-card system, then merge three independently verified slices into `main`.

**Architecture:** Extend the existing `TranscriptEventProcessor` path by normalizing rich message and tool presentation values when `TranscriptMessage` and `ToolPresentation` are created or updated. SwiftUI renders those immutable values through one document renderer, one two-corner tool contract, and a small set of source, console, collection, media, progress, and data-tree surfaces. Preserve current transcript identity, reconciliation, disclosure, and near-bottom scrolling behavior.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Foundation `AttributedString`, Swift Testing, Xcode snapshot tests, existing OmpKit `JSONValue`; no new dependency.

**Baseline note:** The clean `main` commit starts with two full-transcript snapshot byte mismatches and a timing-sensitive `mutationLockDetachesBeforeCloseAndBlocksReentrantActions()` failure. Every task below uses isolated tests. Final verification reruns the baseline failures separately and reports their pre-existing status.

---

## File map

### New files

- `App/Sessions/ContentDocument.swift`: immutable semantic block, inline, list, and table presentation values.
- `App/Design/SourceSurface.swift`: source presentation, lightweight tokenization, line gutters, wrapping, bounded disclosure, and copy controls.
- `App/Tools/ToolCardView.swift`: universal two-corner card renderer for normalized tool presentations.
- `App/Tools/ToolSurfaceView.swift`: semantic body renderer for document, source, diff, console, collection, media, progress, and data-tree bodies.
- `Tests/TenXAppTests/SourcePresentationTests.swift`: tokenizer and source-line behavior.
- `Tests/TenXAppTests/ToolCardRegistryTests.swift`: canonical, alias, adapter, MCP, and unknown route coverage.

### Modified files

- `App/Sessions/MessageContentParser.swift`: parse block Markdown into `ContentDocument` and normalize inline attributed content/references.
- `App/Sessions/TranscriptMessage.swift`: store the normalized document with the raw message.
- `App/Sessions/AssistantMessageContentView.swift`: render the stored document and remove the duplicate reference tray.
- `App/Sessions/MessageBlockView.swift`: render semantic blocks, nested lists, quotes, dividers, and tables.
- `App/Sessions/CodeBlockView.swift`: delegate fenced code to `SourceSurface`.
- `App/Sessions/TranscriptReference.swift`: expose safe inline reference parsing and custom file-link encoding/decoding.
- `App/Sessions/TranscriptReferenceView.swift`: share file-reference activation with inline attributed links.
- `App/Sessions/MessageBubbleView.swift`: use document identity and a wider continuous-document measure without changing user bubbles.
- `App/Sessions/TranscriptView.swift`: route all tool rows through `ToolCardView` and preserve transcript controls.
- `App/Tools/ToolPresentation.swift`: retain a normalized `ToolCardContent` updated with arguments, results, and phase.
- `App/Tools/ToolCardRegistry.swift`: explicit 32-tool catalog and compatibility routing.
- `App/Tools/ToolContentExtractor.swift`: normalize result envelopes, compact summaries, and semantic tool bodies.
- `App/Tools/ToolCardScaffold.swift`: compact header contract, lifecycle, primary object, disclosure, and shared error/empty behavior.
- `App/Tools/UnifiedDiff.swift`: make diff presentation values safe to carry inside normalized tool content.
- `App/Tools/DiffView.swift`: reuse source rows, wrap by default, and remove nested vertical scrolling.
- existing per-family card files: become thin compatibility wrappers until all call sites use `ToolCardView`, then delete if unreferenced.
- `Tests/TenXAppTests/MessageContentParserTests.swift`: semantic block, inline reference, and document-caching coverage.
- `Tests/TenXAppTests/TranscriptReferenceTests.swift`: custom inline link round trips and punctuation/path cases.
- `Tests/TenXAppTests/ToolContentExtractorTests.swift`: normalized result/body behavior for every family.
- `Tests/TenXAppTests/ToolDisclosureStateTests.swift`: attention-state defaults and stable user choices.
- `Tests/TenXAppTests/ViewSnapshotTests.swift`: real SwiftUI snapshots for rich content, source, tool families, fallback, and full transcript.
- `10x.xcodeproj/project.pbxproj`: add the new source and test files to their existing groups and targets.

---

### Task 1: Normalize semantic assistant documents

**Files:**
- Create: `App/Sessions/ContentDocument.swift`
- Modify: `App/Sessions/MessageContentParser.swift`
- Modify: `App/Sessions/TranscriptMessage.swift`
- Test: `Tests/TenXAppTests/MessageContentParserTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing semantic-document tests**

Replace the flat parser assertion and add nesting/table/task-list coverage using the desired API:

```swift
@Test func messageParserBuildsSemanticDocumentBlocks() {
    let document = MessageContentParser.parse("""
    # Result

    A **readable** paragraph.

    - first item
      - nested item
    - [x] finished item

    | File | State |
    | --- | --- |
    | App.swift | changed |

    ---

    > Keep the interface quiet.

    ```swift
    let answer = 10
    ```
    """)

    #expect(document.blocks.map(\.kind) == [
        .heading, .paragraph, .list, .table, .divider, .quote, .source,
    ])
    #expect(document.plainText.contains("nested item"))
    #expect(document.plainText.contains("let answer = 10"))
}

@Test func transcriptMessageNormalizesContentAtInitialization() {
    let message = TranscriptMessage(
        id: "message",
        raw: .object([
            "role": .string("assistant"),
            "content": .string("## Result\n\nRendered once."),
        ]),
        isFinal: true)

    #expect(message.document.blocks.map(\.kind) == [.heading, .paragraph])
    #expect(message.document.source == message.visibleText)
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:'TenXAppTests/messageParserBuildsSemanticDocumentBlocks()' -only-testing:'TenXAppTests/transcriptMessageNormalizesContentAtInitialization()'
```

Expected: compilation fails because `ContentDocument`, `ContentBlock.kind`, and `TranscriptMessage.document` do not exist.

- [ ] **Step 3: Add the immutable content model**

Create the following public shape in `ContentDocument.swift`; keep constructors internal to the app target:

```swift
import Foundation

struct ContentDocument: Equatable, Sendable {
    let source: String
    let blocks: [ContentBlock]

    var plainText: String { blocks.map(\.plainText).joined(separator: "\n") }
    static let empty = ContentDocument(source: "", blocks: [])
}

indirect enum ContentBlock: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case paragraph, heading, list, quote, table, divider, source, unsupported }
    case paragraph(InlineContent)
    case heading(level: Int, content: InlineContent)
    case list(ContentList)
    case quote([ContentBlock])
    case table(ContentTable)
    case divider
    case source(SourcePresentation)
    case unsupported(label: String)

    var kind: Kind {
        switch self {
        case .paragraph: .paragraph
        case .heading: .heading
        case .list: .list
        case .quote: .quote
        case .table: .table
        case .divider: .divider
        case .source: .source
        case .unsupported: .unsupported
        }
    }

    var plainText: String {
        switch self {
        case .paragraph(let content), .heading(_, let content):
            content.plainText
        case .list(let list):
            list.items.map { item in
                ([item.content.plainText] + item.children.flatMap { child in
                    child.items.map { $0.content.plainText }
                }).joined(separator: "\n")
            }.joined(separator: "\n")
        case .quote(let blocks):
            blocks.map(\.plainText).joined(separator: "\n")
        case .table(let table):
            ([table.headers] + table.rows).map { row in
                row.map(\.plainText).joined(separator: "\t")
            }.joined(separator: "\n")
        case .divider:
            ""
        case .source(let source):
            source.text
        case .unsupported(let label):
            label
        }
    }
}

struct InlineContent: Equatable, Sendable {
    let source: String
    let attributed: AttributedString
    var plainText: String { String(attributed.characters) }
}

struct ContentList: Equatable, Sendable {
    enum Style: Equatable, Sendable { case unordered, ordered(start: Int), task }
    let style: Style
    let items: [ContentListItem]
}

struct ContentListItem: Equatable, Sendable {
    let content: InlineContent
    let isChecked: Bool?
    let children: [ContentList]
}

struct ContentTable: Equatable, Sendable {
    let headers: [InlineContent]
    let rows: [[InlineContent]]
}

struct SourcePresentation: Equatable, Sendable {
    let language: String?
    let text: String
}
```

`SourcePresentation` is introduced in Task 3. For Task 1, place its small data-only definition beside `ContentDocument` and move the implementation without changing the API in Task 3.

- [ ] **Step 4: Replace the flat parser with deterministic block parsing**

Change `MessageContentParser.parse` to return `ContentDocument`. Parse in this order: blank lines, fenced code, headings, table header plus delimiter, divider, quote run, list run with indentation, then paragraph. Keep the existing unmatched-fence behavior by treating the opening fence and remaining lines as paragraph source.

```swift
enum MessageContentParser {
    static func parse(_ source: String) -> ContentDocument {
        var parser = Parser(source: source)
        return ContentDocument(source: source, blocks: parser.blocks())
    }

    static func inline(_ source: String) -> InlineContent {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        let attributed = (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source)
        return InlineContent(source: source, attributed: attributed)
    }
}
```

The private parser must retain original line order, use leading spaces to build child lists, normalize task markers `[ ]` and `[x]`, pad short table rows with empty cells, and never drop unmatched syntax.

- [ ] **Step 5: Store normalized content in each message**

Add a stored property and initialize it once from visible text:

```swift
struct TranscriptMessage: Identifiable, Equatable, Sendable {
    let id: String
    let role: TranscriptMessageRole
    let raw: JSONValue
    let timestamp: Date?
    let attribution: TranscriptResponseAttribution
    let isFinal: Bool
    let stopReason: String?
    let document: ContentDocument

    init(
        id: String,
        raw: JSONValue,
        timestamp: Date? = nil,
        attribution: TranscriptResponseAttribution = .none,
        isFinal: Bool
    ) {
        self.id = id
        role = switch raw["role"]?.stringValue {
        case "user": .user
        case "assistant": .assistant
        default: .other
        }
        self.raw = raw
        self.timestamp = Self.messageDate(raw) ?? timestamp
        self.attribution = TranscriptResponseAttribution(
            provider: raw["provider"]?.stringValue ?? attribution.provider,
            model: raw["model"]?.stringValue ?? attribution.model,
            mode: attribution.mode,
            agent: attribution.agent,
            modelRole: attribution.modelRole)
        self.isFinal = isFinal
        stopReason = raw["stopReason"]?.stringValue

        let text = Self.visibleText(from: raw)
        let fallback = if let error = raw["errorMessage"]?.stringValue, !error.isEmpty {
            error
        } else {
            switch stopReason?.lowercased() {
            case "error": "Response failed."
            case "aborted": "Response aborted."
            default: ""
            }
        }
        document = MessageContentParser.parse(text.isEmpty ? fallback : text)
    }

    var visibleText: String { document.source }
}
```

Do not parse in an accessor. `TranscriptReducer` and `TranscriptHistoryMapper` already construct messages on the processor path, so this moves work off the SwiftUI render path without adding another cache.

- [ ] **Step 6: Run semantic tests and the transcript processor tests**

Run:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:'TenXAppTests/messageParserBuildsSemanticDocumentBlocks()' -only-testing:'TenXAppTests/transcriptMessageNormalizesContentAtInitialization()' -only-testing:TenXAppTests/TranscriptEventProcessorTests -only-testing:TenXAppTests/TranscriptHistoryMapperTests
```

Expected: all selected tests pass.

- [ ] **Step 7: Commit**

```bash
git add App/Sessions/ContentDocument.swift App/Sessions/MessageContentParser.swift App/Sessions/TranscriptMessage.swift Tests/TenXAppTests/MessageContentParserTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat(chat): normalize semantic message content"
```

---

### Task 2: Make references truly inline

**Files:**
- Modify: `App/Sessions/TranscriptReference.swift`
- Modify: `App/Sessions/TranscriptReferenceView.swift`
- Modify: `App/Sessions/MessageContentParser.swift`
- Modify: `App/Sessions/AssistantMessageContentView.swift`
- Modify: `App/Sessions/MessageBlockView.swift`
- Modify: `App/Sessions/MessageBubbleView.swift`
- Test: `Tests/TenXAppTests/TranscriptReferenceTests.swift`
- Test: `Tests/TenXAppTests/MessageContentParserTests.swift`

- [ ] **Step 1: Write failing inline-reference tests**

```swift
@Test func inlineFileReferencesRoundTripThroughAttributedLinks() throws {
    let reference = TranscriptReference.file(path: "App/Foo.swift", line: 8)
    let url = try #require(reference.inlineURL)
    #expect(TranscriptReference(inlineURL: url) == reference)
}

@Test func inlineMarkdownKeepsReferencesInTheirWrittenPosition() {
    let content = MessageContentParser.inline(
        "Open `App/Foo.swift:8` and [the docs](https://example.com/docs).")
    let destinations = content.attributed.runs.compactMap { $0.link }.compactMap(TranscriptReference.init(inlineURL:))
    #expect(destinations == [
        .file(path: "App/Foo.swift", line: 8),
        .web(url: "https://example.com/docs", label: nil),
    ])
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run the two functions with `-only-testing`. Expected: failure because `inlineURL`, `init(inlineURL:)`, and inline run rewriting do not exist.

- [ ] **Step 3: Add lossless custom file-link encoding**

Use `URLComponents` with scheme `tenx-file`, percent-encoded path in a query item, and optional line query item. Web references retain their original HTTP(S) URL. Add `Sendable` to `TranscriptReference`.

```swift
extension TranscriptReference {
    var inlineURL: URL? {
        switch self {
        case .web(let value, _):
            return URL(string: value)
        case .file(let path, let line):
            var components = URLComponents()
            components.scheme = "tenx-file"
            components.host = "reference"
            components.queryItems = [URLQueryItem(name: "path", value: path)]
            if let line {
                components.queryItems?.append(URLQueryItem(name: "line", value: String(line)))
            }
            return components.url
        }
    }

    init?(inlineURL: URL) {
        if inlineURL.scheme == "http" || inlineURL.scheme == "https" {
            self = .web(url: inlineURL.absoluteString, label: nil)
            return
        }
        guard inlineURL.scheme == "tenx-file",
              let components = URLComponents(url: inlineURL, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              !path.isEmpty
        else { return nil }
        let line = components.queryItems?
            .first(where: { $0.name == "line" })?
            .value
            .flatMap(Int.init)
        self = .file(path: path, line: line)
    }

    static func parseInline(_ candidate: String, label: String? = nil) -> TranscriptReference? {
        parse(candidate, label: label, allowsRelativeFile: true)
    }
}
```

- [ ] **Step 4: Rewrite attributed links during normalization**

After Foundation parses inline Markdown, visit attributed runs. Convert relative markdown destinations and inline-code runs that contain file references into `tenx-file` links. Preserve all presentation intents. Plain HTTP(S) links remain links; invalid destinations remain visible text.

- [ ] **Step 5: Render blocks from `message.document` and intercept inline links**

`AssistantMessageContentView` must iterate `message.document.blocks`, remove `TranscriptReference.extract` and its `FlowLayout`, and install one `OpenURLAction`. The handler returns `.systemAction` for HTTP(S), and for `tenx-file` it uses the existing `FileReferenceResolver`, `FileReferenceActivation`, `IDEPreferenceStore`, and `FileOpenService`. Extract shared activation code from `TranscriptReferenceView` instead of copying it.

```swift
ForEach(Array(message.document.blocks.enumerated()), id: \.offset) { _, block in
    MessageBlockView(block: block)
}
.environment(\.openURL, OpenURLAction { url in
    referenceAction.open(url)
})
```

The shared action reports sanitized errors through the existing accessibility announcer. Text selection remains enabled, so inline references remain copyable without a duplicate tray.

- [ ] **Step 6: Render semantic blocks**

Update `MessageBlockView` to switch over every `ContentBlock` case. Nested lists recurse with a 20-point indentation step. `ViewThatFits(in: .horizontal)` tries a wrapped `Grid` table first and falls back to a local horizontal `ScrollView` only when needed. Quotes recursively render their child blocks. Divider uses the existing separator token.

- [ ] **Step 7: Run parser, reference, file-action, and accessibility tests**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TenXAppTests/MessageContentParserTests -only-testing:TenXAppTests/TranscriptReferenceTests -only-testing:TenXAppTests/FileReferenceActionPresentationTests -only-testing:TenXAppTests/AccessibilityLabelTests
```

Expected: all selected tests pass.

- [ ] **Step 8: Commit**

```bash
git add App/Sessions/TranscriptReference.swift App/Sessions/TranscriptReferenceView.swift App/Sessions/MessageContentParser.swift App/Sessions/AssistantMessageContentView.swift App/Sessions/MessageBlockView.swift App/Sessions/MessageBubbleView.swift Tests/TenXAppTests/TranscriptReferenceTests.swift Tests/TenXAppTests/MessageContentParserTests.swift
git commit -m "feat(chat): render references inline"
```

---

### Task 3: Add the reusable wrapped source surface

**Files:**
- Create: `App/Design/SourceSurface.swift`
- Create: `Tests/TenXAppTests/SourcePresentationTests.swift`
- Modify: `App/Sessions/ContentDocument.swift`
- Modify: `App/Sessions/CodeBlockView.swift`
- Modify: `App/Tools/DiffView.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing tokenizer and line-model tests**

```swift
@Test func sourcePresentationPreservesIndentationAndSemanticTokens() {
    let source = SourcePresentation(language: "swift", text: "  let count = 12 // rows")
    #expect(source.lines.count == 1)
    #expect(source.lines[0].plainText == "  let count = 12 // rows")
    #expect(source.lines[0].spans.map(\.role).contains(.keyword))
    #expect(source.lines[0].spans.map(\.role).contains(.number))
    #expect(source.lines[0].spans.map(\.role).contains(.comment))
}

@Test func unknownLanguageKeepsReadablePlainSource() {
    let source = SourcePresentation(language: "future-lang", text: "alpha  beta")
    #expect(source.lines[0].plainText == "alpha  beta")
    #expect(source.lines[0].spans == [.init(text: "alpha  beta", role: .plain)])
}
```

- [ ] **Step 2: Run both tests and verify RED**

Expected: compile failure because `SourceLine`, `SourceSpan`, and roles do not exist.

- [ ] **Step 3: Implement the data-only tokenizer**

Move `SourcePresentation` into `SourceSurface.swift` and define:

```swift
struct SourcePresentation: Equatable, Sendable {
    let language: String?
    let text: String
    let lines: [SourceLine]

    init(language: String?, text: String) {
        self.language = language
        self.text = text
        lines = SourceTokenizer.lines(text, language: language)
    }
}

struct SourceLine: Equatable, Sendable, Identifiable {
    let number: Int
    let spans: [SourceSpan]
    var id: Int { number }
    var plainText: String { spans.map(\.text).joined() }
}

struct SourceSpan: Equatable, Sendable {
    enum Role: Equatable, Sendable { case plain, keyword, type, string, number, comment }
    let text: String
    let role: Role
}
```

The scanner walks Unicode scalars once per line, preserves whitespace exactly,
recognizes language-specific comment markers and keyword sets, handles escaped
single/double-quoted strings, and falls back to one `.plain` span for unknown
languages. Do not add regular expressions or a dependency.

- [ ] **Step 4: Implement `SourceSurface`**

The view owns `isWrapped` and optional `isShowingAll` state. It renders a small
language label, Copy, and Wrap/Scroll controls; a fixed-width line-number gutter;
and one attributed `Text` per source line. Wrapped mode has no horizontal scroll.
Scroll mode wraps the rows in a horizontal `ScrollView` and fixes their ideal
width. Tool callers can pass a preview-line limit; assistant fenced code passes
`nil` so response content is never automatically hidden.

- [ ] **Step 5: Reuse the surface in fenced code and diffs**

`CodeBlockView` becomes a small wrapper around `SourceSurface`. `DiffView` keeps
its hunk/context-fold logic and old/new gutters, but builds the content column
from `SourceTokenizer` spans, defaults to wrapping, and removes the nested
vertical `ScrollView` and fixed hunk height.

- [ ] **Step 6: Add visual snapshots**

Add `wrappedSourceSurfaceSnapshot`, `scrollingSourceSurfaceSnapshot`, and update
`richAssistantMessageSnapshot` plus `structuredDiffSnapshot`. Fixtures must
include nested indentation, a long line, a comment, a string, and a number.

- [ ] **Step 7: Run source, parser, diff, and selected snapshot tests**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TenXAppTests/SourcePresentationTests -only-testing:TenXAppTests/UnifiedDiffParserTests -only-testing:'TenXAppTests/richAssistantMessageSnapshot()' -only-testing:'TenXAppTests/structuredDiffSnapshot()' -only-testing:'TenXAppTests/wrappedSourceSurfaceSnapshot()' -only-testing:'TenXAppTests/scrollingSourceSurfaceSnapshot()'
```

Expected: all selected tests pass after recording and visually inspecting the intentional new references.

- [ ] **Step 8: Build Release and integrate slice 1**

```bash
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
git add App/Design/SourceSurface.swift App/Sessions/ContentDocument.swift App/Sessions/CodeBlockView.swift App/Tools/DiffView.swift Tests/TenXAppTests/SourcePresentationTests.swift Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/ReferenceImages 10x.xcodeproj/project.pbxproj
git commit -m "feat(chat): add wrapped source surfaces"
```

Only after the selected tests and Release build pass, merge the branch tip into local `main` with `--no-ff`, then merge that `main` commit back into this branch before continuing. Abort the integration if `git diff --name-only main...HEAD` overlaps Tanner's uncommitted files.

---

### Task 4: Normalize the complete tool catalog

**Files:**
- Create: `Tests/TenXAppTests/ToolCardRegistryTests.swift`
- Modify: `App/Tools/ToolCardRegistry.swift`
- Modify: `App/Tools/ToolContentExtractor.swift`
- Modify: `App/Tools/ToolPresentation.swift`
- Modify: `App/Tools/UnifiedDiff.swift`
- Modify: `Tests/TenXAppTests/ToolContentExtractorTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing exhaustive routing tests**

```swift
@Test func registryExplicitlyRoutesEveryCanonicalOMPTool() {
    let canonical = [
        "read", "bash", "edit", "ast_grep", "ast_edit", "ask", "debug", "eval",
        "github", "glob", "grep", "lsp", "inspect_image", "browser", "computer",
        "checkpoint", "rewind", "security_scan", "task", "hub", "todo", "web_search",
        "write", "memory_edit", "retain", "recall", "reflect", "learn", "manage_skill",
        "yield", "goal", "think",
    ]
    #expect(canonical.count == 32)
    #expect(canonical.allSatisfy { ToolCardRegistry.kind(for: $0).isExplicit })
}

@Test func registryRoutesAliasesAdaptersAndOpenEndedTools() {
    #expect(ToolCardRegistry.kind(for: "search") == .grep)
    #expect(ToolCardRegistry.kind(for: "find") == .glob)
    #expect(ToolCardRegistry.kind(for: "apply_patch") == .edit)
    #expect(ToolCardRegistry.kind(for: "vibe_wait") == .vibe(.wait))
    #expect(ToolCardRegistry.kind(for: "mcp__figma_render") == .mcp(server: "figma", tool: "render"))
    #expect(ToolCardRegistry.kind(for: "future_tool") == .custom(name: "future_tool"))
}
```

- [ ] **Step 2: Run routing tests and verify RED**

Expected: compile/test failure because the current enum has only nine broad cases.

- [ ] **Step 3: Implement exact registry cases**

Define one enum case for each canonical name, associated adapter cases for resolution and Vibe, and associated MCP/custom cases. `normalizeName` lowercases only known canonical names/aliases and preserves extension names. `isExplicit` is false only for `.custom`.

- [ ] **Step 4: Write failing result-envelope and card-content tests**

Cover ordered text/image/resource blocks, structured details, duplicate text suppression, failed results, and one compact/body expectation per family:

```swift
@Test func toolResultEnvelopePreservesOrderedTypedBlocks() {
    let envelope = ToolResultEnvelope(result: .object([
        "content": .array([
            .object(["type": .string("text"), "text": .string("Found 2")]),
            .object(["type": .string("image"), "data": .string("AA=="), "mimeType": .string("image/png")]),
            .object(["type": .string("resource_link"), "name": .string("report"), "uri": .string("file:///tmp/report.txt")]),
        ]),
        "details": .object(["count": .int(2)]),
    ]))
    #expect(envelope.blocks.map(\.kind) == [.text, .image, .resource])
    #expect(envelope.details?["count"]?.intValue == 2)
}
```

- [ ] **Step 5: Implement normalized tool presentation values**

Add:

```swift
struct ToolCardContent: Equatable, Sendable {
    let title: String
    let verb: String
    let primary: String?
    let outcome: String?
    let reference: TranscriptReference?
    let body: ToolBody
}

indirect enum ToolBody: Equatable, Sendable {
    case document(ContentDocument)
    case source(SourcePresentation, previewLines: Int?)
    case diff(UnifiedDiff, fallbackPath: String?)
    case console(command: String?, output: String, exitCode: Int?)
    case collection([ToolCollectionItem])
    case media([ToolMediaItem], caption: ContentDocument?)
    case progress(ToolProgress)
    case data(label: String, value: JSONValue)
    case stack([ToolBody])
    case empty(String)
    case privateActivity
}
```

`ToolResultEnvelope` parses the result once. `ToolContentExtractor.card(name:arguments:result:phase:)` has an exhaustive switch over `ToolCardKind`. Familiar tool cases extract semantic fields; unfamiliar payload shapes still retain complete text/details in a bounded body.

Add `Sendable` conformance to `UnifiedDiff`, `UnifiedDiffFile`, `UnifiedDiffHunk`,
`UnifiedDiffLine`, and `UnifiedDiffDisplayRow` so `.diff` can remain a normal
value inside `ToolBody`.

- [ ] **Step 6: Refresh normalized content inside `ToolPresentation`**

Use a custom initializer with the existing call signature. Property observers on `name`, `arguments`, `result`, and `phase` call one private mutating refresh method. Existing reducer assignments therefore keep normalized content current without moving extraction into SwiftUI.

- [ ] **Step 7: Run registry, extractor, reducer, and history tests**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TenXAppTests/ToolCardRegistryTests -only-testing:TenXAppTests/ToolContentExtractorTests -only-testing:TenXAppTests/ToolEventReducerTests -only-testing:TenXAppTests/TranscriptHistoryMapperTests
```

Expected: all selected tests pass.

- [ ] **Step 8: Commit**

```bash
git add App/Tools/ToolCardRegistry.swift App/Tools/ToolContentExtractor.swift App/Tools/ToolPresentation.swift App/Tools/UnifiedDiff.swift Tests/TenXAppTests/ToolCardRegistryTests.swift Tests/TenXAppTests/ToolContentExtractorTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat(chat): normalize OMP tool presentations"
```

---

### Task 5: Build the shared two-corner card and semantic surfaces

**Files:**
- Create: `App/Tools/ToolCardView.swift`
- Create: `App/Tools/ToolSurfaceView.swift`
- Modify: `App/Tools/ToolCardScaffold.swift`
- Modify: `App/Sessions/TranscriptView.swift`
- Modify: `App/Tools/DiffView.swift`
- Modify: `App/Tools/ToolDisclosureState.swift`
- Test: `Tests/TenXAppTests/ToolDisclosureStateTests.swift`
- Test: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing header and lifecycle tests**

Add pure presentation assertions for collapsed text, attention defaults, empty output, and errors:

```swift
@Test func compactToolHeaderNamesObjectOutcomeAndLifecycle() {
    let header = ToolCardHeaderPresentation(
        content: ToolCardContent(title: "Read", verb: "Read", primary: "App.swift", outcome: "42 lines", reference: nil, body: .empty("Completed without output")),
        phase: .complete,
        duration: "0.3s")
    #expect(header.accessibilityLabel == "Read App.swift, 42 lines, Complete, 0.3 seconds")
}

@Test func attentionToolsDefaultExpandedAfterCompletion() {
    #expect(ToolDisclosureState.defaultExpanded(for: tool(id: "edit", name: "edit", phase: .complete)))
    #expect(ToolDisclosureState.defaultExpanded(for: tool(id: "proposal", name: "resolve", phase: .complete)))
    #expect(!ToolDisclosureState.defaultExpanded(for: tool(id: "read", name: "read", phase: .complete)))
}
```

- [ ] **Step 2: Run the tests and verify RED**

Expected: compile failure for `ToolCardHeaderPresentation` and failed proposal expectation.

- [ ] **Step 3: Tighten `ToolCardScaffold`**

The compact row renders disclosure, verb/title, inline primary object or reference, outcome, lifecycle, and duration on one wrapping-safe line. Subtitle text uses `.lineLimit(1, reservesSpace: false)` only when a native reference is not present. The entire leading row remains the disclosure target. Failed state uses red; all others use cyan. Keep the existing two-corner `CornerCard` unchanged.

- [ ] **Step 4: Implement `ToolSurfaceView`**

Switch exhaustively over `ToolBody`. Reuse `ContentDocumentView`, `SourceSurface`, and `DiffView`. Implement private focused renderers for:

- console: command header, complete output, exit label, preview disclosure, Copy;
- collection: semantic label/value/reference rows with compact-count disclosure;
- media: decode valid image data to `NSImage`, show dimensions/type, preserve invalid blocks in data fallback;
- progress: labeled stage/status/count rows followed by optional document;
- data: recursive object/array disclosure capped at depth six, stable sorted object keys, scalar copy, and one Copy raw action.

No surface owns a vertical `ScrollView`. Long values use `fixedSize(horizontal: false, vertical: true)` and `textSelection(.enabled)`.

- [ ] **Step 5: Route every transcript tool through `ToolCardView`**

Replace the large `TranscriptView` switch with:

```swift
case .tool(let presentation):
    ToolCardView(presentation: presentation)
```

`ToolCardView` passes normalized content into `ToolCardScaffold` and `ToolSurfaceView`. Existing specific card types may remain only as thin wrappers required by focused snapshots; remove unreferenced duplicates before Task 8.

- [ ] **Step 6: Add snapshots for source, console, collection, media/data fallback, and errors**

Fixtures must include narrow long values, multiline command output, a failed tool, a valid MCP text/resource result, and malformed image/details content.

- [ ] **Step 7: Run disclosure and selected visual tests**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TenXAppTests/ToolDisclosureStateTests -only-testing:'TenXAppTests/genericToolCardSnapshot()' -only-testing:'TenXAppTests/activityDisclosureSnapshot()' -only-testing:'TenXAppTests/structuredDiffSnapshot()'
```

Expected: all selected tests pass with visually inspected references.

- [ ] **Step 8: Commit**

```bash
git add App/Tools/ToolCardView.swift App/Tools/ToolSurfaceView.swift App/Tools/ToolCardScaffold.swift App/Sessions/TranscriptView.swift App/Tools/DiffView.swift App/Tools/ToolDisclosureState.swift Tests/TenXAppTests/ToolDisclosureStateTests.swift Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/ReferenceImages 10x.xcodeproj/project.pbxproj
git commit -m "feat(chat): unify semantic tool cards"
```

---

### Task 6: Prove the high-value developer tool flow and integrate slice 2

**Files:**
- Modify: `App/Tools/ToolContentExtractor.swift`
- Modify: `Tests/TenXAppTests/ToolContentExtractorTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`

- [ ] **Step 1: Add failing behavior tests for the primary developer tools**

Add separate tests for `read`, `write`, `edit`/`apply_patch`, `grep`, `glob`, `ast_grep`, `ast_edit`, `lsp`, `bash`, `eval`, `web_search`, `browser`, and `github`. Each test asserts the compact primary/outcome and exact `ToolBody` case. Include zero results, long output, partial result, failed result, and a multi-file diff.

- [ ] **Step 2: Run the new tests and verify RED**

Expected: at least the structural, LSP, eval, GitHub, and partial-result cases fail before their extractors are completed.

- [ ] **Step 3: Implement the minimum semantic extraction for each tool**

Use structured detail paths from OMP first and text parsing only as fallback. Search matches become referenced collection rows. File results select source, collection, or media based on content. Edit cards use `UnifiedDiff`. Bash/eval use console. Web/GitHub rows use native URLs. Never discard the original result if semantic extraction fails; use `.data` or `.document` fallback.

- [ ] **Step 4: Add one developer-flow snapshot**

Create a vertical transcript fixture containing collapsed Read, expanded Edit with wrapped highlighted hunks, grouped Grep results, running Bash output, and Web Search links. Render at 720 points and inspect hierarchy, spacing, corners, wrapping, and action order.

- [ ] **Step 5: Run primary tool tests, snapshots, and Release build**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TenXAppTests/ToolContentExtractorTests -only-testing:TenXAppTests/UnifiedDiffParserTests -only-testing:'TenXAppTests/developerToolFlowSnapshot()'
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: all selected tests and the Release build pass.

- [ ] **Step 6: Commit and integrate slice 2**

```bash
git add App/Tools/ToolContentExtractor.swift Tests/TenXAppTests/ToolContentExtractorTests.swift Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/ReferenceImages
git commit -m "feat(chat): present developer tool results"
```

After checking for overlap with Tanner's dirty main files, merge the verified tip into local `main` with `--no-ff`, then merge `main` back into the feature branch.

---

### Task 7: Complete all OMP, adapter, MCP, and fallback cards

**Files:**
- Modify: `App/Tools/ToolContentExtractor.swift`
- Modify: `App/Tools/ToolCardRegistry.swift`
- Modify: `Tests/TenXAppTests/ToolContentExtractorTests.swift`
- Modify: `Tests/TenXAppTests/ToolCardRegistryTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`

- [ ] **Step 1: Add a table-driven failing coverage test**

Build one fixture per remaining canonical tool: `ask`, `debug`, `inspect_image`, `computer`, `checkpoint`, `rewind`, `security_scan`, `task`, `hub`, `todo`, `goal`, `yield`, `think`, `memory_edit`, `retain`, `recall`, `reflect`, `learn`, and `manage_skill`. Assert a non-generic title/verb and the intended semantic body category from the approved design.

Add resolution-device fixtures for `resolve`, `reject`, and `propose`; all five Vibe names; an MCP tool with text/image/resource/details; an extension tool; and an unknown malformed tool.

- [ ] **Step 2: Run the coverage tests and verify RED**

Expected: remaining tools that still use generic document/data fallbacks fail their required body-category assertions.

- [ ] **Step 3: Complete explicit semantic mappings**

Implement each remaining switch case. `think` always maps to `.privateActivity` and never includes result text. Resolution devices show applied/discarded/proposed state and reason. Vibe routes to Hub-flavored progress. MCP labels split the server/tool prefix and preserve every supported content block. Malformed custom tools use depth-limited data and `Completed without output` when truly empty.

- [ ] **Step 4: Add grouped snapshots**

Add coordination/runtime, memory/skills, media/interaction, and MCP/fallback snapshots. Include running, complete, empty, and failed states, plus a long primary object at compact width.

- [ ] **Step 5: Run complete registry, extractor, disclosure, and grouped snapshot tests**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TenXAppTests/ToolCardRegistryTests -only-testing:TenXAppTests/ToolContentExtractorTests -only-testing:TenXAppTests/ToolDisclosureStateTests -only-testing:'TenXAppTests/coordinationToolCardsSnapshot()' -only-testing:'TenXAppTests/memoryToolCardsSnapshot()' -only-testing:'TenXAppTests/mediaToolCardsSnapshot()' -only-testing:'TenXAppTests/mcpFallbackToolCardsSnapshot()'
```

Expected: all selected tests pass.

- [ ] **Step 6: Commit**

```bash
git add App/Tools/ToolContentExtractor.swift App/Tools/ToolCardRegistry.swift Tests/TenXAppTests/ToolContentExtractorTests.swift Tests/TenXAppTests/ToolCardRegistryTests.swift Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/ReferenceImages
git commit -m "feat(chat): cover the complete OMP tool catalog"
```

---

### Task 8: Polish the complete transcript and remove superseded code

**Files:**
- Modify: `App/Sessions/TranscriptView.swift`
- Modify: `App/Sessions/MessageBubbleView.swift`
- Modify: `App/Sessions/AssistantMessageContentView.swift`
- Modify: `App/Tools/ToolCardScaffold.swift`
- Delete only if unreferenced: old per-tool card view files and flat-output helpers superseded by `ToolCardView`/`ToolSurfaceView`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add failing full-transcript layout assertions**

Update compact and wide fixtures to include rich prose, a nested list/table,
inline file/web references, wrapped code, collapsed routine cards, expanded
edit/running/error cards, an MCP fallback, and a long unbroken value. Add pure
assertions that assistant content can use the transcript column width and that
tool headers expose functional, singular/plural-safe labels.

- [ ] **Step 2: Run the new tests and verify RED**

Expected: snapshot and width/copy assertions fail against the old fixtures and 720-point assistant cap.

- [ ] **Step 3: Apply final layout and copy polish**

Use one transcript content width, retain readable line length through the
existing 860-point column, and allow block surfaces to use that width. Keep
user bubbles at their current cap. Tighten activity spacing so collapsed cards
read as rows while expanded bodies retain 10–14 point internal rhythm. Audit all
new labels against `writing-ui`: factual verbs, no performed intelligence, no
em dashes, correct singular/plural forms.

- [ ] **Step 4: Remove dead render paths**

Use `rg` to prove old per-tool card types and flat `BoundedToolOutputView` call
sites are unreferenced. Delete only proven dead files/types and their PBX entries.
Do not refactor composer, rail, providers, or unrelated snapshots.

- [ ] **Step 5: Record and visually inspect focused snapshots**

Run compact/wide, rich assistant, long wrapping, source, diff, developer flow,
error, and fallback snapshots. Inspect actual images for clipping, horizontal
runoff, duplicate references, corner consistency, status text, and action order.

- [ ] **Step 6: Run all transcript/tool tests**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TenXAppTests/MessageContentParserTests -only-testing:TenXAppTests/TranscriptReferenceTests -only-testing:TenXAppTests/SourcePresentationTests -only-testing:TenXAppTests/ToolCardRegistryTests -only-testing:TenXAppTests/ToolContentExtractorTests -only-testing:TenXAppTests/ToolDisclosureStateTests -only-testing:TenXAppTests/ToolEventReducerTests -only-testing:TenXAppTests/TranscriptEventProcessorTests -only-testing:TenXAppTests/TranscriptHistoryMapperTests -only-testing:TenXAppTests/TranscriptReducerTests
```

Expected: all selected tests pass.

- [ ] **Step 7: Commit**

```bash
git add App/Sessions App/Tools Tests/TenXAppTests 10x.xcodeproj/project.pbxproj
git commit -m "fix(chat): finish transcript wrapping and hierarchy"
```

---

### Task 9: Verify the production experience and integrate slice 3

**Files:**
- Modify if evidence requires a scoped fix: only files already listed in this plan
- Update: this plan's checkboxes and the branch handoff status

- [ ] **Step 1: Load the launch and verification skills**

Read `launching-local-builds`, `verifying-work`, and `reviewing-code` before launching or claiming completion.

- [ ] **Step 2: Build the production application**

```bash
xcodebuild clean build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Launch the exact Release artifact and confirm visibility**

Use the DerivedData path reported by `xcodebuild -showBuildSettings`, launch that `.app`, and confirm the 10x window is visible before interacting. Do not use a Debug build or port 3000.

- [ ] **Step 4: Drive a real developer session**

In the visible app, open or create a real OMP session and verify: long assistant prose; headings/lists/table; inline local file and web references; fenced code; Read; Edit; Grep/Glob; Bash output; Web Search or Browser; collapsed/expanded persistence; failed tool treatment; and resizing from compact to wide. Capture screenshots from the real Release build.

- [ ] **Step 5: Run automated verification**

Run the targeted transcript/tool suite from Task 8, the selected UI snapshots,
then the complete test target. Separately rerun the three known baseline
failures and compare them with the initial evidence. Do not update Tanner's
uncommitted `chat-full-*` references in the main checkout.

- [ ] **Step 6: Review the branch diff**

Invoke `reviewing-code`, inspect `git diff main...HEAD`, and fix only findings
that affect the approved transcript goal. Every fix starts with a failing test.
Rerun the relevant targeted test and Release build after a fix.

- [ ] **Step 7: Commit verification fixes and integrate**

If verification required changes:

```bash
git add App/Sessions App/Tools Tests/TenXAppTests 10x.xcodeproj/project.pbxproj
git commit -m "fix(chat): address transcript verification findings"
```

Confirm `git status --short` is empty, all relevant checks are green, and the
feature diff does not overlap Tanner's uncommitted main files. Merge the final
verified branch tip into local `main` with `--no-ff`. Do not discard, stage, or
overwrite any pre-existing main-checkout change.

- [ ] **Step 8: Record the handoff**

Report `DONE`, branch and merge SHAs, every command and result, screenshots from
the real Release build, the unavailable PR/CI limitation caused by no remote,
the known baseline failures, any skipped tool interaction that could not be
produced locally, and exact remaining checks for Tanner.

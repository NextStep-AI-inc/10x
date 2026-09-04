# Search-to-Match Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open a selected search result at its exact renderable transcript row, reveal older history and grouped tools through the caller, and highlight the matched user-message substring.

**Architecture:** The persistent index keeps its schema and stores only active-path text that the transcript can display. Search results carry the current query transiently when opened. A one-shot `TranscriptSearchRequest` owns the stable source entry ID, trimmed query, and nonce; a pure resolver maps that request to existing presentation rows by message lineage or tool-call ID and never falls back to another text match.

**Tech Stack:** Swift 6, SwiftUI, Foundation string folding/search, OmpKit session parsing, Swift Testing

---

### Task 1: Active-path, display-safe search documents

**Files:**
- Modify: `App/Search/SessionSearchDocumentBuilder.swift`
- Modify: `Tests/TenXAppTests/SessionSearchServiceTests.swift`

- [ ] **Step 1: Write failing search-index regression tests**

Add Swift Testing cases that build branched fixtures and mixed assistant content. Assert inactive-branch text, private reasoning, JSON argument keys, and tool calls without stable IDs are absent; assert visible message text and tool argument values remain searchable; assert tool results and calls resolve to their real `toolCallId`/block `id`.

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -configuration Debug -derivedDataPath /tmp/10x-search-tdd -only-testing:TenXAppTests/searchExcludesInactiveBranchEntries -only-testing:TenXAppTests/searchIndexesOnlyRenderableContent`

Expected: FAIL because the builder scans `parsed.entries`, recursively indexes object keys/private blocks, and uses the source message entry ID for tools.

- [ ] **Step 3: Implement the minimum document mapping**

Iterate `SessionTree.activePath(of:)`. Emit message documents from `TranscriptMessage.visibleText(from:)` only when displayable. Emit one tool document per renderable tool call using its inner stable ID, name, and flattened argument values; let a tool-result message contribute its display-safe result text under `toolCallId` only when there is no corresponding call document. Keep the existing database shape and normalization.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run the same selectors. Expected: PASS.

### Task 2: One-shot request and stable row resolver

**Files:**
- Create: `App/Sessions/TranscriptSearchRequest.swift`
- Create: `App/Sessions/TranscriptSearchResolver.swift`
- Create: `Tests/TenXAppTests/TranscriptSearchResolverTests.swift`

- [ ] **Step 1: Write failing resolver tests**

Cover a base assistant entry split around tools, a user entry, a grouped tool, a missing/deleted entry, and case/diacritic-insensitive matching. Assert the returned row ID is the actual `TranscriptPresentationRow.id`, grouped tools return their owning group ID, and stale requests return `nil` rather than another row containing the same text.

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -configuration Debug -derivedDataPath /tmp/10x-search-tdd -only-testing:TenXAppTests/transcriptSearchResolvesSplitMessageLineage -only-testing:TenXAppTests/transcriptSearchResolvesGroupedTool -only-testing:TenXAppTests/transcriptSearchDoesNotFallbackFromMissingTarget`

Expected: build failure because the request and resolver do not exist.

- [ ] **Step 3: Implement request and resolver**

Create a failable request initializer requiring a nonempty entry ID and trimmed query, plus an injectable UUID nonce for deterministic tests. Resolve messages only when `renderLineageKey.baseMessageID` equals the requested entry and that exact row contains the folded query. Resolve tools only by `ToolPresentation.id`; return a group ID for hidden grouped rows so the caller can expand before scrolling.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run the same selectors. Expected: PASS.

### Task 3: Preserve the query and render exact user-message highlights

**Files:**
- Modify: `App/Search/SearchResult.swift`
- Modify: `App/Search/SearchModalView.swift`
- Modify: `App/Sessions/TranscriptTextSegments.swift`
- Modify: `App/Sessions/MessageBubbleView.swift`
- Modify: `Tests/TenXAppTests/MessageBubbleViewTests.swift`

- [ ] **Step 1: Write failing query/highlight tests**

Assert an opened result receives the trimmed modal query without changing persistent search storage, and assert case/diacritic-insensitive match ranges point to the exact source substring while unmatched and empty queries produce no ranges.

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -configuration Debug -derivedDataPath /tmp/10x-search-tdd -only-testing:TenXAppTests/searchResultCopiesOpeningQuery -only-testing:TenXAppTests/transcriptHighlightFindsExactFoldedSubstring`

Expected: build failure because the transient query and highlight API do not exist.

- [ ] **Step 3: Implement query copying and segmented highlight rendering**

Add a default-empty transient `query` to `SearchResult` plus a copy helper. Route Return, Open session, and double-click through one helper that copies `model.query`. Add a Foundation range helper and render matched ranges with the app's existing yellow emphasis while retaining bounded text segments. Pass the query into `MessageBubbleView` through an optional argument so existing callers remain source-compatible.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the same selectors. Expected: PASS.

### Task 4: Parent integration handoff

**Files:**
- No edits outside owned paths

- [ ] **Step 1: Provide exact integration snippets**

Give the parent the calls needed to turn an opened `SearchResult` into `TranscriptSearchRequest`, install it on the selected session controller, wait until complete history is loaded, resolve against `TranscriptPresentationRow.rows(from:)`, expand `resolution.groupID`, unlock following, and center-scroll to `resolution.rowID`.

- [ ] **Step 2: Report verification boundaries**

List exact Swift Testing function selectors with `()` and identify build/UI verification as parent-owned. Do not regenerate the project or run shared final build destinations.

# Renderer Saturation Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep large displayed skill messages ordered ahead of the assistant response without allowing any stable transcript row to be repeatedly laid out until the macOS UI thread reaches 100% CPU.

**Architecture:** Treat displayed custom messages as complete boundary events, then render arbitrary plain transcript text as several bounded SwiftUI `Text` nodes inside one visually contiguous row. Isolate stable message and tool rows from unrelated streaming snapshots, and make automatic stream-follow scrolling non-animated so 50 ms publications cannot stack 150 ms layout animations. Record independent renderer hazards separately and change them only when the packaged repro still identifies them.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing, Xcode Release builds, macOS `sample`/`ps` profiling.

---

### Task 1: Preserve the displayed skill boundary

**Files:**
- Modify: `Tests/TenXAppTests/TranscriptReducerTests.swift`
- Modify: `App/Sessions/TranscriptReducer.swift`

- [ ] **Step 1: Write the failing ordering test**

Add a test that consumes a full displayed `custom` `skill-prompt` message followed by an assistant `message_start`. Assert that the reducer retains two messages, keeps the skill first, preserves its complete text, and marks the skill final before the assistant starts.

```swift
@Test func aDisplayedSkillMessageCompletesBeforeTheAssistantStarts() {
    var reducer = TranscriptReducer()
    let skill = JSONValue.object([
        "id": .string("skill-1"),
        "role": .string("custom"),
        "customType": .string("skill-prompt"),
        "display": .bool(true),
        "content": .string("# Skill\n\n" + String(repeating: "Instruction line.\n", count: 240)),
    ])
    let assistant = JSONValue.object([
        "id": .string("assistant-1"),
        "role": .string("assistant"),
        "content": .string("Starting work."),
    ])

    _ = reducer.consume(.event(type: "message_start", payload: .object(["message": skill])))
    _ = reducer.consume(.event(type: "message_start", payload: .object(["message": assistant])))

    let messages = reducer.items.compactMap { item -> TranscriptMessage? in
        guard case .message(let message) = item else { return nil }
        return message
    }
    #expect(messages.map(\.id) == ["skill-1", "assistant-1"])
    #expect(messages[0].visibleText == skill["content"]?.stringValue)
    #expect(messages[0].isFinal)
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/TranscriptReducerTests
```

Expected: FAIL because the second `message_start` currently replaces the still-inflight displayed custom message.

- [ ] **Step 3: Complete displayed custom messages atomically**

Add a narrow role predicate to `TranscriptMessage` or `TranscriptReducer`. In the `message_start` branch, displayed `custom` and `hookMessage` payloads must be normalized with `isFinal: true`, inserted before later messages, and removed from `inflightMessageID` / `inflightItemIDs` immediately. Ordinary assistant streaming remains unchanged.

- [ ] **Step 4: Run the targeted test and verify GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit the boundary fix**

```bash
git add App/Sessions/TranscriptReducer.swift Tests/TenXAppTests/TranscriptReducerTests.swift
git commit -m "fix(transcript): finalize displayed skill messages"
```

### Task 2: Bound arbitrary transcript text layout

**Files:**
- Create: `App/Sessions/TranscriptTextSegments.swift`
- Modify: `App/Sessions/MessageBubbleView.swift`
- Modify: `Tests/TenXAppTests/MessageBubbleViewTests.swift`
- Regenerate: `10x.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing segmentation tests**

Test a skill-shaped string with headings, blank lines, a long paragraph, and an unbroken token. Require more than one segment, require every segment to stay within the declared character budget, and require `segments.map(\.text).joined()` to equal the original byte-for-byte. Add a short-text case that remains one segment.

```swift
@Test func skillTextSegmentsAreBoundedAndLossless() {
    let source = "# Skill\n\n" + String(repeating: "Follow this instruction carefully. ", count: 180)
    let segments = TranscriptTextSegments.make(source, maximumCharacters: 1_024)

    #expect(segments.count > 1)
    #expect(segments.allSatisfy { $0.text.count <= 1_024 })
    #expect(segments.map(\.text).joined() == source)
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/MessageBubbleViewTests
```

Expected: compile failure because `TranscriptTextSegments` does not exist.

- [ ] **Step 3: Implement the lossless segmenter and view**

Create a value-type segmenter that advances through `String.Index`, prefers a newline or whitespace boundary inside the maximum, and hard-splits only an unbroken token. Give segments stable integer offsets. Add one small `TranscriptPlainTextView` that renders the segments in a zero-spacing leading `VStack`; the enclosing message remains one transcript row and arrives atomically.

- [ ] **Step 4: Route user and custom transcript text through the bounded view**

Replace the raw user and `other` role `Text(message.visibleText)` calls with `TranscriptPlainTextView`. Keep fonts, colors, selection, bubble padding, and background unchanged. Do not render the skill as rich Markdown; its raw monospace appearance is part of the current UI.

- [ ] **Step 5: Regenerate the Xcode project**

Run:

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
```

Expected: the generated project includes `TranscriptTextSegments.swift`; no manual project edits.

- [ ] **Step 6: Run the targeted tests and verify GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 7: Commit the bounded text renderer**

```bash
git add App/Sessions/TranscriptTextSegments.swift App/Sessions/MessageBubbleView.swift Tests/TenXAppTests/MessageBubbleViewTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "fix(transcript): bound plain text layout"
```

### Task 3: Stop unrelated stream updates from relaying stable rows

**Files:**
- Modify: `App/Sessions/MessageBubbleView.swift`
- Modify: `App/Tools/ToolCardView.swift`
- Modify: `App/Sessions/TranscriptView.swift`
- Modify: `Tests/TenXAppTests/MessageBubbleViewTests.swift`
- Modify: `Tests/TenXAppTests/TranscriptPresentationRowTests.swift`

- [ ] **Step 1: Write failing equality and scroll-policy tests**

Require two message views with identical rendered content but unrelated raw bookkeeping to compare equal. Require changed text or finality to compare unequal. Require automatic follow while `.streaming` to use an immediate scroll while the explicit Jump to latest action remains eligible for animation.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/MessageBubbleViewTests -only-testing:TenXAppTests/TranscriptPresentationRowTests
```

Expected: FAIL because the row-level equality and automatic-follow policy do not exist.

- [ ] **Step 3: Add stable render boundaries**

Make `MessageBubbleView` equatable on the message identity, role, normalized document, visible text, finality, and response metadata inputs, then mount it with `.equatable()` from `TranscriptView`. Apply the same boundary to `ToolCardView` using `ToolPresentation` so a large completed diff or decoded tool result does not re-tokenize when a later assistant message streams.

- [ ] **Step 4: Make stream-follow scrolling immediate**

Split the scroll helper into automatic and explicit intents. Automatic row and activity following must call `proxy.scrollTo` without animation during streaming publications. The user-triggered Jump to latest button may keep the existing 0.15 second animation when Reduce Motion is off.

- [ ] **Step 5: Run the focused tests and verify GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 6: Commit row isolation**

```bash
git add App/Sessions/MessageBubbleView.swift App/Tools/ToolCardView.swift App/Sessions/TranscriptView.swift Tests/TenXAppTests/MessageBubbleViewTests.swift Tests/TenXAppTests/TranscriptPresentationRowTests.swift
git commit -m "perf(transcript): isolate stable rows during streaming"
```

### Task 4: Audit the remaining renderer budget

**Files:**
- Create: `docs/performance/2026-09-01-renderer-saturation-audit.md`

- [ ] **Step 1: Record evidence and classify every dynamic surface**

Document the captured frozen-process evidence (`99% CPU`, approximately `905 MB` footprint, and main-thread AttributeGraph/LazyVStack layout recursion) without copying session content. Inventory transcript messages, rich content blocks, source, console, diff, data tree, media, onboarding logs, command browser, side rail, and provider usage wheels.

- [ ] **Step 2: Distinguish existing guardrails from uncovered hazards**

Record existing preview/depth limits for source, console, collections, JSON trees, images, and rail/browser virtualization. Flag independent risks with evidence:

- `MediaItemView` decodes base64/`NSImage` in computed view properties.
- `DiffView` tokenizes visible lines inside `body` and edits start expanded.
- `ProviderUsageWheelView` redraws an active pulse at 30 FPS.
- `OnboardingInstallStepView` retains and renders an unbounded installation log.
- Rich Markdown lists/tables can create unbounded child counts, although ordinary paragraphs are already separate text nodes.

Do not change these independent subsystems in this PR unless the packaged transcript repro remains hot after Tasks 1–3.

- [ ] **Step 3: Commit the audit**

```bash
git add docs/performance/2026-09-01-renderer-saturation-audit.md
git commit -m "docs: audit renderer saturation risks"
```

### Task 5: Verify the packaged application under load

**Files:**
- Modify: PR #18 body with exact evidence

- [ ] **Step 1: Run the full test suite**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
```

Expected: all tests pass.

- [ ] **Step 2: Build a fresh Release artifact**

```bash
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-renderer-saturation-release
```

Expected: `** BUILD SUCCEEDED **` and the app at `/private/tmp/tenx-renderer-saturation-release/Build/Products/Release/10x.app`.

- [ ] **Step 3: Exercise a deterministic skill-sized transcript fixture**

Launch the exact Release artifact, render a displayed custom message matching the captured skill size followed by streaming assistant/tool updates, and record responsiveness plus CPU/RSS samples during and after the stream. The complete skill row must precede later output, text must remain selectable, and CPU must return toward idle after updates stop.

- [ ] **Step 4: Perform visual verification**

Capture the real Release window at the large skill block. Compare it with the existing raw monospace presentation: no missing text, no duplicated spacing, no bubble/style drift, and Jump to latest remains usable.

- [ ] **Step 5: Review the full branch diff and update PR #18**

Run the review workflow against `origin/main...HEAD`. Update the PR with targeted tests, full-suite output, Release build path, CPU/RSS evidence, screenshot path, and any audit risk deliberately deferred.

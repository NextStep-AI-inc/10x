# Streaming Transcript Order and Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep high-frequency streaming frames off the main actor, preserve assistant text/tool/text order live and after reopening, and render each consecutive tool batch as one collapsible inline section.

**Architecture:** `TranscriptEventProcessor` remains the single lossless consumer of `RpcClient.events`; it reduces message traffic on its actor and forwards only rare controls, including typed provider-account changes, to `SessionController`. A shared `TranscriptMessageNormalizer` converts one assistant message into ordered message and tool items for both live reduction and persisted history. `TranscriptView` derives stable presentation rows from those ordered items and renders consecutive tools through a group disclosure without changing the existing per-card disclosure state.

**Tech Stack:** Swift 6.2, SwiftUI, Observation, Swift Testing, OmpKit, generated Xcode project

---

## File map

- Create `App/Sessions/TranscriptMessageNormalizer.swift`: one source of truth for ordered assistant message/tool segmentation.
- Create `App/Sessions/TranscriptPresentationRow.swift`: pure grouping of consecutive tool items for display.
- Create `App/Tools/ToolCallGroupView.swift`: accessible group header and group-level disclosure UI.
- Modify `App/Sessions/SessionController.swift`: restore direct processor ingestion and consume account changes from filtered controls.
- Modify `App/Sessions/TranscriptEventProcessor.swift`: forward typed account changes without publishing transcript snapshots.
- Modify `App/Sessions/TranscriptMessage.swift`: mark continuation segments so response metadata appears once.
- Modify `App/Sessions/MessageBubbleView.swift`: honor the metadata flag.
- Modify `App/Sessions/TranscriptReducer.swift`: replace the full in-flight normalized range and update inline tools in place.
- Modify `App/Sessions/TranscriptHistoryMapper.swift`: normalize persisted messages through the same ordered path.
- Modify `App/Sessions/TranscriptView.swift`: render grouped presentation rows and scroll to their stable IDs.
- Modify `App/Tools/ToolDisclosureState.swift`: store group disclosure independently from individual tool-card choices.
- Modify focused tests under `Tests/TenXAppTests/` and regenerate `10x.xcodeproj/project.pbxproj` through `scripts/generate_xcodeproj.rb` only.

### Task 1: Restore actor-owned streaming ingestion

**Files:**
- Modify: `App/Sessions/TranscriptEventProcessor.swift:55-90,178-210`
- Modify: `App/Sessions/SessionController.swift:644-727,820-848,886-902`
- Test: `Tests/TenXAppTests/TranscriptEventProcessorTests.swift`
- Test: `Tests/TenXAppTests/SessionControllerTests.swift:330-355`

- [ ] **Step 1: Add a failing processor test for typed provider-account controls**

Add this test beside the existing control-order tests:

```swift
@Test func providerAccountChangesAreLosslessControlEvents() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    let initial = await processor.load(
        .messages([]),
        threadStartDate: nil,
        hasReconciliationWarning: false,
        runtimeState: .idle)
    let collector = Task { await collectControlLabels(from: processor.controlEvents) }

    await processor.consume(.providerAccountChanged(ProviderAccountChangedEvent(
        providerID: "openai-codex",
        accountRef: "acct-a",
        reason: .manual,
        sequence: 1)))
    await processor.consume(.providerAccountChanged(ProviderAccountChangedEvent(
        providerID: "openai-codex",
        accountRef: "acct-b",
        reason: .automaticFailover,
        sequence: 2)))
    await processor.stop()

    #expect(await collector.value == [
        "provider-account:acct-a:1",
        "provider-account:acct-b:2",
    ])
    #expect(await processor.currentSnapshot() == initial)
}
```

Extend the test-only `controlLabel` switch:

```swift
case .providerAccountChanged(let event):
    return "provider-account:\(event.accountRef):\(event.sequence)"
```

- [ ] **Step 2: Run the focused test and verify the red state**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-stream-control-red test \
  '-only-testing:TenXAppTests/providerAccountChangesAreLosslessControlEvents()'
```

Expected: FAIL because `.providerAccountChanged` is not forwarded to `controlEvents`.

- [ ] **Step 3: Forward account changes as controls without reducing them**

In `TranscriptEventProcessor.consume`, route both out-of-band control frame kinds before the reducer:

```swift
func consume(_ frame: RpcFrame) {
    guard !isStopped else { return }
    switch frame {
    case .extensionUIRequest, .providerAccountChanged:
        controlContinuation.yield(frame)
        return
    default:
        break
    }

    let mutation = reducer.consume(frame)
    // Keep the existing publication and event-control forwarding code unchanged.
}
```

This keeps account events lossless and ordered while producing no transcript snapshot.

- [ ] **Step 4: Restore direct event draining by the processor actor**

Replace the main-actor frame loop in `SessionController.startEventPipeline` with:

```swift
private func startEventPipeline(processor: TranscriptEventProcessor, client: RpcClient) {
    guard currentPipelineContext(for: processor) != nil else { return }
    attachAccountChannel(client: client)
    eventTask = Task { [processor, events = client.events] in
        await processor.run(events: events)
    }
    snapshotTask = Task { [weak self, processor] in
        for await snapshot in processor.snapshots {
            guard !Task.isCancelled else { return }
            self?.install(snapshot: snapshot)
        }
    }
    controlTask = Task { [weak self, processor] in
        for await frame in processor.controlEvents {
            guard !Task.isCancelled else { return }
            await self?.handleControl(frame, processor: processor)
        }
    }
}
```

Delete the private `consume(_:processor:context:)` method. In `handleControl`, apply account changes after current-pipeline validation and before event metadata:

```swift
if case .providerAccountChanged(let event) = frame {
    handleProviderAccountChange(event)
    return
}
```

Replace the DEBUG helper with a filtered-control helper so the stale-pipeline test still verifies the same guard without restoring the raw-frame path:

```swift
#if DEBUG
func testingCapturedControlConsumer(
    _ frame: RpcFrame
) -> (@MainActor () async -> Void)? {
    guard let processor else { return nil }
    return { [weak self, processor] in
        await self?.handleControl(frame, processor: processor)
    }
}
#endif
```

Update `accountEventCapturedFromClosedPipelineIsIgnored` to call `testingCapturedControlConsumer`.

Add the active-path companion test:

```swift
@MainActor @Test func accountControlFromActivePipelineUpdatesController() async throws {
    let manager = fakeManager(mode: "basic")
    let controller = SessionController(processManager: manager)
    await controller.openExisting(metadata(path: "/tmp/active-account-event.jsonl", cwd: "/tmp"))
    let consume = try #require(controller.testingCapturedControlConsumer(
        .providerAccountChanged(ProviderAccountChangedEvent(
            providerID: "openai-codex",
            accountRef: "acct_active",
            reason: .manual,
            sequence: 4))))

    await consume()

    #expect(controller.currentProviderAccountRef == "acct_active")
    #expect(controller.providerAccountSequence == 4)
    await manager.closeAll()
}
```

- [ ] **Step 5: Run the control and controller tests**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-stream-control-green test \
  '-only-testing:TenXAppTests/providerAccountChangesAreLosslessControlEvents()' \
  '-only-testing:TenXAppTests/accountControlFromActivePipelineUpdatesController()' \
  '-only-testing:TenXAppTests/accountEventCapturedFromClosedPipelineIsIgnored()' \
  '-only-testing:TenXAppTests/burstUpdatesCoalesceIntoOneManualFlush()' \
  '-only-testing:TenXAppTests/coalescedPublicationNeverExceedsTwentyPerSecond()'
```

Expected: PASS. The account test observes two controls, the stale controller ignores its captured control, and the publication tests retain their coalescing ceiling.

Run the architectural guard:

```bash
rg -n 'await self\?\.consume|private func consume\(' App/Sessions/SessionController.swift
rg -n 'await processor\.run\(events:' App/Sessions/SessionController.swift
```

Expected: the first command prints no matches; the second prints the single direct processor-ingestion call.

- [ ] **Step 6: Commit the performance fix**

```bash
git add App/Sessions/SessionController.swift \
  App/Sessions/TranscriptEventProcessor.swift \
  Tests/TenXAppTests/SessionControllerTests.swift \
  Tests/TenXAppTests/TranscriptEventProcessorTests.swift
git commit -m "fix(sessions): keep streaming frames off main actor"
```

### Task 2: Normalize assistant content into ordered transcript items

**Files:**
- Create: `App/Sessions/TranscriptMessageNormalizer.swift`
- Modify: `App/Sessions/TranscriptMessage.swift:20-61`
- Modify: `App/Sessions/MessageBubbleView.swift:34-44`
- Create: `Tests/TenXAppTests/TranscriptMessageTests.swift`

- [ ] **Step 1: Add failing normalizer tests**

Add tests that cover source order, stable segment identity, hidden reasoning, and metadata placement:

```swift
import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func normalizerPreservesTextToolTextOrder() throws {
    let raw = try transcriptJSON(#"{
      "role":"assistant",
      "content":[
        {"type":"text","text":"I will inspect this."},
        {"type":"image","data":"AQ==","mimeType":"image/png"},
        {"type":"toolCall","id":"read-1","name":"read","arguments":{"path":"App.swift"}},
        {"type":"analysis","text":"private"},
        {"type":"text","text":"The issue is in the reducer."}
      ]
    }"#)

    let items = TranscriptMessageNormalizer.items(
        id: "assistant-1",
        raw: raw,
        isFinal: false)

    #expect(items.map(\.id) == ["assistant-1", "read-1", "assistant-1-segment-1"])
    #expect(items.compactMap(\.messageValue).map(\.visibleText) == [
        "I will inspect this.",
        "The issue is in the reducer.",
    ])
    #expect(items.compactMap(\.messageValue).map(\.showsResponseMetadata) == [true, false])
    #expect(items.compactMap(\.messageValue)[0].document.images.count == 1)
}

@Test func normalizerReusesInlineToolExecutionState() throws {
    let raw = try transcriptJSON(#"{
      "role":"assistant",
      "content":[{"type":"toolCall","id":"bash-1","name":"bash","arguments":{"command":"pwd"}}]
    }"#)
    let completed = ToolPresentation(
        id: "bash-1",
        name: "stale-bash",
        arguments: .object(["command": .string("old")]),
        result: .object(["output": .string("/tmp")]),
        phase: .complete,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: Date(timeIntervalSince1970: 2))

    let items = TranscriptMessageNormalizer.items(
        id: "assistant-1",
        raw: raw,
        isFinal: true,
        existingTools: [completed.id: completed])

    guard case .tool(let tool) = items.first else {
        Issue.record("The assistant tool call should produce a tool row")
        return
    }
    #expect(tool.name == "bash")
    #expect(tool.arguments == .object(["command": .string("pwd")]))
    #expect(tool.phase == completed.phase)
    #expect(tool.result == completed.result)
    #expect(tool.startDate == completed.startDate)
    #expect(tool.endDate == completed.endDate)
}

@Test func malformedToolCallDoesNotCreateAGroupBoundary() throws {
    let raw = try transcriptJSON(#"{
      "role":"assistant",
      "content":[
        {"type":"text","text":"Before"},
        {"type":"toolCall","name":"read","arguments":{}},
        {"type":"text","text":"After"}
      ]
    }"#)

    let items = TranscriptMessageNormalizer.items(
        id: "assistant-1",
        raw: raw,
        isFinal: true)

    #expect(items.count == 1)
    #expect(items.compactMap(\.messageValue).map(\.visibleText) == ["Before\nAfter"])
}
```

Add this test helper in the test target if it is not already present:

```swift
private extension TranscriptItem {
    var messageValue: TranscriptMessage? {
        guard case .message(let message) = self else { return nil }
        return message
    }
}

private func transcriptJSON(_ source: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8))
}
```

- [ ] **Step 2: Run the normalizer test and verify the red state**

Run:

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-normalizer-red test \
  '-only-testing:TenXAppTests/normalizerPreservesTextToolTextOrder()'
```

Expected: compile failure because `TranscriptMessageNormalizer` and `showsResponseMetadata` do not exist.

- [ ] **Step 3: Add the message metadata flag**

Add a stored property and defaulted initializer argument to `TranscriptMessage`:

```swift
let showsResponseMetadata: Bool

init(
    id: String,
    raw: JSONValue,
    timestamp: Date? = nil,
    attribution: TranscriptResponseAttribution = .none,
    isFinal: Bool,
    showsResponseMetadata: Bool = true
) {
    self.id = id
    self.showsResponseMetadata = showsResponseMetadata
    // Keep the remaining existing initialization unchanged.
}
```

In `MessageBubbleView`, render metadata only on the first segment:

```swift
if message.showsResponseMetadata {
    ResponseMetadataView(message: message)
}
AssistantMessageContentView(message: message)
    .equatable()
```

- [ ] **Step 4: Implement the shared ordered normalizer**

Create `TranscriptMessageNormalizer.swift` with this public surface and helpers:

```swift
import Foundation
import OmpKit

enum TranscriptMessageNormalizer {
    static func items(
        id: String,
        raw: JSONValue,
        timestamp: Date? = nil,
        attribution: TranscriptResponseAttribution = .none,
        isFinal: Bool,
        existingTools: [String: ToolPresentation] = [:],
        fallbackDate: Date = Date()
    ) -> [TranscriptItem] {
        guard raw["role"]?.stringValue == "assistant",
              let blocks = raw["content"]?.arrayValue
        else {
            let message = TranscriptMessage(
                id: id,
                raw: raw,
                timestamp: timestamp,
                attribution: attribution,
                isFinal: isFinal)
            let retainsPlaceholder = message.role == .assistant && !isFinal
            return keeps(message) || retainsPlaceholder ? [.message(message)] : []
        }

        var result: [TranscriptItem] = []
        var visibleBlocks: [JSONValue] = []
        var visibleSegmentOrdinal = 0
        var hasVisibleMessage = false

        func segmentRaw(_ blocks: [JSONValue]) -> JSONValue {
            guard case .object(var object) = raw else { return raw }
            object["content"] = .array(blocks)
            return .object(object)
        }

        func appendVisibleSegment() {
            guard !visibleBlocks.isEmpty else { return }
            let segmentID = visibleSegmentOrdinal == 0
                ? id
                : "\(id)-segment-\(visibleSegmentOrdinal)"
            let messageRaw = segmentRaw(visibleBlocks)
            let message = TranscriptMessage(
                id: segmentID,
                raw: messageRaw,
                timestamp: timestamp,
                attribution: attribution,
                isFinal: isFinal,
                showsResponseMetadata: visibleSegmentOrdinal == 0)
            if keepsVisible(message, raw: messageRaw) {
                result.append(.message(message))
                visibleSegmentOrdinal += 1
                hasVisibleMessage = true
            }
            visibleBlocks.removeAll(keepingCapacity: true)
        }

        for block in blocks {
            guard isToolCall(block),
                  let tool = toolPresentation(
                    block,
                    raw: raw,
                    existingTools: existingTools,
                    fallbackDate: fallbackDate)
            else {
                visibleBlocks.append(block)
                continue
            }
            appendVisibleSegment()
            result.append(.tool(tool))
        }
        appendVisibleSegment()

        if !hasVisibleMessage, isTerminalFailure(raw) {
            let message = TranscriptMessage(
                id: id,
                raw: raw,
                timestamp: timestamp,
                attribution: attribution,
                isFinal: isFinal)
            result.append(.message(message))
        } else if result.isEmpty, blocks.isEmpty, !isFinal {
            let message = TranscriptMessage(
                id: id,
                raw: raw,
                timestamp: timestamp,
                attribution: attribution,
                isFinal: isFinal)
            result.append(.message(message))
        }
        return result
    }

    private static func isToolCall(_ block: JSONValue) -> Bool {
        let type = block["type"]?.stringValue?.lowercased() ?? ""
        let compact = type.filter(\.isLetter)
        return compact == "toolcall" || compact == "tooluse"
    }

    private static func toolPresentation(
        _ block: JSONValue,
        raw: JSONValue,
        existingTools: [String: ToolPresentation],
        fallbackDate: Date
    ) -> ToolPresentation? {
        guard let id = block["id"]?.stringValue ?? block["toolCallId"]?.stringValue,
              let name = block["name"]?.stringValue ?? block["toolName"]?.stringValue
        else { return nil }
        if let existing = existingTools[id] {
            var refreshed = existing
            refreshed.name = name
            if let arguments = block["arguments"] ?? block["args"] {
                refreshed.arguments = arguments
            }
            return refreshed
        }
        return ToolPresentation(
            id: id,
            name: name,
            arguments: block["arguments"] ?? block["args"] ?? .object([:]),
            result: nil,
            phase: .running,
            startDate: TranscriptMessage.messageDate(raw) ?? fallbackDate,
            endDate: nil)
    }

    private static func keeps(_ message: TranscriptMessage) -> Bool {
        if message.role == .user || !message.document.blocks.isEmpty { return true }
        guard message.role == .assistant else { return false }
        return ["error", "aborted"].contains(message.stopReason?.lowercased())
    }

    private static func keepsVisible(_ message: TranscriptMessage, raw: JSONValue) -> Bool {
        guard TranscriptMessage.isDisplayable(raw) else { return false }
        return !TranscriptMessage.visibleText(from: raw).isEmpty
            || !message.document.images.isEmpty
    }

    private static func isTerminalFailure(_ raw: JSONValue) -> Bool {
        guard raw["role"]?.stringValue == "assistant" else { return false }
        return ["error", "aborted"].contains(raw["stopReason"]?.stringValue?.lowercased())
    }
}
```

Keep private thinking/reasoning blocks in `visibleBlocks`; `TranscriptMessage` already removes them. They therefore cannot create transcript text, but surrounding visible blocks stay in their correct segment.

- [ ] **Step 5: Run the focused normalizer and message-view tests**

Run:

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-normalizer-green test \
  '-only-testing:TenXAppTests/normalizerPreservesTextToolTextOrder()' \
  '-only-testing:TenXAppTests/normalizerReusesInlineToolExecutionState()' \
  '-only-testing:TenXAppTests/malformedToolCallDoesNotCreateAGroupBoundary()'
```

Expected: PASS with ordered IDs and only the first assistant segment carrying metadata.

### Task 3: Use ordered normalization for live and persisted transcripts

**Files:**
- Modify: `App/Sessions/TranscriptReducer.swift:15-75,176-220,259-290,307-365,549-558`
- Modify: `App/Sessions/TranscriptHistoryMapper.swift:62-92,128-147`
- Test: `Tests/TenXAppTests/TranscriptReducerTests.swift`
- Test: `Tests/TenXAppTests/TranscriptHistoryMapperTests.swift`

- [ ] **Step 1: Add failing live-order and in-place update tests**

Add a reducer test that drives full assistant snapshots through the actual event path:

```swift
@Test func liveAssistantToolSegmentsStayInSourceOrderAndUpdateInPlace() throws {
    var reducer = TranscriptReducer()
    let message = #"{
      "id":"assistant-1","role":"assistant","content":[
        {"type":"text","text":"Checking."},
        {"type":"toolCall","id":"read-1","name":"read","arguments":{"path":"App.swift"}},
        {"type":"text","text":"Found it."}
      ]
    }"#

    reducer.consume(try eventFrame("""
      {"type":"message_update","message":\(message)}
      """))
    #expect(reducer.items.map(\.id) == ["assistant-1", "read-1", "assistant-1-segment-1"])

    reducer.consume(try eventFrame(#"{
      "type":"tool_execution_end","toolCallId":"read-1","toolName":"read",
      "args":{"path":"App.swift"},"result":{"output":"ok"},"isError":false
    }"#))

    #expect(reducer.items.map(\.id) == ["assistant-1", "read-1", "assistant-1-segment-1"])
    guard case .tool(let tool) = reducer.items[1] else {
        Issue.record("Expected inline tool"); return
    }
    #expect(tool.phase == .complete)
}

@Test func reconciliationKeepsPendingInlineToolBetweenAssistantSegments() throws {
    var reducer = TranscriptReducer()
    let message = #"{
      "id":"assistant-1","role":"assistant","content":[
        {"type":"text","text":"Checking."},
        {"type":"toolCall","id":"read-1","name":"read","arguments":{"path":"App.swift"}},
        {"type":"text","text":"Found it."}
      ]
    }"#
    reducer.consume(try eventFrame("""
      {"type":"message_end","message":\(message)}
      """))
    let before = reducer.items

    reducer.reconcile(history: TranscriptHistory(items: []))

    #expect(reducer.items == before)
    #expect(reducer.items.map(\.id) == ["assistant-1", "read-1", "assistant-1-segment-1"])
}
```

Use the existing `eventFrame(_:)` event-decoding helper in `TranscriptReducerTests.swift`.

- [ ] **Step 2: Add a failing persisted-history equivalence test**

Extend `historyMapperPreservesThreadModelModeAndToolOrder` so the assistant content is `text → toolCall → text`, then assert:

```swift
#expect(history.items.map(\.id) == [
    "thread-start-session-1",
    "user-1",
    "assistant-1",
    "tool-1",
    "assistant-1-segment-1",
])
#expect(history.items.compactMap(\.messageValue).map(\.visibleText) == [
    "Update App.swift",
    "I will update it.",
    "The update is complete.",
])

private extension TranscriptItem {
    var messageValue: TranscriptMessage? {
        guard case .message(let message) = self else { return nil }
        return message
    }
}
```

The existing tool-result entry should still merge into item index 3 and leave the order unchanged.

- [ ] **Step 3: Run both tests and verify the red state**

Run:

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-ordered-reducer-red test \
  '-only-testing:TenXAppTests/liveAssistantToolSegmentsStayInSourceOrderAndUpdateInPlace()' \
  '-only-testing:TenXAppTests/reconciliationKeepsPendingInlineToolBetweenAssistantSegments()' \
  '-only-testing:TenXAppTests/historyMapperPreservesThreadModelModeAndToolOrder()'
```

Expected: FAIL because both paths still flatten visible text and append tools afterward.

- [ ] **Step 4: Replace the live in-flight range atomically**

Add state to `TranscriptReducer`:

```swift
private var inflightMessageID: String?
private var inflightItemIDs: [String] = []
```

Replace the three message cases with calls to one helper:

```swift
private mutating func replaceInflightMessage(
    id: String,
    raw: JSONValue,
    isFinal: Bool
) -> Bool {
    let previous = items
    let previousIDs = Set(inflightItemIDs)
    let existingTools = Dictionary(uniqueKeysWithValues: items.compactMap { item in
        guard case .tool(let tool) = item else { return nil }
        return (tool.id, tool)
    })
    let normalized = TranscriptMessageNormalizer.items(
        id: id,
        raw: raw,
        isFinal: isFinal,
        existingTools: existingTools)
    let nextIDs = Set(normalized.map(\.id))
    let insertionIndex = items.firstIndex { previousIDs.contains($0.id) } ?? items.count
    items.removeAll { previousIDs.contains($0.id) || nextIDs.contains($0.id) }
    items.insert(contentsOf: normalized, at: min(insertionIndex, items.count))
    inflightItemIDs = normalized.map(\.id)
    return previous != items
}
```

For `message_start` and `message_update`, set `inflightMessageID`, call the helper with `isFinal: false`, and preserve the current immediate/coalesced mutation choices. For `message_end`, call it with `isFinal: true`, record pending fingerprints for every normalized `.message`, then clear both in-flight fields:

```swift
for item in items where inflightItemIDs.contains(item.id) {
    guard case .message(let message) = item else { continue }
    pendingPersistenceIDs.insert(message.id)
    pendingMessageFingerprints[message.id] = Self.fingerprint(message)
}
inflightMessageID = nil
inflightItemIDs = []
```

Reset `inflightItemIDs` in both `load` methods. In reconciliation, retain nonfinal IDs in `inflightItemIDs` and clear `inflightMessageID` only when none remain.

- [ ] **Step 5: Normalize message-page loading and persisted history**

In `TranscriptReducer.load(messages:)`, replace the separate visible-message and tool-call appends with:

```swift
let id = message["id"]?.stringValue ?? "history-\(index)"
items.append(contentsOf: TranscriptMessageNormalizer.items(
    id: id,
    raw: message,
    isFinal: true,
    existingTools: previousTools,
    fallbackDate: fallbackDate))
```

Keep the existing tool-result branch before this code so results still merge by tool-call ID.

In `TranscriptHistoryMapper.Mapper.consumeMessage`, replace the flattened message plus appended tools with:

```swift
let normalized = TranscriptMessageNormalizer.items(
    id: base.id,
    raw: message,
    timestamp: TranscriptHistoryMapper.date(from: base.timestamp),
    attribution: attribution,
    isFinal: true,
    fallbackDate: TranscriptHistoryMapper.date(from: base.timestamp) ?? Date())
items.append(contentsOf: normalized)
if normalized.contains(where: {
    if case .message = $0 { return true }
    if case .tool = $0 { return true }
    return false
}) {
    hasConversation = true
}
```

Delete the duplicated `toolCallPresentations` helpers from both mapper and reducer after all callers use the normalizer.

- [ ] **Step 6: Run live, history, reconciliation, and tool-result tests**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-ordered-reducer-green test \
  '-only-testing:TenXAppTests/liveAssistantToolSegmentsStayInSourceOrderAndUpdateInPlace()' \
  '-only-testing:TenXAppTests/reconciliationKeepsPendingInlineToolBetweenAssistantSegments()' \
  '-only-testing:TenXAppTests/historyMapperPreservesThreadModelModeAndToolOrder()' \
  '-only-testing:TenXAppTests/TranscriptReducerTests' \
  '-only-testing:TenXAppTests/TranscriptHistoryMapperTests'
```

Expected: PASS. Tool execution and tool-result updates change the inline item without moving it, and persisted history produces the same ordered IDs.

- [ ] **Step 7: Regenerate the project and commit ordered normalization**

Run:

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
bundle exec ruby scripts/generate_xcodeproj.rb
git diff --check
```

Expected: both generations are byte-stable after the focused green run added `TranscriptMessageNormalizer.swift`; `git diff --check` prints nothing.

Commit:

```bash
git add App/Sessions/TranscriptMessage.swift \
  App/Sessions/TranscriptMessageNormalizer.swift \
  App/Sessions/MessageBubbleView.swift \
  App/Sessions/TranscriptReducer.swift \
  App/Sessions/TranscriptHistoryMapper.swift \
  Tests/TenXAppTests/TranscriptMessageTests.swift \
  Tests/TenXAppTests/TranscriptReducerTests.swift \
  Tests/TenXAppTests/TranscriptHistoryMapperTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "fix(transcript): preserve assistant tool call order"
```

### Task 4: Group consecutive tools behind one disclosure

**Files:**
- Create: `App/Sessions/TranscriptPresentationRow.swift`
- Create: `App/Tools/ToolCallGroupView.swift`
- Modify: `App/Tools/ToolDisclosureState.swift:4-32`
- Modify: `App/Sessions/TranscriptView.swift:12-80,125-205`
- Test: `Tests/TenXAppTests/TranscriptPresentationRowTests.swift`
- Test: `Tests/TenXAppTests/ToolDisclosureStateTests.swift`

- [ ] **Step 1: Add failing grouping tests**

Create `TranscriptPresentationRowTests.swift`:

```swift
import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func consecutiveToolsFormOneGroupAndAssistantContentSplitsGroups() {
    let rows = TranscriptPresentationRow.rows(from: [
        messageItem(id: "before", text: "Before"),
        .tool(tool(id: "one", phase: .complete)),
        .tool(tool(id: "two", phase: .running)),
        messageItem(id: "after", text: "After"),
        .tool(tool(id: "three", phase: .failed)),
    ])

    #expect(rows.map(\.id) == [
        "before",
        "tool-group-one",
        "after",
        "tool-group-three",
    ])
    let groups = rows.compactMap { row -> TranscriptToolGroup? in
        guard case .toolGroup(let group) = row else { return nil }
        return group
    }
    #expect(groups.map(\.tools.map(\.id)) == [
        ["one", "two"],
        ["three"],
    ])
    #expect(groups.map(\.phase) == [.running, .failed])
}

private func messageItem(id: String, text: String) -> TranscriptItem {
    .message(TranscriptMessage(
        id: id,
        raw: .object([
            "role": .string("assistant"),
            "content": .string(text),
        ]),
        isFinal: true))
}

private func tool(id: String, phase: ToolPhase) -> ToolPresentation {
    ToolPresentation(
        id: id,
        name: "read",
        arguments: .object([:]),
        result: nil,
        phase: phase,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: phase == .running ? nil : Date(timeIntervalSince1970: 2))
}
```

- [ ] **Step 2: Add a failing group-disclosure persistence test**

Add to `ToolDisclosureStateTests.swift`:

```swift
@Test func collapsedToolGroupStaysCollapsedAsToolsUpdateAndAppend() {
    let state = ToolDisclosureState()
    let initialRows = TranscriptPresentationRow.rows(from: [
        .tool(tool(id: "one", name: "read", phase: .running)),
    ])
    let groupID = initialRows[0].id

    #expect(state.isGroupExpanded(id: groupID))
    state.setGroupExpanded(false, id: groupID)

    let updatedRows = TranscriptPresentationRow.rows(from: [
        .tool(tool(id: "one", name: "read", phase: .complete)),
        .tool(tool(id: "two", name: "bash", phase: .running)),
    ])

    #expect(updatedRows[0].id == groupID)
    #expect(!state.isGroupExpanded(id: groupID))
}
```

- [ ] **Step 3: Run the two tests and verify the red state**

Run:

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-tool-group-red test \
  '-only-testing:TenXAppTests/consecutiveToolsFormOneGroupAndAssistantContentSplitsGroups()' \
  '-only-testing:TenXAppTests/collapsedToolGroupStaysCollapsedAsToolsUpdateAndAppend()'
```

Expected: compile failure because the presentation row and group disclosure API do not exist.

- [ ] **Step 4: Implement the pure presentation grouping model**

Create `TranscriptPresentationRow.swift`:

```swift
import Foundation

struct TranscriptToolGroup: Identifiable, Equatable, Sendable {
    let id: String
    let tools: [ToolPresentation]

    init?(tools: [ToolPresentation]) {
        guard let first = tools.first else { return nil }
        id = "tool-group-\(first.id)"
        self.tools = tools
    }

    var phase: ToolPhase {
        if tools.contains(where: { $0.phase == .failed }) { return .failed }
        if tools.contains(where: { $0.phase == .running }) { return .running }
        return .complete
    }
}

enum TranscriptPresentationRow: Identifiable, Equatable, Sendable {
    case item(TranscriptItem)
    case toolGroup(TranscriptToolGroup)

    var id: String {
        switch self {
        case .item(let item): item.id
        case .toolGroup(let group): group.id
        }
    }

    static func rows(from items: [TranscriptItem]) -> [Self] {
        var rows: [Self] = []
        var tools: [ToolPresentation] = []
        func flushTools() {
            guard !tools.isEmpty else { return }
            if let group = TranscriptToolGroup(tools: tools) {
                rows.append(.toolGroup(group))
            }
            tools.removeAll(keepingCapacity: true)
        }
        for item in items {
            if case .tool(let tool) = item {
                tools.append(tool)
            } else {
                flushTools()
                rows.append(.item(item))
            }
        }
        flushTools()
        return rows
    }
}
```

Only `.tool` rows join a group. Subagent and extension rows remain unchanged and therefore end a group, matching the approved non-goals.

- [ ] **Step 5: Store group choices separately from card choices**

Extend `ToolDisclosureState`:

```swift
private var groupChoices: [String: Bool] = [:]

func isGroupExpanded(id: String) -> Bool {
    groupChoices[id] ?? true
}

func setGroupExpanded(_ isExpanded: Bool, id: String) {
    groupChoices[id] = isExpanded
}
```

Do not add group IDs to `collapseAll` or `expand`; those existing commands remain scoped to individual card detail disclosures.

- [ ] **Step 6: Build the accessible group view**

Create `ToolCallGroupView.swift`:

```swift
import SwiftUI

struct ToolCallGroupView: View {
    let group: TranscriptToolGroup

    @Environment(\.toolDisclosureState) private var disclosureState
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    @State private var fallbackIsExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text(group.tools.count == 1
                        ? "Tool call"
                        : "Tool calls (\(group.tools.count))")
                        .font(TenXTypography.body(size: 11, weight: .semibold))
                    Spacer()
                    Text(group.phase.label)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(statusColor)
                }
                .contentShape(Rectangle())
                .frame(minHeight: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                VStack(spacing: 10) {
                    ForEach(group.tools) { tool in
                        ToolCardView(presentation: tool)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private var isExpanded: Bool {
        disclosureState?.isGroupExpanded(id: group.id) ?? fallbackIsExpanded
    }

    private var statusColor: Color {
        switch group.phase {
        case .running: TenXPalette.color(TenXPalette.interactiveCyanHex)
        case .complete: TenXPalette.color(TenXPalette.mutedTextHex)
        case .failed: TenXPalette.color(TenXPalette.signalRedHex)
        }
    }

    private var accessibilityLabel: String {
        let count = group.tools.count
        let noun = count == 1 ? "tool call" : "tool calls"
        return "\(count) \(noun), \(group.phase.label)"
    }

    private func toggle() {
        let next = !isExpanded
        let update = {
            if let disclosureState {
                disclosureState.setGroupExpanded(next, id: group.id)
            } else {
                fallbackIsExpanded = next
            }
        }
        if isReduceMotionEnabled {
            update()
        } else {
            withAnimation(.easeOut(duration: 0.15), update)
        }
    }
}
```

- [ ] **Step 7: Render presentation rows and preserve bottom-following**

Add to `TranscriptView`:

```swift
private var presentationRows: [TranscriptPresentationRow] {
    TranscriptPresentationRow.rows(from: controller.items)
}

@ViewBuilder
private func rowView(_ row: TranscriptPresentationRow) -> some View {
    switch row {
    case .item(let item):
        itemView(item)
    case .toolGroup(let group):
        ToolCallGroupView(group: group)
    }
}
```

Replace the transcript `ForEach` with:

```swift
ForEach(presentationRows) { row in
    rowView(row)
        .id(row.id)
}
```

Keep `.onChange(of: controller.items.last)` so streamed content and phase updates continue to trigger bottom-following, but scroll to `presentationRows.last?.id`. Use the same presentation-row ID in the “Jump to latest” button. Remove the direct `.tool` branch from `itemView`; tool items are now rendered only inside a group.

- [ ] **Step 8: Run grouping, disclosure, and transcript-view tests**

Run:

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-tool-group-green test \
  '-only-testing:TenXAppTests/consecutiveToolsFormOneGroupAndAssistantContentSplitsGroups()' \
  '-only-testing:TenXAppTests/collapsedToolGroupStaysCollapsedAsToolsUpdateAndAppend()' \
  '-only-testing:TenXAppTests/ToolDisclosureStateTests' \
  '-only-testing:TenXAppTests/ViewSnapshotTests'
```

Expected: PASS. Consecutive tools create one stable group, assistant content creates a boundary, and group state remains independent from card state.

- [ ] **Step 9: Regenerate the project and commit grouped disclosure**

Run:

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
bundle exec ruby scripts/generate_xcodeproj.rb
git diff --check
```

Commit:

```bash
git add App/Sessions/TranscriptPresentationRow.swift \
  App/Sessions/TranscriptView.swift \
  App/Tools/ToolCallGroupView.swift \
  App/Tools/ToolDisclosureState.swift \
  Tests/TenXAppTests/TranscriptPresentationRowTests.swift \
  Tests/TenXAppTests/ToolDisclosureStateTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "feat(transcript): group inline tool calls"
```

### Task 5: Verify the complete behavior in a Release build

**Files:**
- Verify: all changed Swift and test files
- Verify: `10x.xcodeproj/project.pbxproj`
- Evidence: `/private/tmp/tenx-streaming-order-evidence/`

- [ ] **Step 1: Run project-generation reproducibility and static diff checks**

Run:

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
git diff --exit-code -- 10x.xcodeproj/project.pbxproj
git diff --check origin/main...HEAD
git status --short
```

Expected: generation leaves the project unchanged, diff check prints nothing, and status is clean.

- [ ] **Step 2: Run the complete app and OmpKit test suites**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-streaming-order-full test
swift test --package-path OmpKit
```

Expected: both commands exit 0 with no failing tests.

- [ ] **Step 3: Build the Release app**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-streaming-order-release build
```

Expected: `** BUILD SUCCEEDED **` and the app exists at `/private/tmp/tenx-streaming-order-release/Build/Products/Release/10x.app`.

- [ ] **Step 4: Launch and drive the real UI**

Load the `launching-local-builds`, `visual-ui`, `writing-ui`, `figma:figma-swiftui`, and `verifying-work` skills before this step. Launch the Release app without using port 3000, confirm its window is visible, then use the real composer to run a deterministic or real prompt that yields assistant text, at least two consecutive tool calls, and assistant follow-up text.

Verify through the UI:

1. The first response streams while the composer, scroll view, and window remain interactive.
2. The timeline reads assistant text, one `Tool calls (2)` group, then assistant follow-up text.
3. Collapsing the running group hides all cards and does not reopen when a tool phase updates.
4. Expanding the group restores cards and each card's existing detail disclosure still works.
5. Reopening the session preserves the same source order.
6. VoiceOver exposes the group count, aggregate state, and expanded/collapsed value.

- [ ] **Step 5: Capture visual evidence from the real Release build**

Create `/private/tmp/tenx-streaming-order-evidence/` and capture:

- `expanded.png`: text → expanded tool group → follow-up text.
- `collapsed.png`: the same inline group collapsed with count and status visible.

Record the session path and prompt in `verification.txt` so the flow is reproducible. Do not include account secrets or full provider tokens.

- [ ] **Step 6: Review only the scoped diff and commit any verification-only adjustment**

Run:

```bash
git diff --stat origin/main...HEAD
git diff --check origin/main...HEAD
git log --oneline --decorate origin/main..HEAD
git status --short
```

Expected: only the files named in this plan are changed, each implementation concern has an atomic conventional commit, and the worktree is clean. If live verification required a scoped code adjustment, rerun its focused test plus Steps 1-5 and commit it with a conventional `fix(transcript): ...` message.

The final handoff must report:

- **Verified:** exact test/build commands and paths to `expanded.png` and `collapsed.png`.
- **Not verified:** any unavailable real-provider or accessibility path and the concrete reason.
- **For Tanner to test:** the shortest manual flow remaining, or “Nothing” when every approved behavior was exercised.

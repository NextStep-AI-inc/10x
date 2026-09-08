# Harness Message Notices Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the transcript gate hides a harness message, show an in-place notice with a one-line summary from a small model — opt-in via Settings.

**Architecture:** The reducer/mapper already drop hidden messages at four sites; they now also record a `HarnessMessageDescriptor` (deduped by content signature). `TranscriptEventProcessor` forwards drained descriptors to `SessionController`, which applies the user's preferences (toggle + threshold), appends a `.notice` item, and kicks a `HarnessNoticeSummarizer` (`omp -p` one-shot, disk-cached by content hash) that rewrites the notice in place. Settings gets a structured row (toggle, threshold dropdown, model dropdown).

**Tech Stack:** Swift, SwiftUI, Swift Testing, OmpKit (`OmpCommandRunner`, `OmpConfigService`), UserDefaults.

**Spec:** `docs/superpowers/specs/2026-09-07-harness-message-notices-design.md`

**Context:** Work happens in the current checkout, on top of the uncommitted
gate changes (`TranscriptMessage.isDisplayable` allowlist, harness cap). The
reducer drops hidden messages at exactly these sites:

- `App/Sessions/TranscriptReducer.swift:41` — `message_start`
- `App/Sessions/TranscriptReducer.swift:53` — `message_update`
- `App/Sessions/TranscriptReducer.swift:62` — `message_end`
- `App/Sessions/TranscriptReducer.swift:358` — `shouldKeepMessage` (used by `load(messages:)`)
- `App/Sessions/TranscriptHistoryMapper.swift:80` — `consumeMessage` (session-file path)

**Test command** (full suite — use after every task unless a task says otherwise):

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests test
```

To run one Swift Testing free function:
`-only-testing:'TenXAppTests/functionName()'`

**Known pre-existing failures:** 3 tests in `ComposerPasteboardTests` fail from
another session's untracked WIP (`App/Sessions/ComposerPasteboard.swift`).
Ignore them; they are not yours to fix.

**New files** require regenerating the project (AGENTS.md — never hand-edit the pbxproj):

```bash
ruby scripts/generate_xcodeproj.rb
```

---

### Task 1: `HarnessMessageDescriptor` + live-path collection

**Files:**
- Create: `App/Sessions/HarnessMessageDescriptor.swift`
- Modify: `App/Sessions/TranscriptReducer.swift` (gates at lines 41, 53, 62; state near line 20; `reset()`)
- Test: `Tests/TenXAppTests/TranscriptReducerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/TenXAppTests/TranscriptReducerTests.swift`:

```swift
@Test func droppedHarnessMessagesAreCollectedForTheNoticePipeline() {
    var reducer = TranscriptReducer()
    _ = reducer.consume(.event("message_start", .object([
        "message": .object([
            "role": .string("developer"),
            "content": .string("You MUST execute this plan step by step."),
        ]),
    ])))

    let dropped = reducer.drainDroppedHarnessMessages()

    #expect(dropped.count == 1)
    #expect(dropped.first?.role == "developer")
    #expect(dropped.first?.customType == nil)
    #expect(dropped.first?.text == "You MUST execute this plan step by step.")
    #expect(dropped.first?.byteCount == "You MUST execute this plan step by step.".count)
    #expect(reducer.drainDroppedHarnessMessages().isEmpty)
}

@Test func aMessageStartEndPairRecordsOneDescriptor() {
    var reducer = TranscriptReducer()
    let message = JSONValue.object([
        "role": .string("developer"),
        "content": .string("Same wall"),
    ])

    _ = reducer.consume(.event("message_start", .object(["message": message])))
    _ = reducer.consume(.event("message_end", .object(["message": message])))

    #expect(reducer.drainDroppedHarnessMessages().count == 1)
}

@Test func anEmptyHiddenMessageRecordsNothing() {
    var reducer = TranscriptReducer()
    _ = reducer.consume(.event("message_start", .object([
        "message": .object(["role": .string("fileMention")]),
    ])))

    #expect(reducer.drainDroppedHarnessMessages().isEmpty)
}

@Test func repeatedIdenticalHiddenMessagesRecordOneDescriptor() {
    var reducer = TranscriptReducer()
    let message = JSONValue.object([
        "role": .string("custom"),
        "customType": .string("nudge"),
        "display": .bool(false),
        "content": .string("Keep going"),
    ])

    for _ in 0..<3 {
        _ = reducer.consume(.event("message_start", .object(["message": message])))
    }

    #expect(reducer.drainDroppedHarnessMessages().count == 1)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
ruby scripts/generate_xcodeproj.rb  # only if HarnessMessageDescriptor.swift already exists; on first run it won't compile — that's the expected failure
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:'TenXAppTests/droppedHarnessMessagesAreCollectedForTheNoticePipeline()' test
```

Expected: FAIL — compile error, `drainDroppedHarnessMessages` does not exist.

- [ ] **Step 3: Create the descriptor type**

Create `App/Sessions/HarnessMessageDescriptor.swift`:

```swift
import Foundation

/// A harness message the transcript gate kept out of the conversation —
/// developer instruction walls, display:false steering customs, or a role a
/// future omp adds. Collected so the UI can notice the drop instead of
/// staying silent.
struct HarnessMessageDescriptor: Equatable, Sendable {
    let role: String?
    let customType: String?
    /// Character count of the extracted text — what the threshold compares against.
    let byteCount: Int
    let text: String

    /// Dedup key: identical content hidden twice (message_start + message_end,
    /// or repeated nudges) is one notice.
    var signature: String {
        "\(role ?? "")\u{0}\(customType ?? "")\u{0}\(text)"
    }

    /// Human-facing kind for the notice label: "nudge", "developer", "unknown".
    var kindLabel: String {
        customType ?? role ?? "unknown"
    }
}
```

- [ ] **Step 4: Collect descriptors in the reducer**

In `App/Sessions/TranscriptReducer.swift`, add state next to the other private
properties (near line 20):

```swift
    private(set) var droppedHarnessMessages: [HarnessMessageDescriptor] = []
    private var droppedHarnessMessageSignatures: Set<String> = []
```

Add the drain + record methods (next to `appendNotice`):

```swift
    /// Drained by the processor after each consume/load; the controller turns
    /// descriptors into notices. The reducer stays settings-free.
    mutating func drainDroppedHarnessMessages() -> [HarnessMessageDescriptor] {
        let drained = droppedHarnessMessages
        droppedHarnessMessages = []
        return drained
    }

    private mutating func recordDroppedHarnessMessage(_ message: JSONValue) {
        let text = TranscriptMessage.visibleText(from: message)
        guard !text.isEmpty else { return }
        let descriptor = HarnessMessageDescriptor(
            role: message["role"]?.stringValue,
            customType: message["customType"]?.stringValue,
            byteCount: text.count,
            text: text)
        guard droppedHarnessMessageSignatures.insert(descriptor.signature).inserted
        else { return }
        droppedHarnessMessages.append(descriptor)
    }
```

Change the `message_start` and `message_end` gates (lines 41 and 62). Each
currently reads `guard TranscriptMessage.isDisplayable(message) else { return .none }` —
replace both with:

```swift
            guard TranscriptMessage.isDisplayable(message) else {
                recordDroppedHarnessMessage(message)
                return .none
            }
```

Leave the `message_update` gate (line 53) as a plain drop: updates are growing
token snapshots, and with content-signature dedup a streamed hidden message
would fan out one descriptor per prefix. Start + end cover every case
(complete injections have both; reconciliation-boundary messages have a lone
end).

In `reset()`, clear the new state alongside the existing clears:

```swift
        droppedHarnessMessages = []
        droppedHarnessMessageSignatures = []
```

(Do NOT clear signatures in `load(history:)` / `load(messages:)` — dedup must
survive reconciliation reloads.)

- [ ] **Step 5: Regenerate the project and run the tests**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/TranscriptReducerTests test
```

Expected: PASS (all reducer tests, old and new).

- [ ] **Step 6: Commit**

```bash
git add App/Sessions/HarnessMessageDescriptor.swift App/Sessions/TranscriptReducer.swift Tests/TenXAppTests/TranscriptReducerTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat: collect dropped harness messages for transcript notices"
```

---

### Task 2: Collect on the RPC history-load path

**Files:**
- Modify: `App/Sessions/TranscriptReducer.swift` (`load(messages:)`, line 205-206 area)
- Test: `Tests/TenXAppTests/TranscriptReducerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test func aHistoryLoadCollectsDroppedDescriptors() {
    var reducer = TranscriptReducer()

    _ = reducer.load(messages: [
        .object(["role": .string("user"), "content": .string("Ship it")]),
        .object([
            "role": .string("custom"),
            "customType": .string("nudge"),
            "display": .bool(false),
            "content": .string("Steer harder"),
        ]),
    ])

    let dropped = reducer.drainDroppedHarnessMessages()
    #expect(dropped.map(\.customType) == ["nudge"])
    #expect(dropped.first?.text == "Steer harder")
    #expect(reducer.items.count == 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:'TenXAppTests/aHistoryLoadCollectsDroppedDescriptors()' test
```

Expected: FAIL — `dropped` is empty.

- [ ] **Step 3: Record in `load(messages:)`**

In `load(messages:)`, the loop currently does:

```swift
            let visibleText = Self.visibleMessageText(message)
            if Self.shouldKeepMessage(message, visibleText: visibleText) {
```

Insert the recording line between them (`shouldKeepMessage` keeps its own
gate — the double `isDisplayable` check is a trivial switch):

```swift
            let visibleText = Self.visibleMessageText(message)
            if !TranscriptMessage.isDisplayable(message) {
                recordDroppedHarnessMessage(message)
            }
            if Self.shouldKeepMessage(message, visibleText: visibleText) {
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/TranscriptReducer.swift Tests/TenXAppTests/TranscriptReducerTests.swift
git commit -m "feat: collect dropped descriptors on the RPC history path"
```

---

### Task 3: Collect on the session-file path

**Files:**
- Modify: `App/Sessions/TranscriptHistoryMapper.swift` (`TranscriptHistory`, `map` return at line 17, `Mapper.consumeMessage` at line 80)
- Modify: `App/Sessions/TranscriptReducer.swift` (`load(history:)`, line 224)
- Test: `Tests/TenXAppTests/TranscriptHistoryMapperTests.swift`, `Tests/TenXAppTests/TranscriptReducerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/TenXAppTests/TranscriptHistoryMapperTests.swift` (reuse the
file's existing `historyBase` / `historyJSON` helpers):

```swift
@Test func historyMapperCollectsDroppedDescriptors() throws {
    let header = SessionHeader(
        id: "session-dropped",
        cwd: "/tmp/project",
        timestamp: "2026-08-24T20:00:00.000Z",
        version: 3,
        title: nil,
        titleSource: nil,
        parentSession: nil)
    let entries: [SessionEntry] = [
        .message(
            base: historyBase("user-1", nil, 1),
            message: try historyJSON(#"{"role":"user","content":[{"type":"text","text":"Ship it"}]}"#)),
        .message(
            base: historyBase("developer-1", "user-1", 2),
            message: try historyJSON(#"{"role":"developer","content":[{"type":"text","text":"Plan approved. Execute it."}]}"#)),
    ]

    let history = TranscriptHistoryMapper.map(header: header, path: entries)

    #expect(history.dropped.count == 1)
    #expect(history.dropped.first?.role == "developer")
    #expect(history.dropped.first?.text == "Plan approved. Execute it.")
}
```

Append to `Tests/TenXAppTests/TranscriptReducerTests.swift`:

```swift
@Test func loadingHistoryAdoptsItsDroppedDescriptors() {
    var reducer = TranscriptReducer()
    let descriptor = HarnessMessageDescriptor(
        role: "developer",
        customType: nil,
        byteCount: 4,
        text: "wall")

    _ = reducer.load(history: TranscriptHistory(items: [], dropped: [descriptor]))

    #expect(reducer.drainDroppedHarnessMessages() == [descriptor])
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:'TenXAppTests/historyMapperCollectsDroppedDescriptors()' -only-testing:'TenXAppTests/loadingHistoryAdoptsItsDroppedDescriptors()' test
```

Expected: FAIL — compile error, `TranscriptHistory` has no `dropped`.

- [ ] **Step 3: Add `dropped` to `TranscriptHistory` and the mapper**

In `App/Sessions/TranscriptHistoryMapper.swift`, replace:

```swift
struct TranscriptHistory: Equatable, Sendable {
    let items: [TranscriptItem]
}
```

with:

```swift
struct TranscriptHistory: Equatable, Sendable {
    let items: [TranscriptItem]
    /// Hidden messages encountered while mapping, for the notice pipeline.
    let dropped: [HarnessMessageDescriptor]

    init(items: [TranscriptItem], dropped: [HarnessMessageDescriptor] = []) {
        self.items = items
        self.dropped = dropped
    }
}
```

(The defaulted parameter keeps the other construction site —
`SessionController.swift:685` — compiling unchanged.)

In `Mapper`, add state and the recorder:

```swift
        private(set) var dropped: [HarnessMessageDescriptor] = []
        private var droppedSignatures: Set<String> = []

        private mutating func recordDropped(_ message: JSONValue) {
            let text = TranscriptMessage.visibleText(from: message)
            guard !text.isEmpty else { return }
            let descriptor = HarnessMessageDescriptor(
                role: message["role"]?.stringValue,
                customType: message["customType"]?.stringValue,
                byteCount: text.count,
                text: text)
            guard droppedSignatures.insert(descriptor.signature).inserted else { return }
            dropped.append(descriptor)
        }
```

In `consumeMessage`, replace the display gate:

```swift
            if TranscriptMessage.isDisplayable(message),
               transcriptMessage.role == .user
                || !transcriptMessage.visibleText.isEmpty
                || isTerminalFailure {
                items.append(.message(transcriptMessage))
                hasConversation = true
            }
```

with:

```swift
            let isDisplayable = TranscriptMessage.isDisplayable(message)
            if isDisplayable,
               transcriptMessage.role == .user
                || !transcriptMessage.visibleText.isEmpty
                || isTerminalFailure {
                items.append(.message(transcriptMessage))
                hasConversation = true
            }
            if !isDisplayable {
                recordDropped(message)
            }
```

Change the `map` return (line 17):

```swift
        return TranscriptHistory(items: mapper.items, dropped: mapper.dropped)
```

- [ ] **Step 4: Adopt descriptors in `load(history:)`**

In `TranscriptReducer.load(history:)`, after `items = history.items`:

```swift
        for descriptor in history.dropped
        where droppedHarnessMessageSignatures.insert(descriptor.signature).inserted {
            droppedHarnessMessages.append(descriptor)
        }
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/TranscriptHistoryMapperTests -only-testing:TenXAppTests/TranscriptReducerTests test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add App/Sessions/TranscriptHistoryMapper.swift App/Sessions/TranscriptReducer.swift Tests/TenXAppTests/TranscriptHistoryMapperTests.swift Tests/TenXAppTests/TranscriptReducerTests.swift
git commit -m "feat: collect dropped descriptors on the session-file path"
```

---

### Task 4: Notice id/update path + processor forwarding

**Files:**
- Modify: `App/Sessions/TranscriptReducer.swift` (`appendNotice` at line 441)
- Modify: `App/Sessions/TranscriptEventProcessor.swift` (`consume`, `load`, `appendNotice` at line 114)
- Test: `Tests/TenXAppTests/TranscriptReducerTests.swift`, `Tests/TenXAppTests/TranscriptEventProcessorTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/TenXAppTests/TranscriptReducerTests.swift`:

```swift
@Test func updateNoticeRewritesTheMessageInPlace() {
    var reducer = TranscriptReducer()
    _ = reducer.appendNotice(id: "n1", level: "info", message: "before")
    _ = reducer.appendNotice(id: "n2", level: "info", message: "other")

    let mutation = reducer.updateNotice(id: "n1", message: "after")

    #expect(mutation == .immediate)
    let notices = reducer.items.compactMap { item -> (String, String)? in
        guard case .notice(let id, _, let message) = item else { return nil }
        return (id, message)
    }
    #expect(notices.map(\.0) == ["n1", "n2"])
    #expect(notices.map(\.1) == ["after", "other"])
    #expect(reducer.updateNotice(id: "missing", message: "x") == .none)
}
```

Append to `Tests/TenXAppTests/TranscriptEventProcessorTests.swift`:

```swift
@Test func processorForwardsDroppedHarnessMessages() async {
    let processor = TranscriptEventProcessor()
    await confirmation(expectedCount: 1) { confirm in
        await processor.setOnDroppedHarnessMessages { dropped in
            #expect(dropped.first?.role == "developer")
            #expect(dropped.first?.text == "wall")
            confirm()
        }
        await processor.consume(.event("message_start", .object([
            "message": .object([
                "role": .string("developer"),
                "content": .string("wall"),
            ]),
        ])))
    }
    await processor.stop()
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:'TenXAppTests/updateNoticeRewritesTheMessageInPlace()' -only-testing:'TenXAppTests/processorForwardsDroppedHarnessMessages()' test
```

Expected: FAIL — compile errors, `appendNotice(id:...)`, `updateNotice`, `setOnDroppedHarnessMessages` don't exist.

- [ ] **Step 3: Reducer — id-carrying append + update**

In `TranscriptReducer.swift`, replace the existing `appendNotice`:

```swift
    @discardableResult
    mutating func appendNotice(level: String, message: String) -> TranscriptMutation {
        items.append(.notice(
            id: syntheticID(prefix: "notice"),
            level: level,
            message: message))
        return .immediate
    }
```

with:

```swift
    @discardableResult
    mutating func appendNotice(level: String, message: String) -> TranscriptMutation {
        appendNotice(id: syntheticID(prefix: "notice"), level: level, message: message)
    }

    /// Caller-chosen id, so the caller can rewrite the notice in place later
    /// (harness-message notices swap in their summary).
    @discardableResult
    mutating func appendNotice(id: String, level: String, message: String) -> TranscriptMutation {
        items.append(.notice(id: id, level: level, message: message))
        return .immediate
    }

    @discardableResult
    mutating func updateNotice(id: String, message: String) -> TranscriptMutation {
        guard let index = items.firstIndex(where: { $0.id == id }),
              case .notice(let noticeID, let level, _) = items[index]
        else { return .none }
        items[index] = .notice(id: noticeID, level: level, message: message)
        return .immediate
    }
```

- [ ] **Step 4: Processor — passthroughs + drop forwarding**

In `TranscriptEventProcessor.swift`, add state and setter:

```swift
    private var onDroppedHarnessMessages: (@Sendable ([HarnessMessageDescriptor]) -> Void)?

    func setOnDroppedHarnessMessages(
        _ handler: @escaping @Sendable ([HarnessMessageDescriptor]) -> Void
    ) {
        onDroppedHarnessMessages = handler
    }
```

Add passthroughs next to the existing `appendNotice`:

```swift
    func appendNotice(id: String, level: String, message: String) {
        guard !isStopped else { return }
        publish(reducer.appendNotice(id: id, level: level, message: message))
    }

    func updateNotice(id: String, message: String) {
        guard !isStopped else { return }
        publish(reducer.updateNotice(id: id, message: message))
    }
```

At the end of `consume(_ frame:)` (after the control-forwarding block), and at
the end of `load(...)` (before `return currentSnapshot()`), add:

```swift
        let dropped = reducer.drainDroppedHarnessMessages()
        if !dropped.isEmpty {
            onDroppedHarnessMessages?(dropped)
        }
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/TranscriptReducerTests -only-testing:TenXAppTests/TranscriptEventProcessorTests test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add App/Sessions/TranscriptReducer.swift App/Sessions/TranscriptEventProcessor.swift Tests/TenXAppTests/TranscriptReducerTests.swift Tests/TenXAppTests/TranscriptEventProcessorTests.swift
git commit -m "feat: forward dropped harness messages and support in-place notice updates"
```

---

### Task 5: `HarnessNoticePreferenceStore`

**Files:**
- Create: `App/Settings/HarnessNoticePreferenceStore.swift`
- Test: `Tests/TenXAppTests/HarnessNoticePreferenceStoreTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/TenXAppTests/HarnessNoticePreferenceStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import TenXApp

@MainActor @Test func harnessNoticePreferencesDefaultToOff() {
    let suiteName = "harness-notice-defaults-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = HarnessNoticePreferenceStore(defaults: defaults)

    #expect(!store.isEnabled)
    #expect(store.threshold == 0)
    #expect(store.modelOverride == nil)
}

@MainActor @Test func harnessNoticePreferencesPersistAcrossInstances() {
    let suiteName = "harness-notice-persist-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = HarnessNoticePreferenceStore(defaults: defaults)
    store.isEnabled = true
    store.threshold = 1_000
    store.modelOverride = "cursor/composer-2.5-fast"

    let reloaded = HarnessNoticePreferenceStore(defaults: defaults)
    #expect(reloaded.isEnabled)
    #expect(reloaded.threshold == 1_000)
    #expect(reloaded.modelOverride == "cursor/composer-2.5-fast")
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:'TenXAppTests/harnessNoticePreferencesDefaultToOff()' test
```

Expected: FAIL — compile error, type doesn't exist. (Run the generator first
if you already created the source file so the test file is in the project.)

- [ ] **Step 3: Implement the store**

Create `App/Settings/HarnessNoticePreferenceStore.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class HarnessNoticePreferenceStore {
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    /// Minimum hidden-message size (characters) that earns a notice. 0 = everything.
    var threshold: Int {
        didSet { defaults.set(threshold, forKey: Self.thresholdKey) }
    }

    /// Model id for summaries; nil = OMP's configured smol role.
    var modelOverride: String? {
        didSet { defaults.set(modelOverride, forKey: Self.modelOverrideKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let enabledKey = "tenx.harnessNotices.enabled.v1"
    private static let thresholdKey = "tenx.harnessNotices.threshold.v1"
    private static let modelOverrideKey = "tenx.harnessNotices.modelOverride.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        threshold = defaults.object(forKey: Self.thresholdKey) as? Int ?? 0
        modelOverride = defaults.string(forKey: Self.modelOverrideKey)
    }
}
```

- [ ] **Step 4: Regenerate, run tests**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/HarnessNoticePreferenceStoreTests test
```

Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add App/Settings/HarnessNoticePreferenceStore.swift Tests/TenXAppTests/HarnessNoticePreferenceStoreTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat: add harness notice preference store"
```

---

### Task 6: `HarnessNoticeSummarizer`

**Files:**
- Create: `App/Sessions/HarnessNoticeSummarizer.swift`
- Test: `Tests/TenXAppTests/HarnessNoticeSummarizerTests.swift` (create)

- [ ] **Step 1: Write the failing tests**

Create `Tests/TenXAppTests/HarnessNoticeSummarizerTests.swift`:

```swift
import Foundation
import Testing
@testable import TenXApp

private func noticeDescriptor(
    text: String = "Consider addressing the user's question directly."
) -> HarnessMessageDescriptor {
    HarnessMessageDescriptor(
        role: "custom",
        customType: "advisor",
        byteCount: text.count,
        text: text)
}

private func tempCacheURL() -> URL {
    URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("harness-summarizer-\(UUID().uuidString)")
        .appendingPathComponent("summaries.json")
}

@Test func summarizerReturnsTheLastStdoutLine() async {
    let summarizer = HarnessNoticeSummarizer(
        resolveModel: { "cursor/smol" },
        cacheURL: tempCacheURL(),
        run: { args in
            #expect(args.contains("-p"))
            #expect(args.contains("--no-session"))
            #expect(args.contains("--no-tools"))
            #expect(args.contains("cursor/smol"))
            return Data("Working...\nAn advisor note suggesting a direct answer.\n".utf8)
        })

    let summary = await summarizer.summarize(noticeDescriptor())

    #expect(summary == "An advisor note suggesting a direct answer.")
}

@Test func summarizerSkipsTheRunWhenNoModelResolves() async {
    let runCount = RunCount()
    let summarizer = HarnessNoticeSummarizer(
        resolveModel: { nil },
        cacheURL: tempCacheURL(),
        run: { _ in
            await runCount.increment()
            return Data()
        })

    let summary = await summarizer.summarize(noticeDescriptor())

    #expect(summary == nil)
    #expect(await runCount.value == 0)
}

@Test func summarizerCachesByContentHashAcrossInstances() async {
    let cacheURL = tempCacheURL()
    let runCount = RunCount()
    let make: () -> HarnessNoticeSummarizer = {
        HarnessNoticeSummarizer(
            resolveModel: { "cursor/smol" },
            cacheURL: cacheURL,
            run: { _ in
                await runCount.increment()
                return Data("cached summary\n".utf8)
            })
    }

    let first = await make().summarize(noticeDescriptor())
    let second = await make().summarize(noticeDescriptor())

    #expect(first == "cached summary")
    #expect(second == "cached summary")
    #expect(await runCount.value == 1)
}

@Test func summarizerReturnsNilWhenTheRunFails() async {
    struct RunError: Error {}
    let summarizer = HarnessNoticeSummarizer(
        resolveModel: { "cursor/smol" },
        cacheURL: tempCacheURL(),
        run: { _ in throw RunError() })

    #expect(await summarizer.summarize(noticeDescriptor()) == nil)
}

private actor RunCount {
    private(set) var value = 0
    func increment() { value += 1 }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — compile error, `HarnessNoticeSummarizer` doesn't exist.

- [ ] **Step 3: Implement the summarizer**

Create `App/Sessions/HarnessNoticeSummarizer.swift`:

```swift
import CryptoKit
import Foundation

protocol HarnessNoticeSummarizing: Sendable {
    /// One-line summary, or nil when no model is configured or the run fails —
    /// the caller then keeps the static notice text.
    func summarize(_ descriptor: HarnessMessageDescriptor) async -> String?
}

actor HarnessNoticeSummarizer: HarnessNoticeSummarizing {
    private let resolveModel: @Sendable () async -> String?
    private let run: @Sendable ([String]) async throws -> Data
    private let cacheURL: URL
    private var cache: [String: String]?
    private static let promptLimit = 8_000

    init(
        resolveModel: @escaping @Sendable () async -> String?,
        cacheURL: URL,
        run: @escaping @Sendable ([String]) async throws -> Data
    ) {
        self.resolveModel = resolveModel
        self.cacheURL = cacheURL
        self.run = run
    }

    static func defaultCacheURL() -> URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "10x", directoryHint: .isDirectory)
            .appending(path: "harness-summaries.json")
    }

    func summarize(_ descriptor: HarnessMessageDescriptor) async -> String? {
        let key = SHA256.hash(data: Data(descriptor.text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        if let cached = cachedSummaries()[key] { return cached }
        guard let model = await resolveModel() else { return nil }
        let prompt = """
            Summarize in one short sentence, for the user of a chat UI, what \
            this hidden harness message says. Plain text, no markup, 120 \
            characters max.

            \(descriptor.text.prefix(Self.promptLimit))
            """
        // omp -p self-terminates after answering; a hung child just leaves the
        // static notice. ponytail ceiling: no timeout — upgrade path is a
        // task-group race with a 60 s cap.
        guard let data = try? await run([
                "-p", "--model", model, "--no-session", "--no-tools", prompt]),
              let output = String(data: data, encoding: .utf8),
              let summary = output
                  .split(whereSeparator: \.isNewline)
                  .last?
                  .trimmingCharacters(in: .whitespaces),
              !summary.isEmpty
        else { return nil }
        cache?[key] = summary
        persist()
        return summary
    }

    private func cachedSummaries() -> [String: String] {
        if let cache { return cache }
        let loaded = (try? Data(contentsOf: cacheURL))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        cache = loaded
        return loaded
    }

    private func persist() {
        guard let cache,
              let data = try? JSONEncoder().encode(cache)
        else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Regenerate, run tests**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/HarnessNoticeSummarizerTests test
```

Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/HarnessNoticeSummarizer.swift Tests/TenXAppTests/HarnessNoticeSummarizerTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat: add cached omp -p summarizer for hidden harness messages"
```

---

### Task 7: SessionController wiring

**Files:**
- Modify: `App/Sessions/SessionController.swift` (init at line 80, processor creation at line 496)
- Test: `Tests/TenXAppTests/SessionControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/TenXAppTests/SessionControllerTests.swift`. These reuse the
file's existing `makeNavigationExecutable(in:mode:)` fake-omp helper (mode
`"activity-lifecycle"` handles the RPC handshake) and poll `controller.items`:

```swift
private struct StubHarnessSummarizer: HarnessNoticeSummarizing {
    let summary: String?
    func summarize(_ descriptor: HarnessMessageDescriptor) async -> String? {
        summary
    }
}

@MainActor @Test func droppedHarnessMessagesBecomeNoticesThatUpdateInPlace() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("controller-notices-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container, mode: "activity-lifecycle")

    let suiteName = "harness-notice-controller-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = HarnessNoticePreferenceStore(defaults: defaults)
    preferences.isEnabled = true

    let descriptor = HarnessMessageDescriptor(
        role: "developer",
        customType: nil,
        byteCount: 13,
        text: "Plan approved.")
    let controller = SessionController(
        processManager: SessionProcessManager(executable: executable.path),
        historyLoader: { _ in TranscriptHistory(items: [], dropped: [descriptor]) },
        harnessNoticePreferences: preferences,
        harnessNoticeSummarizer: StubHarnessSummarizer(summary: "A plan-approval gate."))
    let metadata = SessionMetadata(
        path: "/tmp/fake.jsonl",
        sessionId: "fake-session",
        cwd: "/tmp",
        title: "Fixture",
        createdAt: Date(),
        updatedAt: Date(),
        messageCount: 0,
        isArchived: false)

    await controller.openExisting(metadata)

    var noticeMessage: String?
    for _ in 0..<100 {
        noticeMessage = controller.items.compactMap { item -> String? in
            guard case .notice(_, _, let message) = item else { return nil }
            return message
        }.first
        if noticeMessage?.contains("A plan-approval gate.") == true { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(noticeMessage == "Hidden developer message (13 chars): A plan-approval gate.")
}

@MainActor @Test func droppedHarnessMessagesStaySilentWhenThePreferenceIsOff() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("controller-notices-off-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container, mode: "activity-lifecycle")

    let suiteName = "harness-notice-off-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = HarnessNoticePreferenceStore(defaults: defaults)  // isEnabled = false

    let descriptor = HarnessMessageDescriptor(
        role: "developer",
        customType: nil,
        byteCount: 13,
        text: "Plan approved.")
    let controller = SessionController(
        processManager: SessionProcessManager(executable: executable.path),
        historyLoader: { _ in TranscriptHistory(items: [], dropped: [descriptor]) },
        harnessNoticePreferences: preferences,
        harnessNoticeSummarizer: StubHarnessSummarizer(summary: "unused"))
    let metadata = SessionMetadata(
        path: "/tmp/fake.jsonl",
        sessionId: "fake-session",
        cwd: "/tmp",
        title: "Fixture",
        createdAt: Date(),
        updatedAt: Date(),
        messageCount: 0,
        isArchived: false)

    await controller.openExisting(metadata)
    try await Task.sleep(for: .milliseconds(200))

    #expect(controller.items.allSatisfy {
        if case .notice = $0 { return false }
        return true
    })
}
```

Check the existing `SessionMetadata` initializer labels against a nearby test
(e.g. `controllerReportsProviderAndRuntimeTransitionsFromRPCLifecycle`) and
match them — if the fixture there omits or renames a field, copy its shape.

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:'TenXAppTests/droppedHarnessMessagesBecomeNoticesThatUpdateInPlace()' test
```

Expected: FAIL — compile error, `SessionController` has no `harnessNoticePreferences` parameter.

- [ ] **Step 3: Wire the controller**

In `SessionController.swift`, add stored properties next to `historyLoader`:

```swift
    private let harnessNoticePreferences: HarnessNoticePreferenceStore?
    private let harnessNoticeSummarizer: (any HarnessNoticeSummarizing)?
```

Extend the primary `init` (line 80) — new parameters with defaults so every
existing call site keeps compiling:

```swift
    init(
        processManager: SessionProcessManager,
        id: UUID = UUID(),
        activityRegistry: SessionActivityRegistry? = nil,
        historyLoader: @escaping HistoryLoader = SessionController.loadHistory(path:),
        harnessNoticePreferences: HarnessNoticePreferenceStore? = nil,
        harnessNoticeSummarizer: (any HarnessNoticeSummarizing)? = nil
    ) {
        self.processManager = processManager
        self.id = id
        self.activityRegistry = activityRegistry
        self.historyLoader = historyLoader
        self.harnessNoticePreferences = harnessNoticePreferences
        self.harnessNoticeSummarizer = harnessNoticeSummarizer
    }
```

(The preview `init` at line 92 can stay as-is — previews get no notices.)

Add the handler:

```swift
    private func handleDroppedHarnessMessages(
        _ dropped: [HarnessMessageDescriptor],
        from source: TranscriptEventProcessor
    ) {
        guard let preferences = harnessNoticePreferences, preferences.isEnabled,
              let processor, processor === source
        else { return }
        for descriptor in dropped where descriptor.byteCount >= preferences.threshold {
            let label = Self.harnessNoticeLabel(descriptor)
            let noticeID = UUID().uuidString
            let summarizer = harnessNoticeSummarizer
            Task { [weak self] in
                await processor.appendNotice(id: noticeID, level: "info", message: label)
                guard let summarizer, self?.processor === processor else { return }
                let summary = await summarizer.summarize(descriptor)
                guard let summary else { return }
                await processor.updateNotice(id: noticeID, message: "\(label): \(summary)")
            }
        }
    }

    private static func harnessNoticeLabel(_ descriptor: HarnessMessageDescriptor) -> String {
        let size = descriptor.byteCount < 1_000
            ? "\(descriptor.byteCount) chars"
            : String(format: "%.1f KB", Double(descriptor.byteCount) / 1_000)
        return "Hidden \(descriptor.kindLabel) message (\(size))"
    }
```

Hook the callback where the processor is created (line 496-497):

```swift
            let processor = TranscriptEventProcessor()
            await processor.setOnDroppedHarnessMessages { [weak self, weak processor] dropped in
                Task { @MainActor [weak self, weak processor] in
                    guard let processor else { return }
                    self?.handleDroppedHarnessMessages(dropped, from: processor)
                }
            }
            self.processor = processor
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/SessionControllerTests test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/SessionController.swift Tests/TenXAppTests/SessionControllerTests.swift
git commit -m "feat: turn dropped harness messages into summarized transcript notices"
```

---

### Task 8: AppModel wiring

**Files:**
- Modify: `App/Application/AppModel.swift` (init at line 94, `makeSessionController` at line 696, the two `processManager = nil` teardowns at lines 858 and 1024)

No new tests — covered by the build and the existing suite.

- [ ] **Step 1: Add the store and summarizer**

Add the property next to `idePreferenceStore` (line 57):

```swift
    let harnessNoticePreferenceStore: HarnessNoticePreferenceStore
    private var harnessNoticeSummarizer: (any HarnessNoticeSummarizing)?
```

In `init`, next to the `idePreferenceStore` assignment (line 98):

```swift
        harnessNoticePreferenceStore = HarnessNoticePreferenceStore(defaults: preferenceDefaults)
```

In `makeSessionController` (line 696), build the summarizer lazily and pass
both dependencies:

```swift
    private func makeSessionController(
        processManager: SessionProcessManager,
        intendedSessionPath: String? = nil
    ) -> SessionController {
        if harnessNoticeSummarizer == nil, let installation {
            let executableURL = installation.executableURL
            let preferences = harnessNoticePreferenceStore
            let configService = OmpConfigService(
                runner: OmpConfigProcessRunner(executableURL: executableURL))
            harnessNoticeSummarizer = HarnessNoticeSummarizer(
                resolveModel: {
                    if let override = await preferences.modelOverride { return override }
                    guard let config = try? await configService.list() else { return nil }
                    return config["modelRoles"]?["value"]?["smol"]?.stringValue
                },
                cacheURL: HarnessNoticeSummarizer.defaultCacheURL(),
                run: { args in
                    try await OmpCommandRunner().run(
                        executableURL: executableURL,
                        arguments: args)
                })
        }
        let controller = SessionController(
            processManager: processManager,
            activityRegistry: sessionActivityRegistry,
            harnessNoticePreferences: harnessNoticePreferenceStore,
            harnessNoticeSummarizer: harnessNoticeSummarizer)
        // ... rest of the existing method unchanged ...
    }
```

(`config["modelRoles"]?["value"]?` — `omp config list --json` wraps each key
in an object whose `value` field holds the setting; `modelRoles.value` is the
`{"smol": "...", ...}` dictionary.)

Wherever `processManager = nil` happens on teardown (lines 858 and 1024), also
clear the summarizer so a changed executable doesn't leave a stale runner:

```swift
            harnessNoticeSummarizer = nil
```

- [ ] **Step 2: Build and run the suite**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests test
```

Expected: PASS (except the 3 known `ComposerPasteboardTests` failures).

- [ ] **Step 3: Commit**

```bash
git add App/Application/AppModel.swift
git commit -m "feat: wire harness notice preferences and summarizer into sessions"
```

---

### Task 9: Settings row

**Files:**
- Create: `App/Settings/HarnessNoticeSettingRowView.swift`
- Modify: `App/Settings/SettingsView.swift` (init, general-section row at line 208)
- Modify: `App/Shell/AppShellView.swift` (SettingsView call at line 200)
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift` (`continuous-settings` call at line 303)

- [ ] **Step 1: Create the row view**

Create `App/Settings/HarnessNoticeSettingRowView.swift`, mirroring
`PreferredIDESettingRowView`'s layout:

```swift
import SwiftUI

struct HarnessNoticeSettingRowView: View {
    @Bindable var store: HarnessNoticePreferenceStore
    let availableModels: [ComposerModelInfo]

    private static let thresholds: [(value: Int, label: String)] = [
        (0, "Everything"),
        (500, "500 chars"),
        (1_000, "1 KB"),
        (4_000, "4 KB"),
    ]

    static func matches(query: String) -> Bool {
        query.isEmpty
            || "hidden harness messages".localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Hidden harness messages")
                        .font(TenXTypography.body(size: 13, weight: .semibold))
                    Text("Show a transcript notice when a harness message is kept out of the chat, with a one-line summary from a small model")
                        .font(TenXTypography.body(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: $store.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if store.isEnabled {
                HStack(spacing: 30) {
                    Text("Notice threshold")
                        .font(TenXTypography.body(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        ForEach(Self.thresholds, id: \.value) { option in
                            Button(option.label) { store.threshold = option.value }
                        }
                    } label: {
                        Text(thresholdLabel)
                            .font(TenXTypography.body(size: 12))
                            .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    }
                    .menuStyle(.borderlessButton)
                }

                HStack(spacing: 30) {
                    Text("Summary model")
                        .font(TenXTypography.body(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        Button("OMP smol role") { store.modelOverride = nil }
                        if !availableModels.isEmpty {
                            Divider()
                            ForEach(availableModels) { model in
                                Button(model.name) { store.modelOverride = model.modelID }
                            }
                        }
                    } label: {
                        Text(modelLabel)
                            .font(TenXTypography.body(size: 12))
                            .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
        .padding(.vertical, 14)
    }

    private var thresholdLabel: String {
        Self.thresholds.first(where: { $0.value == store.threshold })?.label
            ?? "\(store.threshold) chars"
    }

    private var modelLabel: String {
        guard let override = store.modelOverride else { return "OMP smol role" }
        return availableModels.first(where: { $0.modelID == override })?.name ?? override
    }
}
```

- [ ] **Step 2: Wire it into SettingsView**

In `App/Settings/SettingsView.swift`, add two parameters with defaults (keeps
previews and other call sites compiling):

```swift
    let harnessNoticeStore: HarnessNoticePreferenceStore?
    let availableModels: [ComposerModelInfo]
```

with `= nil` / `= []` defaults in the init, matching how the existing
parameters are declared.

Add the visibility helper next to `showsPreferredIDERow` (line 239):

```swift
    private var showsHarnessNoticeRow: Bool {
        harnessNoticeStore != nil
            && HarnessNoticeSettingRowView.matches(query: model.query)
    }
```

In `sectionView`, immediately after the `showsPreferredIDERow` block (after
line 222's closing brace), add:

```swift
            if section.category == .general, let harnessNoticeStore, showsHarnessNoticeRow {
                HarnessNoticeSettingRowView(
                    store: harnessNoticeStore,
                    availableModels: availableModels)

                if !section.definitions.isEmpty {
                    Divider()
                }
            }
```

`documentSections` (line 231) already synthesizes an empty `.general` section
when `showsPreferredIDERow` is true; extend that condition so the general
section also appears when only the harness row shows:

```swift
    private var documentSections: [SettingsSection] {
        let sections = model.sections
        let showsAppRows = showsPreferredIDERow || showsHarnessNoticeRow
        guard showsAppRows, !sections.contains(where: { $0.category == .general }) else {
            return sections
        }
        return [SettingsSection(category: .general, definitions: [])] + sections
    }
```

- [ ] **Step 3: Pass the dependencies at the call sites**

In `App/Shell/AppShellView.swift` (line 200):

```swift
                SettingsView(
                    model: settingsModel,
                    registry: model.ideRegistry,
                    store: model.idePreferenceStore,
                    focusTarget: model.settingsFocusTarget,
                    onFocusConsumed: model.consumeSettingsFocus,
                    onBack: { model.leaveSettings() },
                    providerModel: model.providerModel,
                    harnessNoticeStore: model.harnessNoticePreferenceStore,
                    availableModels: model.composerControls?.models ?? [])
```

In `Tests/TenXAppTests/ViewSnapshotTests.swift` (line 303), pass a store backed
by the test's `defaults` so the row is covered by the snapshot:

```swift
        SettingsView(
            model: model,
            registry: registry,
            store: store,
            providerModel: providerModel,
            harnessNoticeStore: HarnessNoticePreferenceStore(defaults: defaults),
            availableModels: []),
```

- [ ] **Step 4: Regenerate, build, re-record the settings snapshot**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/ViewSnapshotTests test
```

Expected: the `continuous-settings` snapshot FAILS against the old reference
and writes `continuous-settings.actual.png` next to the references (host
environment variables don't reach the test process, so the record-env path
isn't available — the actual-file flow is the established one).

Open the actual image, confirm the new "Hidden harness messages" row renders
correctly in the General section (toggle off, no threshold/model rows visible),
then promote it:

```bash
mv <references-dir>/continuous-settings.actual.png <references-dir>/continuous-settings.png
```

(The references directory is the one `SnapshotHarness.swift` resolves — check
its header for the exact path.) Re-run the snapshot tests: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/Settings/HarnessNoticeSettingRowView.swift App/Settings/SettingsView.swift App/Shell/AppShellView.swift Tests/TenXAppTests/ViewSnapshotTests.swift 10x.xcodeproj/project.pbxproj <references-dir>/continuous-settings.png
git commit -m "feat: add hidden harness message settings row"
```

---

### Task 10: Full verification

- [ ] **Step 1: Full suite**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests test
```

Expected: PASS, except the 3 known pre-existing `ComposerPasteboardTests`
failures (another session's WIP — do not fix).

- [ ] **Step 2: App build**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual smoke (report to user, don't gate on it)**

With the toggle on and a `smol` role configured, open a session known to
contain developer walls or display:false nudges (e.g. the advisor session from
the spec's table) and confirm notices appear with summaries. With the toggle
off, confirm silence.

---

## Self-review notes (already applied)

- **Spec coverage:** catch rule (Tasks 1-3), notice + in-place update (4, 7),
  summarizer + cache (6), model resolution incl. override (8), settings (5, 9),
  off-by-default (5 test), silence-when-off (7 test), threshold (5, 7, 9).
  Out-of-scope items (badge, popover, session-file advisor rendering) have no
  tasks — intentional.
- **Type consistency:** `HarnessMessageDescriptor(role:customType:byteCount:text:)`
  + `signature`/`kindLabel`; `drainDroppedHarnessMessages()`;
  `setOnDroppedHarnessMessages(_:)`; `appendNotice(id:level:message:)` /
  `updateNotice(id:message:)` on both reducer and processor;
  `HarnessNoticePreferenceStore(defaults:)` with `isEnabled`/`threshold`/
  `modelOverride`; `HarnessNoticeSummarizing.summarize(_:)`;
  `HarnessNoticeSummarizer(resolveModel:cacheURL:run:)` +
  `defaultCacheURL()`; controller params `harnessNoticePreferences:` /
  `harnessNoticeSummarizer:`; view `HarnessNoticeSettingRowView(store:availableModels:)`.
- **Deliberate simplifications:** threshold compares characters
  (`String.count`), labeled "chars" in the UI; no summarization timeout
  (ponytail ceiling noted in code); model override stores `modelID` only
  (omp resolves provider ambiguity); repeated identical hidden messages
  collapse to one notice per session (signature dedup).

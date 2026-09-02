# Streaming Normalization Backpressure Implementation Plan

**Goal:** Prevent cumulative streaming messages from repeatedly normalizing the full growing payload on every chunk while preserving complete content and event order.

**Architecture:** `TranscriptEventProcessor` keeps one pending identified `message_update`. Consecutive updates for the same message replace that slot; the existing 50 ms timer, an ordering boundary, an explicit snapshot read, reconciliation, or shutdown drains the newest frame through `TranscriptReducer` once. Different message identities drain in arrival order so custom skill blocks and assistant messages remain lossless.

**Tech Stack:** Swift 6, Foundation concurrency, OmpKit, Swift Testing, Xcode 17, macOS 15+

**Spec:** `docs/superpowers/specs/2026-09-02-streaming-normalization-backpressure-design.md`

## Baseline and Constraints

- The follow-up is stacked on `codex/harden-renderer-surfaces` / PR #19 and must not modify that branch.
- Baseline at `0dc4deb` passed all 1,217 tests in `/private/tmp/tenx-stream-normalization-baseline`.
- Preserve the existing 50 ms / maximum 20 Hz publication cadence.
- Never truncate or discard a final payload.
- Coalesce only consecutive `message_update` frames with the same explicit message ID. Different IDs and unidentified updates stay lossless.
- Keep backpressure inside `TranscriptEventProcessor`; do not add renderer workarounds, dependencies, or provider assumptions.
- Do not hand-edit `10x.xcodeproj/project.pbxproj`.
- Use deterministic counters and explicit timer hooks in tests; do not assert wall-clock performance.

---

### Task 1: Lock the Backpressure Contract with Failing Tests

**Files:**
- Modify: `Tests/TenXAppTests/TranscriptEventProcessorTests.swift`
- Modify: `App/Sessions/TranscriptEventProcessor.swift` only to add the Debug test counter seam

**Interfaces:**
- Produces: `testingMessageUpdateReductionCount()` under `#if DEBUG`
- Changes: the existing 1,000-update burst test proves reducer work, not only publication count

- [ ] **Step 1: Add the Debug-only reduction counter seam**

Add a counter stored only in Debug builds and increment it immediately before a `message_update` is passed into `TranscriptReducer.consume`. Expose it next to the existing timer-generation helpers:

```swift
#if DEBUG
private var messageUpdateReductionCount = 0
#endif

#if DEBUG
func testingMessageUpdateReductionCount() -> Int {
    messageUpdateReductionCount
}
#endif
```

At this step, keep the existing eager reducer call so the counter accurately exposes the failing behavior.

- [ ] **Step 2: Strengthen the existing burst test**

Rename `burstUpdatesCoalesceIntoOneManualFlush` to `burstUpdatesNormalizeOnlyNewestPayloadOnManualFlush`. After 1,000 `consume` calls, assert the counter is still zero; after `flush()`, assert it is one and the visible content is `token-1000`.

Add a test that sends two same-ID updates and checks:

```swift
let originalTimer = await processor.testingTimerGeneration()
#expect(await processor.testingMessageUpdateReductionCount() == 0)
#expect(await processor.testingTimerGeneration() == originalTimer)
```

The final flush must expose only the second payload and increment the counter once.

- [ ] **Step 3: Prove distinct message identities are not collapsed**

Queue a displayed custom skill update for `skill-1`, then an assistant update for `assistant-1`, flush, and assert both IDs and complete texts remain in arrival order. The reduction counter must equal two because changing identity is an ordering boundary.

- [ ] **Step 4: Run the focused tests and capture the red result**

Run:

```bash
xcodebuild test -quiet -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/tenx-stream-normalization-red \
  -only-testing:'TenXAppTests/burstUpdatesNormalizeOnlyNewestPayloadOnManualFlush()' \
  -only-testing:'TenXAppTests/replacementUpdateReusesPendingSlotAndTimer()' \
  -only-testing:'TenXAppTests/differentMessageIdentitiesRemainLossless()'
```

Expected: the eager implementation reports one reduction per same-ID update, so the zero/one count assertions fail.

- [ ] **Step 5: Commit the failing contract**

```bash
git add App/Sessions/TranscriptEventProcessor.swift Tests/TenXAppTests/TranscriptEventProcessorTests.swift
git commit -m "test(streaming): expose cumulative normalization pressure"
```

---

### Task 2: Move Coalescing Ahead of Normalization

**Files:**
- Modify: `App/Sessions/TranscriptEventProcessor.swift`
- Modify: `Tests/TenXAppTests/TranscriptEventProcessorTests.swift`

**Interfaces:**
- Adds: one private pending update containing explicit message ID and `RpcFrame`
- Adds: private `messageUpdateIdentity`, `enqueueMessageUpdate`, `drainPendingMessageUpdate`, `combinedMutation`, and snapshot-construction helpers
- Changes: `consume`, `load`, `currentSnapshot`, `flush`, `reconcile`, `publishNow`, and `stop`

- [ ] **Step 1: Add one pending slot and identity extraction**

Use a private value that retains only one frame:

```swift
private struct PendingMessageUpdate {
    let messageID: String
    let frame: RpcFrame
}

private var pendingMessageUpdate: PendingMessageUpdate?
```

`messageUpdateIdentity(_:)` returns an ID only for an event whose type is `message_update` and whose payload contains `message.id`. Do not invent an identity for malformed or unidentified updates.

- [ ] **Step 2: Enqueue same-ID updates without invoking the reducer**

In `consume(_:)`:

1. Keep `.extensionUIRequest` and `.providerAccountChanged` on their existing control-only path.
2. If the frame is an identified `message_update`, replace a same-ID pending frame and ensure one publication timer exists.
3. If the ID differs, drain and publish/schedule the older mutation before retaining the new frame.
4. If the frame is not coalescible, drain pending work first, reduce the new frame, combine mutation precedence, then publish once.

The mutation combiner returns `.immediate` if either input is immediate, otherwise `.coalesced` if either is coalesced, otherwise `.none`.

- [ ] **Step 3: Centralize draining and snapshot construction**

`drainPendingMessageUpdate()` clears the slot before calling the reducer so no reentrant path can process it twice. Increment the Debug counter at this single reducer boundary.

Create a private `makeSnapshot()` that reads reducer state without draining. `currentSnapshot()` drains pending work, marks a changed reducer result dirty and scheduled, then returns `makeSnapshot()` without incrementing the revision. `publishNow()` drains any remaining pending work, cancels the timer, clears dirty state, increments the revision, yields `makeSnapshot()`, and never calls `currentSnapshot()`.

- [ ] **Step 4: Apply lifecycle semantics**

- `load(...)`: cancel the timer and clear any pending frame before loading authoritative initial content.
- `flush()`: drain first, treat every non-`.none` result as dirty, then publish only when dirty.
- `reconcile(...)`: drain first and combine that mutation with history and warning mutations.
- `stop()`: flush pending or dirty content before marking stopped and finishing both streams.
- Existing immediate mutation methods may continue calling `publishNow()` because it now drains pending work before snapshot creation.

- [ ] **Step 5: Run the focused contract tests**

Run the command from Task 1.

Expected: all three tests pass; 1,000 same-ID updates produce one reducer normalization, and different IDs remain lossless.

- [ ] **Step 6: Commit the processor implementation**

```bash
git add App/Sessions/TranscriptEventProcessor.swift Tests/TenXAppTests/TranscriptEventProcessorTests.swift
git commit -m "perf(streaming): coalesce cumulative normalization"
```

---

### Task 3: Verify Ordering, Reads, Reconciliation, and Shutdown

**Files:**
- Modify: `Tests/TenXAppTests/TranscriptEventProcessorTests.swift`
- Modify: `App/Sessions/TranscriptEventProcessor.swift` only if a test exposes a contract defect

**Behavior:**
- A pending update is visible to explicit reads without premature revision changes.
- Final and lifecycle boundaries cannot overtake pending content.
- Reconciliation sees the newest accepted update.
- Shutdown publishes the last accepted cumulative payload before stream completion.

- [ ] **Step 1: Add current-snapshot and timer tests**

After queuing one update, call `currentSnapshot()` and assert it contains the update, the reduction count becomes one, and revision is unchanged. Assert a following `flush()` yields exactly one publication and increments the revision once. Fire the captured stale timer token and assert it cannot publish again.

- [ ] **Step 2: Strengthen boundary tests**

Extend `immediateBoundaryFlushesBeforeControlForwarding` and `turnEndFlushesPendingCoalescedSnapshotBeforeControl` to assert the pending update was reduced exactly once before the control event. Retain the existing final-content and control-order assertions.

- [ ] **Step 3: Add reconciliation and stop tests**

- Queue an update, reconcile with a newer generation, and assert the Debug count proves the update drained before reconciliation.
- Queue an update, call `stop()`, consume the buffered snapshot, and assert it contains the newest text before the snapshot stream returns `nil`.
- Queue an update, then call `load(...)` with authoritative content and assert the pre-load pending frame is absent.

- [ ] **Step 4: Run all processor and reducer tests**

```bash
xcodebuild test -quiet -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/tenx-stream-normalization-focused \
  -only-testing:TenXAppTests/TranscriptEventProcessorTests \
  -only-testing:TenXAppTests/TranscriptReducerTests
```

Expected: both suites pass with no loss or reordering regressions.

- [ ] **Step 5: Commit lifecycle coverage**

```bash
git add App/Sessions/TranscriptEventProcessor.swift Tests/TenXAppTests/TranscriptEventProcessorTests.swift
git commit -m "test(streaming): cover normalization drain boundaries"
```

---

### Task 4: Add the Saturation Regression and Verify the Product

**Files:**
- Modify: `Tests/TenXAppTests/RendererSaturationFixtureTests.swift`
- Modify: `docs/performance/2026-09-01-renderer-saturation-audit.md` with fresh evidence only

**Behavior:**
- A multi-megabyte final cumulative payload is normalized once and remains complete.
- The exact optimized Release artifact remains responsive during the real skill invocation.

- [ ] **Step 1: Add a bounded multi-megabyte fixture**

Build 32 identified assistant `message_update` frames whose cumulative plain-text payload grows to at least 2 MiB. Keep the publication interval at 60 seconds, then flush manually. Assert:

- zero reductions before the flush;
- one reduction after the flush;
- one final transcript message;
- visible text length equals the final payload length;
- first and last sentinels remain intact.

Do not use elapsed-time assertions. The finite reducer count is the deterministic performance contract.

- [ ] **Step 2: Run saturation and full test suites**

```bash
xcodebuild test -quiet -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/tenx-stream-normalization-saturation \
  -only-testing:TenXAppTests/RendererSaturationFixtureTests

xcodebuild test -quiet -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/tenx-stream-normalization-full
```

Expected: saturation coverage and the complete suite pass.

- [ ] **Step 3: Confirm project generation is reproducible**

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
git diff --exit-code -- 10x.xcodeproj/project.pbxproj
git diff --check
```

Expected: the generated project is unchanged and the patch has no whitespace errors.

- [ ] **Step 4: Build the optimized universal Release artifact**

```bash
xcodebuild build -quiet -project 10x.xcodeproj -scheme 10x \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-stream-normalization-release

lipo -archs /private/tmp/tenx-stream-normalization-release/Build/Products/Release/10x.app/Contents/MacOS/10x
```

Expected: the build succeeds and reports `x86_64 arm64`.

- [ ] **Step 5: Launch and sample the exact artifact**

Before launching, invoke `launching-local-builds`. Launch only the app at `/private/tmp/tenx-stream-normalization-release/Build/Products/Release/10x.app`, confirm the visible process executable resolves to that path, and invoke the local `using-superpowers` skill from the UI.

Capture CPU/RSS during the skill load and after completion. Confirm the skill block precedes later output, the application stays interactive, CPU returns toward idle, RSS stabilizes, and the complete content remains copyable.

- [ ] **Step 6: Record evidence and update the draft PR**

Append only the new follow-up evidence to `docs/performance/2026-09-01-renderer-saturation-audit.md`, commit it, and update PR #20 with exact commands, test counts, artifact path, executable architectures, process identity, and manual observations.

```bash
git add Tests/TenXAppTests/RendererSaturationFixtureTests.swift docs/performance/2026-09-01-renderer-saturation-audit.md
git commit -m "test(streaming): verify normalization saturation"
git push
```

Do not flip the draft PR, merge, or change PR #19 in this plan.

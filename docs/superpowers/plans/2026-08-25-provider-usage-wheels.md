# Provider Usage Wheels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the expanded rail usage ledger with persistent bottom-right concentric provider wheels that show every remaining-capacity limit, count all generating 10x-managed sessions by provider, and expand in place into the full account and bar breakdown.

**Architecture:** Keep OMP usage normalization in `ProviderUsagePresentation`, adding deterministic provider abbreviations and stable window-duration ordering. Retain each opened `SessionController` in `AppModel` and have it report provider and streaming changes to one main-actor `SessionActivityRegistry`, avoiding a second RPC event consumer. Compose the compact and expanded states in a shell-owned `ProviderUsageDockView`; reuse `ProviderUsageLimitDetailView` for the expanded semantic-color bars and remove the rail ledger.

**Tech Stack:** macOS 15+, Swift 6, SwiftUI, Observation, Foundation, OmpKit RPC state/events, Swift Testing, Xcode snapshot tests. No new dependency.

**Spec:** `docs/superpowers/specs/2026-08-25-provider-usage-wheels-design.md`

## Global Constraints

- Execute in `/Users/tannerpham/CS Projects/.worktrees/10x-usage-wheels` on branch `codex/usage-wheels`. Never edit the main checkout or another session's worktree.
- The repository has no Git remote. Keep atomic local commits as the handoff boundary; a draft PR cannot be opened until a remote exists.
- Before implementation, load `superpowers:test-driven-development`; for Tasks 5 through 7 also load `writing-ui` and `visual-ui`; before Task 8 launch and completion claims load `launching-local-builds` and `verifying-work`.
- Use the existing usage snapshot and session RPC contracts. Do not modify OMP, authentication, usage refresh cadence, or OmpKit production code.
- Render one compact wheel per provider with computable limits. Render every such limit; never cap or summarize the ring count.
- Order rings from short to long window duration, inner to outer. Keep equal-duration and unknown-duration limits in OMP source order.
- Use stable labels `ANT`, `OAI`, `CUR`, and `GCA` for the approved known providers; derive a deterministic three-character fallback for all others.
- Compact wheels are 54 points in diameter. Do not add provider logos, filled cards, shadows, pills, or decorative backgrounds.
- Compact arcs use cyan above 20%, yellow from 1% through 20%, and signal red at 0%. When and only when the foreground `.session` controller is streaming, all compact limit arcs use grayscale.
- The provider activity core remains provider-specific and continues showing its count and pulse while compact limit arcs are grayscale. Expanded wheel tabs and bars always use semantic colors.
- Activity counts include top-level sessions opened by this 10x process only. Do not count external OMP processes, accounts, or subagents separately.
- Expanded content preserves provider and account grouping, shows every limit bar, scrolls internally, and dismisses by close, Escape, or outside click without navigating away from the current route.
- Respect Reduce Motion: keep the numeric activity state, remove pulse and geometry morph, and use an immediate or opacity-only state change.
- Keep the existing Providers workspace for refresh, stale warnings, notes, non-percentage amounts, credentials, and recovery.
- Move existing user-facing usage accessibility copy into a shared provider file before deleting the ledger. Full provider names must remain accessible; abbreviations are visual only.
- Run `ruby scripts/generate_xcodeproj.rb` after adding or removing Swift files and before every `xcodebuild` command.
- Use a task-specific DerivedData directory under `/tmp`; do not use port 3000.
- Baseline recorded on 2026-08-25: `cd OmpKit && swift test` passed with two expected opt-in integration skips; the app scheme passed 237 tests.

## File Structure

### New production files

- `App/Sessions/SessionActivityRegistry.swift`: one observable main-actor registry mapping stable controller ids to provider and generating state.
- `App/Providers/ProviderUsageAccessibility.swift`: shared limit and compact-wheel accessibility descriptions moved out of the deleted rail ledger.
- `App/Providers/ProviderUsageWheelView.swift`: 54-point concentric geometry, semantic/grayscale arcs, activity core, pulse, and three-letter label.
- `App/Providers/ProviderUsageDockView.swift`: collapsed wheel group, anchored expansion, provider switching, account/bar breakdown, dismissal, and focus restoration.

### New test files

- `Tests/TenXAppTests/SessionActivityRegistryTests.swift`: aggregation, deduplication, provider changes, idle transitions, and cleanup.
- `Tests/TenXAppTests/ProviderUsageRingGeometryTests.swift`: one-ring through dense-ring geometry and no-limit omission.

### Existing files changed

- Presentation: `App/Providers/ProviderUsagePresentation.swift`, `App/Providers/ProviderManagementViewModel.swift`, `Tests/TenXAppTests/ProviderUsagePresentationTests.swift`.
- Session observation: `App/Sessions/SessionController.swift`, `App/Application/AppModel.swift`, `Tests/TenXAppTests/SessionControllerTests.swift`, `Tests/TenXAppTests/AppModelNavigationTests.swift`, `OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py`.
- Shell integration: `App/Shell/AppShellView.swift`, `App/Shell/FloatingRailView.swift`, `App/Providers/ProviderUsageDetailView.swift`, `Tests/TenXAppTests/AccessibilityLabelTests.swift`, `Tests/TenXAppTests/ViewSnapshotTests.swift`.
- Remove: `App/Shell/ProviderUsageLedgerView.swift`, `Tests/TenXAppTests/ReferenceImages/provider-usage-rail.png`.
- Add/update snapshot evidence under `Tests/TenXAppTests/ReferenceImages/` for compact idle, compact generating, expanded generating, full shell, and minimum window.
- Generated project membership: `10x.xcodeproj/project.pbxproj` via `scripts/generate_xcodeproj.rb`.

---

### Task 1: Normalize provider abbreviations and stable ring order

**Files:**
- Modify: `Tests/TenXAppTests/ProviderUsagePresentationTests.swift`
- Modify: `App/Providers/ProviderUsagePresentation.swift`
- Modify: `App/Providers/ProviderManagementViewModel.swift`

**Interfaces:**
- Consumes: `OmpUsageLimit.window.id`, `window.label`, `scope.windowId`, and provider-local source position.
- Produces: `ProviderUsageLimit.windowDurationRank`, `sourceIndex`, and `ProviderUsageProvider.ringLimits` ordered inner-to-outer.
- Produces: `ProviderUsageProvider.abbreviation` and `ProviderUsagePresentation.dockProviders`.

- [ ] **Step 1: Write failing duration-order tests**

Add a fixture whose source order is weekly, unknown A, 5-hour, daily, unknown B, then assert:

```swift
let provider = try #require(presentation.dockProviders.first)
#expect(provider.ringLimits.map(\.label) == [
    "5 hour",
    "Unknown A",
    "Daily",
    "Weekly",
    "Unknown B",
])
```

Add a second fixture with two daily limits and two unknown limits. Assert daily ties retain their original order, unknowns retain their original order, and `ringLimits.count` equals the number of computable limits across every account.

- [ ] **Step 2: Write failing abbreviation tests**

Assert the known mapping and two deterministic fallbacks:

```swift
#expect(ProviderUsageProvider(id: "anthropic", name: "Anthropic", accounts: []).abbreviation == "ANT")
#expect(ProviderUsageProvider(id: "openai-codex", name: "ChatGPT", accounts: []).abbreviation == "OAI")
#expect(ProviderUsageProvider(id: "cursor", name: "Cursor", accounts: []).abbreviation == "CUR")
#expect(ProviderUsageProvider(id: "google-gemini-cli", name: "Google Cloud Code Assist", accounts: []).abbreviation == "GCA")
#expect(ProviderUsageProvider(id: "github-copilot", name: "GitHub Copilot", accounts: []).abbreviation == "GHC")
#expect(ProviderUsageProvider(id: "x", name: "X", accounts: []).abbreviation.count == 3)
```

- [ ] **Step 3: Run the focused tests and verify RED**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-usage-wheels-tests \
  -only-testing:TenXAppTests/ProviderUsagePresentationTests test
```

Expected: compilation fails because `dockProviders`, `ringLimits`, ordering metadata, and `abbreviation` do not exist.

- [ ] **Step 4: Add explicit ordering metadata without changing percentage math**

Extend `ProviderUsageLimit` with defaulted metadata so existing fixtures remain source-compatible:

```swift
let windowDurationRank: Int?
let sourceIndex: Int

init(
    id: String,
    label: String,
    percentage: Int,
    detailReset: String?,
    railReset: String,
    windowDurationRank: Int? = nil,
    sourceIndex: Int = 0
) {
    self.id = id
    self.label = label
    self.percentage = percentage
    self.detailReset = detailReset
    self.railReset = railReset
    self.windowDurationRank = windowDurationRank
    self.sourceIndex = sourceIndex
}
```

Keep all current convenience initializers and forward their default metadata. In `ProviderUsagePresentation.make`, maintain a provider-local next-source-index counter and pass a unique source index into `account(from:now:sourceIndexOffset:)` for each original OMP limit, including positions occupied by non-computable limits.

Normalize the first recognized value from `window.id`, `window.label`, and `scope.windowId`. Map the contract's known windows to ascending minute-like ranks:

```swift
private static let knownWindowDurationRanks = [
    "hourly": 60,
    "1-hour": 60,
    "five-hour": 300,
    "5-hour": 300,
    "5 hour": 300,
    "daily": 1_440,
    "day": 1_440,
    "weekly": 10_080,
    "week": 10_080,
    "monthly": 43_200,
    "month": 43_200,
    "annual": 525_600,
    "yearly": 525_600,
    "year": 525_600,
]
```

Do not infer a duration from reset timestamps. An unrecognized window gets `nil`.

- [ ] **Step 5: Add provider-level ring ordering and abbreviation**

Add `ringLimits` by flattening in OMP source order, extracting only known-duration entries, and sorting those known entries by duration rank, stored source index, then flattened offset. Walk the original flattened slots and replace only known-duration slots from that sorted sequence; leave each unknown-duration entry in its original slot. This orders every comparable window without guessing where an unknown duration belongs.

Add the known abbreviation map. For fallback values, split the display name into alphanumeric words. Three or more words use their first three initials; two words use the first two characters of the first word plus the second word's initial; one word uses its first three characters. Append uppercase alphanumeric characters from the provider id, then `X`, only when the display name supplies fewer than three characters. This yields `GHC` for GitHub Copilot and always returns exactly three user-perceived characters without truncating by UTF-8 byte count.

Rename the filtered usage surface from `railProviders` to `dockProviders` in both `ProviderUsagePresentation` and `ProviderManagementViewModel`. Continue filtering only non-computable amounts from the compact dock; do not alter detailed provider usage.

- [ ] **Step 6: Run the focused tests and verify GREEN**

Run the Step 3 command. Expected: duration, retention, and abbreviation tests pass with the pre-existing percentage, account, and tone tests unchanged.

- [ ] **Step 7: Commit the presentation slice**

```bash
git add App/Providers/ProviderUsagePresentation.swift \
  App/Providers/ProviderManagementViewModel.swift \
  Tests/TenXAppTests/ProviderUsagePresentationTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "feat(providers): order usage wheel limits"
```

---

### Task 2: Aggregate activity for all managed sessions

**Files:**
- Create: `Tests/TenXAppTests/SessionActivityRegistryTests.swift`
- Create: `App/Sessions/SessionActivityRegistry.swift`
- Modify: `10x.xcodeproj/project.pbxproj` through `scripts/generate_xcodeproj.rb`

**Interfaces:**
- Consumes: stable controller `UUID`, optional OMP provider id, and `isGenerating`.
- Produces: observable `[String: Int]` active counts, deduplicated by controller id.

- [ ] **Step 1: Write failing registry tests**

Cover these behaviors in isolated `@MainActor` tests:

```swift
let registry = SessionActivityRegistry()
let first = UUID()
let second = UUID()

registry.update(sessionID: first, providerID: "anthropic", isGenerating: true)
registry.update(sessionID: second, providerID: "anthropic", isGenerating: true)
#expect(registry.activeCounts == ["anthropic": 2])

registry.update(sessionID: first, providerID: "openai-codex", isGenerating: true)
#expect(registry.activeCounts == ["anthropic": 1, "openai-codex": 1])

registry.update(sessionID: second, providerID: "anthropic", isGenerating: false)
#expect(registry.activeCounts == ["openai-codex": 1])

registry.remove(sessionID: first)
#expect(registry.activeCounts.isEmpty)
```

Add assertions that repeating the same update does not double-count, an unknown provider does not contribute, and removal of a missing id is harmless.

- [ ] **Step 2: Run the focused tests and verify RED**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-usage-wheels-tests \
  -only-testing:TenXAppTests/SessionActivityRegistryTests test
```

Expected: compilation fails because `SessionActivityRegistry` does not exist.

- [ ] **Step 3: Implement the minimal observable registry**

Use one private state dictionary and derive counts on update rather than exposing session identities:

```swift
import Observation

@MainActor
@Observable
final class SessionActivityRegistry {
    private struct State: Equatable {
        let providerID: String?
        let isGenerating: Bool
    }

    private(set) var activeCounts: [String: Int] = [:]
    @ObservationIgnored private var states: [UUID: State] = [:]

    func update(sessionID: UUID, providerID: String?, isGenerating: Bool) {
        states[sessionID] = State(providerID: providerID, isGenerating: isGenerating)
        activeCounts = Self.counts(states.values)
    }

    func remove(sessionID: UUID) {
        states.removeValue(forKey: sessionID)
        activeCounts = Self.counts(states.values)
    }
}
```

Implement `counts` with a single reduction that includes only `isGenerating == true` and nonempty provider ids. Do not expose mutable session state or introduce a service protocol.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run the Step 2 command. Expected: all registry tests pass.

- [ ] **Step 5: Commit the registry**

```bash
git add App/Sessions/SessionActivityRegistry.swift \
  Tests/TenXAppTests/SessionActivityRegistryTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "feat(sessions): aggregate provider activity"
```

---

### Task 3: Report provider and runtime transitions from each controller

**Files:**
- Modify: `Tests/TenXAppTests/SessionControllerTests.swift`
- Modify: `App/Sessions/SessionController.swift`

**Interfaces:**
- Consumes: `get_state.model.provider`, `config_update.model.provider`, model refreshes, reducer runtime transitions, failures, and unexpected exits.
- Produces: `SessionController.id`, `providerID`, registry updates, and explicit tracking cleanup.

- [ ] **Step 1: Write failing provider parsing and lifecycle tests**

Add pure parsing assertions for OMP's object model shape and safe missing values:

```swift
#expect(SessionController.providerID(from: .object([
    "id": .string("claude-sonnet"),
    "provider": .string("anthropic"),
])) == "anthropic")
#expect(SessionController.providerID(from: .string("claude-sonnet")) == nil)
#expect(SessionController.providerID(from: nil) == nil)
```

Update `unexpectedExitPreservesDraftAndOffersRecovery` to inject a registry and a stable id, seed an active entry, call `handleUnexpectedExit`, and assert the count is removed. Add a cleanup test proving `stopActivityTracking()` removes the controller entry.

- [ ] **Step 2: Run the focused tests and verify RED**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-usage-wheels-tests \
  -only-testing:TenXAppTests/SessionControllerTests test
```

Expected: compilation fails because controller identity, provider parsing, registry injection, and cleanup do not exist.

- [ ] **Step 3: Add identity and optional registry injection**

Add these controller members and preserve the current simple initializer call sites with defaults:

```swift
let id: UUID
private(set) var providerID: String?
private let activityRegistry: SessionActivityRegistry?

init(
    processManager: SessionProcessManager,
    id: UUID = UUID(),
    activityRegistry: SessionActivityRegistry? = nil
) {
    self.processManager = processManager
    self.id = id
    self.activityRegistry = activityRegistry
}
```

Give the preview initializer the same defaulted identity and optional provider/registry inputs without changing existing snapshot call sites.

- [ ] **Step 4: Parse and report every authoritative transition**

Implement `providerID(from:)` by reading only the model object's nonempty `provider` string. Do not infer provider identity from the model name.

Add one helper:

```swift
private func reportActivity() {
    activityRegistry?.update(
        sessionID: id,
        providerID: providerID,
        isGenerating: runtimeState == .streaming)
}
```

Call it after:

- `openExisting`, `openNew`, and `restart` set `.loading`;
- `applyState` updates provider and `isStreaming`;
- `syncReducerState` adopts reducer state;
- `config_update` changes model/provider metadata;
- `refreshState` applies a new state;
- `fail` changes the runtime to `.failed`.

When a state payload contains a `model` member, update both `modelName` and `providerID`; when it omits `model`, retain the previous provider. Keep `model_changed` using the existing `get_state` refresh so the provider remains authoritative.

On `handleUnexpectedExit`, remove the registry entry after setting recovery state. Add internal `stopActivityTracking()` for `AppModel` close/archive/delete cleanup. A later restart re-registers through the normal loading/state path.

- [ ] **Step 5: Run controller and registry tests**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-usage-wheels-tests \
  -only-testing:TenXAppTests/SessionControllerTests \
  -only-testing:TenXAppTests/SessionActivityRegistryTests test
```

Expected: provider parsing and all activity cleanup tests pass.

- [ ] **Step 6: Commit controller reporting**

```bash
git add App/Sessions/SessionController.swift \
  Tests/TenXAppTests/SessionControllerTests.swift
git commit -m "feat(sessions): report provider runtime activity"
```

---

### Task 4: Retain and reuse all 10x-managed session controllers

**Files:**
- Modify: `OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py`
- Modify: `Tests/TenXAppTests/AppModelNavigationTests.swift`
- Modify: `App/Application/AppModel.swift`

**Interfaces:**
- Consumes: controller ids, controller session paths, process exits, session mutations, and current route.
- Produces: retained controller ownership, background provider counts, controller reuse, and `isForegroundSessionGenerating`.

- [ ] **Step 1: Add a deterministic slow-turn test fixture**

Extend only the fake server's documented mode list and prompt branch with `slow-turn`. After `agent_start`, sleep for two seconds before the terminal `agent_end`. Keep all other modes byte-for-byte behaviorally unchanged. This creates a bounded window for observing a background streaming controller; it is not production OmpKit work.

- [ ] **Step 2: Write failing AppModel ownership tests**

Add an async test that boots through the `slow-turn` executable, starts a new session, waits until `model.providerActivityCounts["test"] == 1`, then calls `model.openNewSession()`. Assert:

```swift
#expect(model.activeSession == nil)
#expect(model.route == .newSession)
#expect(model.providerActivityCounts["test"] == 1)
#expect(!model.isForegroundSessionGenerating)
```

Wait for the fake turn to finish and assert the count becomes zero without reopening the chat.

Add a reuse test that stores the first controller, waits for its `/tmp/fake.jsonl` path, navigates away, opens metadata for that same path, and asserts object identity:

```swift
let original = try #require(model.activeSession)
model.openNewSession()
model.openSession(navigationMetadata("/tmp/fake.jsonl"))
let reopened = try #require(model.activeSession)
#expect(reopened === original)
```

Add a foreground-state unit assertion showing Settings, Providers, New Session, and Archived Sessions all report `false` even while the retained registry still has an active provider. Keep the existing archive/delete mutation expectations.

- [ ] **Step 3: Run navigation tests and verify RED**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-usage-wheels-tests \
  -only-testing:TenXAppTests/AppModelNavigationTests test
```

Expected: activity count and reuse assertions fail because `AppModel` drops background controllers and always creates a new controller.

- [ ] **Step 4: Add registry ownership and retained controller storage**

Add:

```swift
let sessionActivityRegistry = SessionActivityRegistry()
@ObservationIgnored private var managedSessions: [UUID: SessionController] = [:]

var providerActivityCounts: [String: Int] {
    sessionActivityRegistry.activeCounts
}

var isForegroundSessionGenerating: Bool {
    guard case .session = route else { return false }
    return activeSession?.runtimeState == .streaming
}
```

Create controllers through one private helper that passes `sessionActivityRegistry`, retains the controller by `id`, and returns it. Do not add a factory protocol.

- [ ] **Step 5: Reuse managed sessions and route exits correctly**

Before creating a controller in `openSession`, search retained controllers for an exact `sessionPath` match. Reuse the match as `activeSession`, set `.session(metadata.path)`, and do not call `openExisting` or create another RPC event consumer.

Update `watchUnexpectedExits` to find the retained controller with the exited session path, including when it is not active, and forward the recovery state there.

Replace `closeActiveSessionIfNeeded(paths:)` with managed-session cleanup that:

1. finds every retained controller whose reported path is in `paths`;
2. calls `stopActivityTracking()`;
3. removes it from `managedSessions`;
4. clears `activeSession` and returns a matching foreground route to `.newSession`;
5. awaits `processManager.close(sessionPath:)` once for each distinct matching path.

Preserve the route-path fallback used by existing archive/delete tests when no controller has reported a path. When replacing or losing an OMP installation, stop tracking all retained controllers, clear the map and active reference, cancel exit observation, and close the prior manager before installing the replacement.

- [ ] **Step 6: Run navigation, controller, and registry tests**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-usage-wheels-tests \
  -only-testing:TenXAppTests/AppModelNavigationTests \
  -only-testing:TenXAppTests/SessionControllerTests \
  -only-testing:TenXAppTests/SessionActivityRegistryTests test
```

Expected: background counts remain observable, completed turns decrement, reopening uses the same controller, exits reach retained controllers, and mutation tests remain green.

- [ ] **Step 7: Commit managed-session ownership**

```bash
git add App/Application/AppModel.swift \
  Tests/TenXAppTests/AppModelNavigationTests.swift \
  OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py
git commit -m "feat(sessions): retain managed activity observers"
```

---

### Task 5: Render accessible concentric usage wheels

**Files:**
- Create: `Tests/TenXAppTests/ProviderUsageRingGeometryTests.swift`
- Modify: `Tests/TenXAppTests/AccessibilityLabelTests.swift`
- Create: `App/Providers/ProviderUsageAccessibility.swift`
- Create: `App/Providers/ProviderUsageWheelView.swift`
- Modify: `App/Providers/ProviderUsageDetailView.swift`
- Modify: `10x.xcodeproj/project.pbxproj` through `scripts/generate_xcodeproj.rb`

**Interfaces:**
- Consumes: ordered `ringLimits`, provider abbreviation, active count, compact grayscale flag, and Reduce Motion.
- Produces: a 54-point visual wheel and one full-provider-name accessibility value.

- [ ] **Step 1: Write failing ring geometry tests**

Test `ProviderUsageRingGeometry.metrics(limitCount:)` for counts 0, 1, 2, 3, and 12. Assert:

- the returned count exactly equals the positive input;
- zero produces an empty array;
- radii strictly increase from inner to outer;
- every stroke width is positive;
- the first ring clears the activity core;
- the outer edge never exceeds the 54-point diameter;
- dense input retains all rings rather than capping the result.

Use exact constants in the assertions:

```swift
#expect(ProviderUsageRingGeometry.diameter == 54)
#expect(ProviderUsageRingGeometry.coreDiameter == 18)
#expect(ProviderUsageRingGeometry.metrics(limitCount: 12).count == 12)
```

- [ ] **Step 2: Write failing compact accessibility tests**

Move the existing `ProviderUsageAccessibility.limitLabel` expectations unchanged, then add wheel summary assertions for zero, singular, and plural activity. The value must use the full provider name and include every limit in inner-to-outer order, for example:

```swift
#expect(ProviderUsageAccessibility.wheelValue(
    provider: provider,
    activeCount: 2
).contains("2 active sessions"))
#expect(ProviderUsageAccessibility.wheelValue(
    provider: provider,
    activeCount: 2
).contains("5 hour, 20 percent remaining"))
```

- [ ] **Step 3: Run the focused tests and verify RED**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-usage-wheels-tests \
  -only-testing:TenXAppTests/ProviderUsageRingGeometryTests \
  -only-testing:TenXAppTests/AccessibilityLabelTests test
```

Expected: compilation fails because the shared accessibility file, wheel summary, and geometry do not exist.

- [ ] **Step 4: Move accessibility logic before deleting the ledger**

Create `ProviderUsageAccessibility.swift` and move `limitLabel`, `displayReset`, and reset normalization there without changing output. Keep `ProviderUsageDetailAccessibility` delegating to it. Add `wheelValue(provider:activeCount:)` with grammatically correct `No active sessions`, `1 active session`, and `N active sessions`, followed by every ring limit's remaining percentage and reset summary.

- [ ] **Step 5: Implement scalable annulus geometry**

Use fixed diameter/core constants and split the available radial distance into equal slots:

```swift
struct ProviderUsageRingMetric: Equatable {
    let diameter: CGFloat
    let lineWidth: CGFloat
}

enum ProviderUsageRingGeometry {
    static let diameter: CGFloat = 54
    static let coreDiameter: CGFloat = 18

    static func metrics(limitCount: Int) -> [ProviderUsageRingMetric] {
        guard limitCount > 0 else { return [] }
        let availableRadius = (diameter - coreDiameter) / 2
        let slotWidth = availableRadius / CGFloat(limitCount)
        let lineWidth = slotWidth * 0.68
        return (0..<limitCount).map { index in
            let radius = coreDiameter / 2 + slotWidth * (CGFloat(index) + 0.5)
            return ProviderUsageRingMetric(
                diameter: radius * 2,
                lineWidth: lineWidth)
        }
    }
}
```

Do not clamp dense stroke widths upward, because doing so would push the outer ring past 54 points.

- [ ] **Step 6: Implement the wheel visual**

Render each `provider.ringLimits` entry with a neutral full-circle track and a trimmed remaining arc rotated to 12 o'clock. Use `.round` line caps. Choose the progress color from `ProviderUsageLimit.tone`; replace only progress colors with neutral gray when `isGrayscale` is true.

The center behavior is exact:

- count zero: quiet neutral 18-point core, no numeral, no pulse;
- count above zero: solid near-black core, centered count, and a restrained cyan outline pulse;
- Reduce Motion: static cyan outline and numeral, no animated scale or opacity.

Use `TimelineView(.animation(paused:))` or an equivalently cancellable native SwiftUI animation so changing the count to zero stops work. Do not create an unstructured repeating task. Render the three-letter abbreviation under the 54-point wheel in existing compact typography. Hide visual subelements from accessibility; the wrapping button in the dock will provide the full label/value.

- [ ] **Step 7: Run focused tests and compile the view**

Run the Step 3 command. Expected: geometry and accessibility tests pass and the app target compiles.

- [ ] **Step 8: Commit the wheel slice**

```bash
git add App/Providers/ProviderUsageAccessibility.swift \
  App/Providers/ProviderUsageWheelView.swift \
  App/Providers/ProviderUsageDetailView.swift \
  Tests/TenXAppTests/ProviderUsageRingGeometryTests.swift \
  Tests/TenXAppTests/AccessibilityLabelTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "feat(providers): render concentric usage wheels"
```

---

### Task 6: Build the anchored compact-to-expanded dock

**Files:**
- Create: `App/Providers/ProviderUsageDockView.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Add: `Tests/TenXAppTests/ReferenceImages/provider-usage-dock-idle.png`
- Add: `Tests/TenXAppTests/ReferenceImages/provider-usage-dock-generating.png`
- Add: `Tests/TenXAppTests/ReferenceImages/provider-usage-dock-expanded.png`
- Modify: `10x.xcodeproj/project.pbxproj` through `scripts/generate_xcodeproj.rb`

**Interfaces:**
- Consumes: dock providers, active counts, foreground-generating flag, and Reduce Motion.
- Produces: collapsed provider buttons or one anchored expanded provider/account panel.

- [ ] **Step 1: Add deterministic dock snapshot fixtures**

Replace the old rail-only snapshot fixture with three direct dock fixtures using the existing three-provider usage data:

1. collapsed idle: semantic cyan/yellow/red arcs, `ANT`, `OAI`, `CUR`, with Anthropic count 2;
2. collapsed generating: the same arcs in grayscale while the active count remains visible;
3. expanded generating: Anthropic selected, full-color wheel tabs and full-color bars despite `isForegroundGenerating == true`.

Apply `.environment(\.accessibilityReduceMotion, true)` to snapshot fixtures so pulse and morph timing cannot change pixels. Give the dock initializer a legitimate `initiallySelectedProviderID: String? = nil` preview/snapshot input rather than adding test-only mutation hooks.

- [ ] **Step 2: Run the snapshot tests and verify RED**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-usage-wheels-tests \
  -only-testing:TenXAppTests/ViewSnapshotTests/providerUsageDockIdleSnapshot \
  -only-testing:TenXAppTests/ViewSnapshotTests/providerUsageDockGeneratingSnapshot \
  -only-testing:TenXAppTests/ViewSnapshotTests/providerUsageDockExpandedSnapshot test
```

Expected: compilation fails because `ProviderUsageDockView` does not exist.

- [ ] **Step 3: Implement the collapsed dock and focus model**

`ProviderUsageDockView` owns:

```swift
let providers: [ProviderUsageProvider]
let activeCounts: [String: Int]
let isForegroundGenerating: Bool
@State private var selectedProviderID: String?
@FocusState private var focusedProviderID: String?
@Namespace private var expansionNamespace
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

Render providers in source order as plain buttons with `ProviderUsageWheelView`. Pass `isForegroundGenerating` only in collapsed mode. Set `.accessibilityLabel(provider.name)` and `.accessibilityValue(ProviderUsageAccessibility.wheelValue(provider: provider, activeCount: activeCounts[provider.id] ?? 0))`. Keep at least an 8-point gap between controls and 16-point trailing/bottom shell inset.

- [ ] **Step 4: Implement anchored expansion and provider switching**

When a provider is selected, replace the compact group with a panel bounded to approximately 360 points wide and no more than the available shell height. Keep its bottom-trailing anchor. Use a matched-geometry id derived from the selected provider for the normal transition; with Reduce Motion, use no geometry animation and an opacity-only or immediate transition.

The expanded panel contains, in keyboard order:

1. full-color provider wheel selector buttons;
2. selected provider's full name and active-session count;
3. a vertically scrolling account list;
4. every account's `ProviderUsageLimitDetailView` row;
5. a close button named `Close usage details`.

Show account labels whenever a provider has multiple accounts; preserve the current detailed usage convention for a single account. Do not show notes, unbounded amounts, stale warnings, or credential recovery in the dock.

Wrap expanded content in a full-size aligned `ZStack`. Only while expanded, place a transparent content-shaped dismissal layer behind the panel so an outside click collapses it. Add `.onExitCommand(perform:)` to collapse. After closing, restore focus to the provider button that opened the panel.

- [ ] **Step 5: Record only the three approved reference images**

```bash
RECORD_SNAPSHOTS=1 xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-usage-wheels-tests \
  -only-testing:TenXAppTests/ViewSnapshotTests/providerUsageDockIdleSnapshot \
  -only-testing:TenXAppTests/ViewSnapshotTests/providerUsageDockGeneratingSnapshot \
  -only-testing:TenXAppTests/ViewSnapshotTests/providerUsageDockExpandedSnapshot test
git status --short Tests/TenXAppTests/ReferenceImages
```

Expected: exactly the three new dock images change in this step.

- [ ] **Step 6: Run the snapshots normally and inspect all three images**

Repeat the Step 2 command without `RECORD_SNAPSHOTS=1`. Open each PNG at original resolution and verify ring order, 54-point scale, label legibility, active numeral, grayscale-only collapsed arcs, expanded semantic color, account grouping, no clipping, and no unintended card ornament.

- [ ] **Step 7: Commit the dock slice**

```bash
git add App/Providers/ProviderUsageDockView.swift \
  Tests/TenXAppTests/ViewSnapshotTests.swift \
  Tests/TenXAppTests/ReferenceImages/provider-usage-dock-idle.png \
  Tests/TenXAppTests/ReferenceImages/provider-usage-dock-generating.png \
  Tests/TenXAppTests/ReferenceImages/provider-usage-dock-expanded.png \
  10x.xcodeproj/project.pbxproj
git commit -m "feat(providers): expand usage wheel dock"
```

---

### Task 7: Move usage out of the rail and into the post-setup shell

**Files:**
- Modify: `App/Shell/AppShellView.swift`
- Modify: `App/Shell/FloatingRailView.swift`
- Delete: `App/Shell/ProviderUsageLedgerView.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Delete: `Tests/TenXAppTests/ReferenceImages/provider-usage-rail.png`
- Modify: `Tests/TenXAppTests/ReferenceImages/full-shell-expanded-rail-overflow.png`
- Add: `Tests/TenXAppTests/ReferenceImages/full-shell-usage-dock-small-window.png`
- Modify: `10x.xcodeproj/project.pbxproj` through `scripts/generate_xcodeproj.rb`

**Interfaces:**
- Consumes: `providerModel.dockProviders`, `providerActivityCounts`, and `isForegroundSessionGenerating`.
- Produces: one bottom-trailing dock across all post-setup routes and no rail-reserved usage space.

- [ ] **Step 1: Add shell-level failing snapshots**

Update `fullShellExpandedRailOverflowSnapshot` to expect session navigation to use the space previously reserved for usage. Add `fullShellUsageDockSmallWindowSnapshot` at the app's supported minimum 760 by 560, using three providers and several rings. The small-window assertion must show the compact dock clear of the composer, rail, and top actions.

- [ ] **Step 2: Integrate the shell-owned dock**

In the post-setup shell branch only, add:

```swift
.overlay(alignment: .bottomTrailing) {
    if let providerModel = model.providerModel,
       !providerModel.dockProviders.isEmpty {
        ProviderUsageDockView(
            providers: providerModel.dockProviders,
            activeCounts: model.providerActivityCounts,
            isForegroundGenerating: model.isForegroundSessionGenerating)
            .padding(.trailing, 16)
            .padding(.bottom, 16)
    }
}
```

Ensure this overlay sits below modal search/deletion interception in the composition order so modal interaction remains authoritative. Setup and provider onboarding must not instantiate the dock.

- [ ] **Step 3: Remove the rail ledger completely**

Delete the `providers` computed property, ledger block, and `usageLedgerHeight` from `FloatingRailView`. Delete `ProviderUsageLedgerView.swift`; its accessibility helper already moved in Task 5. Remove the obsolete rail snapshot and its fixture function. Do not change rail expansion behavior otherwise.

- [ ] **Step 4: Regenerate the project and compile**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-usage-wheels-tests \
  -only-testing:TenXAppTests/ViewSnapshotTests test
```

Expected before recording: only the updated/new shell references fail; existing provider detail references remain unchanged.

- [ ] **Step 5: Record and inspect only shell references**

```bash
RECORD_SNAPSHOTS=1 xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-usage-wheels-tests \
  -only-testing:TenXAppTests/ViewSnapshotTests/fullShellExpandedRailOverflowSnapshot \
  -only-testing:TenXAppTests/ViewSnapshotTests/fullShellUsageDockSmallWindowSnapshot test
git status --short Tests/TenXAppTests/ReferenceImages
```

Expected: `provider-usage-rail.png` is deleted, the full-shell expanded rail image is updated, and the minimum-window image is added. Revert any unrelated reference changes before continuing.

Inspect both shell images at original resolution. Confirm the rail gains the freed vertical space, the dock remains bottom-right, and the small window has no overlap or clipping.

- [ ] **Step 6: Run every affected app test normally**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-usage-wheels-tests \
  -only-testing:TenXAppTests/ProviderUsagePresentationTests \
  -only-testing:TenXAppTests/SessionActivityRegistryTests \
  -only-testing:TenXAppTests/SessionControllerTests \
  -only-testing:TenXAppTests/AppModelNavigationTests \
  -only-testing:TenXAppTests/ProviderUsageRingGeometryTests \
  -only-testing:TenXAppTests/AccessibilityLabelTests \
  -only-testing:TenXAppTests/ViewSnapshotTests test
```

Expected: all affected tests pass with recording disabled.

- [ ] **Step 7: Commit shell integration**

```bash
git add App/Shell/AppShellView.swift \
  App/Shell/FloatingRailView.swift \
  App/Shell/ProviderUsageLedgerView.swift \
  Tests/TenXAppTests/ViewSnapshotTests.swift \
  Tests/TenXAppTests/ReferenceImages \
  10x.xcodeproj/project.pbxproj
git commit -m "feat(shell): move usage into wheel dock"
```

---

### Task 8: Verify the production build and real interaction

**Files:**
- Modify only if a verification-discovered defect directly violates this plan.
- Evidence output outside Git: `/tmp/tenx-usage-wheels-evidence/`.

- [ ] **Step 1: Regenerate and prove the project is deterministic**

```bash
ruby scripts/generate_xcodeproj.rb
git diff --exit-code -- 10x.xcodeproj/project.pbxproj
```

Expected: no diff after regeneration.

- [ ] **Step 2: Run the complete automated baseline**

```bash
cd OmpKit && swift test
cd ..
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-usage-wheels-full-tests test
```

Expected: OmpKit passes with only the two existing opt-in integration skips; the full app suite passes with snapshot recording disabled.

- [ ] **Step 3: Build Release, not a dev-only surface**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-usage-wheels-release build
```

Expected: `** BUILD SUCCEEDED **` and an app at `/tmp/tenx-usage-wheels-release/Build/Products/Release/10x.app`.

- [ ] **Step 4: Launch through the local-build workflow and confirm visibility**

Invoke `launching-local-builds`, terminate only stale instances of this exact Release app if needed, launch the built `.app`, and confirm its real window is visible before claiming it is open. Do not use a dev server as verification.

- [ ] **Step 5: Drive the approved behavior as a user**

Using real configured providers and at least two 10x-managed chats, verify in order:

1. an idle foreground chat shows semantic compact colors;
2. starting a foreground turn makes every compact provider's limit arcs grayscale;
3. the generating provider core shows the all-managed-session count and pulses;
4. opening a wheel during generation restores semantic colors in tabs and bars;
5. switching provider selectors changes the account and limit breakdown;
6. close, Escape, and outside click each collapse without changing chat route;
7. leaving another managed chat generating while the foreground chat becomes idle produces colored compact rings with the background provider core still active;
8. Reduce Motion removes pulse/morph but retains the number and state;
9. the 760 by 560 window has no collision with composer, rail, top actions, or safe area.

- [ ] **Step 6: Capture and inspect real-build evidence**

Create `/tmp/tenx-usage-wheels-evidence/` and capture full-window PNGs for:

- `collapsed-idle.png`;
- `collapsed-generating.png`;
- `expanded-generating.png`.

Open all three at original resolution. Reject the verification if any ring is clipped, the 5-hour ring is outside weekly, labels are illegible, grayscale leaks into expanded bars, the core count disagrees with managed sessions, or the dock overlaps another control.

- [ ] **Step 7: Review scope and working tree**

```bash
git status --short
git diff --stat HEAD~7..HEAD
git log --oneline --decorate -10
```

Confirm there are no unrelated refactors, dependencies, OMP production changes, test recording flags, or uncommitted generated files. If verification required a direct bug fix, rerun the exact failing check, the complete app suite, and the Release build before committing the smallest correction.

- [ ] **Step 8: Commit only a necessary verification correction**

If and only if Step 5 or Step 6 exposed a plan violation, make one atomic conventional commit after the reruns. Otherwise create no empty verification commit.

## Completion Gate

Do not report completion until all of these are true:

- every approved behavior in the design spec maps to implemented code and a test or real-build check;
- all ring limits are retained and duration-ordered inner-to-outer;
- background controllers remain observed without duplicate RPC event consumers;
- compact foreground generation is grayscale while expanded usage stays colored;
- full-provider accessibility, keyboard dismissal, focus restoration, and Reduce Motion work;
- the rail ledger and its reserved height are gone;
- deterministic project generation, OmpKit tests, full app tests, snapshots, and Release build pass in this session;
- the three real-build screenshots have been visually inspected;
- the final report follows `Verified`, `Not verified`, and `For you to test`, and explicitly notes that no PR exists because the repository has no remote.

# 10x Multi-Account Provider Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consume OMP's account RPC to present per-account usage and route retained 10x sessions with explicit scopes, queued post-turn switches, safe removal, compatibility fallback, and the approved rightward account-wheel UI.

**Architecture:** Extend OmpKit with typed account commands/models while preserving its forward-compatible event stream. Replace provider-only activity aggregation with one `@MainActor ProviderAccountCoordinator` that owns primary preferences, retained-session account attribution, latest-choice queues, exact generating counts, and removal coordination; keep `ProviderManagementViewModel` responsible for account metadata/usage and keep SwiftUI views presentation-only.

**Tech Stack:** Swift 6.1, SwiftUI, Observation, Swift Testing, OmpKit RPC protocol v2, AppKit snapshot harness, UserDefaults, macOS 15+

**Spec:** `docs/superpowers/specs/2026-08-26-multi-account-provider-routing-design.md`

## Global Constraints

- Start from approved design commit `9fa36aa`. Implement only after the companion OMP contract is available in a testable OMP build.
- macOS 15+, Swift 6.1, strict concurrency, typed `Sendable` values at actor boundaries, no `any`, and no `as` casts.
- OMP owns credentials, safe identity, availability, usage adapters, exact pin persistence, retry/quota policy, failover, and exact credential removal.
- 10x stores only `providerId -> accountRef` primary preferences and runtime per-session queues. Never show or routinely log an account ref.
- One `ProviderAccountCoordinator` replaces `SessionActivityRegistry`; there must be one consumer of each `RpcClient.events` stream.
- Compact: foreground account is full-size; siblings cascade behind toward the right; exact generating count is centered; all grayscale while the open chat generates except a hovered/focused background wheel raises and colorizes.
- Expanded: existing bounded 360x440 corner panel, always semantic color, grows up/left, scrolls internally, and never changes composer frame/inset.
- Clicking inspects only. Every routing change requires `Use this account` confirmation and one scope: `This session`, `All current sessions`, or `All new sessions`.
- Idle sessions pin immediately. Generating sessions retain only the latest queued choice and apply once idle. Closing 10x discards pending choices.
- Older OMP keeps the existing provider-only wheel and hides account selectors, switch, and removal actions.
- UI copy is exact, factual, compact, contains no em dash, and never leaks protocol or credential details.
- Run `ruby scripts/generate_xcodeproj.rb` after adding/removing Swift files. Verification uses `xcodebuild` and a built app, not a dev-only surface. Port 3000 is irrelevant and must not be used.
- Prior verified baseline at `9fa36aa`: 267 tests across 4 suites passed with `xcodebuild`.

## File Map

### OmpKit account contract

- Modify `OmpKit/Sources/OmpKit/Wire/RpcCommand.swift`: account command factories.
- Create `OmpKit/Sources/OmpKit/Providers/ProviderAccount.swift`: typed summaries, usage windows, availability, change reason/event, and response decoders.
- Modify `OmpKit/Sources/OmpKit/Wire/RpcFrame.swift`: decode `provider_account_changed` as a typed additive frame.
- Modify `OmpKit/Tests/OmpKitTests/CommandEncodingTests.swift`: exact account command envelopes.
- Modify `OmpKit/Tests/OmpKitTests/LineTransportTests.swift`: typed event/state/forward-compat decoding.

### Account data and orchestration

- Create `App/Providers/ProviderAccountManaging.swift`: account RPC abstraction for provider and session clients.
- Modify `App/Providers/ProviderManagementService.swift`: no-session list, batched usage, exact removal, and unsupported-command capability detection.
- Modify `App/Providers/ProviderManagementViewModel.swift`: safe accounts, account usage, add/remove state, and refresh joining by opaque ref.
- Create `App/Providers/ProviderPrimaryPreferenceStore.swift`: UserDefaults-backed provider-primary map.
- Create `App/Providers/ProviderAccountCoordinator.swift`: primary policy, managed-session registry, queues, sequence dedupe, exact counts, scope application, and safe removal.
- Delete `App/Sessions/SessionActivityRegistry.swift` after its callers move to the coordinator.
- Modify `App/Sessions/SessionController.swift`: expose a narrow session account port and forward state/events once through the coordinator.
- Modify `App/Application/AppDependencies.swift`: construct provider service, preference store, and coordinator.
- Modify `App/Application/AppModel.swift`: own coordinator, retain/unretain controllers, apply primary before first new turn, preserve resumed pins, and close the panel on open-session change.

### Presentation and UI

- Modify `App/Providers/ProviderUsagePresentation.swift`: join RPC usage by `accountRef`, derive foreground/fallback/order, and retain provider-only fallback.
- Modify `App/Providers/ProviderUsageDockLayout.swift`: calculate complete stack widths.
- Create `App/Providers/ProviderAccountStackView.swift`: rightward overlapped account buttons and hover/focus elevation.
- Modify `App/Providers/ProviderUsageWheelView.swift`: account-level input and highlighted-background color override.
- Modify `App/Providers/ProviderUsageDockView.swift`: inspected account, bounded account panel, switch confirmation, scope radio semantics, manage navigation, focus restoration, and open-session invalidation.
- Create `App/Providers/ProviderAccountSwitchConfirmationView.swift`: small corner-modal confirmation body.
- Modify `App/Providers/ProviderConnectionsView.swift`: provider groups, account rows, add action, pending removal state.
- Create `App/Providers/ProviderAccountConnectionRowView.swift`: safe label, primary/in-use status, and remove action.
- Create `App/Providers/ProviderAccountRemovalConfirmationView.swift`: affected managed-session copy and last-account warning.
- Modify `App/Providers/ProvidersView.swift`: focus selected provider in Connections.
- Modify `App/Shell/AppShellView.swift`: pass account presentation/callbacks without changing composer geometry.
- Modify `App/Providers/ProviderUsageAccessibility.swift`: exact account identity, limits, counts, status, and focus semantics.

### Tests and evidence

- Create `Tests/TenXAppTests/ProviderAccountCoordinatorTests.swift`.
- Create `Tests/TenXAppTests/ProviderPrimaryPreferenceStoreTests.swift`.
- Create `Tests/TenXAppTests/ProviderAccountStackTests.swift`.
- Modify provider service/model, session controller, presentation, layout, focus, snapshot, accessibility, navigation, and fixture tests.
- Add reference images under `Tests/TenXAppTests/ReferenceImages/provider-account-*.png`.
- Modify `10x.xcodeproj/project.pbxproj` only through `ruby scripts/generate_xcodeproj.rb`.

---

### Task 1: Add Typed OmpKit Account Commands and Events

**Files:**
- Modify: `OmpKit/Sources/OmpKit/Wire/RpcCommand.swift`
- Create: `OmpKit/Sources/OmpKit/Providers/ProviderAccount.swift`
- Modify: `OmpKit/Sources/OmpKit/Wire/RpcFrame.swift`
- Modify: `OmpKit/Tests/OmpKitTests/CommandEncodingTests.swift`
- Modify: `OmpKit/Tests/OmpKitTests/LineTransportTests.swift`

**Interfaces:**
- Produces command factories matching the companion OMP plan.
- Produces `ProviderAccountSummary`, `ProviderAccountUsage`, `ProviderAccountChangedEvent`.
- Produces `RpcFrame.providerAccountChanged(ProviderAccountChangedEvent)`.

- [ ] **Step 1: Write failing exact-envelope tests**

```swift
@Test func providerAccountCommandsMatchTheOMPContract() throws {
    #expect(try object(.listProviderAccounts(providerID: "openai-codex"))["type"] as? String == "list_provider_accounts")
    #expect(try object(.providerAccountUsage(providerID: "openai-codex"))["type"] as? String == "get_provider_account_usage")
    let pin = try object(.setSessionProviderAccount(providerID: "openai-codex", accountRef: "acct_B"))
    #expect(pin["providerId"] as? String == "openai-codex")
    #expect(pin["accountRef"] as? String == "acct_B")
    #expect(try object(.removeProviderAccount(providerID: "openai-codex", accountRef: "acct_B"))["type"] as? String == "remove_provider_account")
}
```

Add line-decoding tests for the full summary, unknown availability fallback to unavailable, usage windows with unknown fields, and `provider_account_changed`.

- [ ] **Step 2: Regenerate and verify RED**

```bash
ruby scripts/generate_xcodeproj.rb
cd OmpKit
swift test --filter providerAccount
```

Expected: compile failure because command factories and account types are absent.

- [ ] **Step 3: Implement narrow typed values and factories**

```swift
public struct ProviderAccountSummary: Sendable, Equatable, Decodable, Identifiable {
    public let providerID: String
    public let accountRef: String
    public let displayLabel: String
    public let detailLabel: String?
    public let connectionOrder: Int
    public let availability: ProviderAccountAvailability
    public let isActiveForSession: Bool?
    public var id: String { "\(providerID):\(accountRef)" }
}

public struct ProviderAccountChangedEvent: Sendable, Equatable {
    public let providerID: String
    public let accountRef: String
    public let reason: ProviderAccountChangeReason
    public let sequence: Int
}
```

Decode dates as ISO-8601, tolerate unknown response fields, and treat unknown enum cases safely without dropping the entire event stream.

- [ ] **Step 4: Verify focused and full OmpKit suites**

```bash
cd OmpKit
swift test --filter providerAccount
swift test
```

Expected: focused and full package suites pass.

- [ ] **Step 5: Commit OmpKit contract support**

```bash
git add OmpKit/Sources/OmpKit OmpKit/Tests/OmpKitTests 10x.xcodeproj/project.pbxproj
git commit -m "feat(ompkit): add provider account RPC"
```

---

### Task 2: Add Account-Capable Provider Service with Compatibility Fallback

**Files:**
- Create: `App/Providers/ProviderAccountManaging.swift`
- Modify: `App/Providers/ProviderManagementService.swift`
- Modify: `App/Providers/ProviderManaging.swift`
- Modify: `Tests/TenXAppTests/ProviderManagementServiceTests.swift`

**Interfaces:**
- Produces `ProviderAccountCapability`: `.accountRouting` or `.providerOnly`.
- Produces provider-client methods `accounts`, `accountUsage`, and `removeAccount`.
- Maps unsupported command to `.providerOnly`; propagates other failures.

- [ ] **Step 1: Write failing capability and response tests**

Test successful decoding, account usage partial data, exact removal, and an older fake server returning unsupported-command. Assert unsupported mode does not retry account calls indefinitely and keeps existing login/provider behavior.

- [ ] **Step 2: Verify RED**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-account-task2-red -parallel-testing-enabled NO \
  -only-testing:'TenXAppTests/ProviderManagementServiceTests' test
```

Expected: compile failure for missing account service API.

- [ ] **Step 3: Implement the narrow service abstraction**

```swift
protocol ProviderAccountManaging: Sendable {
    func accounts(providerID: String) async throws -> [ProviderAccountSummary]
    func accountUsage(providerID: String) async throws -> [ProviderAccountUsage]
    func removeAccount(providerID: String, accountRef: String) async throws -> ProviderAccountRemovalResult
}
```

Use the existing dedicated no-session client. Detect only OMP's stable unsupported-command code/message as compatibility fallback; do not convert timeouts, decoding errors, or connection failures to provider-only mode.

- [ ] **Step 4: Verify GREEN**

Run the Task 2 selector with derived data `/tmp/tenx-account-task2-green`.

Expected: account responses decode; older OMP capability becomes `.providerOnly`; existing provider login tests pass.

- [ ] **Step 5: Commit provider service support**

```bash
git add App/Providers/ProviderAccountManaging.swift App/Providers/ProviderManaging.swift \
  App/Providers/ProviderManagementService.swift Tests/TenXAppTests/ProviderManagementServiceTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "feat(providers): load provider accounts"
```

---

### Task 3: Persist and Repair Provider Primary Preferences

**Files:**
- Create: `App/Providers/ProviderPrimaryPreferenceStore.swift`
- Create: `Tests/TenXAppTests/ProviderPrimaryPreferenceStoreTests.swift`

**Interfaces:**
- Produces `primaryAccountRef(providerID:)`, `setPrimaryAccountRef(_:providerID:)`, and `repairPrimary(providerID:accounts:)`.
- Stores one dictionary under `providerPrimaryAccountRefs.v1`.

- [ ] **Step 1: Write failing persistence and fallback tests**

```swift
@Test func missingPrimaryRepairsToFirstEligibleConnectionOrder() {
    let replacement = store.repairPrimary(
        providerID: "openai-codex",
        accounts: [unavailable(order: 0), available(ref: "acct_B", order: 1)])
    #expect(replacement == "acct_B")
    #expect(store.primaryAccountRef(providerID: "openai-codex") == "acct_B")
}
```

Also prove an existing eligible primary is retained, no eligible account clears the mapping, and only provider/account refs are serialized.

- [ ] **Step 2: Verify RED**

Run only `ProviderPrimaryPreferenceStoreTests`; expect missing type compilation failure.

- [ ] **Step 3: Implement the UserDefaults store**

Use a typed `[String: String]` dictionary and stable connection-order sorting. Eligibility is only `.available` or `.limited`; `.unavailable` is not selected. Do not store labels, identity, usage, or session ids.

- [ ] **Step 4: Verify GREEN and inspect persisted fixture**

Expected: tests pass and the test defaults domain contains only `{ "openai-codex": "acct_B" }` under the one versioned key.

- [ ] **Step 5: Commit primary persistence**

```bash
git add App/Providers/ProviderPrimaryPreferenceStore.swift \
  Tests/TenXAppTests/ProviderPrimaryPreferenceStoreTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat(providers): persist primary accounts"
```

---

### Task 4: Build the Main-Actor Routing Coordinator

**Files:**
- Create: `App/Providers/ProviderAccountCoordinator.swift`
- Delete: `App/Sessions/SessionActivityRegistry.swift`
- Modify: `App/Sessions/SessionController.swift`
- Modify: `Tests/TenXAppTests/ProviderAccountCoordinatorTests.swift`
- Modify: `Tests/TenXAppTests/SessionControllerTests.swift`
- Delete or migrate: `Tests/TenXAppTests/SessionActivityRegistryTests.swift`

**Interfaces:**
- Produces `ProviderAccountScope`: `.thisSession`, `.allCurrentSessions`, `.allNewSessions`.
- Produces `managedSessions`, `activeAccountRefs`, `generatingCounts`, and latest pending switch per session.
- Session port exposes provider id, runtime state, current account ref/sequence, and `setProviderAccount` through its own RPC client.

- [ ] **Step 1: Write failing scope, queue, and count tests**

Cover all three scopes, immediate idle pin, generating queue, latest-choice replacement, partial failure, cleanup, and exact `(providerID, accountRef)` counts.

```swift
await coordinator.useAccount("acct_C", providerID: providerID, scope: .allCurrentSessions, openSessionID: first.id)
#expect(first.pins == ["acct_C"])
#expect(second.pins.isEmpty)
#expect(coordinator.pendingAccountRef(sessionID: second.id) == "acct_C")
second.setGenerating(false)
await coordinator.sessionDidBecomeIdle(second.id)
#expect(second.pins == ["acct_C"])
```

- [ ] **Step 2: Verify RED**

Run coordinator and session-controller selectors; expect missing coordinator/session port failures.

- [ ] **Step 3: Implement one event consumer and latest-choice queues**

`SessionController` remains the sole consumer of its `RpcClient.events`; it forwards typed account changes to the coordinator alongside its existing reducer handling. The coordinator ignores sequences at or below the stored sequence, updates exact counts without double-counting, and applies a queued valid ref once runtime becomes idle. A later queued choice overwrites the earlier value.

- [ ] **Step 4: Implement scope semantics**

`thisSession` targets the open retained controller. `allCurrentSessions` targets retained top-level controllers whose provider matches, excluding archives/closed sessions. `allNewSessions` only updates the primary store. Per-session failures do not stop other targets; publish a sanitized failure summary for UI.

- [ ] **Step 5: Verify and commit coordinator**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-account-task4 -parallel-testing-enabled NO \
  -only-testing:'TenXAppTests/ProviderAccountCoordinatorTests' \
  -only-testing:'TenXAppTests/SessionControllerTests' test
git add App/Providers/ProviderAccountCoordinator.swift App/Sessions/SessionController.swift \
  App/Sessions/SessionActivityRegistry.swift Tests/TenXAppTests/ProviderAccountCoordinatorTests.swift \
  Tests/TenXAppTests/SessionControllerTests.swift Tests/TenXAppTests/SessionActivityRegistryTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "feat(providers): coordinate session account routing"
```

---

### Task 5: Apply Primaries to New Sessions and Preserve Resumed Pins

**Files:**
- Modify: `App/Application/AppDependencies.swift`
- Modify: `App/Application/AppModel.swift`
- Modify: `Tests/TenXAppTests/AppModelNavigationTests.swift`
- Modify: `Tests/TenXAppTests/ProviderAccountCoordinatorTests.swift`

**Interfaces:**
- Consumes coordinator primary preferences and session state `activeProviderAccounts`.
- Guarantees new-session primary pin occurs before first prompt; resumed pins win over current primary.

- [ ] **Step 1: Add failing new/resume/failover tests**

Assert call order for a new session is open, get-state, set account, prompt. Assert an existing session reporting `acct_B` is never repinned to newer primary `acct_A`. Assert automatic failover updates the session but not the primary.

- [ ] **Step 2: Verify RED**

Run `AppModelNavigationTests` and the named coordinator tests. Expected: call-order and preservation assertions fail.

- [ ] **Step 3: Wire coordinator lifecycle**

Construct the preference store/coordinator in dependencies, register every retained controller once, unregister on archive/delete/exit, apply primary after new-session state is available and before `sendPrompt`, and accept authoritative resumed state before considering a primary.

- [ ] **Step 4: Close stale inspection state on open-chat change**

Publish an active-session identity token from `AppModel` and pass it to the dock so any panel/confirmation collapses when the open chat changes. Do not retain a switch target captured from a previous chat.

- [ ] **Step 5: Verify and commit app integration**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-account-task5 -parallel-testing-enabled NO \
  -only-testing:'TenXAppTests/AppModelNavigationTests' \
  -only-testing:'TenXAppTests/ProviderAccountCoordinatorTests' test
git add App/Application/AppDependencies.swift App/Application/AppModel.swift \
  Tests/TenXAppTests/AppModelNavigationTests.swift Tests/TenXAppTests/ProviderAccountCoordinatorTests.swift
git commit -m "feat(providers): route new and resumed sessions"
```

---

### Task 6: Join Account Metadata and Usage Without Identity Guessing

**Files:**
- Modify: `App/Providers/ProviderManagementViewModel.swift`
- Modify: `App/Providers/ProviderUsagePresentation.swift`
- Modify: `Tests/TenXAppTests/ProviderManagementViewModelTests.swift`
- Modify: `Tests/TenXAppTests/ProviderUsagePresentationTests.swift`
- Modify: `Tests/TenXAppTests/ProviderTestFixtures.swift`

**Interfaces:**
- Produces account presentation keyed only by `(providerID, accountRef)`.
- Preserves existing `OmpUsageService` provider-only presentation when capability is `.providerOnly`.

- [ ] **Step 1: Add failing join and compatibility tests**

Cover metadata-before-usage, per-account usage failure, duplicate visible labels, stable connection order, unknown duration order, missing primary fallback, all unavailable, and older OMP provider-only fallback. Explicitly prove CLI usage identities are never guessed into account refs.

- [ ] **Step 2: Verify RED**

Run provider model and presentation selectors; expect missing account collections and wrong provider-only joins.

- [ ] **Step 3: Implement account presentation values**

Keep `accountRef` internal to identity and action plumbing. Derive selected foreground: open session active ref for its provider; otherwise primary; otherwise first eligible in connection order. Account usage loading failure preserves the account with neutral tracks and `Usage unavailable` in expanded details.

- [ ] **Step 4: Preserve compatibility behavior**

When capability is `.providerOnly`, use existing `OmpUsageService`, render one provider wheel, and set presentation flags so selectors, switch, and removal controls are absent. A failed account request that is not unsupported remains an error, not compatibility mode.

- [ ] **Step 5: Verify and commit presentation joining**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-account-task6 -parallel-testing-enabled NO \
  -only-testing:'TenXAppTests/ProviderManagementViewModelTests' \
  -only-testing:'TenXAppTests/ProviderUsagePresentationTests' test
git add App/Providers/ProviderManagementViewModel.swift App/Providers/ProviderUsagePresentation.swift \
  Tests/TenXAppTests/ProviderManagementViewModelTests.swift \
  Tests/TenXAppTests/ProviderUsagePresentationTests.swift Tests/TenXAppTests/ProviderTestFixtures.swift
git commit -m "feat(providers): present account usage"
```

---

### Task 7: Render Rightward Account Stacks and Responsive Width

**Files:**
- Create: `App/Providers/ProviderAccountStackView.swift`
- Modify: `App/Providers/ProviderUsageWheelView.swift`
- Modify: `App/Providers/ProviderUsageDockLayout.swift`
- Create: `Tests/TenXAppTests/ProviderAccountStackTests.swift`
- Modify: `Tests/TenXAppTests/ProviderUsageDockLayoutTests.swift`
- Modify: `Tests/TenXAppTests/ProviderUsageRingGeometryTests.swift`

**Interfaces:**
- Produces one provider stack width used by responsive fit.
- Produces independently focusable account buttons ordered back-to-front visually but stable in accessibility order.

- [ ] **Step 1: Add failing geometry and interaction tests**

Assert foreground diameter matches current compact layout, siblings scale smaller and offset right, complete stack width affects side/above placement, provider label appears once, foreground owns primary z-order, and hovered/focused background state becomes raised/colorized.

- [ ] **Step 2: Verify RED**

Run stack/layout/ring selectors; expect missing stack type and provider-count-only width failures.

- [ ] **Step 3: Implement stack geometry and input states**

Reuse `ProviderUsageWheelView`; add account presentation input rather than forking a second wheel. Draw stable connection order back-to-front with the foreground rendered last. Keep every button at least 44x44 even when its visual wheel is smaller. With Reduce Motion, change z-order/color immediately and omit elevation/reordering animation.

- [ ] **Step 4: Update fit calculation**

Replace provider-count width with `stackWidths: [CGFloat]`. Sum each rendered stack width plus existing inter-provider spacing. Do not read or modify composer height, width, inset, or frame to make the dock fit.

- [ ] **Step 5: Verify and commit account stacks**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-account-task7 -parallel-testing-enabled NO \
  -only-testing:'TenXAppTests/ProviderAccountStackTests' \
  -only-testing:'TenXAppTests/ProviderUsageDockLayoutTests' \
  -only-testing:'TenXAppTests/ProviderUsageRingGeometryTests' test
git add App/Providers/ProviderAccountStackView.swift App/Providers/ProviderUsageWheelView.swift \
  App/Providers/ProviderUsageDockLayout.swift Tests/TenXAppTests/ProviderAccountStackTests.swift \
  Tests/TenXAppTests/ProviderUsageDockLayoutTests.swift \
  Tests/TenXAppTests/ProviderUsageRingGeometryTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat(usage): stack provider accounts"
```

---

### Task 8: Add Bounded Account Inspection and Scoped Confirmation

**Files:**
- Modify: `App/Providers/ProviderUsageDockView.swift`
- Create: `App/Providers/ProviderAccountSwitchConfirmationView.swift`
- Modify: `App/Providers/ProviderUsageAccessibility.swift`
- Modify: `Tests/TenXAppTests/ProviderUsageDockFocusTests.swift`
- Modify: `Tests/TenXAppTests/AccessibilityLabelTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`

**Interfaces:**
- Clicking selects inspection only.
- `onUseAccount(accountRef, scope)` fires only after confirmation.
- `onManageAccounts(providerID)` navigates to Connections.

- [ ] **Step 1: Add failing state, focus, copy, and snapshot tests**

Snapshots cover multiple accounts idle, generating grayscale, hovered background, expanded semantic color, and confirmation. Interaction tests prove clicking never invokes routing; open-session identity change collapses; dismissal restores the opening account button; scope options expose radio-group semantics.

- [ ] **Step 2: Verify RED**

Run focus, accessibility, and snapshot selectors with `RECORD_SNAPSHOTS=0`. Expected: new states and reference images are absent.

- [ ] **Step 3: Implement the bounded account panel**

Keep `.frame(width: 360)` and `.frame(maxHeight: 440)`, internal scrolling, bottom-right anchor, outside click, Escape, close, and focus restoration. Expanded rings/bars always pass `isGrayscale: false`. Account selectors change inspected account only. Use exact action labels `Use this account`, `Manage accounts`, and `Close usage details`.

- [ ] **Step 4: Implement exact confirmation copy and disabled scopes**

Use this user-facing text:

```text
Use [account]?
Choose where this account should be used.

This session
Switch the open session. If it is generating, switch after the current turn.

All current sessions
Switch every 10x-managed session using this provider. Generating sessions finish their current turn first.

All new sessions
Set this as the provider's primary account. Existing sessions stay unchanged.

Cancel
Switch account
```

Show `In use for this session` where applicable. Disable only satisfied scopes; disable the entire action only when all three scopes are satisfied. Unavailable or pending-removal accounts cannot be selected.

- [ ] **Step 5: Record, inspect, and commit UI references**

```bash
RECORD_SNAPSHOTS=1 xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' -derivedDataPath /tmp/tenx-account-task8-record \
  -parallel-testing-enabled NO -only-testing:'TenXAppTests/ViewSnapshotTests' test
RECORD_SNAPSHOTS=0 xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' -derivedDataPath /tmp/tenx-account-task8-green \
  -parallel-testing-enabled NO -only-testing:'TenXAppTests/ViewSnapshotTests' \
  -only-testing:'TenXAppTests/ProviderUsageDockFocusTests' \
  -only-testing:'TenXAppTests/AccessibilityLabelTests' test
git add App/Providers/ProviderUsageDockView.swift \
  App/Providers/ProviderAccountSwitchConfirmationView.swift \
  App/Providers/ProviderUsageAccessibility.swift Tests/TenXAppTests \
  10x.xcodeproj/project.pbxproj
git commit -m "feat(usage): inspect and switch provider accounts"
```

Inspect every new reference image before committing: no clipping, one provider label, rightward cascade, visible exact count, fixed panel bounds, and unchanged composer geometry.

---

### Task 9: Add Connections Account Rows and Safe Removal Coordination

**Files:**
- Modify: `App/Providers/ProviderConnectionsView.swift`
- Create: `App/Providers/ProviderAccountConnectionRowView.swift`
- Create: `App/Providers/ProviderAccountRemovalConfirmationView.swift`
- Modify: `App/Providers/ProvidersView.swift`
- Modify: `App/Providers/ProviderManagementViewModel.swift`
- Modify: `App/Providers/ProviderAccountCoordinator.swift`
- Modify: `Tests/TenXAppTests/ProviderManagementViewModelTests.swift`
- Modify: `Tests/TenXAppTests/ProviderAccountCoordinatorTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`

**Interfaces:**
- Login remains `login(providerID:)` and appends through OMP.
- Removal flow: mark target pending, repin idle sessions, queue generating sessions, await queues/turns, repair primary, call exact remove, refresh metadata/usage.

- [ ] **Step 1: Add failing add/remove and conflict tests**

Cover login append refresh, idle reassignment, generating wait, removal plus pending manual switch, primary removal, last account, stale external removal, and partial repin failure. Assert the remove RPC is not called while a managed turn or switch queue still targets the account.

- [ ] **Step 2: Verify RED**

Run provider model, coordinator, and snapshot selectors. Expected: missing removal state/UI failures.

- [ ] **Step 3: Implement grouped Connections rows**

Show safe label/detail, `Primary`, and grammatically correct `In use by 1 session` / `In use by N sessions`. Use `Add account` for the existing login flow. Duplicate labels remain separate rows. `Manage accounts` navigation focuses the selected provider group.

- [ ] **Step 4: Implement exact removal confirmation and coordination**

Normal copy names affected 10x-managed sessions and states that generating turns finish first. Last-account copy is: `Remove the last account? This disconnects [provider]. Sessions using this provider cannot continue through it.` Do not claim protection for terminals or other apps. Reject new switches to a pending-removal ref. If the target is primary, persist the first eligible remaining account before moving affected sessions.

- [ ] **Step 5: Verify and commit Connections management**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-account-task9 -parallel-testing-enabled NO \
  -only-testing:'TenXAppTests/ProviderManagementViewModelTests' \
  -only-testing:'TenXAppTests/ProviderAccountCoordinatorTests' \
  -only-testing:'TenXAppTests/ViewSnapshotTests' test
git add App/Providers Tests/TenXAppTests 10x.xcodeproj/project.pbxproj
git commit -m "feat(providers): manage connected accounts"
```

---

### Task 10: Integrate the Dock Without Moving the Composer

**Files:**
- Modify: `App/Shell/AppShellView.swift`
- Modify: `App/Application/AppModel.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Modify: `Tests/TenXAppTests/ProviderUsageDockLayoutTests.swift`

**Interfaces:**
- Supplies stack presentation, exact counts, open-session account, generating state, callbacks, and active-session identity.
- Preserves existing composer layout inputs and expanded dock anchoring.

- [ ] **Step 1: Add failing full-shell geometry tests**

Capture composer frame before/after compact multi-account, expanded panel, and confirmation at wide, compact-trigger, and minimum supported widths. Assert exact equality and no horizontal overflow.

- [ ] **Step 2: Verify RED**

Run full-shell snapshot/layout selectors; expect missing integration and references.

- [ ] **Step 3: Pass account state through the existing overlay**

Keep `ProviderUsageDockView` presentation-only. Route switch/manage actions to coordinator/AppModel. Do not add padding, safe-area inset, frame width, or indentation to composer/new-session/active-session views.

- [ ] **Step 4: Record and inspect shell references**

Record wide, compact-trigger, and minimum-width images for idle, generating, hovered background, expanded, and confirmation. Visually confirm no wheel/panel clipping, no collision, no scrollbar, and identical composer frame.

- [ ] **Step 5: Commit shell integration**

```bash
git add App/Shell/AppShellView.swift App/Application/AppModel.swift \
  Tests/TenXAppTests/ViewSnapshotTests.swift \
  Tests/TenXAppTests/ProviderUsageDockLayoutTests.swift \
  Tests/TenXAppTests/ReferenceImages
git commit -m "feat(shell): integrate provider account routing"
```

---

### Task 11: Verify Conflict, Accessibility, Compatibility, and the Built App

**Files:**
- Modify only if verification exposes a defect in files already owned by Tasks 1-10.
- Add evidence under `docs/superpowers/evidence/2026-08-26-multi-account-provider-routing/`.

**Interfaces:**
- Verifies the complete 10x behavior against the approved spec and companion OMP build.

- [ ] **Step 1: Run generator stability and all automated tests**

```bash
ruby scripts/generate_xcodeproj.rb
git diff --check
ruby scripts/generate_xcodeproj.rb
git diff --check
cd OmpKit && swift test
cd ..
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-account-full -parallel-testing-enabled NO test
```

Expected: second generator run adds no diff; OmpKit and all 10x suites pass. Record executed counts and skips.

- [ ] **Step 2: Build a Release app with the account-capable OMP executable**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' -derivedDataPath /tmp/tenx-account-release build
```

Expected: `10x.app` builds successfully. Use the repository's local-build launching workflow before opening it.

- [ ] **Step 3: Exercise the 15 built-app acceptance cases**

Use a non-production test account set. Verify one/multiple accounts, hover/focus color, bounded inspection, all three scopes, queue-after-turn, exact counts, automatic failover, recovered-primary behavior, safe removal, three widths, error/duplicate/all-exhausted states, VoiceOver/keyboard/Reduce Motion, and RPC redaction. Do not mutate Tanner's real provider authentication during automated checks.

- [ ] **Step 4: Capture required visual and wire evidence**

Save screenshots for wide, compact-trigger, and minimum widths plus idle color, generating grayscale, hovered background color, expanded account usage, scope confirmation, Connections rows, and safe removal. Save sanitized RPC inspection proving no token/secret appears in payloads, preferences, UI state, or routine logs.

- [ ] **Step 5: Verify older OMP compatibility**

Launch the same built app against an older OMP without account commands. Expected: existing provider-only wheel remains, account selectors/switch/removal are absent, login and provider-level usage still work, and no unsupported action is visible.

- [ ] **Step 6: Commit only verification evidence/corrections**

```bash
git add docs/superpowers/evidence/2026-08-26-multi-account-provider-routing App OmpKit Tests 10x.xcodeproj
git commit -m "test(providers): verify multi-account routing"
```

If no source corrections were needed, stage only evidence. Do not create an empty commit.

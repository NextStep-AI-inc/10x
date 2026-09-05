# Responsive Provider Dock Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore 54-point provider controls outside the composer when the live trailing gutter can hold them, while retaining the measured 28-point footer slot at constrained widths.

**Architecture:** `ProviderUsageDockLayout` regains a pure `placement(...)` policy based on shell width, rail inset, provider count, and composer presence. `AppShellView` derives that decision inside live shell geometry, reserves composer footer width only for `.composerFooter`, and renders either the existing anchor-resolved compact layout or a shell-owned outside/standalone layout.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, AppKit snapshot harness, Xcode 26

## Global Constraints

- Work only in `/Users/tannerpham/CS Projects/10x/.claude/worktrees/responsive-provider-dock` on `tannerpham/responsive-provider-dock`.
- Preserve the measured composer-footer anchor for constrained windows.
- Preserve Context, Steer, Send, Stop, footer wrapping, provider account stacks, hover expansion, detail panels, focus restoration, reduced motion, and account-routing actions.
- Wide placement uses 54-point controls, 8-point provider spacing, the existing 16-point shell inset, and at least 16 points between composer and dock.
- Compact placement uses 28-point controls and the existing exact provider-aware footer reservation.
- Fit uses live shell width, current rail inset, and provider count; do not introduce a fixed breakpoint or stored resize state.
- Routes without a composer keep the standalone bottom-right dock.
- Do not hand-edit `10x.xcodeproj`; no source files are added by this plan, so regeneration is unnecessary.
- Capture only the 10x window during manual verification; never capture the desktop or unrelated applications.
- Baseline: the full suite ran 1,324 tests with one unrelated failure in `providerServiceForwardsExtensionRequestsOnlyForTheActiveLogin()`; its immediate focused rerun passed 1/1.

---

### Task 1: Restore the pure responsive placement policy

**Files:**
- Modify: `Tests/TenXAppTests/ProviderUsageDockLayoutTests.swift:28-39`
- Modify: `App/Providers/ProviderUsageDockLayout.swift:24-59`

**Interfaces:**
- Consumes: existing `ProviderUsageDockCompactLayout`, `ProviderUsageDockLayout.regular54`, `inComposer28`, `spacing8`, and `compact(shellSize:footerFrame:)`.
- Produces: `ProviderUsageDockPlacement`, `ProviderUsageDockLayout.placement(shellWidth:contentLeadingInset:providerCount:hasComposer:)`, and `ProviderUsageDockCompactLayout.outsideComposer` for Task 2.

- [ ] **Step 1: Add failing placement tests**

Replace the two layout tests at the bottom of `ProviderUsageDockLayoutTests.swift` with these tests, retaining the three hover tests unchanged:

```swift
@Test func usageDockUsesRegularWheelsBesideComposerWhenGutterFitsThreeProviders() {
    let placement = ProviderUsageDockLayout.placement(
        shellWidth: 1280,
        contentLeadingInset: 64,
        providerCount: 3,
        hasComposer: true)

    #expect(placement == .outsideComposer)
    #expect(ProviderUsageDockCompactLayout.outsideComposer == ProviderUsageDockCompactLayout(
        wheelDiameter: 54,
        trailingOffset: 0,
        bottomOffset: 12))
}

@Test func usageDockUsesReservedFooterSlotWhenGutterDoesNotFitThreeProviders() {
    let placement = ProviderUsageDockLayout.placement(
        shellWidth: 760,
        contentLeadingInset: 64,
        providerCount: 3,
        hasComposer: true)

    #expect(placement == .composerFooter)

    let layout = ProviderUsageDockLayout.compact(
        shellSize: CGSize(width: 900, height: 700),
        footerFrame: CGRect(x: 620, y: 570, width: 148, height: 60))
    #expect(layout.wheelDiameter == 28)
    #expect(layout.trailingOffset + 16 == CGFloat(132))
    #expect(layout.bottomOffset + 16 == CGFloat(70))
}

@Test func usageDockProviderCountControlsWidePlacementDecision() {
    let twoProviders = ProviderUsageDockLayout.placement(
        shellWidth: 1180,
        contentLeadingInset: 64,
        providerCount: 2,
        hasComposer: true)
    let threeProviders = ProviderUsageDockLayout.placement(
        shellWidth: 1180,
        contentLeadingInset: 64,
        providerCount: 3,
        hasComposer: true)

    #expect(twoProviders == .outsideComposer)
    #expect(threeProviders == .composerFooter)
}

@Test func expandedRailCanConsumeTheOutsideDockGutter() {
    let collapsedRail = ProviderUsageDockLayout.placement(
        shellWidth: 1280,
        contentLeadingInset: 64,
        providerCount: 3,
        hasComposer: true)
    let expandedRail = ProviderUsageDockLayout.placement(
        shellWidth: 1280,
        contentLeadingInset: 220,
        providerCount: 3,
        hasComposer: true)

    #expect(collapsedRail == .outsideComposer)
    #expect(expandedRail == .composerFooter)
}

@Test func usageDockStandaloneRoutesKeepRegularWheelsWithoutOffsets() {
    let placement = ProviderUsageDockLayout.placement(
        shellWidth: 760,
        contentLeadingInset: 64,
        providerCount: 3,
        hasComposer: false)

    #expect(placement == .standalone)
    #expect(ProviderUsageDockCompactLayout.standalone == ProviderUsageDockCompactLayout(
        wheelDiameter: 54,
        trailingOffset: 0,
        bottomOffset: 0))
}

@Test func noProvidersReserveNoFooterSpace() {
    #expect(ProviderUsageDockLayout.footerWidth(providers: []) == 0)
}
```

- [ ] **Step 2: Run one new test to verify RED**

Run:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-responsive-dock-task1-red \
  -parallel-testing-enabled NO \
  -only-testing:'TenXAppTests/usageDockUsesRegularWheelsBesideComposerWhenGutterFitsThreeProviders()'
```

Expected: build failure because `ProviderUsageDockPlacement`, `placement(...)`, and `ProviderUsageDockCompactLayout.outsideComposer` do not exist. A vacuous zero-test success is not acceptable.

- [ ] **Step 3: Implement the minimum pure policy**

Add this enum above `ProviderUsageDockCompactLayout`:

```swift
enum ProviderUsageDockPlacement: Equatable {
    case standalone
    case outsideComposer
    case composerFooter
}
```

Add this static layout beside `.standalone`:

```swift
static let outsideComposer = ProviderUsageDockCompactLayout(
    wheelDiameter: ProviderUsageDockLayout.regular54,
    trailingOffset: 0,
    bottomOffset: 28 - 16)
```

Add this function before `compact(shellSize:footerFrame:)`:

```swift
static func placement(
    shellWidth: CGFloat,
    contentLeadingInset: CGFloat,
    providerCount: Int,
    hasComposer: Bool
) -> ProviderUsageDockPlacement {
    guard hasComposer else { return .standalone }

    let routeWidth = max(0, shellWidth - contentLeadingInset)
    let composerWidth = min(780, max(0, routeWidth - 84))
    let trailingGutter = max(0, (routeWidth - composerWidth) / 2)
    let normalizedCount = max(0, providerCount)
    let groupWidth = normalizedCount > 0
        ? CGFloat(normalizedCount) * regular54
            + CGFloat(normalizedCount - 1) * spacing8
        : 0
    let requiredGutter = groupWidth + 16 + 16

    return trailingGutter >= requiredGutter
        ? .outsideComposer
        : .composerFooter
}
```

Do not change `compact(shellSize:footerFrame:)` or `footerWidth(providers:)`; they remain the compact anchor resolver and provider-aware reservation calculator.

- [ ] **Step 4: Run all placement tests to verify GREEN**

Run the six changed/new functions explicitly:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-responsive-dock-task1-green \
  -parallel-testing-enabled NO \
  -only-testing:'TenXAppTests/usageDockUsesRegularWheelsBesideComposerWhenGutterFitsThreeProviders()' \
  -only-testing:'TenXAppTests/usageDockUsesReservedFooterSlotWhenGutterDoesNotFitThreeProviders()' \
  -only-testing:'TenXAppTests/usageDockProviderCountControlsWidePlacementDecision()' \
  -only-testing:'TenXAppTests/expandedRailCanConsumeTheOutsideDockGutter()' \
  -only-testing:'TenXAppTests/usageDockStandaloneRoutesKeepRegularWheelsWithoutOffsets()' \
  -only-testing:'TenXAppTests/noProvidersReserveNoFooterSpace()'
```

Expected: Swift Testing reports 6 tests passed and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit the pure policy**

```bash
git add App/Providers/ProviderUsageDockLayout.swift \
  Tests/TenXAppTests/ProviderUsageDockLayoutTests.swift
git commit -m "fix(usage): restore responsive dock policy"
git push
```

---

### Task 2: Apply placement to composer reservation and shell rendering

**Files:**
- Modify: `App/Shell/AppShellView.swift:15-62,221-258`
- Verify unchanged: `App/Sessions/ComposerView.swift:800-822` — the slot remains conditional on `composerProviderDockWidth > 0`.
- Modify references: `Tests/TenXAppTests/ReferenceImages/full-shell-usage-dock-wide-window.png`
- Modify references if rendered pixels change: `Tests/TenXAppTests/ReferenceImages/full-shell-account-dock-wide-window.png`
- Verify unchanged references: `full-shell-usage-dock-small-window.png`, `full-shell-account-dock-compact-trigger-window.png`, `full-shell-account-dock-minimum-window.png`

**Interfaces:**
- Consumes: `ProviderUsageDockPlacement`, `ProviderUsageDockLayout.placement(...)`, `.outsideComposer`, `.standalone`, `compact(shellSize:footerFrame:)`, and `footerWidth(providers:)` from Task 1.
- Produces: live shell integration that reserves footer width only for `.composerFooter` and renders all three placements through the existing `ProviderUsageDockView`.

- [ ] **Step 1: Confirm the current wide snapshot proves the regression**

Inspect `Tests/TenXAppTests/ReferenceImages/full-shell-usage-dock-wide-window.png` and record the current fact: the controls are 28 points and inside the composer despite the 1280-point shell. This is the pre-fix visual reproduction; do not modify the image yet.

- [ ] **Step 2: Derive placement inside live shell geometry**

In the non-onboarding branch of `AppShellView.body`, wrap the existing workspace shell in `GeometryReader { shellGeometry in ... }`. Inside that closure, derive:

```swift
let dockProviders = model.providerModel?.dockProviders ?? []
let dockPlacement = ProviderUsageDockLayout.placement(
    shellWidth: shellGeometry.size.width,
    contentLeadingInset: railExpansion.contentLeadingInset,
    providerCount: dockProviders.count,
    hasComposer: hasComposer)
let composerDockWidth = dockPlacement == .composerFooter
    ? ProviderUsageDockLayout.footerWidth(providers: dockProviders)
    : 0
```

Inject `composerDockWidth` into `routeCanvas`:

```swift
.environment(\.composerProviderDockWidth, composerDockWidth)
```

This replaces the current unconditional `hasComposer ? footerWidth(...) : 0` expression. Keep the rail padding and every other environment value unchanged.

- [ ] **Step 3: Render compact and non-compact branches without duplicated dock construction**

Change `usageDock` to consume an already-resolved layout:

```swift
@ViewBuilder
private func usageDock(compactLayout: ProviderUsageDockCompactLayout) -> some View {
    if let providerModel = model.providerModel, !providerModel.dockProviders.isEmpty {
        let dockProviders = providerModel.dockProviders

        ProviderUsageDockView(
            providers: dockProviders,
            activeCounts: model.providerActivityCounts,
            generatingCounts: model.accountGeneratingCounts,
            isForegroundGenerating: model.isForegroundSessionGenerating,
            compactLayout: compactLayout,
            accountScopeSatisfaction: model.accountScopeSatisfaction(
                openSessionID: model.activeSessionIdentityToken),
            accountScopeAvailability: model.accountScopeAvailability(
                openSessionID: model.activeSessionIdentityToken),
            pendingRemovalAccounts: model.pendingRemovalAccounts,
            requiresRestartToSwitch: providerModel.accountTier.requiresRestartToSwitch,
            activeSessionIdentityToken: model.activeSessionIdentityToken,
            onUseAccount: { accountRef, scope in
                let openSessionID = model.activeSessionIdentityToken
                Task {
                    await model.useProviderAccount(
                        accountRef,
                        scope: scope,
                        openSessionID: openSessionID)
                }
            },
            onManageAccounts: { providerID in
                model.manageProviderAccounts(providerID: providerID)
            })
            .padding(.trailing, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}
```

Keep `overlayPreferenceValue(ComposerProviderDockAnchorKey.self)` only for `.composerFooter`:

```swift
.overlayPreferenceValue(ComposerProviderDockAnchorKey.self) { anchor in
    if dockPlacement == .composerFooter, let anchor {
        GeometryReader { geometry in
            usageDock(compactLayout: ProviderUsageDockLayout.compact(
                shellSize: geometry.size,
                footerFrame: geometry[anchor]))
        }
    }
}
```

Add a sibling shell overlay for non-footer placements:

```swift
.overlay {
    switch dockPlacement {
    case .outsideComposer:
        usageDock(compactLayout: .outsideComposer)
    case .standalone:
        usageDock(compactLayout: .standalone)
    case .composerFooter:
        EmptyView()
    }
}
```

Keep the search overlay after the dock overlays so search continues to cover and disable shell content as it does now.

- [ ] **Step 4: Run focused shell snapshots to verify the expected RED references**

Run:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-responsive-dock-task2-snapshots \
  -parallel-testing-enabled NO \
  -only-testing:'TenXAppTests/fullShellUsageDockSmallWindowSnapshot()' \
  -only-testing:'TenXAppTests/fullShellUsageDockWideWindowSnapshot()' \
  -only-testing:'TenXAppTests/fullShellAccountDockWideWindowSnapshot()' \
  -only-testing:'TenXAppTests/fullShellAccountDockCompactTriggerWindowSnapshot()' \
  -only-testing:'TenXAppTests/fullShellAccountDockMinimumWindowSnapshot()'
```

Expected: exactly the wide reference or references fail and write `.actual.png` files. The small, compact-trigger, and minimum references must pass. If a constrained reference changes, stop and fix the layout rather than accepting the regression.

- [ ] **Step 5: Inspect and promote only correct wide references**

Inspect each generated `.actual.png` before promotion. Required visual facts:

- Wide controls are outside the composer at 54 points with labels visible.
- The composer footer contains no empty reserved gap.
- The first provider control is at least 16 points from the composer.
- Controls are not clipped at the shell trailing edge.
- Account stacks remain vertically collapsed at rest.

Promote only the wide actual images that meet those checks:

```bash
mv Tests/TenXAppTests/ReferenceImages/full-shell-usage-dock-wide-window.actual.png \
  Tests/TenXAppTests/ReferenceImages/full-shell-usage-dock-wide-window.png
```

If the account-dock wide reference also changed correctly:

```bash
mv Tests/TenXAppTests/ReferenceImages/full-shell-account-dock-wide-window.actual.png \
  Tests/TenXAppTests/ReferenceImages/full-shell-account-dock-wide-window.png
```

- [ ] **Step 6: Re-run snapshots to verify GREEN**

Run the Step 4 command again.

Expected: Swift Testing reports 5 tests passed, no `.actual.png` files remain, and `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit the shell integration and reviewed snapshots**

```bash
git add App/Shell/AppShellView.swift \
  Tests/TenXAppTests/ReferenceImages/full-shell-usage-dock-wide-window.png \
  Tests/TenXAppTests/ReferenceImages/full-shell-account-dock-wide-window.png
git commit -m "fix(usage): move provider dock outside when it fits"
git push
```

If the account-dock wide reference is byte-identical, omit it from `git add`.

---

### Task 3: Verify the responsive behavior end to end

**Files:**
- Modify checklist state: `docs/superpowers/plans/2026-09-04-responsive-provider-dock-repair.md`
- Update through GitHub API: PR `#24`
- No production-code changes unless a verification failure traces back to this repair.

**Interfaces:**
- Consumes: the complete Task 1 policy and Task 2 shell integration.
- Produces: focused automated proof, full-suite signal, real-app visual proof, and an accurate draft PR record.

- [ ] **Step 1: Run focused layout and snapshot verification**

Run the Task 1 six-test command and Task 2 five-snapshot command once more from the final source state.

Expected: 6/6 placement tests and 5/5 snapshot tests pass with `** TEST SUCCEEDED **`.

- [ ] **Step 2: Run the full suite**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-responsive-dock-final \
  -parallel-testing-enabled NO
```

Expected: 1,324 or more Swift tests plus 4 XCTest tests pass. If `providerServiceForwardsExtensionRequestsOnlyForTheActiveLogin()` alone flakes again, rerun that exact function and record both results; any dock, shell, composer, or snapshot failure blocks completion.

- [ ] **Step 3: Read the local-build handoff skill and launch the final app**

Before launching or telling the user the build is ready, read `skill://launching-local-builds`. Build the `10x` scheme into a dedicated derived-data path, launch its `10x.app`, and verify that the worktree build—not `/Applications/10x.app`—is the visible frontmost app.

- [ ] **Step 4: Exercise the real responsive path**

With three visible provider controls in a real session:

1. Resize the 10x window to a constrained width and verify 28-point controls remain inside the composer footer without covering Context, Steer, Send, or Stop.
2. Resize past the fit boundary and verify the controls move outside, grow to 54 points, show labels, and leave no reserved composer gap.
3. Resize back below the boundary and verify the controls return to the measured slot.
4. Expand and collapse the rail and verify the same placement policy recalculates.
5. Open and close a provider detail panel in both placements; verify account-stack hover and keyboard focus still work.
6. Repeat with Reduce Motion enabled or injected in the verified surface; placement must change without relying on motion.

- [ ] **Step 5: Capture sanitized visual evidence**

Capture only the 10x window by window ID or exact window bounds. Inspect the capture before retaining or attaching it. Delete any capture that includes another app, notification, email address, access code, or desktop content.

- [ ] **Step 6: Complete cleanup and update the draft PR**

- Remove `.actual.png` files and temporary diagnostic artifacts.
- Confirm no project generator churn and no unrelated files are included.
- Mark completed plan checkboxes, commit the plan status as `docs(usage): complete responsive dock plan`, and push.
- Update PR #24 through `gh api repos/NextStep-AI-inc/10x/pulls/24 -X PATCH` with exact test counts, focused commands, full-suite outcome, manual resize results, and sanitized screenshot evidence.
- Keep PR #24 in draft until base synchronization and review gates are complete; do not merge.

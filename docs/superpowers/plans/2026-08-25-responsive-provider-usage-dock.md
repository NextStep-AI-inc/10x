# Responsive Provider Usage Dock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Place 54-point provider usage wheels beside the composer on the bottom row when they fit, and move 44-point wheels above the unchanged composer when the trailing gutter is too narrow.

**Architecture:** Add a pure geometry policy that calculates compact wheel size and offsets from shell width, rail inset, provider count, and composer presence. `AppShellView` supplies that result to the existing dock overlay; `ProviderUsageDockView` applies it only while collapsed, and `ProviderUsageWheelView` scales its existing ring geometry. The composer and bounded expanded popup remain unchanged.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, AppKit snapshot harness, Xcode 26

---

## Constraints and acceptance geometry

- Work only in `/Users/tannerpham/CS Projects/.worktrees/10x-usage-wheels` on `codex/usage-wheels`.
- Do not modify `NewSessionView`, `ActiveSessionView`, or `ComposerView`; the composer remains `maxWidth: 780`, 42 points from constrained route edges, and 28 points from the bottom.
- Keep the shell's existing 16-point trailing and bottom dock padding. Responsive offsets are additional to that base.
- Side placement uses 54-point rings, 8-point wheel spacing, and a 16-point minimum composer gap.
- Above placement uses 44-point rings, keeps labels and at least 44-point button targets, aligns the group to the composer's trailing edge, and places the label stack 8 points above the composer.
- The expanded panel remains 360 points wide, at most 440 points high, full color, and anchored to the existing bottom-right shell inset.
- The fit decision uses provider count and live shell geometry, not a fixed window-width breakpoint.
- Preserve grayscale, pulse, activity count, focus restoration, Escape, outside-click, and close behavior.

## File structure

- Create `App/Providers/ProviderUsageDockLayout.swift`: pure compact placement policy and layout result.
- Create `Tests/TenXAppTests/ProviderUsageDockLayoutTests.swift`: geometry decision tests.
- Modify `App/Providers/ProviderUsageWheelView.swift`: scale the existing ring/core geometry for 54- and 44-point variants.
- Modify `Tests/TenXAppTests/ProviderUsageRingGeometryTests.swift`: prove the constrained variant scales without dropping rings.
- Modify `App/Providers/ProviderUsageDockView.swift`: apply compact size and offsets only to the collapsed group.
- Modify `App/Shell/AppShellView.swift`: calculate responsive layout from shell width and rail inset without changing route layout.
- Modify `Tests/TenXAppTests/ViewSnapshotTests.swift`: add wide-shell coverage and retain the constrained-shell case.
- Add `Tests/TenXAppTests/ReferenceImages/full-shell-usage-dock-wide-window.png` and update `full-shell-usage-dock-small-window.png`.
- Regenerate `10x.xcodeproj/project.pbxproj` after adding Swift files.

---

### Task 1: Add the pure responsive placement policy

**Files:**
- Create: `App/Providers/ProviderUsageDockLayout.swift`
- Create: `Tests/TenXAppTests/ProviderUsageDockLayoutTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing layout tests**

Create `Tests/TenXAppTests/ProviderUsageDockLayoutTests.swift`:

```swift
import Testing
@testable import TenXApp

@Suite struct ProviderUsageDockLayoutTests {
    @Test func wideComposerGutterUsesRegularBottomRowPlacement() {
        let layout = ProviderUsageDockLayout.compact(
            shellWidth: 1_280,
            contentLeadingInset: 64,
            providerCount: 3,
            hasComposer: true)

        #expect(layout == ProviderUsageDockCompactLayout(
            wheelDiameter: 54,
            trailingOffset: 0,
            bottomOffset: 12))
    }

    @Test func constrainedComposerGutterUsesSmallerAbovePlacement() {
        let layout = ProviderUsageDockLayout.compact(
            shellWidth: 760,
            contentLeadingInset: 64,
            providerCount: 3,
            hasComposer: true)

        #expect(layout == ProviderUsageDockCompactLayout(
            wheelDiameter: 44,
            trailingOffset: 26,
            bottomOffset: 116))
    }

    @Test func providerCountParticipatesInTheFitDecision() {
        let twoProviders = ProviderUsageDockLayout.compact(
            shellWidth: 1_180,
            contentLeadingInset: 64,
            providerCount: 2,
            hasComposer: true)
        let threeProviders = ProviderUsageDockLayout.compact(
            shellWidth: 1_180,
            contentLeadingInset: 64,
            providerCount: 3,
            hasComposer: true)

        #expect(twoProviders.wheelDiameter == 54)
        #expect(threeProviders.wheelDiameter == 44)
    }

    @Test func routesWithoutAComposerKeepTheExistingCornerPlacement() {
        let layout = ProviderUsageDockLayout.compact(
            shellWidth: 760,
            contentLeadingInset: 64,
            providerCount: 3,
            hasComposer: false)

        #expect(layout == .standalone)
    }
}
```

- [ ] **Step 2: Regenerate the project and verify RED**

Run:

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-responsive-dock-task1-red \
  -parallel-testing-enabled NO \
  -only-testing:'TenXAppTests/ProviderUsageDockLayoutTests' test
```

Expected: build failure because `ProviderUsageDockLayout` and `ProviderUsageDockCompactLayout` do not exist.

- [ ] **Step 3: Implement the minimum geometry policy**

Create `App/Providers/ProviderUsageDockLayout.swift`:

```swift
import CoreGraphics

struct ProviderUsageDockCompactLayout: Equatable {
    static let standalone = Self(
        wheelDiameter: ProviderUsageDockLayout.regularWheelDiameter,
        trailingOffset: 0,
        bottomOffset: 0)

    let wheelDiameter: CGFloat
    let trailingOffset: CGFloat
    let bottomOffset: CGFloat
}

enum ProviderUsageDockLayout {
    static let regularWheelDiameter: CGFloat = 54
    static let constrainedWheelDiameter: CGFloat = 44
    static let wheelSpacing: CGFloat = 8

    private static let composerMaxWidth: CGFloat = 780
    private static let composerHorizontalInset: CGFloat = 42
    private static let composerHeight: CGFloat = 96
    private static let composerBottomInset: CGFloat = 28
    private static let shellInset: CGFloat = 16
    private static let minimumComposerGap: CGFloat = 16
    private static let aboveComposerGap: CGFloat = 8

    static func compact(
        shellWidth: CGFloat,
        contentLeadingInset: CGFloat,
        providerCount: Int,
        hasComposer: Bool
    ) -> ProviderUsageDockCompactLayout {
        guard hasComposer else { return .standalone }

        let routeWidth = max(0, shellWidth - contentLeadingInset)
        let composerWidth = min(
            composerMaxWidth,
            max(0, routeWidth - composerHorizontalInset * 2))
        let trailingGutter = max(0, (routeWidth - composerWidth) / 2)
        let count = max(0, providerCount)
        let groupWidth = count == 0
            ? 0
            : CGFloat(count) * regularWheelDiameter
                + CGFloat(count - 1) * wheelSpacing
        let requiredGutter = groupWidth + shellInset + minimumComposerGap

        if trailingGutter >= requiredGutter {
            return ProviderUsageDockCompactLayout(
                wheelDiameter: regularWheelDiameter,
                trailingOffset: 0,
                bottomOffset: composerBottomInset - shellInset)
        }

        return ProviderUsageDockCompactLayout(
            wheelDiameter: constrainedWheelDiameter,
            trailingOffset: max(0, trailingGutter - shellInset),
            bottomOffset: composerBottomInset
                + composerHeight
                + aboveComposerGap
                - shellInset)
    }
}
```

- [ ] **Step 4: Verify GREEN and project stability**

Run the Task 1 selector again with derived data at `/tmp/tenx-responsive-dock-task1-green`.

Expected: all four layout tests pass.

Then run:

```bash
git diff --check
ruby scripts/generate_xcodeproj.rb
git diff --check
```

Expected: no second generator diff and no whitespace errors.

- [ ] **Step 5: Commit the policy**

```bash
git add App/Providers/ProviderUsageDockLayout.swift \
  Tests/TenXAppTests/ProviderUsageDockLayoutTests.swift \
  10x.xcodeproj/project.pbxproj \
  10x.xcodeproj/xcshareddata/xcschemes/10x.xcscheme
git commit -m "feat(usage): add responsive dock placement policy"
```

---

### Task 2: Scale the wheel without losing limits or accessibility

**Files:**
- Modify: `Tests/TenXAppTests/ProviderUsageRingGeometryTests.swift`
- Modify: `App/Providers/ProviderUsageWheelView.swift`

- [ ] **Step 1: Add the failing constrained-geometry test**

Add this test inside `ProviderUsageRingGeometryTests`:

```swift
@Test func constrainedUsageRingMetricsScaleTheCoreAndRetainEveryLimit() {
    let metrics = ProviderUsageRingGeometry.metrics(
        limitCount: 12,
        outerDiameter: 44)
    let coreDiameter = ProviderUsageRingGeometry.coreDiameter(for: 44)

    #expect(metrics.count == 12)
    #expect(abs(coreDiameter - 44 / 3) < 0.001)
    #expect(metrics.first.map {
        ($0.diameter - $0.lineWidth) / 2 > coreDiameter / 2
    } ?? false)
    #expect(metrics.last.map {
        ($0.diameter + $0.lineWidth) / 2 <= 22
    } ?? false)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-responsive-dock-task2-red \
  -parallel-testing-enabled NO \
  -only-testing:'TenXAppTests/ProviderUsageRingGeometryTests' test
```

Expected: compile failure because `metrics(limitCount:outerDiameter:)` and `coreDiameter(for:)` are absent.

- [ ] **Step 3: Make ring geometry diameter-aware**

Replace `ProviderUsageRingGeometry` with:

```swift
enum ProviderUsageRingGeometry {
    static let diameter: CGFloat = 54
    static let coreDiameter: CGFloat = 18

    static func coreDiameter(for outerDiameter: CGFloat) -> CGFloat {
        coreDiameter * outerDiameter / diameter
    }

    static func metrics(
        limitCount: Int,
        outerDiameter: CGFloat = diameter
    ) -> [ProviderUsageRingMetric] {
        guard limitCount > 0 else { return [] }
        let scaledCoreDiameter = coreDiameter(for: outerDiameter)
        let availableRadius = (outerDiameter - scaledCoreDiameter) / 2
        let slotWidth = availableRadius / CGFloat(limitCount)
        let lineWidth = slotWidth * 0.68

        return (0..<limitCount).map { index in
            let radius = scaledCoreDiameter / 2
                + slotWidth * (CGFloat(index) + 0.5)
            return ProviderUsageRingMetric(
                diameter: radius * 2,
                lineWidth: lineWidth)
        }
    }
}
```

Replace the four stored-property declarations at the top of
`ProviderUsageWheelView` and insert this initializer immediately before the
existing environment declaration:

```swift
let provider: ProviderUsageProvider
let activeCount: Int
let isGrayscale: Bool
let diameter: CGFloat

init(
    provider: ProviderUsageProvider,
    activeCount: Int,
    isGrayscale: Bool,
    diameter: CGFloat = ProviderUsageRingGeometry.diameter
) {
    self.provider = provider
    self.activeCount = activeCount
    self.isGrayscale = isGrayscale
    self.diameter = diameter
}
```

Update its derived geometry and frames exactly as follows:

```swift
private var metrics: [ProviderUsageRingMetric] {
    ProviderUsageRingGeometry.metrics(
        limitCount: ringLimits.count,
        outerDiameter: diameter)
}

private var activityCoreDiameter: CGFloat {
    ProviderUsageRingGeometry.coreDiameter(for: diameter)
}
```

Replace the outer wheel frame with:

```swift
.frame(width: diameter, height: diameter)
```

Replace the two core-sized frames in `pulseOutline` and `activityCore` with:

```swift
.frame(
    width: activityCoreDiameter,
    height: activityCoreDiameter)
```

Do not change colors, labels, animation timing, or accessibility containment.

- [ ] **Step 4: Verify both wheel sizes**

Run the Task 2 selector again at `/tmp/tenx-responsive-dock-task2-green`.

Expected: all ring geometry tests pass, including the 12-limit 44-point case.

Then run the three existing direct dock snapshot selectors without recording:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-responsive-dock-task2-snapshots \
  -parallel-testing-enabled NO \
  -only-testing:'TenXAppTests/providerUsageDockIdleSnapshot()' \
  -only-testing:'TenXAppTests/providerUsageDockGeneratingSnapshot()' \
  -only-testing:'TenXAppTests/providerUsageDockExpandedSnapshot()' test
```

Expected: all three existing 54-point snapshots remain byte-identical.

- [ ] **Step 5: Commit scalable geometry**

```bash
git add App/Providers/ProviderUsageWheelView.swift \
  Tests/TenXAppTests/ProviderUsageRingGeometryTests.swift
git commit -m "feat(usage): add constrained wheel geometry"
```

---

### Task 3: Wire responsive placement into the shell and record acceptance snapshots

**Files:**
- Modify: `App/Providers/ProviderUsageDockView.swift`
- Modify: `App/Shell/AppShellView.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Create: `Tests/TenXAppTests/ReferenceImages/full-shell-usage-dock-wide-window.png`
- Modify: `Tests/TenXAppTests/ReferenceImages/full-shell-usage-dock-small-window.png`

- [ ] **Step 1: Add the wide-shell snapshot before production wiring**

Add this test immediately after `fullShellUsageDockSmallWindowSnapshot`:

```swift
@MainActor
@Test func fullShellUsageDockWideWindowSnapshot() async throws {
    let providerModel = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: fullShellProviders),
        usageService: FakeUsageService(snapshot: try fullShellUsageSnapshot()),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 1_787_675_746) })
    let model = AppModel(dependencies: AppDependencies(
        ompLocator: SnapshotOmpLocator(),
        sessionLibrary: SessionLibrary(root: URL(
            filePath: "/tmp/10x-full-shell-wide-usage-dock-snapshot",
            directoryHint: .isDirectory)),
        makeProviderModel: { _ in providerModel }))
    await model.bootstrap()
    model.selectedProjectURL = URL(
        filePath: "/tmp/full-shell-project",
        directoryHint: .isDirectory)
    model.sessions = fullShellSessions

    try assertSnapshot(
        AppShellView(model: model),
        name: "full-shell-usage-dock-wide-window",
        size: CGSize(width: 1_280, height: 760))
}
```

- [ ] **Step 2: Run the new snapshot and verify RED**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-responsive-dock-task3-red \
  -parallel-testing-enabled NO \
  -only-testing:'TenXAppTests/fullShellUsageDockWideWindowSnapshot()' test
```

Expected: failure reporting the missing `full-shell-usage-dock-wide-window.png` reference.

- [ ] **Step 3: Pass compact layout through `ProviderUsageDockView`**

Replace `collapsedBottomOffset` with:

```swift
let compactLayout: ProviderUsageDockCompactLayout
```

Replace the initializer with:

```swift
init(
    providers: [ProviderUsageProvider],
    activeCounts: [String: Int],
    isForegroundGenerating: Bool,
    compactLayout: ProviderUsageDockCompactLayout = .standalone,
    initiallySelectedProviderID: String? = nil
) {
    self.providers = providers
    self.activeCounts = activeCounts
    self.isForegroundGenerating = isForegroundGenerating
    self.compactLayout = compactLayout
    _selectedProviderID = State(initialValue: providers.contains(where: {
        $0.id == initiallySelectedProviderID
    }) ? initiallySelectedProviderID : nil)
}
```

Replace the collapsed branch padding with:

```swift
collapsedDock
    .padding(.trailing, compactLayout.trailingOffset)
    .padding(.bottom, compactLayout.bottomOffset)
```

Replace `providerButton`, `compactProviderButton`, `expandedProviderButton`, and
`providerWheel` with:

```swift
private func providerButton(
    _ provider: ProviderUsageProvider,
    isGrayscale: Bool,
    diameter: CGFloat
) -> some View {
    Button {
        select(provider)
    } label: {
        providerWheel(
            provider,
            isGrayscale: isGrayscale,
            diameter: diameter)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusable()
    .focusEffectDisabled()
    .accessibilityLabel(provider.name)
    .accessibilityValue(ProviderUsageAccessibility.wheelValue(
        provider: provider,
        activeCount: activeCounts[provider.id] ?? 0))
}

private func compactProviderButton(
    _ provider: ProviderUsageProvider,
    isGrayscale: Bool
) -> some View {
    providerButton(
        provider,
        isGrayscale: isGrayscale,
        diameter: compactLayout.wheelDiameter)
        .focused($compactFocusedProviderID, equals: provider.id)
}

private func expandedProviderButton(
    _ provider: ProviderUsageProvider,
    isGrayscale: Bool
) -> some View {
    providerButton(
        provider,
        isGrayscale: isGrayscale,
        diameter: ProviderUsageRingGeometry.diameter)
        .focused($expandedFocusedProviderID, equals: provider.id)
}

@ViewBuilder
private func providerWheel(
    _ provider: ProviderUsageProvider,
    isGrayscale: Bool,
    diameter: CGFloat
) -> some View {
    let wheel = ProviderUsageWheelView(
        provider: provider,
        activeCount: activeCounts[provider.id] ?? 0,
        isGrayscale: isGrayscale,
        diameter: diameter)

    if !reduceMotion {
        wheel.matchedGeometryEffect(
            id: "usage-wheel-\(provider.id)",
            in: expansionNamespace,
            isSource: selectedProviderID == nil || provider.id != selectedProviderID)
    } else {
        wheel
    }
}
```

Keep the matched-geometry id, focus bindings, and accessibility value unchanged.

- [ ] **Step 4: Calculate layout in `AppShellView` without touching the composer**

Replace the current bottom-trailing dock overlay with a geometry-backed overlay:

```swift
.overlay {
    GeometryReader { geometry in
        if let providerModel = model.providerModel,
           !providerModel.dockProviders.isEmpty {
            let compactLayout = ProviderUsageDockLayout.compact(
                shellWidth: geometry.size.width,
                contentLeadingInset: railExpansion.contentLeadingInset,
                providerCount: providerModel.dockProviders.count,
                hasComposer: hasComposer)

            ProviderUsageDockView(
                providers: providerModel.dockProviders,
                activeCounts: model.providerActivityCounts,
                isForegroundGenerating: model.isForegroundSessionGenerating,
                compactLayout: compactLayout)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .bottomTrailing)
        }
    }
}
```

Delete `collapsedDockBottomOffset` and replace it with:

```swift
private var hasComposer: Bool {
    switch model.route {
    case .newSession, .session:
        return true
    default:
        return false
    }
}
```

Do not add padding to `routeCanvas` and do not modify any session or composer view.

- [ ] **Step 5: Record only the two shell acceptance references**

```bash
RECORD_SNAPSHOTS=1 xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-responsive-dock-task3-record \
  -parallel-testing-enabled NO \
  -only-testing:'TenXAppTests/fullShellUsageDockSmallWindowSnapshot()' \
  -only-testing:'TenXAppTests/fullShellUsageDockWideWindowSnapshot()' test
```

Expected: both selectors pass and write only:

- `Tests/TenXAppTests/ReferenceImages/full-shell-usage-dock-small-window.png`
- `Tests/TenXAppTests/ReferenceImages/full-shell-usage-dock-wide-window.png`

Inspect both files at original resolution with `view_image`.

Wide acceptance: the three 54-point wheels are at the shell's bottom-right, their label bottoms align with the composer's bottom edge, and at least 16 points separate the wheel group from the composer.

Constrained acceptance: the three 44-point wheels are above the composer, both trailing edges align, at least 8 points separate the labels from the composer border, and the composer has the same 42-point horizontal and 28-point bottom insets as before.

- [ ] **Step 6: Verify snapshots, focus, and direct dock behavior without recording**

Unset `RECORD_SNAPSHOTS`, then run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-responsive-dock-task3-green \
  -parallel-testing-enabled NO \
  -only-testing:'TenXAppTests/fullShellUsageDockSmallWindowSnapshot()' \
  -only-testing:'TenXAppTests/fullShellUsageDockWideWindowSnapshot()' \
  -only-testing:'TenXAppTests/providerUsageDockIdleSnapshot()' \
  -only-testing:'TenXAppTests/providerUsageDockGeneratingSnapshot()' \
  -only-testing:'TenXAppTests/providerUsageDockExpandedSnapshot()' \
  -only-testing:'TenXAppTests/ProviderUsageDockFocusTests' \
  -only-testing:'TenXAppTests/AccessibilityLabelTests' test
```

Expected: every selected test passes. Confirm `git status --short` contains only the planned Swift files and two planned PNGs.

- [ ] **Step 7: Commit responsive shell integration**

```bash
git add App/Providers/ProviderUsageDockView.swift \
  App/Shell/AppShellView.swift \
  Tests/TenXAppTests/ViewSnapshotTests.swift \
  Tests/TenXAppTests/ReferenceImages/full-shell-usage-dock-small-window.png \
  Tests/TenXAppTests/ReferenceImages/full-shell-usage-dock-wide-window.png
git commit -m "feat(usage): responsively place provider wheels"
```

---

### Task 4: Verify the real Release experience and review the branch delta

**Files:**
- No planned source changes.
- If verification finds a direct requirement failure, return to the owning task with a new failing test before editing.

- [ ] **Step 1: Confirm generated project and patch hygiene**

```bash
ruby scripts/generate_xcodeproj.rb
git diff --exit-code -- 10x.xcodeproj
git diff --check
git status --short --branch
```

Expected: generator is stable, patch check is clean, and the worktree has no uncommitted files.

- [ ] **Step 2: Run the complete app and package suites**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-responsive-dock-final-tests \
  PRODUCT_BUNDLE_IDENTIFIER=com.tannerpham.tenx.responsivedock \
  -parallel-testing-enabled NO test

cd OmpKit && swift test
```

Expected: the complete app suite passes, followed by all 141 OmpKit tests with only the two existing opt-in fixture skips.

- [ ] **Step 3: Build and launch the exact-head Release app**

Use the `launching-local-builds` skill before launch.

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-responsive-dock-final-release build
open -na '/tmp/tenx-responsive-dock-final-release/Build/Products/Release/10x.app' \
  --args -ApplePersistenceIgnoreState YES
```

Expected: the exact-head Release process survives and has one visible window. Do not stop or reuse another worktree's 10x process.

- [ ] **Step 4: Exercise both responsive states in the real app**

With three configured providers visible:

1. Set the content size to 1,280 by 760. Confirm 54-point wheels share the composer's 28-point bottom inset and remain outside its border.
2. Resize to 760 by 560. Confirm the group switches to 44-point rings above the composer, aligns to its trailing edge, and leaves the composer at the same 42-point horizontal and 28-point bottom insets.
3. Resize slowly across the fit threshold. Confirm the group switches as one unit and never overlaps the composer.
4. Open a provider in both widths. Confirm the expanded popup remains bounded at 360 by at most 440 and stays full color.
5. Close by button, Escape, and outside click. Confirm focus returns to the compact provider button in the currently selected responsive layout.
6. If a real turn is available, confirm compact grayscale/count/pulse behavior remains unchanged.

Capture real-build screenshots if macOS Screen Recording permission is available. If permission remains denied, report the exact blocker and present the inspected snapshot references separately as automated evidence.

- [ ] **Step 5: Review the complete delta and hand off**

Use `reviewing-code` on `665dcf2..HEAD`, prioritizing composer geometry, rail-inset math, provider-count fit behavior, expanded-popup containment, focus restoration, accessibility, and snapshot fidelity. Fix Important findings through a failing test and re-review the correction once.

Final report must use these headings:

- **Verified:** exact commands, suite results, inspected images, Release PID/path, and review verdict.
- **Not verified:** only externally blocked live states, with the exact reason.
- **For you to test:** the entry point, wide/narrow resize path, branch, and SHA.

Do not merge, push, or stop unrelated 10x processes without Tanner's instruction.

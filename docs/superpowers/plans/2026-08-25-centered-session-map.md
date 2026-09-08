# Centered Session Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the sidebar session map vertically centered with equal 24-point minimum spacing above and below while preserving scrolling and full-height overflow capacity.

**Architecture:** Add a small pure layout calculation beside the existing rail scroll calculation, then use it from `FloatingRailView` inside the middle-region `GeometryReader`. Existing snapshots remain the visual contract; their references are re-recorded only after the layout invariant is green.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, Xcode snapshot tests.

---

### Task 1: Define the centered map-height invariant

**Files:**
- Create: `App/Shell/RailMapLayout.swift`
- Create: `Tests/TenXAppTests/RailMapLayoutTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing pure-layout tests**

Create `Tests/TenXAppTests/RailMapLayoutTests.swift`:

```swift
import Testing
@testable import TenXApp

@Test func shortRailMapUsesItsNaturalHeight() {
    #expect(RailMapLayout.height(itemCount: 4, availableHeight: 500) == 128)
}

@Test func overflowingRailMapPreservesEqualMinimumSpacing() {
    #expect(RailMapLayout.minimumVerticalSpacing == 24)
    #expect(RailMapLayout.height(itemCount: 20, availableHeight: 500) == 452)
}

@Test func railMapHeightNeverBecomesNegative() {
    #expect(RailMapLayout.height(itemCount: 20, availableHeight: 30) == 0)
}
```

Add only the new source and test file references to the existing app and test targets in `10x.xcodeproj/project.pbxproj`.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests test
```

Expected: compilation fails because `RailMapLayout` does not exist. Confirm the Swift Testing run is nonzero when GREEN; this project may ignore file-style selectors.

- [ ] **Step 3: Implement the minimum pure layout calculation**

Create `App/Shell/RailMapLayout.swift`:

```swift
import CoreGraphics

enum RailMapLayout {
    static let minimumVerticalSpacing: CGFloat = 24

    static func height(itemCount: Int, availableHeight: CGFloat) -> CGFloat {
        let naturalHeight = CGFloat(itemCount) * RailScrollNavigation.rowHeight
        let maximumHeight = max(0, availableHeight - minimumVerticalSpacing * 2)
        return min(naturalHeight, maximumHeight)
    }
}
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run the Step 2 command. Expected: the three new layout tests execute and pass with the existing suite.

- [ ] **Step 5: Commit the pure invariant**

```bash
git add App/Shell/RailMapLayout.swift Tests/TenXAppTests/RailMapLayoutTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "test(shell): define centered rail geometry"
```

---

### Task 2: Center the session map in the flexible middle region

**Files:**
- Modify: `App/Shell/FloatingRailView.swift`
- Modify: `Tests/TenXAppTests/ReferenceImages/shell-rail-collapsed.png`
- Modify: `Tests/TenXAppTests/ReferenceImages/shell-rail-expanded.png`
- Modify: `Tests/TenXAppTests/ReferenceImages/shell-rail-overflow-expanded.png`

- [ ] **Step 1: Replace the full-height map frame with symmetric spacers**

Replace:

```swift
sessionMap
    .frame(maxHeight: .infinity)
```

with:

```swift
GeometryReader { proxy in
    VStack(spacing: 0) {
        Spacer(minLength: RailMapLayout.minimumVerticalSpacing)

        if !items.isEmpty {
            sessionMap
                .frame(height: RailMapLayout.height(
                    itemCount: items.count,
                    availableHeight: proxy.size.height))
        }

        Spacer(minLength: RailMapLayout.minimumVerticalSpacing)
    }
}
```

The two flexible `Spacer` values divide surplus height equally. The map remains natural-height for short content and uses all middle-region space except 24 points on each side when overflowing. Do not add a percentage cap or move Archived into the scroll region.

- [ ] **Step 2: Run snapshots and verify the existing references fail**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' test
```

Expected: the three rail snapshots fail because their vertical placement changed; all non-rail tests pass.

- [ ] **Step 3: Record only the affected rail references**

Use the repository's normal-scheme recording workflow. If shell environment propagation fails, temporarily set the scheme's existing `RECORD_SNAPSHOTS` value to `1`, record, and fully restore the scheme before committing. Revert every changed reference except:

```text
shell-rail-collapsed.png
shell-rail-expanded.png
shell-rail-overflow-expanded.png
```

- [ ] **Step 4: Inspect the three images at original resolution**

Confirm:

- Collapsed and expanded short maps have equal visual space above and below.
- Overflow retains at least 24 points above and below the map.
- The down chevron remains in a dedicated strip and does not cover a row.
- Archived remains pinned and separate.
- No text or tree connector is clipped.

- [ ] **Step 5: Run the full suite and commit**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' test
git diff --check
```

Expected: the full Swift Testing suite passes and only the intended files are modified.

Commit:

```bash
git add App/Shell/FloatingRailView.swift \
  Tests/TenXAppTests/ReferenceImages/shell-rail-collapsed.png \
  Tests/TenXAppTests/ReferenceImages/shell-rail-expanded.png \
  Tests/TenXAppTests/ReferenceImages/shell-rail-overflow-expanded.png
git commit -m "fix(shell): center the session map"
```

---

### Task 3: Verify the Release layout and refresh the open app

**Files:**
- Modify only files required to fix failures introduced by Tasks 1-2.

- [ ] **Step 1: Run fresh automated verification**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' test
swift test --package-path OmpKit
```

Expected: all app tests pass; all package tests pass except the two existing environment-gated integrations.

- [ ] **Step 2: Build the universal Release app**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-session-rail-management-derived build
lipo -archs /tmp/tenx-session-rail-management-derived/Build/Products/Release/10x.app/Contents/MacOS/10x
```

Expected: `BUILD SUCCEEDED` and `x86_64 arm64`.

- [ ] **Step 3: Launch and inspect the real layout**

Following `launching-local-builds`, replace only the existing feature PID, launch one new instance, and confirm one visible, main, non-minimized window through Accessibility. At both short and tall heights, inspect collapsed and expanded rails and confirm equal top/bottom separation, correct centering, preserved chevrons, and pinned Archived placement.

- [ ] **Step 4: Capture evidence and leave the branch clean**

If live screen capture remains blocked, cite the three newly recorded deterministic rail snapshots. Run:

```bash
git diff --check
git status --short
```

Expected: clean output. Keep the refreshed feature app open for review.

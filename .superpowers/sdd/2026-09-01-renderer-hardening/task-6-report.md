# Task 6 Report: Stop Continuous Provider Wheel Evaluation

## Status

DONE

## Implementation

- Added the pure `ProviderActivityAnimation.shouldPulse(activeCount:reduceMotion:isSceneActive:)` gate.
- Replaced the provider wheel's 30 FPS `TimelineView` with `@State isPulseExpanded` and a one-second repeating ease-in-out animation.
- The pulse starts only with active providers, an active scene, and Reduce Motion disabled. Activity, scene, or accessibility changes collapse the state without a repeating animation; repeated updates do not restart an already-running animation.
- Preserved static ring geometry, opaque canvas fill, grayscale/reducing-motion appearance, and the existing accessibility container.
- Added the four gate combinations to `ProviderUsageRingGeometryTests`.

## TDD Evidence

The focused gate run first failed as expected because `ProviderActivityAnimation` was missing (`/tmp/10x-task6-red.log`). After implementing the gate, the ring suite passed all 12 tests, including all four parameterized gate cases:

```text
Test providerPulseRunsOnlyWhenUseful(activeCount:reduceMotion:isSceneActive:expected:) with 4 test cases passed
Test run with 12 tests in 1 suite passed
```

## Verification

```bash
! rg -n 'TimelineView' App/Providers/ProviderUsageWheelView.swift
```

Passed: no `TimelineView` remains in the provider wheel.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/ProviderUsageRingGeometryTests'
```

Passed: 12 tests.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/ViewSnapshotTests'
```

Passed: 15 tests, including the ruling-mandated `usageWheelFillsSpacesBetweenRingsWithCanvasColor()` and `providerAccountGeneratingGrayscaleSnapshot()` cases. No snapshot references changed.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
```

Passed: 1,179 tests in 26 suites.

```bash
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS'
git diff --check
```

Passed: universal signed Release build and whitespace validation.

## Snapshot Inspection

No visual delta was produced. The existing static-wheel and grayscale/generating references passed unchanged; no reference-image update was needed.

## Self-review

- `updatePulseAnimation()` is guarded by the target state, so repeated `onAppear`/`onChange` callbacks do not stack repeat-forever animations.
- Scene phase and Reduce Motion changes stop and collapse the pulse immediately; no timer, task, or wall-clock evaluation remains.
- The change is scoped to the wheel and its geometry tests.

## Concerns

None.

## Not verified

- No standalone Release-app launch or CPU sample was run here; those are part of the milestone's Task 8 packaged-app verification.

## For you to test

- In a running app, confirm an actively generating provider wheel pulses while foregrounded, then collapses when the app backgrounds or Reduce Motion is enabled.

## Commit

`fcf918dcf785cbedcba40d55941084efc105b832` (`perf(providers): stop continuous wheel evaluation`)

# Task 6 Report: Stop Continuous Provider Wheel Evaluation

## Status

DONE

## Implementation

- Added the pure `ProviderActivityAnimation.shouldPulse(activeCount:reduceMotion:isSceneActive:)` gate.
- Replaced the provider wheel's 30 FPS `TimelineView` with `@State isPulseExpanded` and a one-second repeating ease-in-out animation.
- The pulse starts only with active providers, an active scene, and Reduce Motion disabled. Activity, scene, or accessibility changes collapse the state without a repeating animation; repeated updates do not restart an already-running animation.
- Preserved static ring geometry, opaque canvas fill, grayscale/reducing-motion appearance, and the existing accessibility container.
- Added the four gate combinations to `ProviderUsageRingGeometryTests`.
- Fix Round 1 adds an explicit `onDisappear` collapse so retained offscreen wheels cannot keep a repeating animation alive; the existing guarded `onAppear` restarts it only when the pulse gate is true.

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

## Fix Round 1

Review finding addressed: `onDisappear` now calls `stopPulseAnimation()`, which clears `isPulseExpanded` under `withAnimation(nil)`. `onAppear` remains the restart point and the existing target-state guard prevents duplicate repeat-forever animations. No additional state machine or snapshot fixture was needed for this direct lifecycle hook.

Verification after the lifecycle correction:

```text
ProviderUsageRingGeometryTests: 12 tests passed
ViewSnapshotTests: 15 tests passed
Full suite: 1,179 tests in 26 suites passed on rerun
DiffRenderPresentationTests in isolation: 12 tests passed
Release build: BUILD SUCCEEDED
No TimelineView; git diff --check passed
```

The first post-fix full-suite attempt reproduced the pre-existing unrelated
`DiffRenderPresentationTests.cancelledOldTokenizationCannotPublishIntoReplacementContent()` race; its isolated suite and the immediate full-suite rerun passed.

## Self-review

- `updatePulseAnimation()` is guarded by the target state, so repeated `onAppear`/`onChange` callbacks do not stack repeat-forever animations.
- `stopPulseAnimation()` collapses the state without animation on disappearance, ensuring a retained offscreen wheel cannot keep a repeat-forever animation active; scene phase and Reduce Motion changes also stop and collapse it immediately.
- The change is scoped to the wheel and its geometry tests.

## Concerns

None.

## Not verified

- No standalone Release-app launch or CPU sample was run here; those are part of the milestone's Task 8 packaged-app verification.

## For you to test

- In a running app, confirm an actively generating provider wheel pulses while foregrounded, then collapses when the app backgrounds or Reduce Motion is enabled.

## Commit

Reviewed base: `f1086b0b137bb884a9124c24ea2c20290c6853ea` (`perf(providers): stop continuous wheel evaluation`).

Fix Round 1: lifecycle correction committed atomically after review; see the follow-up commit in this branch.

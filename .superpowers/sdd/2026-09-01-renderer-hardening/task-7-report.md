# Task 7 report — batch and paginate installer logs

## Status

DONE

## Implementation

- Added `@MainActor @Observable OnboardingInstallLogBuffer`. Retained lines, delayed task, generation, and scheduler state are observation-ignored; only `totalCount` and `flushRevision` publish to SwiftUI.
- The default scheduler owns a cancellable 100 ms task. Injected schedulers receive only a generation-checked callback, so `flush()` and `reset()` make late callbacks no-ops without a public cancellation protocol.
- Replaced the install view's unbounded `[String]` state with a 200/200 `ProgressiveReveal` tail rendered by `LazyVStack`. Log row IDs are absolute offsets, Copy uses full retained text, and snapshot seed logs flush immediately.
- Installer output flushes before success, thrown-failure, and cancellation phase changes. Live scrolling follows only while the reader is near the newest line.

## TDD evidence

Added `OnboardingInstallLogBufferTests.swift`, regenerated the project, and ran the focused target before production code. It failed as intended because `OnboardingInstallLogBuffer` did not exist. After implementation:

```text
Test run with 6 tests in 1 suite passed
```

The suite covers one scheduled callback for 1,000 lines, full text retention, 200-to-400 tails, stable absolute IDs, reset/late-callback invalidation, explicit-flush invalidation, and one finite reveal page.

## Verification

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  '-only-testing:TenXAppTests/OnboardingInstallLogBufferTests' \
  '-only-testing:TenXAppTests/onboardingInstallStepVerifyingSnapshot()' \
  '-only-testing:TenXAppTests/onboardingInstallStepPagedLogSnapshot()'
```

Passed: 8 tests. The two direct snapshot references were inspected and rerun; the 400-line fixture renders the bounded 200-line tail with `Show 200 older lines` and Copy.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
```

Passed on the immediate rerun: 1,186 tests in 27 suites. The first full run had the existing unrelated `DiffRenderPresentationTests.cancelledOldTokenizationCannotPublishIntoReplacementContent()` race; its isolated suite passed, then the complete rerun passed.

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-task7-release build
git diff --check
```

Passed: Release build and task diff whitespace validation. The broader `origin/codex/fix-large-skill-freeze...HEAD` whitespace check still reports an unrelated pre-existing trailing space in `App/Tools/DiffRenderPresentation.swift`.

## Not verified

- A standalone Release-app install flow was not driven manually. Task 8 owns packaged-app launch and saturation verification.
- The Release artifact is unsigned in this local configuration, so a strict codesign validation is not applicable to this task.

## For you to test

- Start an OMP install with more than 200 output lines, scroll upward, and confirm incoming output does not pull the reader back to the live tail.
- Confirm Copy places the full installer transcript, not just the visible tail, on the clipboard.

## Commit

`perf(onboarding): batch and paginate install logs`

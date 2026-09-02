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

---

## Fix Round 1 (2026-09-02)

### Status

DONE

### Fixes

- The production installer-line consumer now appends a yielded line before checking cancellation. A cancellation immediately after a yield flushes that line, requests the idle phase, and stops the loop.
- The older-log disclosure remains one `Button` whenever the log exceeds the initial 200-line budget. It advances by one 200-line page while more history exists, then becomes `Show newest 200 lines` and collapses to the bounded tail. Its accessibility labels explicitly name installer log lines.
- Added the activated 400-line snapshot. The 126-point viewport remains bounded, Copy remains its sibling, and the snapshot shows the persistent collapse action.

### TDD evidence

The first focused test run failed as expected because `consumeInstallerOutput` and `OnboardingInstallLogDisclosure` did not exist. After the minimal implementation, the focused buffer suite passed with 8 tests. The cancellation regression proves the yielded line reaches `totalCount` and `completeText` before the stop path is requested. The disclosure regression proves 200-to-400 expansion, stable absolute IDs for the newer tail, exact visible and accessibility labels, and the collapse state.

### Verification

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  '-only-testing:TenXAppTests/onboardingInstallStepExpandedPagedLogSnapshot()' \
  '-only-testing:TenXAppTests/onboardingInstallStepPagedLogSnapshot()' \
  '-only-testing:TenXAppTests/OnboardingInstallLogBufferTests'
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-task7-fix1-release build
git diff --check
```

Passed: generator produced no project-file changes; focused coverage passed 10 tests; the expanded snapshot was visually inspected; the final full suite passed 1,189 tests in 27 suites; the fresh Release build succeeded; and the task diff was whitespace-clean.

The first full-suite attempt had the existing nondeterministic `archivingAPendingStreamingSessionClosesAndRemovesActivity()` failure. Its isolated rerun passed, and the immediately following complete suite passed without changes outside Task 7.

### Not verified

- A human-driven cancellation of a real installer process was not run. The deterministic production-helper test covers the line-yield/cancellation ordering.

### For you to test

- During a real long install, cancel immediately after output arrives and confirm the final received line remains visible and copyable.
- Expand a 400-line installer transcript, verify `Show newest 200 lines` retains keyboard focus, then collapse it without a scroll-to-bottom jump.

---

## Fix Round 2 (2026-09-02)

### Status

DONE

### Fix

- The stable older-log disclosure now derives `line` or `lines` from its next-page count in both its visible and accessibility labels. Its existing collapse label remains `Show newest 200 lines`.

### TDD evidence

The new 201-line assertion first failed with `Show 1 older lines` and `Show 1 older installer log lines`. The minimal shared noun helper made both exact singular assertions pass.

### Verification

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  '-only-testing:TenXAppTests/OnboardingInstallLogBufferTests' \
  '-only-testing:TenXAppTests/onboardingInstallStepPagedLogSnapshot()' \
  '-only-testing:TenXAppTests/onboardingInstallStepExpandedPagedLogSnapshot()'
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-task7-fix2-release -quiet build
git diff --check
```

Passed: generator made no project-file changes; focused coverage passed 11 tests; both existing log snapshots passed without asset changes; the full suite passed 1,190 tests in 27 suites; and the fresh Release build succeeded.

### Not verified

- No 201-line snapshot was added because the exact visible and accessibility strings are covered by deterministic assertions, while the existing 400-line snapshots already cover the disclosure’s two rendered control states.

### For you to test

- With exactly 201 installer log lines, confirm the control reads `Show 1 older line` and VoiceOver announces `Show 1 older installer log line`.

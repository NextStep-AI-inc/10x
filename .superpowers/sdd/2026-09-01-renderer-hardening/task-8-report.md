# Task 8 report — integrated saturation fixtures and Release gate

## Status

DONE for the original automated gate and exact-app launch/idle verification at product commit `059d578`. Follow-ups `bcd4007` and `a22e7f8` close the single oversized diff/tool-string and console preprocessing gaps. Final worker evidence is 11 passing saturation fixtures, 4 unchanged focused light/dark snapshots, and a successful unsigned optimized universal Release compile; the earlier string follow-up also passed 17 unchanged snapshots. A signed Developer ID artifact containing the follow-ups is not yet verified; final packaging and launch verification remain controller-owned.

## Implementation

- Added seven original deterministic oversized fixtures against production renderer boundaries, then expanded the suite to eleven with 100,000-character console/diff coverage, exact final-page behavior, independent 1,000-entry progress-history paging, and finite producer-side console probing.
- Asserted exact initial and one-action work counts, hidden token/decode work, detached loader execution, retained full payloads, media load/cache identity, and installer batching/tail identity. There are no elapsed-time assertions and no giant SwiftUI snapshot assets.
- Regenerated the Xcode project and removed only the previously recorded trailing space in `DiffRenderPresentation.swift`.

## TDD evidence

The first focused run contained one intentionally failing placeholder and recorded `Task 8 oversized renderer fixtures are missing` (`/tmp/tenx-task8-red.log`). After replacing it with the original production-boundary fixtures, the Debug run passed 7 tests in 1 suite in 0.108 seconds (`/tmp/tenx-task8-debug-fixtures-postreview.log`). After both single-string follow-ups, the expanded suite passed 11 tests in 1 suite in 0.105 seconds (`/tmp/tenx-console-bounded-saturation-final.log`).

## Verification

### Follow-up corrections at `bcd4007` and `a22e7f8`

- 11 saturation fixtures passed in 1 suite in 0.105 seconds. `ConsoleRenderPresentation` initially inspects/materializes at most 6,049 characters and scans at most 111 lines; console line reveal is 10 then 110, character reveal is 2,048 then 6,048, accessibility matches the bounded display, and Copy retains the exact raw output. The suite also covers bounded 100,000-character diff spans, exact terminal-page totals, and progress history at 8 then 58 entries (`/tmp/tenx-console-bounded-saturation-final.log`).
- 17 existing renderer snapshots passed unchanged after `bcd4007` across two focused runs, split 8 and 9 (`/tmp/tenx-single-string-snapshots.log`, `/tmp/tenx-single-string-additional-snapshots.log`). After `a22e7f8`, 4 focused light/dark snapshots passed unchanged (`/tmp/tenx-console-bounded-snapshots.log`).
- At `a22e7f8`, an unsigned optimized Release build compiled both `arm64` and `x86_64` (`/tmp/tenx-console-bounded-release.log`).
- Two signed Developer ID packaging attempts after `bcd4007` failed while signing Sparkle with `errSecInternalComponent` (`/tmp/tenx-single-string-release-build.log`, `/tmp/tenx-single-string-release-build-retry.log`). No signed artifact containing final `a22e7f8` or strict codesign result is claimed; that verification remains controller-owned.

### Original Task 8 verification at product commit `059d578`

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:TenXAppTests/RendererSaturationFixtureTests
```

Passed: 7 tests in 1 suite. Two consecutive generator runs produced project SHA-1 `4ba0d09933a23cc361f1936f38a68cf2a48d6803`.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/tenx-task8-release-fixtures \
  ENABLE_TESTABILITY=YES SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG \
  CODE_SIGN_IDENTITY=1B00E8025FB364E61FE0CD5C410969A587223D0C \
  -only-testing:TenXAppTests/RendererSaturationFixtureTests
```

Passed: 7 tests in 1 suite in 0.075 seconds. The compile invocation records Release `-O -whole-module-optimization`.

The unoverridden Release command first failed because the shipping module disables testability. A testability-only retry then failed while compiling existing tests that reference DEBUG-only Composer hooks. The approved optimized DEBUG/testability host next exposed a test-bundle Team-ID mismatch; an ad-hoc probe aligned the bundle but conflicted with Sparkle library validation. The successful command applies the repository's existing Developer ID identity to all test-host components. These are command-line-only test-host settings and do not change the project or standalone app.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS,arch=arm64'
```

Passed on the third unchanged normal run: 1,197 tests in 28 suites in 8.493 seconds (`/tmp/tenx-task8-full-suite-rerun-2.log`). The first two runs each had one different existing concurrency-sensitive failure under the fully parallel load. The Task 8 suite passed in both, and the first failing diff suite passed 12/12 in isolation.

After self-review added only an explicit zero-before-media-load assertion, both focused configurations passed again. A fourth normal full run repeated the existing diff gate timeout (`/tmp/tenx-task8-full-suite-final.log`). The requested serial diagnostic then ran all 1,197 tests and found one unrelated snapshot mismatch (`/tmp/tenx-task8-full-suite-serial.log`); the exact snapshot passed immediately in isolation as 1 test in 0 suites (`/tmp/tenx-task8-serial-snapshot-isolated.log`). No unrelated code or reference asset was changed.

```bash
xcodebuild clean build -project 10x.xcodeproj -scheme 10x \
  -configuration Release -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  -derivedDataPath /private/tmp/tenx-renderer-hardening-release
codesign --verify --deep --strict \
  /private/tmp/tenx-renderer-hardening-release/Build/Products/Release/10x.app
git diff --check origin/codex/fix-large-skill-freeze...HEAD
```

The clean standalone build for product commit `059d578` succeeded without testability, DEBUG, or signing overrides. Its executable is universal (`x86_64 arm64`), SHA-256 `d5527bdbb9678cfc7c03128a222a248f3fc7c7a47dc7adbafa5515c763c91f30`, and strict deep signature verification passed with Developer ID Team `345S42BKPY`. The full stacked-range whitespace check passed after the Task 8 commit with no output. This artifact predates `bcd4007` and `a22e7f8`.

## Self-review

- All 11 fixtures reach the current production policy/presentation/loader/buffer instead of duplicating pagination or decode behavior in a test-only implementation.
- Hidden diff/source rows and pre-load media assert zero work; newly visible pages assert exact cache/call counts and off-main execution.
- Full source, diff, console, JSON, media, and installer payloads remain retained after bounded presentation.
- The largest fixture holds one 5 MiB decoded buffer plus its base64 representation; the suite avoids view snapshots and passed in roughly one tenth of a second when focused.
- In the original Task 8 commit, the only production diff was the explicitly authorized removal of trailing whitespace. The later shared presentation changes belong to follow-up `bcd4007`.

## Post-review audit correction

The audit's original R1–R6 inventory is now explicitly labeled as historical pre-follow-up context. Its post-hardening resolution matrix maps R1 to Task 3, R2 to Task 5, R3 to Task 6, R4 to Task 7, R5 to Task 4, and R6 to Task 2 plus the specialized Task 3, 4, and 7 policies.

Follow-up `bcd4007` closes the diff and shared tool visible-string cases through `ProgressiveTextPresentation`: 2,048 characters initially and 4,000 more per action, with matching bounded display/accessibility text and the complete underlying Copy payload retained. Review then found that console still split the full raw output before applying that display cap. `a22e7f8` moves console prefixing into `ConsoleRenderPresentation`, limiting the initial body probe/materialization to 6,049 characters and scan to 111 lines. Diff row count/tokenization, console line count (10/+100), console characters (2,048/+4,000), and progress history (8/+50) remain independently paged. No shipping fixture hook was added.

## Pre-correction exact-app launch evidence

- Launched artifact: `/private/tmp/tenx-renderer-hardening-release/Build/Products/Release/10x.app` from product commit `059d578823cba504a139fbdff29dbb08973c68fe`. This launch predates `bcd4007` and `a22e7f8` and does not verify their shared string or bounded console-producer presentations.
- Process: PID 29413 survived, and its executable path matched the exact artifact whose SHA-256 is `d5527bdbb9678cfc7c03128a222a248f3fc7c7a47dc7adbafa5515c763c91f30`.
- Visible surfaces: Computer Use confirmed the rendered update prompt, then after **Not now** a rendered workspace window and a persisted session with expanded and collapsed tool blocks.
- Before session load: five two-second samples were each 0.0% CPU; RSS was approximately 106,240–106,320 KB.
- After persisted tool-history load: five two-second samples were each 0.0% CPU; RSS was approximately 147,856–148,320 KB.
- No persistent hot main thread appeared, so the conditional one-second stack sample was not triggered.

## Not verified

- A signed Developer ID artifact containing final `a22e7f8` was not produced. Two intermediate packaging attempts after `bcd4007` failed while signing Sparkle with `errSecInternalComponent`; strict codesign verification and an exact-app launch for the corrected product remain controller-owned.
- The persisted session did not contain the original oversized superpowers skill block, so its exact appearance, selectable raw text, and concurrent streaming interaction were not manually reproduced in the standalone process.
- No main-thread stack sample was captured because all ten CPU samples remained at 0.0%; there was no persistent hot interval to sample.
- Artificial oversized fixtures were not routed into the shipping app process, per the preflight ruling against adding a production fixture mode. The original seven fixtures passed in the optimized test host; the four `bcd4007` additions passed in Debug while the corrected production module separately compiled in the optimized universal Release build.

## For you to test

- Complete a signed Developer ID build from `a22e7f8`, verify it with strict deep codesign, and launch that exact artifact. If the original oversized skill payload becomes available again, confirm its raw monospace/selectable appearance and interactivity during live streaming.

## Concerns

- The full suite has existing load-sensitive async and snapshot tests: normal attempts included one clean run and repeated nondeterministic failures, while the serial diagnostic found a snapshot mismatch that passed immediately alone. None implicated the Task 8 suite, and none was expanded into Task 8 scope.
- The remaining follow-up concern is packaging evidence, not the former display/preprocessing gap: both intermediate signed attempts hit `errSecInternalComponent`, while the final `a22e7f8` unsigned optimized universal Release compile succeeded.

# Task 8 report — integrated saturation fixtures and Release gate

## Status

DONE for the automated gate and exact-app launch/idle verification. The original oversized skill block was unavailable in persisted content, so that exact manual shape remains fixture-covered rather than reproduced in the standalone process.

## Implementation

- Added seven deterministic oversized fixtures against production renderer boundaries: a 10,000-line/10-file diff, 10,000 console lines, 1,000 collection entries, 5,000 JSON children plus a 100,000-character scalar, 5,000 mixed document units, 5 MiB inline media, and 10,000 installer lines.
- Asserted exact initial and one-action work counts, hidden token/decode work, detached loader execution, retained full payloads, media load/cache identity, and installer batching/tail identity. There are no elapsed-time assertions and no giant SwiftUI snapshot assets.
- Regenerated the Xcode project and removed only the previously recorded trailing space in `DiffRenderPresentation.swift`.

## TDD evidence

The first focused run contained one intentionally failing placeholder and recorded `Task 8 oversized renderer fixtures are missing` (`/tmp/tenx-task8-red.log`). After replacing it with the production-boundary fixtures, the final Debug run passed 7 tests in 1 suite in 0.108 seconds (`/tmp/tenx-task8-debug-fixtures-postreview.log`).

## Verification

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

The clean standalone build succeeded without testability, DEBUG, or signing overrides. Its executable is universal (`x86_64 arm64`), SHA-256 `d5527bdbb9678cfc7c03128a222a248f3fc7c7a47dc7adbafa5515c763c91f30`, and strict deep signature verification passed with Developer ID Team `345S42BKPY`. The full stacked-range whitespace check passed after the Task 8 commit with no output.

## Self-review

- Every fixture reaches the current production policy/loader/buffer instead of duplicating pagination or decode behavior in a test-only implementation.
- Hidden diff/source rows and pre-load media assert zero work; newly visible pages assert exact cache/call counts and off-main execution.
- Full source, diff, console, JSON, media, and installer payloads remain retained after bounded presentation.
- The largest fixture holds one 5 MiB decoded buffer plus its base64 representation; the suite avoids view snapshots and passed in roughly one tenth of a second when focused.
- The only production diff is the explicitly authorized removal of trailing whitespace.

## Post-review audit correction

The audit's original R1–R6 inventory is now explicitly labeled as historical pre-follow-up context. Its post-hardening resolution matrix maps R1 to Task 3, R2 to Task 5, R3 to Task 6, R4 to Task 7, R5 to Task 4, and R6 to Task 2 plus the specialized Task 3, 4, and 7 policies.

The matrix does not mark every visible-string case closed. The diff fixture proves changed-row and tokenization ceilings, but a single oversized visible diff line is not yet display-character-paged. The console fixture proves line-count paging, but a single oversized visible console string likewise has no display-character ceiling. Those production gaps remain open for a separate follow-up; Task 8 added no shipping hook or broader product change for them.

## Exact-app launch evidence

- Launched artifact: `/private/tmp/tenx-renderer-hardening-release/Build/Products/Release/10x.app` from product commit `059d578823cba504a139fbdff29dbb08973c68fe`.
- Process: PID 29413 survived, and its executable path matched the exact artifact whose SHA-256 is `d5527bdbb9678cfc7c03128a222a248f3fc7c7a47dc7adbafa5515c763c91f30`.
- Visible surfaces: Computer Use confirmed the rendered update prompt, then after **Not now** a rendered workspace window and a persisted session with expanded and collapsed tool blocks.
- Before session load: five two-second samples were each 0.0% CPU; RSS was approximately 106,240–106,320 KB.
- After persisted tool-history load: five two-second samples were each 0.0% CPU; RSS was approximately 147,856–148,320 KB.
- No persistent hot main thread appeared, so the conditional one-second stack sample was not triggered.

## Not verified

- The persisted session did not contain the original oversized superpowers skill block, so its exact appearance, selectable raw text, and concurrent streaming interaction were not manually reproduced in the standalone process.
- No main-thread stack sample was captured because all ten CPU samples remained at 0.0%; there was no persistent hot interval to sample.
- Artificial oversized fixtures were not routed into the shipping app process, per the preflight ruling against adding a production fixture mode. Their exact work ceilings are covered in the optimized fixture host.

## For you to test

- If the original oversized skill payload becomes available again, confirm its raw monospace/selectable appearance and interactivity during live streaming in the exact packaged app. No further launch check is required for the persisted tool-history surface exercised here.

## Concerns

- The full suite has existing load-sensitive async and snapshot tests: normal attempts included one clean run and repeated nondeterministic failures, while the serial diagnostic found a snapshot mismatch that passed immediately alone. None implicated the Task 8 suite, and none was expanded into Task 8 scope.
- A single oversized visible diff line and a single oversized visible console string remain outside the current character-paging safeguards. The current fixtures cover record counts, hidden work, tokenization ceilings, and retained payloads, not those two display-string cases.

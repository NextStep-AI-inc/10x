# Task 8 report — integrated saturation fixtures and Release gate

## Status

DONE for the automated gate. Exact-app visible launch and CPU/main-thread sampling remain pending the controller.

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

## Not verified

- The exact standalone app was not launched, and CPU/main-thread samples were not captured. Those checks belong to the controller under `launching-local-builds`.
- Artificial oversized fixtures were not routed into the shipping app process, per the preflight ruling against adding a production fixture mode.

## For you to test

- Launch the exact app at `/private/tmp/tenx-renderer-hardening-release/Build/Products/Release/10x.app`, confirm it is the visible process, exercise persisted oversized content, and capture idle/streaming CPU plus a main-thread sample.

## Concerns

- The full suite has existing load-sensitive async and snapshot tests: normal attempts included one clean run and repeated nondeterministic failures, while the serial diagnostic found a snapshot mismatch that passed immediately alone. None implicated the Task 8 suite, and none was expanded into Task 8 scope.

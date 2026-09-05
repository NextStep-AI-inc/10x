# Task 5 report: integration, measurement, and review readiness

Status: DONE (live drive of a real session BLOCKED by environment; see below)

## Integration

- Base synced: origin/main `7e04b9e` (PR #22 merged 2026-09-05 00:31Z) merged
  as `d86e970` with no conflicts; `project.pbxproj` needed no regeneration
  because no App or Tests files were added.
- Branch order: `0d98ddc` plan, `43f9123` Task 1, `0fa2154` Task 2, `d86e970`
  merge, `41bb850` Task 3, `f97ac8b` Task 4, then this task's docs/probes commit.

## Verification at `f97ac8b`

- `xcodebuild test -project 10x.xcodeproj -scheme 10x -configuration Debug
  -destination 'platform=macOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
  CODE_SIGNING_ALLOWED=NO` (`full-app-suite-v1.log`): **1,322 Swift Testing
  tests in 34 suites passed** after 13.6 s, plus 4 XCTest checks; 0 failures;
  `** TEST SUCCEEDED **`.
- `swift test --package-path OmpKit` (`ompkit-task4-v2.log`): **212 tests
  passed**, 3 environment-dependent skips.
- Release build: `scripts/performance/audit.py` built Release
  (`perf-final/build.log`, `** BUILD SUCCEEDED **`) and ran both probes
  (`perf-final/app.log`, `perf-final/transport.log`). Comparison against the
  current-main baseline is in `docs/performance/2026-09-04-resource-usage.md`.
- Live launch (`live-launch.log`): isolated Release copy under bundle id
  `com.nextstep.tenx.perf-audit`, pid alive after 12 s, one on-screen window via
  `CGWindowListCopyWindowInfo`, clean exit.

## Blocked

Driving a real session in the Release UI (streaming, session switches beyond
the retention budget, large tool output) could not be observed: `screencapture`
is denied Screen Recording for agent processes and no computer-use grant was
available with the user away. The retention and backlog behaviors are covered
by the deterministic tests above; the human pass should cover the flows listed
in the PR body.

## Bench hygiene

Test DerivedData and the Release probe build live in the session scratch
directory and are deleted at the end of the session; the app copy used for the
live launch was removed immediately. No dev servers or app instances were left
running.

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

## Review round (one pass, three lenses, at `cf21b21`)

Reviewers: concurrency/lifecycle, correctness/data-loss, test-coverage. Accepted
findings and their fixes, each with a regression test that failed first:

- Correctness BLOCKER: a session listing run from a cancelled task cached
  every unscanned file as "not a session" until restart (cancellable header
  split from Task 2 plus the metadata cache). Fixed in `77037da`; RED
  `listingFromACancelledTaskDoesNotHideTheSessionAfterwards` then GREEN.
- Correctness SHOULD_FIX: a transcript deleted and recreated within one
  debounce kept its watcher on the dead inode (deferred topology refresh from
  Task 1). Fixed in `77037da`; RED `watcherFollowsAFileDeletedAndRecreatedWithinOneDebounce`
  (`secondSignal` false with the stale-descriptor drop disabled) then GREEN.
- Concurrency BLOCKER: a request issued while `poison()` was mid-await threw
  `notStarted` instead of the backlog diagnostic, making
  `stdoutBacklogOverflowStopsTheSessionWithADiagnostic` fail about one run in
  three. Fixed in `b4057a3`.
- Concurrency SHOULD_FIX: an exit noticed before a reopen could be reported
  against the replacement controller. Fixed in `ab72913` with a manager-level
  guard and a seam-driven race test.
- Correctness SHOULD_FIX: the spill cap equalled the maximum reassembled
  frame, so a legal 64 MiB frame behind any queued record failed the session.
  Cap is now 65 MiB (`53f1f9d`); a failed queue also releases its spill file.
- Coverage BLOCKER: `park()`'s cancellation guard had no test that reached it.
  `consumerCancelledBetweenTheCheckAndParkStillReturns` cancels inside the
  window through a seam; with the guard removed the test hangs (alarm-killed
  at 90 s, `red-park.log`), with it it passes (`53f1f9d`).
- Coverage BLOCKER: no test exercised the eligibility guards or the
  coordinator seam. `95bb882` adds unit coverage for every runtime state and
  the draft/attachment/initial-submission guards, two navigation tests (a
  drafted session survives an over-budget open; revisiting moves a session
  behind the others), and a managed-turn test for `hasPendingWork`.
- Coverage SHOULD_FIX: sleeps racing the 50 ms reconciliation debounce, a
  dead 800 ms sleep and a 2 s ceiling in the retention test, and semaphores
  blocking cooperative threads in the timeline-loader fixture. All replaced
  with observable waits (`95bb882`); the loader's reader seam is now async.
- Concurrency NIT: warm clients now go before idle runtimes under memory
  pressure (`a91aca6`).

Declined or deferred, recorded in the PR notes: `streamingBehavior` and the
transcript search request are per-session UI state not preserved across a
reclaim; coarse-mtime volumes could serve a same-size in-place rewrite from the
history cache; `ToolPresentation.update`'s test-only observer parameter from
Task 2 is left as is; refill and compaction run under the queue lock
(`ponytail:` comment names the ceiling).

Evidence: `swift test --package-path OmpKit` 217 passed (3 skips);
changed app tests 14/14 passed (`app-review-fixes-v2.log`, `-v3.log`); full
app suite re-run recorded below.

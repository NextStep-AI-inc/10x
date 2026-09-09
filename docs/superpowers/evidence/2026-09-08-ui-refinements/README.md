# Active-session UI refinement evidence

Status: **DONE_WITH_CONCERNS**. The density and appearance corrections passed native acceptance. [PR #46](https://github.com/NextStep-AI-inc/10x/pull/46) remains draft because the full suite has unresolved failures.

[Latest native gallery](progress-gallery.html) · [Verification record](density-verification.json) · [Test results](density-test-results.txt) · [Implementation plan](../../plans/2026-09-08-active-session-ui-refinements.md)

## Latest requested corrections

- [x] Steer and Follow up use two compact single-line choices: 164×56 points, previously 272×104. Pointer and keyboard selection, Escape and composer focus return passed.
- [x] Usage rings occupy their own strip below the composer with an 8-point layout gap. The native model panel and rings fit at normal and minimum sizes in both appearances. A ring opened its usage details and its visible Close button dismissed them.
- [x] Known-mode bubbles use the same semantic fill and foreground as ordinary user messages: black with white text in light mode, white with black text in dark mode. Symbols and accent edges remain. Both delivered modes were inspected in both themes; the queued state was also checked in dark mode.

The seven screenshots in the gallery come from Release source `a78f90d610c6a6dcfbd3eb099838ecd1383de46e`, branch `codex/active-session-ui-refinements`. The [build manifest](native-density-build.json) records the executable SHA and isolated profile. Native windows were 1180×760 and 760×592; the latter includes the title bar above the app's minimum 760×560 content size.

macOS appearance was temporarily switched from Auto to Dark for this check, then restored to **Auto**. The isolated app remains running with an empty draft. The fixture responses were stopped/completed through the demonstrated flow. No external model work is represented by this local RPC session.

## Verification

- Swift 6 compilation/typechecking, Release build, strict ad-hoc signature verification, pinned project generation and diff checks passed.
- Final full suite: **1,605 executed, 1,602 passed, 3 failed**. All changed-layout snapshots and submission-mode checks passed.
- The two running/error snapshot actuals exactly match the hashes recorded against main. Their references remain unchanged.
- The existing provider handshake deadline check exceeded its one-second assertion under full-suite load (1.236 seconds). Its isolated rerun passed in 0.053 seconds. This remains a full-suite verification concern.
- The earlier stale-reconciliation, repeated-queue and opening-task checks passed in this final full run. An initial run also had transient timing failures while seven changed dock references required review.
- All seven dock references were inspected before acceptance, including minimum windows, account stacks, dark mode and an expanded rail. [Snapshot review](density-snapshot-review.json).
- The updated gallery loaded all seven images without horizontal overflow; opening a full-size image and Escape/focus return passed. [Gallery check](density-gallery-verification.json).

## Remaining gaps

Usage details did **not** dismiss with Escape during native QA, and a model panel could open behind them. The visible Close button worked. Provider overlay coordination is recorded as follow-up work; this correction changes only three Swift presentation files.

The acceptance flow uses a local RPC fixture. Live provider work, image-only mode styling, VoiceOver and the OS Reduce Motion setting were not exercised. The expanded rail was covered by snapshots rather than native interaction in this revision. OMP still supplies no originating queue ID, so identical overlapping messages with conflicting modes remain standard after delivery; older unannotated history is also unchanged.

The [first refinement report](first-refinement-report.md) and [earlier five-adjustment gallery](progress-gallery-first-refinement.html) retain the previous source and acceptance evidence, including diff actions, warnings, focus behavior and mode persistence after relaunch. The earlier CJK acceptance gap remains separate. No merge or deployment occurred.

## For Tanner to test

Use the [latest gallery](progress-gallery.html) to compare compact choices, ring spacing and both message themes. The runnable build is `/tmp/10x-ui-density-build/10x-ui-density.app`, from source `a78f90d`. The isolated **UI refinement acceptance** session is available for hands-on inspection.

# Active-session recovery snapshot baseline verification

## Outcome

The six activity snapshot failures reproduce at PR base `e60234a`. Every base actual PNG is byte-identical to the corresponding active-branch actual PNG. Every base reference is also byte-identical to the active-branch reference. The Task 2 recovery diff did not cause these snapshot mismatches.

## Baseline run

Worktree: detached `e60234a` at `/tmp/10x-session-recovery-baseline`

Derived data: `/tmp/10x-session-recovery-baseline-tests`

The valid function-selector run executed 6 Swift Testing tests and reported the same 6 snapshot mismatches:

- `structuredDiffSnapshot()` → `activity-structured-diff.png`
- `activityDisclosureSnapshot()` → `activity-running-error.png`
- `subagentActivitySnapshot()` → `activity-subagent.png`
- `activityDisclosureSnapshotDark()` → `activity-running-error-dark.png`
- `activityStructuredDiffDarkSnapshot()` → `activity-structured-diff-dark.png`
- `subagentActivitySnapshotDark()` → `activity-subagent-dark.png`

The first attempted run used suite-qualified selectors and executed 0 tests. It is retained as diagnostic evidence and is not counted as verification. The corrected function-only selectors produced the nonzero run above.

## Exact comparisons

`cmp` reported `IDENTICAL` for all six base-vs-active actual pairs and all six base-vs-active reference pairs.

Actual PNG SHA-256 values, identical on base and active:

- `activity-running-error-dark.actual.png`: `648841ad4d2e5018fe2af6d6e23df86e5452c9fe8bb39cef0e34571a42158134`
- `activity-running-error.actual.png`: `82a00ca2a562aa7b26f2d6669553599e038a021340ab8a96a0999a2bb7c0fa45`
- `activity-structured-diff-dark.actual.png`: `84c7a70a4ea19966293226cd981b7ecd53a26c812e62c970b4d781d546fb4c2c`
- `activity-structured-diff.actual.png`: `c4b16d8f7041bb08f5f63d442facf6e9bd1b2e76234e20383c758e028b2c844e`
- `activity-subagent-dark.actual.png`: `01b98fbba91a96383ed7d098c3a624620b0141be7f660b928931550d69df8917`
- `activity-subagent.actual.png`: `f3359490ef0241ce25048823abb1b5408750443bf33400c1ef2f769038563bd6`

## Preserved evidence

- `base-actual/`: six actual PNGs rendered at `e60234a`
- `base-reference/`: six reference PNGs from `e60234a`
- `active-actual/`: six actual PNGs from the Task 2 full-suite run
- `active-reference/`: six active-branch reference PNGs
- `xcodebuild-base-six-snapshots-function-selectors.log`: valid 6-test baseline run
- `xcodebuild-base-six-snapshots.log`: invalid 0-test suite-qualified attempt
- `xcodebuild-active-full-suite.log`: active-branch 1380-test run

Baseline xcresult: `/tmp/10x-session-recovery-baseline-tests/Logs/Test/Test-10x-2026.09.07_20-32-14--0700.xcresult`

## Scope

No snapshots were promoted. No source, reference, or active-worktree files were modified. The unrelated snapshot baseline issue remains for parent attribution.

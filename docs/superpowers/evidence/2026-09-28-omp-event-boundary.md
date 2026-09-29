# Event boundary execution evidence

Status: IN PROGRESS. Branch `codex/omp-event-boundary`, draft PR #50.
Implementation checkout: `/Users/tannerpham/CS Projects/.worktrees/10x-omp-event-boundary-design`.
Models: authenticated Cursor CLI `composer-2.5-fast` implements; `grok-4.7-xhigh-fast` reviews. Main session coordinates and verifies native UI.

## Completed code and checks

| Task | Commit | Evidence |
| --- | --- | --- |
| 1 classifier | `e02c9e4` | Runtime RED: 1 test / 4 issues; GREEN and independent review: 7 tests pass. Grok approved. |
| 2 live/history | `5849bc1`, corrected by `040f0a6` | Fixed omission count, live/history duplication, identity promotion, and aborted tools. 26 focused implementation tests pass; independent re-review: 10 pass including 2 suite-qualified controller tests. Grok approved. |
| 3 setting/card | `8d4487e`, copy fix `0825eaa` | 11 scoped tests pass independently; copy-fix RED 1 test / 3 issues, GREEN and re-review 2 pass. Grok approved. No runtime RED captured for original Task 3. |

Task 2 original RED was a build failure with zero executed tests; subsequent fix rounds captured runtime failures. Do not describe it as a passing TDD gate.

## Built app and current GUI checkpoint

Release built successfully from `0825eaa` using:

```sh
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/10x-event-boundary-release PRODUCT_BUNDLE_IDENTIFIER=com.nextstep.tenx.eventboundary CODE_SIGNING_ALLOWED=NO
```

App: `/tmp/10x-event-boundary-release/Build/Products/Release/10x.app`.
Bundle ID checked: `com.nextstep.tenx.eventboundary`.
Final checkpoint build includes the wording fix. Log: `task-3-final-release-build.log`, BUILD SUCCEEDED.

Native CUA observation after Tanner made the window visible: 10x General shows the approved Show agent guidance setting and supporting text; initial state off, switches on and back off. Real screenshot inspected. No clipping seen. The test project `/tmp/10x-event-boundary-qa` ran two real Composer 2.5 Fast turns through OMP. Advisor notes (fixture and an actual advisor correction) and hidden custom guidance appeared as compact cards with the switch on. With it off, guidance disappeared, the referenced file remained without its injected body, and both OK-TURN replies remained. Toggling from a scrolled-up transcript preserved the earlier position and Jump to latest control. Real running-turn and completed-turn screenshots were inspected. After quit/rebuild/relaunch, the session restored both advisor cards, hidden custom guidance, referenced file, and conversation. The on preference persisted; switching off again removed guidance and retained the referenced file. Checkpoint 1 passed; Task 4 may begin.

The disposable project contains a project-local OMP extension emitting an advisor on first turn and hidden custom guidance on second. Static discovery and two real UI turns verified. Fixture and detailed runbook are in the local scratch directory.

## Known limitations and pending triage

- Full suite on an intermediate Task 2 tree: 1616 tests, 194 issues. Cause not established; do not call these all pre-existing.
- Only `richAssistantMessageSnapshot` and `fullTranscriptCompactWindowSnapshot` failures were reproduced on both Task 1 base and Task 2 head.
- `continuousSettingsSnapshot()` fails its reference comparison. Actual frame shows OMP General, not the new 10x General row; no reference was promoted and no baseline attribution is claimed.
- Task 2 review NIT: message_update real-ID promotion leaves inflightGuidanceID on removed synthetic ID (`TranscriptReducer.swift`, around line 832 at `040f0a6`). Final review must triage reconciliation before message_end.
- No merge or deployment authorized. Main checkout remains untouched.

## Local detailed evidence

Ignored scratch: `.superpowers/sdd/2026-09-28-omp-event-boundary/`.
Reports: `task-1-review.md`, `task-2-rereview.md`, `task-3-review.md`, `task-3-rereview.md`.
Logs: task-prefixed RED/GREEN/review logs and `task-3-release-build.log`; status ledger `progress.md`.
These local logs do not travel with git; this document preserves their measured outcomes and outstanding work.

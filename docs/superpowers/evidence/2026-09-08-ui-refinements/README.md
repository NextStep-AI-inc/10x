# Active-session UI refinement evidence

Status: **IN_PROGRESS**. This report tracks Tanner's five requested adjustments after reviewing the combined audit gallery. [Draft PR #46](https://github.com/NextStep-AI-inc/10x/pull/46) is based on `codex/active-session-audit-integration`; no GitHub merge or deployment has occurred.

[Implementation plan](../../plans/2026-09-08-active-session-ui-refinements.md) · [Recorded checks](verification.json)

## Current verification

- Diff behavior checks passed **25 tests in two suites**, including exact path identity, typed totals, header text, progressive rendering and context reveal. Source `3257fe5`.
- The two old structured-diff screenshot fixtures were found to render collapsed cards. Both fixtures now explicitly expand their cards. The expanded light/dark captures were visually reviewed, saved in [diff-snapshots](diff-snapshots), accepted, and passed after rebuilding the reference resources.
- Five popup placement tests first failed because the new placement type was absent, as expected. All five now pass. The full source compiled, and 68 selected behavior checks passed across placement, composer routing/presentation/activity, and context. Source `632d6bf`.
- The [native RPC fixture](native-fixture.py) passed handshake/start/queue/finish/history/shutdown and pipelined-command smoke checks. It simulates provider events locally and records received commands. It performs no model work. It writes only neutral files and session records in the isolated QA profile.

## Native acceptance checklist

- [ ] Composer activity animates; the top status remains readable; Stop and pending-input controls work.
- [ ] One and two warnings use a fitting flyout without changing composer height.
- [ ] Model, context, warnings, send action and project panels fit normal/minimum windows and return focus appropriately.
- [ ] Follow-up and steer receipts look distinct; known unambiguous modes survive delivery and reopening.
- [ ] Expanded single- and multi-file diffs have one colored top summary, aligned actions, working wrapping/copy and file navigation.
- [ ] The progress gallery contains the new native evidence and explanations.

## Known limits

OMP does not persist a queue mode or originating request ID with a user message. Identical pending payloads with conflicting send modes are ambiguous; the UI must not invent a mode for their delivered history entries. Imported or older messages without recorded mode remain standard.

The earlier audit's live CJK gate and unrelated running/error snapshot mismatches remain outside this refinement. The structured-diff reference images are now directly affected by this request and will be reviewed here. Native acceptance has not yet run for this refinement.

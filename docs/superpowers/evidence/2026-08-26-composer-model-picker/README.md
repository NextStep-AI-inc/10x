# Composer Model Picker — Verification Evidence

**Branch:** `tannerpham/model-picker-improvement-ce4522`
**Head:** `f53826c`
**Date:** 2026-08-26
**Plan:** `docs/superpowers/plans/2026-08-26-composer-model-picker.md`
**Spec:** `docs/superpowers/specs/2026-08-26-composer-model-picker-design.md`

## Verified

**Test suite.** 510/510 passing on a clean full run.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
```

Counts by task: 483 at branch point → 490 (Task 1, +7) → 496 (Task 2, +6) → 499
(Task 3, +3) → 505 (Task 4, +6) → 512 (Task 5, +7) → 514 (Task 6, +2) → 517
(Task 7, +3 snapshots). Four tests in this repo flake under full parallel load
and pass in isolation: `continuousSettingsSnapshot`,
`cancellationReapsADescendantSpawnedByTheTerminationHandler`,
`backgroundSessionActivityRemainsTrackedUntilItsTurnFinishes`,
`mutationLockDetachesBeforeCloseAndBlocksReentrantActions`. None touch this
branch's code. This is a known pre-existing pattern, not a regression.

**Release build.** Succeeds.

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' build
```

**Launch.** The Release `.app` was launched directly from its binary (not via
`open`, so it would not activate the unrelated instance already running from
another worktree). The process survived past startup with no crash and no error
output, confirming the rewired composer does not fault on first render.

**Rendered panel.** Reference images in this directory, recorded from the real
view hierarchy and inspected:

| Image | Shows |
| --- | --- |
| `model-picker-default.png` | Search field, RECENT section with mono provider tag, two provider sections rendering the same model name distinguishably, effort chips with `auto` selected, Fast mode row flush left with the switch at the right edge, stepped trigger silhouette |
| `model-picker-searching.png` | RECENT correctly hidden while filtering; provider headers retained so duplicate names stay distinguishable |
| `model-picker-empty.png` | `No models available. Connect a provider in Settings.` on one line, no truncation, panel height correct |
| `composer-footer-fast-present.png` | Footer with one chip where three controls used to be |
| `composer-footer-fast-absent.png` | Same, with Fast mode absent for a model whose family does not support it |

**Duplicate-model handling.** `model-picker-default.png` renders Claude Opus 4.8
three times, under RECENT (tagged `anthropic`), ANTHROPIC, and OPENROUTER. This
was the original complaint and is confirmed fixed in a rendered frame.

## Not verified

Screen Recording is not granted to the automation process, and driving the UI
needs per-application approval that was not available in this session. Every
item below is code-verified but not exercised live, and each needs a human at
the keyboard:

- Escape and outside-click dismissal, in a new session and in an active session.
- **Specifically suspect:** in `ActiveSessionView`, the dismiss scrim sits
  beneath a `zIndex(1)` VStack containing the scrollable transcript. An outside
  click that lands on the transcript may scroll it instead of dismissing the
  panel. This structure mirrors `NewSessionView`, so if it is wrong it is wrong
  in both.
- Arrow-key navigation and Return-to-commit while the search field holds focus.
  A focused `TextField` consumes arrows for caret movement; the code intercepts
  them via `onKeyPress`, but that interception has not been exercised.
- Opening the model flyout closing the project flyout, and the reverse.
- Committing a model leaving the panel open with the effort row re-adapting
  in place.
- Panel z-order over the transcript in an active session. No snapshot renders
  the flyout open inside real composer chrome; this is a code-reading conclusion.
- Switching to a `requiresEffort` model while on `auto` landing on a real effort,
  and the session spawning without an invalid thinking value. Unit-tested at the
  model layer, not observed against a live provider.
- Behavior against a real full-size catalog. All rendered evidence uses fixtures.

## Known gaps carried

Recorded in `.superpowers/sdd/2026-08-26-composer-model-picker/progress.md`:

- `flatIndex`, `handleKey`, and the `.task` highlight-seeding in
  `ModelPickerFlyout.swift` have no unit tests. Snapshots render static frames
  and do not exercise them.
- No test asserts that a model switch issues no `setThinkingLevel` RPC and no
  `setDefaultThinkingLevel` config write. Correct by inspection, unguarded.
- `ModelPickerFlyout.swift` keeps a raw `Color.white` for the effort chip's
  selected text. Ruled to stay: `canvasHex` is a surface token, not a
  foreground-on-dark token, and `ComposerView`'s send button sets the precedent.
- `isolatedRecents` is duplicated across two test files because `private` is
  file-scoped in Swift.

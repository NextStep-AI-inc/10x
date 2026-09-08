# Composer Model Picker — Verification Evidence

**Branch:** `tannerpham/model-picker-improvement-ce4522`
**Head:** `7ad9703`
**Date:** 2026-08-26
**Plan:** `docs/superpowers/plans/2026-08-26-composer-model-picker.md`
**Spec:** `docs/superpowers/specs/2026-08-26-composer-model-picker-design.md`

## Verified

**Test suite.** 518/518 passing on a clean full run.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
```

Counts by task: 476 at branch point → 483 (Task 1, +7) → 489 (Task 2, +6) → 492
(Task 3, +3) → 498 (Task 4, +6) → 505 (Task 5, +7) → 507 (Task 6, +2) → 510
(Task 7, +3 snapshots) → 518 (whole-branch review fixes, +8). Four tests in this
repo flake under full parallel load
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
| `composer-with-model-flyout.png` | The panel open inside real composer chrome. The composer's border runs to the panel edges and stops, with no hairline crossing the list. This image is falsified: reverting the border fix makes the test fail. |

**Duplicate-model handling.** `model-picker-default.png` renders Claude Opus 4.8
three times, under RECENT (tagged `anthropic`), ANTHROPIC, and OPENROUTER. This
was the original complaint and is confirmed fixed in a rendered frame.

## Whole-branch review

A final review of all ten commits returned five Important findings, no Critical.
All five are fixed, plus four minors, in commits `eeef928`, `019683c`, `afae04b`,
`091633b`, `7ad9703`:

1. The composer's border stroke painted across the open flyout. The border moved
   into the card's background layer so it composites behind content. The five
   pre-existing reference images stayed byte-identical, confirming the change is
   pixel-neutral where no flyout is open.
2. In an active session the reconciled thinking level was invented locally and
   never sent. The spec's claim that `applyLiveSelection` corrects it was false:
   the echo is dropped while `isMutating` is true, and it never carried
   `thinkingLevel` anyway. The level is now sent explicitly, only when it
   actually changed. The spec was corrected.
3. `Loading models…` was unreachable, gated out by the exact predicate that
   disabled the trigger. The gate is gone.
4. Outside-click dismissal did not work in an active session, because the scrim
   sat beneath a hit-testable transcript. The scrim now overlays the transcript
   band specifically, leaving the composer interactive.
5. Arrow keys could walk the highlight out of the viewport, after which Return
   committed an unseen model. The list now scrolls the highlight into view.

A follow-up pass corrected finding 2's rollback: when `setModel` succeeds and
`setThinkingLevel` then fails, reverting the model would have made the chip name
a model the runtime was not running. Each RPC now rolls back only what it
invalidated.

## Accepted side effect

The active-session dismiss scrim covers the whole header/transcript band, so it
also sits in front of `RuntimeRecoveryView`'s Restart, Open log, and Dismiss
buttons. With the flyout open during a stopped runtime those are unreachable
until it closes. Escape and click-outside both still close it, so this is not a
trap, and it is consistent with treating the flyout as modal over the background.
Accepted rather than fixed.

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
- `proxy.scrollTo` actually scrolling the highlight into view. `flatIndex` and
  the highlight-index arithmetic are unit-tested, but no automated test can
  exercise `ScrollViewReader`'s scrolling itself, and no snapshot captures a
  scrolled-past-the-fold state.
- Whether SwiftUI's `.onTapGesture` reliably beats `NSScrollView`'s responder
  chain for the dismiss scrim on macOS. Reasoned correct from the view
  hierarchy, not observed.
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

This section is the durable record of them:

- `ModelPickerFlyout.swift` keeps a raw `Color.white` for the effort chip's
  selected text. Ruled to stay: `canvasHex` is a surface token, not a
  foreground-on-dark token, and `ComposerView`'s send button sets the precedent.
- `isolatedRecents` is duplicated across two test files because `private` is
  file-scoped in Swift.
- `model-picker-fast-only.png` was inspected but not falsified, unlike
  `composer-with-model-flyout.png`.
- `ComposerControlsPresentation.parseRoleDefault` has no call sites. It predates
  this branch and is deliberately out of scope here.

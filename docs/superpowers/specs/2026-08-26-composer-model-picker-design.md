# Composer Model Picker

**Status:** Draft, pending review
**Date:** 2026-08-26
**Parent spec:** `docs/superpowers/specs/2026-08-24-10x-omp-macos-gui-design.md`

## Goal

Make the composer's model selection usable against a full OMP catalog. Today the
picker is a flat native `Menu` over every model from every authenticated
provider, rendering only `item.name`. Three problems follow from that:

1. No search and no structure, so finding a model is a linear scan.
2. Models offered by more than one vendor (Claude Opus via `anthropic` and via
   `cursor`) render as identical rows with nothing to tell them apart.
3. Model, thinking level, and Fast mode are three separate chips, even though
   thinking options are derived from the model you just picked.

The replacement is one flyout that covers all three settings, searchable by model
name and by provider, grouped by provider.

## Scope

In scope: the composer footer controls in both modes (`newSession`,
`activeSession`) and the pure presentation functions behind them.

Mostly a view-layer replacement plus additive presentation logic.
`ComposerControlsModel`'s selection semantics stay as they are, with one
necessary addition: `selectModel` reconciles `thinkingLevel` against the incoming
model, described under Effort selection. Everything else about it is untouched
(`newSession` persists a default via `ComposerDefaultPersisting`; `activeSession`
calls `setModel` with optimistic rollback).

## Design direction

The panel reuses the composer's existing flyout language rather than inventing a
new one. `ChooseProjectShelf` already establishes the pattern: a stepped
two-rectangle silhouette, white fill, single near-black hairline, no corner
radius, no shadow, panel growing upward from a trigger that stays in place. The
model flyout is constructed the same way, so the two are indistinguishable in
build.

```text
┌──────────────────────────────────────┐
│ ⌕ Search models                      │  filters on name + provider
├──────────────────────────────────────┤
│ RECENT                               │  omitted when empty or while searching
│ │ Claude Opus 4.5         anthropic  │  cyan rail marks current selection
│   GPT-5.2 Codex        openai-codex  │
├──────────────────────────────────────┤
│ ANTHROPIC                            │  provider section headers, mono caps
│   Claude Opus 4.5                    │
│   Claude Sonnet 4.5                  │
│ CURSOR                               │
│   Claude Opus 4.5                    │
├──────────────────────────────────────┤
│ EFFORT   auto  low  medium  high     │  hidden when the model has no efforts
│ Fast mode                       [ ●] │  hidden when the family has no tier
├──────────────────────────────────────┤
│ Claude Opus 4.5                      │  trigger, stays in the footer
└──────────────────────────────────────┘
```

Section headers are the fix for duplicate model names: the vendor is the header,
so two rows reading "Claude Opus 4.5" are unambiguous. Recent rows sit outside
their section, so they carry a mono provider tag instead.

Colors and type come from the existing tokens only: `TenXPalette.canvasHex`,
`nearBlackHex`, `cyanHex`, `mutedTextHex`, `separatorHex`, `hoverNeutralHex`, and
`TenXTypography.body` / `.mono`. No new tokens, no shadow, no radius.

## Search

One field, focused when the panel opens. The query matches case-insensitively
against both the model's display name and its provider id, so "opus" narrows to
Claude models across every vendor and "cursor" lists everything Cursor offers.
Matching is a plain substring test; no fuzzy ranking.

While the query is non-empty the recents section is hidden and the list shows
only matching rows, with provider headers retained so duplicates stay
distinguishable. Sections with no matches are dropped entirely.

## Effort selection

Effort options are already per-model on the wire: `ComposerModelInfo` carries
`thinkingEfforts` and `requiresEffort`, parsed from the catalog's `thinking`
object. The row renders those efforts as a segmented control and is hidden
entirely when the model reports none, so the control adapts to whatever the
selected model's family supports without any per-family table in the app.

This corrects a live defect. `ComposerControlsPresentation.thinkingOptions`
prepends `"auto"` unconditionally, and `requiresEffort` is parsed, stored on
`ComposerModelInfo`, and never read by any call site. A model that requires an
explicit effort is therefore offered "auto" today. Under this spec:

- `requiresEffort == false` → options are `["auto"] + thinkingEfforts`.
- `requiresEffort == true` → options are `thinkingEfforts` alone.

When a model switch leaves the current thinking level absent from the new
model's options, the selection falls back to `"auto"` where it is offered, and
otherwise to `thinkingEfforts[thinkingEfforts.count / 2]`.

This reconciliation cannot be display-only, which is why it reaches into
`ComposerControlsModel`. `spawnSelection` sends `thinkingLevel` verbatim whenever
the model has options, so a stale `"auto"` held while switching to a
`requiresEffort` model would spawn with the exact invalid value this fix exists to
prevent. `selectModel` therefore assigns the reconciled level to in-memory
`thinkingLevel` in both modes. It does not write that value to config: only an
explicit effort pick persists, so switching models never silently rewrites the
user's stored default.

In `activeSession` the reconciled level has to reach the runtime explicitly. It
cannot ride back on OMP's echo: `SessionController.setModel` publishes its live
selection while `selectModel` is still awaiting, so `applyLiveSelection`'s
`isMutating` guard drops it, and the echo carries only `provider` and `modelID`
anyway — never a thinking level. So after `setModel` succeeds, `selectModel`
compares the reconciled level against the level held before the switch and, when
they differ, issues one `setThinkingLevel` with the reconciled value. A switch
that leaves the level alone issues none.

The two calls are two failure domains, and each rolls back only what it
invalidated:

- `setModel` throws — nothing reached the runtime, so the whole optimistic switch
  reverts: model, level, and Fast-mode intent, under `Couldn’t update the model.`
- `setModel` succeeds and `setThinkingLevel` throws — the runtime is genuinely on
  the new model, so the selection stays switched and Fast mode stays computed from
  that new model. Only the level reverts, under `Couldn’t update the thinking
  level.`

Rolling the model back in the second case would leave the chip naming a model the
session is not running, under an error claiming a model update failed that in fact
succeeded — and nothing would self-correct, since `applyLiveSelection` drops both
echoes while `isMutating` is still true.

## Fast mode

Unchanged in behavior: a binary toggle, shown only when
`ComposerControlsPresentation.supportsFastMode` returns true for the selected
model, cleared when it does not. It moves from a footer chip into the panel and
renders as a labeled toggle rather than a colored text button.

## Recent models

A `RecentModelStore` backed by `UserDefaults`, mirroring `RecentProjectStore`:
`recordSelection(_:)` pushes a `provider/modelID` key to the front of a capped
list, `rankedModels(from:)` resolves those keys against the current catalog and
drops any that no longer resolve. Cap is three.

OMP's own config is shared with the CLI, so 10x-local interface state is not
written there. `ComposerDefaultPersisting` keeps its existing job of writing the
default model role and default thinking level, and gains nothing.

## Keyboard and pointer

- Typing filters. The search field holds focus while the panel is open.
- Up and Down move a highlight across the flat visible row order, skipping
  section headers. The highlight starts on the current selection, or on the first
  row when the query is non-empty.
- Return commits the highlighted row. Clicking a row commits it. Neither closes
  the panel: committing a model re-adapts the effort row in place, which is the
  whole reason the three controls were unified into one surface.
- Escape closes the panel, via `onExitCommand`. So does clicking outside it, or
  clicking the trigger again. Closing never reverts a commit.
- Rows highlight on hover with `hoverNeutralHex`, matching `FlyoutRowBackground`.

## Flyout coordination

`ComposerView` currently takes `isProjectFlyoutPresented` as a `Binding<Bool>`,
owned as `@State` by `NewSessionView` and left at `.constant(false)` by
`ActiveSessionView`. A second flyout in the same corner needs only one open at a
time.

`ComposerView` gains a single `ComposerFlyout?` enum (`.project`, `.model`)
replacing the boolean. `NewSessionView` binds to it for its scrim and dismissals;
`ActiveSessionView` continues to pass nothing and gets the model flyout for free.
Opening either sets the enum, which closes the other by construction.

## Copy

Every user-facing string in the panel:

- Search placeholder: `Search models`
- Section headers: the provider id, uppercased (`ANTHROPIC`, `OPENAI-CODEX`)
- Recents header: `RECENT`
- Effort row label: `EFFORT`
- Fast mode row label: `Fast mode`
- Empty catalog: `No models available. Connect a provider in Settings.`
- Empty search result: `No models match that search.`
- Loading: `Loading models…`

Error copy stays where it is, in `ComposerControlsModel.errorMessage`, rendered
by the existing composer footer row.

## Components

| Unit | Responsibility | Depends on |
| --- | --- | --- |
| `ModelPickerFlyout` | Panel chrome, regions, keyboard handling | presentation funcs, palette, typography |
| `ModelPickerRow` | One model row: name, provider tag, selected rail, hover | palette, typography |
| `ComposerSessionControlsView` | Trigger chip, hosts the flyout | `ComposerControlsModel` |
| `ComposerControlsPresentation` | Grouping, filtering, effort options — pure | `ComposerModelInfo` |
| `RecentModelStore` | MRU persistence | `UserDefaults` |

New presentation functions, all pure and directly testable:

```swift
static func groupedByProvider(_ models: [ComposerModelInfo])
    -> [(provider: String, models: [ComposerModelInfo])]

static func matching(_ models: [ComposerModelInfo], query: String)
    -> [ComposerModelInfo]

static func thinkingOptions(for model: ComposerModelInfo?) -> [String]   // amended

static func resolvedThinkingLevel(current: String, for model: ComposerModelInfo?)
    -> String
```

## States

The panel owns its own states rather than deferring to the composer.

- **Loading** — `isLoading` with an empty catalog shows `Loading models…` in the
  list region. Search, effort, and fast rows are hidden, not disabled-and-empty.
- **Empty** — a loaded but empty catalog shows the connect-a-provider line. The
  trigger chip stays enabled so that line is reachable, which changes today's
  gating: `menusDisabled` currently includes `models.isEmpty`, leaving the user
  with a dead chip and no explanation. Disabled-on-empty is dropped; the trigger
  reads `Model` when nothing is selected.
- **No search match** — list region shows the no-match line; effort and fast rows
  stay visible, since they describe the still-selected model.
- **Mutating** — `isMutating` disables row commits so a second click cannot race
  an in-flight `setModel`. The panel stays open; rollback on failure is already
  handled by `ComposerControlsModel` and surfaces in the footer error row.

## Testing

Unit tests extend `ComposerControlsPresentationTests`:

- Grouping preserves catalog order within a provider and groups every model.
- Search matches on name, matches on provider id, is case-insensitive, and an
  empty query returns everything.
- `thinkingOptions` omits `"auto"` when `requiresEffort` is true and includes it
  otherwise.
- `resolvedThinkingLevel` keeps a still-valid level, falls back to `"auto"` when
  offered, and to the middle effort when not.

`RecentModelStoreTests` mirrors `RecentProjectStoreTests`: most-recent-first
ordering, deduplication on re-selection, cap enforcement, and dropping keys that
no longer resolve against the catalog.

Snapshot coverage in `ViewSnapshotTests` for the open panel in three states:
default, active search with results, and empty catalog. Recording requires the
`TEST_RUNNER_RECORD_SNAPSHOTS` environment prefix.

Arrow-key navigation needs explicit handling: the search field holds focus, and
an AppKit-backed `TextField` consumes Up and Down for caret movement by default.
The field intercepts both, plus Return, through `onKeyPress` rather than relying
on default responder behavior. `SearchModalView` selects with the pointer only,
so there is no existing pattern in the app to lift here.

`AccessibilityLabelTests` covers the trigger and rows: the trigger keeps its
`Model` label and selected-model value; each row is labeled with its model name
and valued with its provider plus selection state; the effort control and fast
toggle keep label and value parity with the chips they replace.

## Verification

Design work is verified by looking at it. A release build is launched and the
panel screenshotted in the three snapshot states plus the duplicate-model case,
confirming no clipping at the panel's height cap, no collision with the composer
border, and correct upward growth when the composer sits at the bottom of a short
window.

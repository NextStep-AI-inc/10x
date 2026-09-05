# Tool Detail Mode

**Status:** Approved; not yet implemented
**Date:** 2026-09-02
**Parent spec:** `docs/superpowers/specs/2026-08-26-rich-chat-tool-surfaces-design.md`

## Goal

Let the reader decide how much tool detail the transcript shows, once, instead
of opening and closing cards one at a time. Three modes, chosen from the
transcript and remembered across sessions and launches:

- **Auto** keeps today's behavior: running and failed activity is open, and
  edits open when they finish.
- **Expanded** opens every tool card, including ones that arrive mid-turn.
- **Compact** leaves every card closed, so each tool reads as a one-line
  summary as it is called.

The per-card disclosure control keeps working in every mode and always wins for
the card it belongs to.

## Scope

### Included

- A `ToolDetailMode` value with the three modes above and the disclosure policy
  for each.
- One app preference, owned by 10x, persisted in `UserDefaults`.
- A mode control in the transcript, above the activity, built from the existing
  chip vocabulary.
- Consolidation of the disclosure defaults that today live in two places, so
  subagent cards follow the same mode as tool cards.
- Extraction of the effort chip in the model picker into one shared chip, used
  by both rows.

### Excluded

- Per-tool or per-kind mode overrides.
- Per-project or per-session modes. The preference is global.
- A row in Settings. The control lives where the transcript is read.
- Changes to what an expanded or collapsed card renders. The compact reading
  is the existing collapsed header.
- Keyboard shortcuts.
- OMP configuration, schema, or RPC changes.

## User experience

### The compact reading already exists

A collapsed tool card is already a summary line:

```text
> Read   RpcClient.swift:42   ·   38 lines      Complete   0.4s
```

Compact mode is therefore not a new rendering. It is the decision to leave
cards closed by default. No card loses information: the file reference,
outcome, phase, and duration all live in the header.

### The control

The mode control sits at the top of the transcript activity, right-aligned,
and replaces the current `Collapse all` and `Expand active` buttons:

```text
                                        DETAIL  auto  expanded  compact
```

- The label uses the mono uppercase treatment already used by `EFFORT` in the
  model picker and by the provider section headers.
- Each mode is a chip. The selected chip is white on near-black; the rest are
  muted on clear. This is the existing `EFFORT` chip, extracted and shared.
- The control is always present, including on a transcript that has no
  activity yet, so the mode can be set before the first tool arrives. The
  current four-row gate on the buttons it replaces is removed.
- Selecting a mode applies immediately to every card on screen and to every
  card that arrives afterwards.

`Collapse all` and `Expand active` are removed rather than kept alongside.
Compact is `Collapse all` made persistent, and Auto is `Expand active` made
persistent; keeping both would offer two controls for one decision.

### Mode switching clears per-card choices

Selecting a mode discards the per-card open and closed choices accumulated
before it. Without that, switching to Expanded would leave previously closed
cards shut, which reads as a control that did not work.

After the switch, the per-card control resumes overriding the mode for
individual cards.

### Compact does not make an exception for errors

A failed tool stays closed in Compact. Its header already carries the red
accent, the `Error` phase, and its outcome text, so the failure is visible
without the body. An exception here would make Compact unpredictable, which is
the reason Auto exists as its own mode.

## Architecture

### `ToolDetailMode`

```swift
enum ToolDetailMode: String, CaseIterable, Identifiable, Sendable {
    case auto, expanded, compact
}
```

The mode owns the policy. It answers one question about one activity row:

```swift
func isExpandedByDefault(_ traits: ToolDisclosureTraits) -> Bool
```

`ToolDisclosureTraits` is the small value both card types can produce:
whether the row is active, whether it failed, and whether its kind opens on
completion. Auto is the disjunction of the three; Expanded is `true`; Compact
is `false`.

Keeping the policy on the mode means the three behaviors are three lines in one
switch, and neither card view carries a copy.

### `ToolDetailPreferenceStore`

A `@MainActor @Observable` store over `UserDefaults`, matching
`IDEPreferenceStore`:

- key `tenx.toolDetailMode.v1`;
- an absent or unrecognized value resolves to `.auto`, so an older or corrupt
  value degrades to the current behavior rather than to a surprise;
- writes publish immediately.

`AppModel` creates it for the app lifetime with the same injected
`UserDefaults` it already passes to `IDEPreferenceStore`, and `AppShellView`
puts it in the environment beside the IDE store.

### `ToolDisclosureState`

The per-transcript state gains the mode and keeps owning per-card choices:

- `mode` defaults to `.auto`;
- `setMode(_:)` replaces the mode and clears the per-card choices;
- `isExpanded(for:)` falls back to `mode.isExpandedByDefault(traits)`.

`TranscriptView` continues to own the state as `@State` and syncs it from the
preference store on appearance and on change, so a transcript opened later
starts in the stored mode.

The one-shot `collapseAll(ids:)` and `expand(ids:)` methods go away with the
buttons that called them.

### Subagent cards

`SubagentCardView` currently computes its own default inline: expanded when
the subagent is active or errored. That default moves into
`ToolDisclosureState` as a `SubagentPresentation` overload, so one mode governs
both card types and the policy has one home.

### Shared chip

`ModelPickerFlyout.effortChip` becomes `SelectionChip` in `App/Design`. Its
inputs are the title, the selected flag, and the action; its rendering is the
current one, unchanged, so the model picker's snapshots hold. The effort row
and the detail row both use it.

## Data flow

```text
UserDefaults ──► ToolDetailPreferenceStore ──► AppShellView environment
                                                       │
                                                       ▼
                                         ToolDetailModeControl (chips)
                                                       │  selection
                                                       ▼
                                          ToolDetailPreferenceStore.mode
                                                       │  observed
                                                       ▼
                                      TranscriptView ──► ToolDisclosureState
                                                       │  (clears per-card choices)
                                                       ▼
                                    ToolCardScaffold / SubagentCardView
                                                       ▲
                                                       └── per-card chevron
```

## Error handling

- An unrecognized stored raw value resolves to `.auto`. Nothing is thrown and
  nothing is shown; the stored string is replaced on the next selection.
- No card view requires the preference store. A view rendered without it, as in
  snapshot tests, uses `ToolDisclosureState`'s own mode, and a view rendered
  without either falls back to `.auto`.

## Accessibility

- The chip row is one container labeled `Tool detail`, with the selected mode
  as its value.
- Each chip keeps the existing chip accessibility shape: the mode name as the
  label, `Selected` or `Not selected` as the value.
- Per-card disclosure labels, values, and hints are unchanged.
- Mode changes respect Reduce Motion through the existing disclosure animation
  path.

## Verification

### Automated checks

- Each mode returns the expected default for an active, a failed, an
  edit-shaped complete, and a read-shaped complete row.
- Auto reproduces today's defaults exactly.
- A per-card choice overrides the mode for that card only.
- `setMode(_:)` clears per-card choices, so a previously closed card follows
  the new mode.
- Subagent rows resolve through the same mode as tool rows.
- The store round-trips each mode through `UserDefaults`.
- An absent value and a garbage value both resolve to `.auto`.
- Snapshots of the transcript in Expanded and in Compact.

### Real build checks

- With the app running, switch to Compact and confirm cards arriving during a
  live turn stay closed.
- Switch to Expanded during the same turn and confirm every card on screen
  opens, including ones closed by hand beforehand.
- Open one card by hand in Compact and confirm its neighbors stay closed.
- Relaunch and confirm the mode persisted.

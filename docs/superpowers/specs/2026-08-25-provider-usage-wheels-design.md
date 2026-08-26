# Provider Usage Wheels

**Status:** Approved for implementation planning

**Date:** 2026-08-25
**Platform:** macOS 15+, Swift 6.1, SwiftUI
**Builds on:** `2026-08-25-provider-setup-usage-design.md`

## Goal

Replace the expanded rail's text-heavy provider usage ledger with a persistent,
compact group of concentric usage wheels in the bottom-right of the post-setup
shell. Each wheel shows one provider's remaining limits, identifies the
provider with a three-letter label, and exposes a live count of 10x-managed
sessions using that provider.

Selecting a wheel morphs it into an anchored, full-color panel containing the
existing bar-based usage breakdown. The compact state remains glanceable while
the expanded state preserves precise percentages, accounts, and reset times.

## Approved product decisions

- Usage moves out of `FloatingRailView` and into a bottom-right shell overlay.
- The compact overlay renders one wheel per provider and a fixed three-letter
  provider label under every wheel.
- A wheel renders every computable limit. Limits are not capped or hidden.
- Shorter usage windows sit closer to the center. Longer usage windows sit
  farther outside. The 5-hour limit is therefore inside the weekly limit.
- Each limit arc represents remaining capacity, beginning at 12 o'clock and
  running clockwise.
- The center is a live activity core. It pulses and shows the count of all
  10x-managed sessions currently generating through that provider.
- Compact limit color follows only the foreground chat's turn state:
  - while the open chat is generating, every compact provider wheel uses
    grayscale limit arcs;
  - while the open chat is idle, every compact wheel uses its semantic limit
    colors, even if other managed sessions remain active.
- The activity core remains visible and keeps pulsing in either compact color
  state.
- Expanded usage always uses semantic colors, including while the foreground
  chat is generating.
- Selecting a compact wheel grows the control up and left into an anchored
  panel. It does not navigate away from the current chat.
- When a composer is visible and its trailing gutter can contain the complete
  provider group, the compact wheels sit beside it on the bottom row. Their
  labels share the composer's 28-point bottom inset.
- When that trailing gutter cannot contain the group, the wheels move directly
  above the composer, align to its trailing edge, and use 44-point visible
  rings. The three-letter labels and minimum 44-point hit targets remain.
- Responsive placement never changes the composer's frame or bottom inset.
- Routes without a composer keep the 54-point group at the shell's bottom-right
  inset.

## Shell interaction

```text
Post-setup shell
  |
  +-- bottom-right provider wheels
        |
        +-- collapsed
        |     +-- all limit rings
        |     +-- three-letter provider label
        |     +-- global managed-session activity core
        |     +-- foreground turn controls color vs grayscale
        |
        +-- select provider
              |
              v
        anchored expanded panel
              +-- full provider name and account
              +-- every limit as a semantic-color bar
              +-- remaining percentage and reset text
              +-- provider switch controls
              +-- active managed-session count
```

The dock is available throughout the post-setup application shell wherever
computable provider usage exists. Setup and required provider onboarding do not
show it. An empty usage presentation does not reserve space.

### Collapsed layout

Provider wheels form a trailing horizontal group whose placement responds to
the space around the composer without participating in the composer's layout.

On New Session and Active Session routes, the shell derives the composer's
actual frame from the post-rail route canvas. In the preferred side layout, the
group uses 54-point rings, sits at the shell's trailing edge, and shares the
composer's 28-point bottom inset. The side layout is allowed only when the
space from the composer's trailing edge to the shell edge can contain the full
provider group, the 16-point shell trailing inset, and a 16-point minimum gap
from the composer.

If the complete group does not fit, it switches as one unit to the above
layout. The visible rings become 44 points, the group's trailing edge aligns
with the composer's trailing edge, and its lower edge sits 8 points above the
composer. Labels remain below their rings. The composer's width, height,
position, and bottom inset remain identical across both layouts.

Provider count is part of the fit calculation, so resizing the window or
adding a provider can select the above layout without a fixed window-width
breakpoint. Routes without a composer retain the original 54-point
bottom-right placement. Expanded content remains the existing bounded corner
popup and does not adopt the compact responsive size.

Each provider wheel includes:

1. one concentric track and remaining-capacity arc for every computable limit;
2. a shared center activity core;
3. a three-letter provider label below the wheel.

Known providers use stable, recognizable abbreviations, including `ANT` for
Anthropic, `OAI` for OpenAI, `CUR` for Cursor, and `GCA` for Google Cloud Code
Assist. Other providers receive a deterministic three-character abbreviation
derived from their display name and provider id. Accessibility always exposes
the full provider name rather than requiring the abbreviation to be understood.

### Ring order and geometry

Ring order reflects the limit window's duration, not the time remaining until
its next reset and not its remaining percentage. A weekly ring must not jump
inside a 5-hour ring merely because the weekly reset is sooner at that moment.

Known window ids and labels are normalized into stable duration ranks, such as
hourly, 5-hour, daily, weekly, monthly, and annual. Unknown windows preserve
OMP's source order. Equal-duration limits also preserve source order. The
presentation model retains the source index so refreshes do not reorder ties.

The wheel accepts a compact outer diameter of either 54 points in the side and
non-composer layouts or 44 points in the above-composer layout. The activity
core and ring strokes scale with that diameter. The available annulus between
the activity core and outer edge is divided across every limit, scaling stroke
and gap widths together. No limit is omitted. This intentionally accepts
greater visual density for providers with many limits; selecting the wheel
restores the full readable breakdown.

### Color states

Semantic colors continue to mean remaining capacity:

- above 20%: cyan;
- 1% through 20%: yellow;
- 0%: signal red.

The compact dock applies a grayscale presentation to every limit arc while the
foreground `SessionController.runtimeState` is `.streaming`. This is one global
collapsed-dock treatment, not a per-provider activity treatment. When the
foreground session is absent or not streaming, all compact semantic colors
return.

"Foreground" specifically means the controller shown by a `.session` route.
Navigating to New Session, Settings, Archived Sessions, or Providers leaves no
foreground chat for this color rule, even if a retained background controller
continues streaming.

Opening the dock always restores semantic colors for the wheel tabs and every
bar. The center count and pulse remain the provider activity signal and are not
used to decide whether compact arcs are grayscale.

### Activity core

The activity core counts top-level sessions managed by this 10x process whose
runtime state is streaming and whose current OMP model reports the matching
provider id. Counts are provider-wide and independent from the currently
selected chat.

- Active provider: solid center, numeric count, and a restrained cyan pulse.
- Inactive provider: quiet neutral center with no pulse and no displayed zero.
- Reduce Motion: keep the numeric active state and static cyan outline, but do
  not animate.

OMP's session state identifies the provider but not the authenticated account
that receives usage. The activity core is therefore provider-level and never
claims account-level attribution. Subagents do not increment the count
separately in this version; the count represents managed top-level sessions.

### Expansion

Selecting a wheel expands the bottom-right dock up and left while preserving
its trailing and bottom anchor. The selected provider becomes the initial
breakdown. Provider controls remain inside the expanded panel so another
provider can be selected without collapsing it.

The expanded panel shows:

- full provider name;
- account label when available;
- active managed-session count;
- every computable limit with label, percentage, reset text, and full-width
  remaining-capacity bar;
- all accounts for the provider in the same provider/account grouping already
  used by the detailed usage surface.

The panel scrolls internally when content exceeds its bounded height. Clicking
outside, pressing Escape, or activating the close control collapses it back to
the wheel group. Reduced Motion replaces the morph with an immediate layout
change and opacity transition.

The existing Providers workspace remains available from Settings for refresh,
stale data, account recovery, notes, and amounts without computable limits. The
new dock does not duplicate those management controls.

## Architecture

```text
OMP usage --json                         OMP session RPC state/events
        |                                          |
        v                                          v
ProviderUsagePresentation                 retained SessionControllers
  + window ordering metadata                        |
  + provider abbreviation                           v
  + every computable limit                 SessionActivityRegistry
        |                                   provider id -> active count
        |                                          |
        +-------------------+----------------------+
                            v
                   ProviderUsageDockView
                   + collapsed wheels
                   + foreground turn color mode
                   + anchored expanded breakdown
```

### Usage presentation

`ProviderUsageLimit` gains stable window-order metadata derived from
`OmpUsageLimit.window`, `scope.windowId`, and the source index. Presentation
continues to calculate remaining capacity exactly as it does today.

`ProviderUsageProvider` gains its deterministic three-letter abbreviation.
The existing provider and account grouping remains authoritative. The compact
dock flattens every account's computable limits within its provider only for
concentric geometry, preserving report and limit source order for duration
ties. The expanded panel preserves explicit account boundaries.

### Managed-session activity

`AppModel` currently owns only one strong `activeSession` reference while
`SessionProcessManager` can retain multiple open OMP processes. To observe
activity across all managed sessions without consuming `RpcClient.events` a
second time, `AppModel` will retain each opened `SessionController` until that
session is closed, deleted, archived, or the app shuts down. A controller whose
process exits stops contributing activity immediately but may remain retained
while its recovery UI is visible.

Each controller reports a stable controller id, current provider id, and
streaming state to a main-actor `SessionActivityRegistry`. Provider id comes
from `get_state.model.provider` and updates after model/config changes. The
registry removes entries when their controller closes or exits, then exposes a
provider-id-to-count map for the dock.

Opening an already managed session reuses its controller rather than creating a
second event consumer. Unexpected process exits route to the retained
controller matching the exited path, not only the foreground controller.

### SwiftUI composition

`AppShellView` owns the bottom-trailing overlay because the feature is global to
the post-setup shell. It supplies:

- normalized provider usage;
- provider activity counts;
- whether the foreground controller is streaming;
- Reduce Motion state.

A small, pure responsive-layout calculation receives the shell width, current
rail inset, provider count, and compact group metrics. It returns either the
54-point side placement or the 44-point above-composer placement together with
the trailing and bottom offsets. `AppShellView` applies that result only to the
dock overlay, leaving `NewSessionView`, `ActiveSessionView`, and `ComposerView`
unchanged.

`FloatingRailView` removes `ProviderUsageLedgerView`, its dynamic ledger height,
and the rail padding reserved for usage. The provider workspace and refresh
behavior do not change.

The minimal UI split is:

- `ProviderUsageDockView`: collapsed/expanded state, provider selection,
  dismissal, focus, and panel layout;
- `ProviderUsageWheelView`: concentric geometry, activity core, abbreviation,
  and compact accessibility;
- a shared limit bar row reused by the dock and existing detail view where that
  reduces duplication without changing the detail screen.

## Accessibility and keyboard behavior

- Every compact wheel is a button named with the full provider name.
- Its accessibility value summarizes active session count and every limit's
  remaining percentage and reset window.
- Visible three-letter labels are never the only accessible provider identity.
- The activity pulse has a non-motion numeric state.
- Expanded controls have a deterministic keyboard order: provider selector,
  account limits, then close.
- Escape collapses the dock and returns focus to the wheel that opened it.
- Grayscale does not carry the only meaning of generation. The foreground chat
  already exposes its generating state, and the wheel retains its numeric core.

## Loading, empty, and error behavior

- No computable provider limits: hide the dock and reserve no layout space.
- Stale but valid usage: continue to show the last successful values; the
  Providers workspace retains the stale warning.
- Usage refresh failure with prior values: preserve the dock values.
- Provider activity without a matching usage report: do not invent a wheel.
- Unknown window duration: preserve OMP order rather than guessing.
- Percentages remain clamped to `0...100` before ring or bar rendering.

## Testing and verification

### Automated

- Presentation tests for known duration ordering, equal-window stability,
  unknown-window stability, and every-limit retention.
- Abbreviation tests for known and fallback providers.
- Geometry tests for one, two, three, and dense multi-limit wheels.
- Responsive-layout tests proving a wide trailing gutter selects 54-point side
  placement, a constrained gutter selects 44-point above placement, provider
  count participates in the decision, and the composer's geometry is not an
  output of the calculation.
- Activity-registry tests for multiple sessions on one provider, sessions on
  different providers, provider changes, idle transitions, exits, and cleanup.
- App-model tests proving background controllers remain observed and reopened
  sessions do not create duplicate consumers.
- Accessibility tests for full provider naming, active counts, limits, and
  reset summaries.
- Snapshots for collapsed idle color, collapsed foreground-generation
  grayscale, expanded generation-time color, multiple providers, all limits,
  a wide shell with bottom-row placement, and a constrained shell with the
  smaller group above the unchanged composer.
- Existing provider detail and rail snapshots are updated only where the usage
  ledger removal changes the expected shell.

### Built application

Verify a production build with realistic provider data:

1. idle foreground chat shows semantic compact colors;
2. starting a turn makes every compact limit grayscale;
3. provider activity cores retain their counts and pulse;
4. selecting a wheel during generation restores full expanded color;
5. switching providers updates the account and bar breakdown;
6. Escape, outside click, and close return to the compact wheels;
7. another managed session can remain active while the foreground chat is
   idle, producing colored rings with a still-pulsing provider core;
8. Reduce Motion removes the pulse and morph without hiding state;
9. a wide window places 54-point wheels beside the composer with matching
   bottom inset;
10. resizing until the trailing gutter no longer fits the group moves 44-point
    wheels above the composer and aligns their trailing edges;
11. the composer does not move or resize during either transition;
12. compact and expanded layouts do not collide with the safe area, top
    actions, rail, or small-window bounds.

Screenshots from the built application must cover collapsed idle, collapsed
generating, and expanded generating states.

## Scope boundaries

- No OMP contract or executable change.
- No provider authentication, refresh cadence, or account-recovery change.
- No activity from CLI tools or applications outside this 10x process.
- No account-level attribution for active sessions.
- No separate subagent count.
- No usage history, prediction, or rate-of-consumption estimate.
- No provider logos or new dependency.

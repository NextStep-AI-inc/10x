# Responsive Provider Dock Repair

**Status:** Approved for implementation planning

**Date:** 2026-09-04

**Platform:** macOS 15+, Swift 6, SwiftUI

## Goal

Restore the provider usage dock's responsive behavior. When the trailing gutter can hold every provider control at the regular 54-point size, the controls sit outside the composer. When that gutter is too narrow, the controls remain at 28 points inside a reserved composer-footer slot.

## Root cause

Commit `fec3cba` replaced the provider-count-aware placement policy with `ProviderUsageDockLayout.compact(shellSize:footerFrame:)`, which always returns `inComposer28`. It also made `AppShellView` always reserve `footerWidth(providers:)` inside `ComposerView`. The measured footer anchor fixed collisions with Context, Steer, Send, and Stop, but removed the wide placement branch entirely. Window width is therefore no longer part of the decision.

## Constraints

- Preserve the measured composer-footer anchor for constrained windows.
- Preserve the current composer controls and their wrapping behavior.
- Preserve provider account stacks, hover expansion, expanded detail panels, keyboard focus restoration, reduced-motion behavior, and account-routing actions.
- The fit decision must use live shell width, current rail inset, and provider count rather than a fixed window breakpoint.
- Wide placement uses 54-point controls, 8-point inter-provider spacing, the shell's existing 16-point trailing inset, and at least 16 points between the composer and dock.
- Constrained placement uses the existing 28-point controls and exact provider-aware footer reservation.
- Routes without a composer retain the standalone bottom-right dock.

## Approaches considered

### A. Restore responsive placement while retaining compact reservation

Reintroduce the pure fit decision removed by `fec3cba`. Reserve footer width only when the result is the compact composer placement. Continue resolving compact offsets from the measured footer anchor.

This is the selected approach. It restores the intended behavior while retaining the collision fix and limits changes to the existing provider dock boundary.

### B. Recompose session screens around `ViewThatFits`

Move provider data and the dock into a shared composer-row container used by `NewSessionView` and `ActiveSessionView`. This would let SwiftUI choose between composer-plus-dock and composer-with-inline-dock directly.

Rejected because it couples shell-owned provider interactions and expanded-panel behavior into both session screens. The larger ownership change is unnecessary for this regression.

### C. Add a fixed wide-window breakpoint

Switch outside above one shell width and inside below it.

Rejected because the required gutter changes with provider count and rail width. A fixed breakpoint would recreate collisions for larger provider sets and waste space for smaller ones.

## Design

### Placement decision

`ProviderUsageDockLayout` will expose a pure responsive decision with two composer placements:

- `outsideComposer`: regular 54-point controls in the shell trailing gutter.
- `composerFooter`: 28-point controls in the measured footer slot.

The decision reconstructs the composer's horizontal bounds from the same stable route metrics used before `fec3cba`: live shell width, live rail inset, the 780-point composer maximum, and 42-point route padding on each side. The outside branch is selected only when the trailing gutter can contain the regular provider group, the shell's 16-point trailing inset, and a 16-point composer gap.

The regular group width is `providerCount * 54 + max(0, providerCount - 1) * 8`. Account-routing stacks fan vertically at rest, so multiple accounts do not increase the horizontal fit requirement.

### Composer reservation

`AppShellView` computes the placement before rendering `routeCanvas`:

- For `outsideComposer`, it injects `composerProviderDockWidth = 0`. `ComposerView` renders no reserved slot, leaving the footer space available to Context, Steer, Send, and Stop.
- For `composerFooter`, it injects the existing `footerWidth(providers:)`. `ComposerView` renders the measured anchor slot exactly as it does now.

This retains the compact collision protection without paying its width cost in wide windows.

### Dock positioning

The shell keeps ownership of `ProviderUsageDockView`.

- Outside placement uses a 54-point diameter, zero additional trailing offset, and a bottom offset that aligns the complete labeled control stack with the composer's bottom edge.
- Footer placement resolves trailing and bottom offsets from `ComposerProviderDockAnchorKey`, preserving correct placement when the footer wraps or the composer height changes.
- Non-composer routes keep `.standalone` placement.

The expanded 360-point details panel remains anchored to the shell's bottom-right inset and does not inherit collapsed offsets.

### Responsive updates

The decision is derived inside live shell geometry, so window resizing, full-screen transitions, provider-count changes, and rail expansion recalculate both the dock placement and composer reservation in the same render path. No stored breakpoint state or delayed layout update is introduced.

## Testing

### Pure layout tests

Add or restore coverage for:

- Three providers at a wide shell width select `outsideComposer` and reserve no footer width.
- Three providers at a constrained shell width select `composerFooter` and reserve the exact compact group width.
- Provider count changes the fit result at a boundary width.
- Rail expansion can move the same shell from outside to footer placement when it consumes the required gutter.
- No providers reserve zero width.
- Routes without a composer retain standalone placement.
- Footer-anchor offset resolution continues to track a moved composer footer.

### Snapshot coverage

Update the existing shell references to prove:

- The wide window shows 54-point labeled controls outside the composer with no empty footer reservation.
- The constrained window shows 28-point controls inside the footer without colliding with composer controls.
- The compact trigger/boundary window selects the intended branch.

### Manual verification

Build and launch the application from the isolated worktree. In a real session with three provider controls:

1. Start narrow and confirm the controls are inside the composer.
2. Widen past the calculated fit boundary and confirm they move outside and grow to 54 points.
3. Narrow again and confirm they return to the measured footer slot.
4. Expand and collapse the rail and confirm placement recalculates without overlap.
5. Open and close a provider details panel in both placements.
6. Confirm hover, account-stack expansion, keyboard focus, and reduced-motion behavior remain intact.

Capture only the 10x window for visual evidence; no desktop or unrelated application content may appear.

## Non-goals

- Redesigning provider usage rings or account stacks.
- Changing provider-account routing semantics.
- Changing composer labels, actions, or wrapping rules.
- Changing the expanded details panel's size or anchor.
- Introducing a user preference for dock placement.

# Expanded Account Peek

**Status:** In implementation
**Date:** 2026-09-07
**Platform:** macOS 15+, Swift 6.1, SwiftUI
**Builds on:** `2026-08-26-multi-account-provider-routing-design.md`

## The bug

The expanded usage panel header lists every provider as a single wheel. A
provider with two signed-in accounts therefore shows one circle, and the
panel body is the only place the second account appears. `compactSelectorProvider`
is what strips the extra accounts. The unused `accountStack(alwaysExpanded:)`
path fans every account upward, which is the compact-dock language, not the
expanded one.

## Intended expanded header

The header shows one stack: the inspected account in front, and at most one
other account of the same provider to the right and behind. Hovering or
focusing the rear wheel raises it. Clicking it inspects it. The bottom panel
follows the inspected account. Inspection still does not change routing.

Arrows sit on either side of that stack. Next moves to the next account of
the same provider; on the last account it inspects the next provider. Previous
is the reverse. The list wraps. Provider-only rows (no account routing) are
one step.

No horizontal provider row. No scroll. No third ring.

## Compact dock

Unchanged. Collapsed-at-rest, badge, fan upward on hover.

## Out of scope

Account routing, confirmation, Connections management, compact geometry.

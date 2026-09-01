# Dark Mode & Dark Tokens — Verification Evidence

**Branch:** `tannerpham/dark-mode-tokens-4c5814`
**Date:** 2026-09-01

## What changed

The app had no appearance handling at all — no `colorScheme` read anywhere, and
`Info.plist` has never set `NSRequiresAquaSystemAppearance`. On a machine set to
dark, the system drew dark chrome behind a UI whose text was pinned near-black
and whose panels were pinned white.

`TenXPalette.color(_:)` was the one funnel every color already passed through
(346 call sites, all using named tokens — no raw hex anywhere). It now returns a
dynamic `NSColor` that resolves against the drawing appearance, so those 346
sites became appearance-correct without being edited.

Two pairings could not be expressed as a light→dark hex map, because their light
value is `0xFFFFFF` and collides with `canvasHex`:

| Token | Light | Dark | Why |
|---|---|---|---|
| `surfaceElevated` | `0xFFFFFF` | `0x232321` | A drop shadow separates a flyout from a white canvas; over a dark canvas it reads as nothing, so the surface carries the elevation itself. |
| `onEmphasis` | `0xFFFFFF` | `0x0C0C0B` | `nearBlack` is both a text color and a **fill**. Inverting the fill without inverting its label paints white on near-white. |

## The failure this design exists to prevent

`nearBlackHex` is used as a fill in five places, each with a white label on top:
the composer send button, the model picker's selected effort chip, the provider
activity core, the "Jump to latest" pill, and **every user message bubble**.
Holding those labels at white while the fill inverts gives **1.12:1** — not a
weak contrast, a disappearance. `emphasisLabelsInvertWithTheirFill` asserts both
the correct pairing and that the naive one fails.

## Verified

**Byte-identity canary.** Before any call site was touched, the full suite ran
against the new dynamic palette alone: **918/918 passed**. The host pins
`NSAppearance(named: .aqua)`, and this machine is set to dark — so a green run
proves both that `srgbRed:` round-trips identically to the old
`Color(red:green:blue:)` and that resolution follows the host, not
`NSApp.effectiveAppearance`.

**Full suite.** 974/974 passing, no stray `.actual.png`, and no light
reference moved when the dark mirrors were added.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
```

**Release build.** Succeeds.

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' build
```

**Contrast, asserted not eyeballed.** Six tests in `DesignSystemTests`. Every
dark foreground clears 4.5:1 on the dark canvas (lowest: `signalRed` 6.58);
`everyLightTokenHasADarkCounterpart` fails if a token is added light-only.
The two accents move *up* in luminance — the light ramp darkens them for
contrast against white, which inverts once the canvas is dark.

**48 dark snapshot references**, rendered from the real views through a
`.darkAqua`-pinned host. Contact sheets, grouped by area, are next to this file:

| Sheet | Screens |
|---|---|
| `01-shell-and-navigation-dark.png` | 7 |
| `02-transcript-and-messages-dark.png` | 6 |
| `03-tool-cards-dark.png` | 12 |
| `04-composer-and-model-picker-dark.png` | 7 |
| `05-providers-and-accounts-dark.png` | 6 |
| `06-onboarding-settings-system-dark.png` | 10 |

37 of these are generated from the light fixtures rather than hand-written, so
the two appearances stay in step: same view, same state, only the host
appearance differs. The generator rewrites the snapshot name only inside
`assertSnapshot(...)` — `name:` is also a `ToolPresentation` argument, and
renaming a tool would change what the card says.

`search-modal` and `choose-project-shelf` had no reference at **either**
appearance; both are now covered in light and dark. Both are raised panels over
a canvas-tinted scrim, the exact pair of tokens contrast math cannot check.

Looking at the renders caught three defects no contrast test could see:

1. The composer card fill was `.fill(.white)` — a bare literal my first sweep's
   pattern missed. It rendered as a white slab on the dark shell.
2. `BrandWordmark` is a fixed-color SVG; it stayed near-black on the dark
   canvas. Now drawn as a template image so it takes the text token.
3. `MessageBubbleView` and `TranscriptView` used bare `.foregroundStyle(.white)`
   on emphasis fills — same missed pattern, and the message bubble is the most
   repeated surface in the app.

**Light-mode drift, bounded.** The wordmark change moved 31 light references.
Each was diffed against its `HEAD` version: every difference is max channel
delta ≤ 11 (pure black → the design system's `0x0C0C0B`) inside a
wordmark-sized box, with no layout shift and no size change.

## Not changed, deliberately

**Inline reference links stay system blue.** Measured rather than assumed: they
adapt on their own (`#2765D6` light → `#327DED` dark) and clear 4.65:1 on the
dark canvas. Off-palette, but that is a pre-existing light-mode design choice —
changing it is a design decision, not a dark-mode fix.

**No light/dark toggle.** The app follows system appearance. A manual override
is a separate feature.

**`SplashView`'s black shadow** stays black; a shadow is not a surface.

## For the owner to test

`continuous-settings-dark` re-recorded once with a sub-pixel difference in the
bottom text field — same layout and content, text rasterization only. It then
held byte-stable across three isolated runs and two full parallel runs, so it is
recorded as-is rather than being marked flaky.

Everything above is snapshot-rendered. Launching the real app in dark mode and
exercising hover states, focus rings, and the provider usage wheels against live
data is the one thing these references cannot stand in for.

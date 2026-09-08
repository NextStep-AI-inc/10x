# System Flyers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This document records future execution; the planning task does not authorize starting implementation.

**Goal:** Add reusable one-line glass-like notices above the composer, with readable overflow descriptions that scroll out and return.

**Architecture:** An app-owned `FlyerCenter` supplies scoped values to one native row/stack component. Pure marquee geometry uses measured overflow and elapsed time; the view supplies pause/lifecycle behavior. A synthetic catch-up fixture proves the component independently; the real producer attaches in Session Map Slice 3.

**Tech Stack:** Swift 6, macOS 15+, SwiftUI/AppKit/Foundation, existing design tokens, Swift Testing and native snapshot harness. No third-party marquee dependency.

**Spec:** [System flyers design](../specs/2026-09-07-system-flyers-design.md). Companion: [Session Map implementation plan](2026-09-07-session-map.md).

## Global Constraints

- Swift 6 / macOS 15+, native SwiftUI/AppKit/Foundation, no new dependency.
- One line per flyer, `.ultraThinMaterial`, 6 pt radius, 6 pt tone mark, 8 pt row gap, 10 pt horizontal padding, typical 32 pt height.
- At most 3 visible; newest nearest composer; replace identical scoped ID in place.
- Match composer maximum width 780 pt and 42 pt horizontal padding; minimum window 760×560 pt.
- Description-only overflow motion: 1.2 s holds, 40 pt/s travel, 10 pt conditional edge fades. Fitting text never animates.
- Hover/focus pauses in place; inactive/hidden content does not tick. Reduce Motion is static; Reduce Transparency uses the opaque elevated token.
- Catch-up first producer has no automatic expiry. No runtime recovery migration, no usage/context producer, no duplicate harness notices, no model calls in this component plan.
- Actual native Release-build recording watched through two complete cycles is required; keyframe tests and screenshots alone do not verify animation.
- New Swift files require `ruby scripts/generate_xcodeproj.rb` with pinned `xcodeproj 1.27.0`; never hand-edit the generated project.
- Fresh implementation worktree/draft PR. No merge/release/deployment; no touching other worktrees or app instances. Port 3000 is reserved.

## File ownership and integration order

| Task | Owned new files | Existing edits |
| --- | --- | --- |
| 1 | `App/Flyers/Flyer.swift`, `FlyerCenter.swift`; `Tests/TenXAppTests/FlyerCenterTests.swift` | None |
| 2 | `App/Flyers/MarqueeMotion.swift`, `MarqueeClock.swift`; matching test files | None |
| 3 | `App/Flyers/MarqueeTextView.swift`, `FlyerRowView.swift`, `FlyerStackView.swift`; `FlyerSnapshotTests.swift` | Reuse existing design tokens; no token redesign |
| 4 | `App/Flyers/FlyerFixtureScene.swift`; `FlyerIntegrationTests.swift` | `App/Application/AppModel.swift`, `App/Sessions/ActiveSessionView.swift`, `TranscriptView.swift`, `App/Shell/AppShellView.swift`, `TenXApp.swift`, shared `App/Application/UIFixtureRoute.swift` |

Only Task 4 owns shell integration. Coordinate it with Session Map Task 6 and Slice 3 and [harness notices #29](https://github.com/NextStep-AI-inc/10x/pull/29). If another task created `UIFixtureRoute`, extend it; do not duplicate a fixture application, transcript or composer. If delegating in the chosen execution workflow, use explicit owned paths and tell workers they are not alone; an out-of-fence need is skip-and-flag for that edit.

Do not execute real catch-up policy in this plan. Its producer is Task 13 of the map plan, which reuses these contracts after the independent motion gate passes. This lets the notice UI ship as one reviewable unit without waiting for model calls.

## Commands and native test setup

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /tmp/10x-system-flyers-derived \
  -only-testing:'TenXAppTests/flyerReplacementPreservesPositionAndScope()'
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' -derivedDataPath /tmp/10x-system-flyers-derived
```

Choose unused per-worktree output paths. Use exact Swift Testing function names from each task, including parentheses; verify a nonzero Swift Testing count. At the final gate run the full app suite plus Release compile. Run OmpKit tests only if its source changes (none planned). `docs/testing.md` covers snapshot promotion; its stale advice to hand-edit generated projects is overridden by AGENTS.md.

For native inspection, load `launching-local-builds`, `verifying-work`, `visual-ui` and `writing-ui`. The task-local `TENX_UI_FIXTURE=flyer-overflow` route seeds synthetic rows into the actual shell, uses isolated preferences/support data and a temporary project, and labels its window with fixture name and SHA. Normal launches do not see test content. Additional fixed fixture names: `flyer-fitting`, `flyer-stack`, `flyer-recovery`. Honor any earlier `UIFixtureRoute` implementation from Session Map.

## Task 1: Scoped flyer values and replacement behavior

**Interfaces:**

```swift
struct Flyer: Equatable, Sendable {
    enum Scope: Equatable, Hashable, Sendable { case global, session(String) }
    enum Tone: Equatable, Sendable { case information, attention, error }
    struct Action: Equatable, Sendable, Identifiable {
        let id: String
        let title: String
    }
    struct Key: Equatable, Hashable, Sendable {
        let scope: Scope
        let id: String
    }
    let id: String
    let scope: Scope
    let tone: Tone
    let title: String
    let detail: String
    let actions: [Action]
    let isDismissible: Bool
    let expiresAt: Date?
    var key: Key { Key(scope: scope, id: id) }
}
// @MainActor @Observable final class FlyerCenter:
// post(_ flyer: Flyer), remove(_ key: Flyer.Key), removeSession(_ key: String)
// visible(sessionKey: String?, at date: Date) -> [Flyer]
// expire(at date: Date)
```

- [ ] Create test helper `flyerFixture(id:scope:detail:expiresAt:) -> Flyer` with information tone, title **Catch up**, detail default **3 turns finished**, action `catch-up` / **Catch up**, dismissible true, expiry default nil. Add/run the red test:

```swift
@Test @MainActor func flyerReplacementPreservesPositionAndScope() {
    let center = FlyerCenter()
    let now = Date(timeIntervalSince1970: 1_000)
    center.post(flyerFixture(id: "a", scope: .session("one")))
    center.post(flyerFixture(id: "b", scope: .global))
    center.post(flyerFixture(id: "a", scope: .session("one"), detail: "4 turns finished"))
    center.post(flyerFixture(id: "a", scope: .session("two")))
    #expect(center.visible(sessionKey: "one", at: now).map(\.id) == ["a", "b"])
    #expect(center.visible(sessionKey: "one", at: now).first?.detail == "4 turns finished")
    #expect(center.visible(sessionKey: "two", at: now).map(\.id) == ["b", "a"])
}
```

- [ ] Implement insertion-ordered values keyed by `Flyer.Key`. On replacement assign the existing slot; on new value append; `visible` filters scope/expiry then takes the newest three **without reversing them**, so the bottom row is newest. Render with `ForEach(..., id: \.key)` to distinguish identical string IDs in different scopes.

```swift
if let index = flyers.firstIndex(where: { $0.key == flyer.key }) {
    flyers[index] = flyer
} else {
    flyers.append(flyer)
}
```

- [ ] Add/run `flyerVisibilityCapsAtThreeAndRevealsOlderRows()` and `flyerSessionRemovalPreservesGlobalRows()`. Cover empty, global-only, four rows, middle dismissal, expired value, expired replacement, and changing selected session. Expiry removes values through one next-expiry task while visible and recomputes on activation; no per-row forever timers. Removal/dismissal calls the supplied producer callback before removal when it needs persisted suppression; center itself never persists domain state.
- [ ] Generate the project and commit `feat(flyers): add scoped system notice values` after nonzero focused passes.

## Task 2: Pure return-scroll motion and pause clock

**Interfaces:** `MarqueeMotion.frame(elapsed: TimeInterval, overflow: CGFloat, isRightToLeft: Bool) -> MarqueeFrame`. Frame has offset CGFloat and booleans fadesLeading/fadesTrailing. `MarqueeClock` is a value with `elapsed(at:)`, `setPaused(_:at:)`, `reset(at:)`, using monotonic seconds supplied by caller; it owns no timer or Task.

- [ ] Add/run `marqueeHoldsTravelsReturnsAndWrapsContinuously()` before implementing the motion. For overflow 160 pt, travel is 4 s and cycle 10.4 s:

```swift
@Test func marqueeHoldsTravelsReturnsAndWrapsContinuously() {
    let samples: [(Double, CGFloat)] = [(0, 0), (1.2, 0), (3.2, -80),
        (5.2, -160), (6.0, -160), (8.4, -80), (10.4, 0)]
    for (time, expected) in samples {
        let frame = MarqueeMotion.frame(elapsed: time, overflow: 160, isRightToLeft: false)
        #expect(abs(frame.offset - expected) < 0.001)
    }
}
```

- [ ] Implement the four spec intervals in one function. Guard finite positive overflow and finite elapsed; invalid/zero/fitting inputs return zero without modulo division. Clamp elapsed at zero, take remainder by cycle and mirror the sign for RTL.

```swift
let hold = 1.2
let speed = 40.0
let distance = Double(overflow)
let travel = distance / speed
let cycle = 2 * hold + 2 * travel
let t = max(0, elapsed).truncatingRemainder(dividingBy: cycle)
let position: Double
if t < hold { position = 0 }
else if t < hold + travel { position = -speed * (t - hold) }
else if t < 2 * hold + travel { position = -distance }
else { position = -distance + speed * (t - 2 * hold - travel) }
```

After guards, derive logical fades from `position < 0` and `position > -distance` with a small endpoint tolerance, and apply the direction sign only to the returned offset. This keeps the leading first character visible at start and the trailing last character visible at far hold.

- [ ] Add/run `marqueeFitAndInvalidGeometryStayStill()`, `marqueeRTLReversesDirection()`, and `marqueePauseResumesWithoutElapsedJump()`. Pause at elapsed 3.2, advance wall clock 20 s, assert elapsed and offset remain unchanged, resume and advance 1 s, require one second of movement. Repeated pause/activation events are idempotent. Model the pause clock as accumulated elapsed + optional running start, rather than subtracting arbitrary calendar dates.
- [ ] Add boundary assertions at every interval ±0.001 s and cycle wrap: finite bounded offset, no teleport, far endpoint reachable, correct fades. Reset returns to start on content/geometry change. Run focused tests and commit `feat(flyers): define deterministic overflow return motion`.

## Task 3: Native material row, measured description and accessible controls

**Interfaces:** `MarqueeTextView(text: String, isVisible: Bool, isPaused: Bool)` measures intrinsic text and viewport; environment controls Reduce Motion, layoutDirection and font. `FlyerRowView(flyer:onAction:onDismiss:)` sends value IDs through callbacks. `FlyerStackView(flyers:onAction:onDismiss:onHeightChange:)` is the only stack; `onAction` takes `Flyer.Key` and action ID. These views never mutate a session checkpoint.

- [ ] Add snapshots `flyer-fitting`, `flyer-overflow-start`, `flyer-three`, `flyer-long-title`, in light/dark; extend with Reduce Motion/Reduce Transparency. Use native `assertSnapshot`, plain test fixtures and fixed elapsed time for image determinism. Add function `flyerRowShowsActionsBesideOverflowDescription()` and run it red on the initial row.
- [ ] Build the row with stationary title/tone/actions and a clipped description viewport:

```swift
HStack(spacing: 8) {
    toneMark
    title
    descriptionViewport.frame(maxWidth: .infinity, alignment: .leading)
    actions
    dismissButton
}
.padding(.horizontal, 10)
.frame(minHeight: 32)
.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
```

The properties above are private computed views on `FlyerRowView`. Add the subtle separator-token edge. Under Reduce Transparency swap only the material for `TenXPalette.surfaceElevated`. Use existing interactive text color and GhostActionStyle; tone label/icon accompanies the colored mark. Catch-up title offers a shorter complete variant when the full title would leave less than 96 pt for detail; keep action targets usable and full text in accessibility.

- [ ] Measure the full single-line Text with the actual font and an independent viewport measurement; no character-count width estimate. `overflow = max(0, textWidth - viewportWidth)`. When it overflows, use a TimelineView schedule (maximum 30 fps initially) to evaluate `MarqueeMotion` from `MarqueeClock` and apply the offset; mask only the text slot with conditional 10 pt fades. Do not add implicit `.animation` to an offset already sampled in time.
- [ ] Pause on hover, keyboard focus, inactive scene or invisible row. Resume at accumulated elapsed. Re-measure/reset on changed text/font/width/direction; an identical replacement must keep the clock. Fitting/removed rows use no animation schedule. Add `marqueePresentationResetsOnTextOrWidthChange()` for the view-state key and verify it includes content/font/direction/viewport but not every flyer repost timestamp.
- [ ] Reduce Motion uses static text, full native help/VoiceOver label, and **Show details** through a context menu/accessibility action opening a stationary local popover. Mark measurement duplicates accessibility-hidden. Do not announce every frame or create a duplicate scrolling copy. Screen-reader navigation and actual action buttons must remain reachable while text animates.
- [ ] Inspect and promote each intended snapshot, run focused tests and commit `feat(flyers): render accessible glass notice rows`.

## Task 4: Composer overlay and real animation gate

**Interfaces:** Inject `FlyerCenter` from `AppModel` to shell/ActiveSessionView. Add `TranscriptView.bottomOverlayClearance: CGFloat = 0` and a corresponding stack height observation; default 0 preserves all callers. Native fixture route seeds the same center/row implementation and real shell, with no model.

- [ ] Add/run `flyerOverlayReservesTranscriptAndJumpClearance()` on a seeded shell containing a long last assistant message, three flyers and a multiline composer. Test that bottom padding and Jump to latest offset use measured stack height plus spacing; no hard-coded three-row reserve when fewer rows are present. Snapshot with runtime recovery and a pending question as well.
- [ ] Install the overlay at the transcript bottom, matched to composer max width/padding. Add clearance inside the scroll content so the last message can move above the glass; move Jump to latest above it. The stack uses only its row bounds for hit testing. Preserve `TranscriptViewportState` when stack/composer height changes, following only if the user was already following latest. Recovery remains between transcript and composer, with flyers anchored above it; never cover recovery or command-browser actions.
- [ ] Add fixed fixture routes `flyer-fitting`, `flyer-overflow`, `flyer-stack`, `flyer-recovery` through the shared route seam. Include synthetic actions that open the existing Map fixture when available, otherwise a callback counter in the fixture host; label this clearly as component-only verification. Real Catch up navigation waits for map Task 13. Test session/global replacement, dismissal and expiry by the actual buttons.
- [ ] Run full app tests and Release build. Confirm the isolated branch app process survives and its correct native window is visible before claiming it is available. Record provenance, and exercise minimum 760×560 and 1440×900 with Map docked when integrated, light/dark, Reduce Motion/Transparency, inactive app, keyboard/VoiceOver, growing composer, attachments, command browser and runtime recovery.
- [ ] **Record and watch the actual motion, not a browser recreation.** Use the native app recording surface available in the execution session; capture at least two cycles with overflow measured in the fixture. For 160 pt overflow the required two cycles total 20.8 s. A much longer message needs a longer recording; compute it from measured width, not an assumed fixed duration. Use this evidence checklist:

| Evidence | Pass criterion |
| --- | --- |
| Start hold | Leading text is readable and still for about 1.2 s; trailing fade only. |
| Outbound travel | Constant readable motion; text stays inside its viewport; action targets stay fixed. |
| Far hold | Last characters fully exposed for about 1.2 s; leading fade only. |
| Return and wrap | Continuous travel to original position, then hold; no jump or duplicate text. |
| Hover/focus pause | Pauses mid-travel; resumes at the same position without a jump. |
| Resize/content update | Restarts measured layout at the leading edge; no stale overshoot or clipped action. |
| Fit and lifecycle | Fitting description is still; removed/hidden/inactive rows do not tick. |
| Reduced motion/transparency | Static readable alternative and full-text access; opaque contrast where requested. |

- [ ] Save screenshots plus recording and reviewed timestamps to `docs/superpowers/evidence/<implementation-date>-system-flyers/README.md` with branch/SHA, actual frame sizes, elapsed motion, test counts, and exact skipped cells. If video capture/playback is unavailable, state the native motion gate is not verified and the blocker; unit keyframes cannot close it.
- [ ] Commit `feat(flyers): place system notices above the composer` plus reviewed evidence; update draft PR to match final diff. Report the working component and hand its API to map Task 13. Do not add unrequested producers, migrate runtime cards, merge or release. After a successful evidence gate, report rather than starting another unbounded polish pass.

## Completion checklist

- [ ] Scope/dedup/replacement/dismissal/expiry tested with globals and two sessions; visible order and three-row cap hold.
- [ ] Pure motion passes keyframes, fit, RTL, pause, content/width reset and endpoint continuity.
- [ ] Native row/stack visually verified in both appearances with actual typography/material and accessible full text.
- [ ] Composer/transcript integration leaves all controls and latest content reachable.
- [ ] At least two complete native cycles observed, including pause/resume and resize evidence.
- [ ] No model call, hidden-notice duplicate or unrequested warning producer added.
- [ ] Report Verified / Not verified / For you to test. Real catch-up producer is explicitly left to Session Map Task 13; no silent partial completion claim.

# Shared Bottom Signal Dock Design

- **Status:** Approved for implementation planning
- **Date:** 2026-09-28
- **Platform:** 10x for macOS 15+, SwiftUI

## Goal

Replace the centered bordered composer with a calmer, borderless prompt surface
attached to a persistent bottom line. The line reuses the splash screen's shape:
mostly straight, with a short smooth wave at the right. In the open session it
visualizes measured context use and the session's current activity. Elsewhere in
the post-setup workspace it signals aggregate background work. The center stays
visually open; small persistent controls sit below the line, while the editor,
attachments, menus, recovery, and transcript remain above it.

Success means a person can type and send without the line moving under their
keystrokes, can distinguish working from waiting for input or failure at a
glance, and can still use the existing message, tool, queue, model, provider,
and recovery interactions.

## Scope and decisions

- One dock owned by `AppShellView` spans the full workspace width on New
  Session, active session, Archived Sessions, Settings, and Providers routes.
  Setup and required provider onboarding keep their own layouts. The startup
  splash keeps its existing signal and is the geometry reference.
- The straight section extends across most of the width. Only the final
  approximately 175 points use the splash wave. The whole path can carry
  context, activity, and status, including the wave; it is not two independent
  bars.
- The active session owns the line when its screen is open. Its measured
  context use occupies the left fraction of the complete path. Session status
  uses the path from that endpoint to the right edge. Other routes have no
  context percentage and show aggregate managed-session activity instead.
- A fixed-height borderless editor occupies the center above the line. Its
  older text fades only at the top of its scrolling viewport. The bottom seam
  is the sharp, unchanged line; typing does not animate or fade the line.
- Model, thinking, measured context, and working timer are compact below-line
  data. Steer, Follow up, Send or Stop, and the existing queue count also live
  below the line. Larger attachments, project choices, flyouts, and recovery
  content rise above it.
- The existing right-aligned near-black user bubble, cyan corner tool card,
  assistant transcript layout, and `TurnActivityView` remain the transcript
  language. The dock does not create a new queue row or replace tool status.

## Layout

```text
Workspace / transcript / current route

                         attachments or flyout, when present
                         fixed borderless prompt viewport
                         older text fades at this top seam ↑
                         newest text sits near the line
─────────────────────────────────────────────────∿∿∿∿  one full-width path
model · thinking · context · timer     Steer · Follow up · Send    provider usage
```

The shell gives route content the space above the dock instead of drawing the
dock over the transcript. The floating rail ends above the line, including its
bottom Archived action. The line itself spans beneath the rail's horizontal
area and is not clipped to the transcript or editor width. The editor remains
centered within the route canvas; the line uses the shell width.

The prompt viewport is about 106 points high. Text is anchored toward its
bottom; long drafts scroll inside that fixed height. Once the text scrolls,
the upper roughly 24 points gain an alpha mask from transparent to opaque so
older lines disappear cleanly at the fixed top seam. The mask belongs only to
the editor content, not to the background or line. The editor has no card fill,
border, lift, or focus halo. Focus is visible through the caret and enabled
Send control.

Below-line content uses three flexible zones: session and model facts on the
left, message actions near the editor center, and provider usage on the right.
At constrained widths, low-priority facts can wrap or collapse, while Send,
Steer or Follow up, context value, and the status label remain readable. The
provider wheels retain their existing control and expanded panel; when their
group cannot fit below the line, the group moves above the line at the right
without covering the editor or shifting the line. Its expanded panel opens
upward. No provider limits or provider interaction are redesigned here.

On New Session the editor and project selection remain available, but there is
no session context percentage. On non-composer routes the editor and message
actions disappear; the line and compact workspace footer remain. The route
transition changes the dock's content without moving the line through the
center of the screen.

## Line meaning and precedence

Context is the latest measured `get_state.contextUsage` value, never a token
count invented from animation time or typed characters. Its colored length is
the same fraction of the complete line path, including the wavy end. If the
reading is unavailable, show `Context —` and no cyan fill. The line is a
display, not a button; a combined accessibility label reports context and
status in words.

Only one active-session status owns the remaining span at a time. Its
precedence is: **terminal failure > required input > retry > compaction >
near-limit warning > working > ready**. Queue presence, typing, and a single
failed tool are facts shown in their existing controls or cards, not
independent line takeovers.

| State | Line | Below-line label and nearby UI |
| --- | --- | --- |
| Opening | Near-black line with a restrained gray shimmer over the full path; no context fill yet. | `Opening` and `Context —`; editor unavailable until ready. |
| Ready / idle | Measured context in cyan; remainder still near-black. | `Ready`; empty Send disabled. |
| Typing | Exactly the ready line, without response to keystrokes. | Send enables when content is valid; long text gains the editor's top mask. |
| Working | Measured cyan context; near-black remainder with a subtle gray shimmer moving across all of that remainder. | `Working` and elapsed timer; Stop when the draft is empty, Send when content is staged. |
| Queued follow-up | Same line as the underlying working state. | Existing `n queued` count beside Steer and Follow up. |
| Required input | Amber status span, still rather than shimmering. | `Needs input`; existing inline approval or sheet remains the place to answer. |
| Retrying response | Amber status span with a restrained traveling highlight. | `Retrying`; existing retry annotation remains in the transcript. |
| Compacting | Right-to-left near-black sweep first covers the status span, then visually eats into the context fill. | `Compacting`; displayed percentage stays at its last measured value during the sweep. |
| Near context limit | Amber mark at the right with a visible marker at the true context endpoint. | `Near limit` and the exact measured percentage. |
| Failed response or unexpected process exit | Red status span, no shimmer. | Specific error or recovery view remains visible above the line. |
| Other workspace route, background work | Near-black full path with a restrained gray shimmer. | Aggregate count such as `2 working`; no context percentage. |
| Other workspace route, idle | Still near-black full path. | Neutral workspace status; no context percentage. |

User-initiated Stop settles to a neutral `Response stopped` label while the
stopped runtime awaits its existing Restart session action. It never turns the
line red or pretends the composer can send before restart. A failed tool card may have red corners;
the line remains Working if the session continues. A terminal retry failure
turns the active status red until the user begins another turn or recovers.

When context reaches 95% or higher, the footer says `Near limit` and an amber
status mark appears at the right. When less than about 80 points remain for a
status signal, that mark may paint over the last part of the cyan context
stroke. A small endpoint marker and the numeric label still identify the true
measured boundary. This exception keeps warnings and errors legible at 100%
without reserving a permanently separate status lane or shortening context.

## Motion and transitions

- Opening and Working use one low-contrast shimmer over the currently available
  activity path. It does not pulse the wave's amplitude, change line geometry,
  or travel under the editor as a typing effect. Idle and typing remain still.
- On send, the draft clears optimistically and Working begins immediately.
  The user bubble appears when the transcript receives the message event; it
  does not fly out of the editor. On dispatch failure, the draft and staged
  attachments return and the existing error presentation remains visible.
- Compaction is event-driven. On `auto_compaction_start`, a reverse sweep
  starts at the right edge and advances left. It slows toward a visual cap
  rather than claiming completion on a timer. Moving marks may continue within
  the covered span while waiting. No numeric pseudo-percentage is shown.
- On `auto_compaction_end`, the sweep finishes covering the line. The app
  requests a fresh measured context value. While waiting, the line stays
  covered and the label says `Refreshing context`. Once the reading arrives,
  the new cyan fill reveals from the left to its measured endpoint over about
  750 ms; the exact new number fades in. Working or Ready then resumes on the
  remainder. The fill does not jump from the old endpoint to the new one.
- If automatic compaction is aborted, the last measured context remains. A
  retryable error moves to Retry; a terminal error moves to failure. If its
  post-compaction reading fails, show `Context —` and keep the appropriate
  Working or Ready state; do not present the old percentage as current. A
  skipped compaction returns to the underlying state without a completion
  animation. Explicit manual compaction retains its existing authoritative
  history reload and recovery behavior when that reload or state read fails.
- Reduce Motion removes traveling shimmer and sweeping movement. State labels,
  exact context values, and color remain; a completed compaction switches to
  the measured result without an animated reveal.

## Composer and transcript behavior

The shared `ComposerView` keeps the current text, attachment, model, thinking,
project, keyboard, paste, drag, and send behavior. Plain Return sends and
modified Return inserts a newline. It focuses only when the current route can
accept typing and no blocking sheet or modal owns focus. Route changes and
session switches close an open flyout. New Session's local draft lifetime stays
as it is today; active-session drafts remain on their `SessionController`.

During streaming, Steer and Follow up remain visible and selectable below the
line. With an empty draft the primary action is Stop; with text or attachments
it is Send, preserving the current ability to steer or queue a follow-up.
Queue count is the small existing footer count, not a new transcript item.
The transcript keeps its normal near-bottom scrolling rule and `TurnActivityView`
for gaps between output. The line reports the turn's broad activity while tool
cards report each tool's specific lifecycle.

## Component and data flow

```text
OMP RPC event stream + get_state
  └─ TranscriptEventProcessor
       ├─ TranscriptReducer → TranscriptView (existing bubbles, cards, annotations)
       └─ selected control events → SessionController
                                  ├─ measured context, queue count, timer
                                  └─ transient compaction/retry/input/failure state

AppModel active route + SessionActivityRegistry total activity
  └─ AppShellView → shared workspace dock
                    ├─ route-specific ComposerView above line
                    ├─ one reusable signal path
                    └─ compact footer and provider usage controls
```

`AppShellView` owns the dock's placement and selects its active-session or
workspace presentation. `SessionController` owns only per-session facts and
short-lived event flags; a pure presentation mapping applies the priority
above. No second global session state store is introduced. The existing
`StartupSignalGeometry` supplies the path shape, while workspace colors and
motion remain separate from splash startup behavior.

Required input means a pending confirm/select request in the transcript or
input/editor sheet. Passive extension notifications, status text, and tool
events do not enter that state. Retry starts and ends with the corresponding
OMP events; a failed terminal retry leaves an error signal until the next turn
or recovery. A context refresh failure changes only context availability, not
the health of the session process.

Today `TranscriptEventProcessor` already forwards automatic compaction start
and end, but not retry start and end. `SessionController` already schedules a
bounded context-only `get_state` refresh on several event boundaries; its
general `refreshState` can still apply stale streaming state. `SessionActivityRegistry`
counts only generating sessions with a known provider ID. The implementation
must forward retry controls, reuse the existing context refresh path after
accepted sends and turn or compaction boundaries, and expose an aggregate
generating count independent of provider ID. Refreshes must be coalesced and
tied to the current session generation so an older reply cannot overwrite a
newer state. Context and queue refreshes must not roll back a newer optimistic
Working state when `get_state` briefly reports the prior turn. There is no
per-token context polling.

`ProviderUsageDockView` moves from offset-based shell overlay positioning into
the dock's trailing layout slot. Its wheels and expanded details retain their
current semantics. `RuntimeRecoveryView` stays above the dock. The floating
rail, transcript, and route content take the remaining height above the dock.

## Verification criteria for implementation

1. A production build renders the line across every post-setup route, with
   the editor only on New Session and active-session screens. The rail and
   provider wheels remain usable at regular and narrow window widths.
2. Type a multiline prompt, scroll it, paste and drop an image, change model
   and project, send, Steer, queue a Follow up, and Stop through the real UI.
   The editor stays fixed and only its top text seam fades.
3. Real or fixture-backed RPC events exercise opening, working, retry,
   required input, compaction start/end/abort, failed response, and unexpected
   process exit. Assert the line's precedence and exact displayed context.
4. A compaction completion with a delayed or missing `get_state` response
   never jumps or shows a stale percentage. The successful path reveals only
   the measured endpoint after the reverse sweep.
5. A failed tool that does not end the turn changes its tool card but leaves
   the line Working. A user Stop returns to neutral rather than error red.
6. Verify keyboard order, focus restoration, combined VoiceOver status, and
   Reduce Motion. Capture screenshots from the running built app for ready,
   working, near-full context, compaction, input, failure, and non-session
   routes.

## Out of scope

- Redesigning message bubbles, tool cards, provider usage data, setup, or the
  startup splash.
- Inventing a new queue transcript format or a numeric compaction progress
  percentage that OMP does not provide.
- Merging or deployment during design and planning. Product implementation
  begins only after the written plan and execution approach are approved.

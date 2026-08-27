# Chat Experience Polish Plan

**Goal:** Remove the interaction jank from the chat surface: flyouts that will not
dismiss, a turn you cannot stop or see progress on, prompts that cannot carry an
image, and a new session whose route never points at the session it created.

**Architecture:** No new subsystems. Every fix lands in the existing composer /
transcript / session-controller stack, plus one `images` field threaded through the
OmpKit `prompt` command. Flyout dismissal becomes one reusable AppKit-backed
modifier shared by both shelves rather than more per-view scrims.

**Tech Stack:** Swift 6.1, SwiftUI, Observation, Swift Testing, OmpKit RPC, macOS 15+

## Global Constraints

- OMP 18.0.4+ compatibility; no OMP change required. `prompt` already accepts
  `images?: ImageContent[]` (`docs/contracts/rpc-wire-contract.md` line 32).
- Reuse `GhostActionStyle`, `TenXPalette`, `TenXTypography`, `FlyoutRowBackground`,
  `TwoRectShelfShape`. No new visual language, no corner radii where the app uses
  square edges, no shadows.
- Every async mutation added to `SessionController` goes through the existing
  `currentPipelineContext()` / `isCurrent(_:)` generation guard.
- User-facing copy: functional disclosure. "Working…", never "Thinking…".
- After adding any `App/`, `Tests/`, or `OmpKit/` source file:
  `ruby scripts/generate_xcodeproj.rb` before `xcodebuild`.

## Workstreams

### A. Flyout dismissal
- [x] `DismissOnOutsideInteraction` modifier: local `NSEvent` monitor for
      `.leftMouseDown` / `.rightMouseDown`, hit-tested against an
      `NSViewRepresentable` anchor inside the flyout, plus
      `NSWindow.didResignKeyNotification`. Monitor is torn down with the view.
- [x] Apply to `ComposerSessionControlsView` (model) and the project shelf.
- [x] `ActiveSessionView` keeps `@State flyout` across session switches because the
      view identity is stable: reset on `controller.id` change.
- [x] Retire the ad-hoc scrims the modifier replaces.

### B. Turn feedback and control
- [x] Wire `SessionController.abort()`: the send button becomes Stop while streaming.
- [x] Re-entrancy guard on `sendPrompt()`; clear the draft optimistically and restore
      it if the RPC throws.
- [x] Working indicator in the transcript for the gap between `prompt` and the first
      assistant token, and for the new-session spawn.
- [x] Elapsed time on the indicator so a long turn reads as progress, not a hang.

### C. Attachments
- [x] `RpcCommand.prompt(message:images:streamingBehavior:)` carrying
      `{type:"image", data, mimeType}`; `CommandEncodingTests` covers the envelope.
- [x] `ComposerAttachment` + downscale/re-encode so one prompt line stays small.
- [x] Composer: attach button, drag and drop, paste. Thumbnail strip with removal.
- [x] Render image blocks in transcript messages as thumbnails instead of the
      "Image attachment" placeholder text.
- [x] Non-image drops degrade to a path reference in the message text.

### D. New-session routing
- [x] Rewrite the `new:<uuid>` placeholder route to the real session path once
      `openNew` lands, guarded on the controller still being active.
- [x] Reproduce the "opens another session" report against a headless `omp --mode rpc`
      before adding any second fix. Root cause found by inspection instead: the rail
      sorted by modification date while omp rewrites the open session file on every
      token, so rows resorted under the pointer.

### E. Polish sweep
- [x] Composer grows with its content up to a cap; placeholder copy.
- [x] Focus the composer when a session becomes ready and after a send.
- [x] Scroll-to-bottom affordance when the transcript is scrolled away from the end.
- [x] Model picker closes on model commit, stays open for effort / fast toggles.
- [x] Remove the inert `Local` control (it advertises a mode that does not exist).

### F. Found while verifying
- [x] omp's internal steering messages (`role: custom`, `display: false`) were being
      rendered as chat. Gated the way omp's own client gates them.
- [x] A model, thinking, mode, or compaction change appeared twice after
      reconciliation, once in place and once stranded at the bottom.

## Verification

- `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'`
- Snapshot coverage for the composer states that changed.
- Live drive of the real build for the interaction behaviors the harness cannot
  render (outside click, hover, drag and drop, paste).

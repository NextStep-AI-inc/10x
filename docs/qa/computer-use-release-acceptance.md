# Computer Use Release Acceptance

Date: 2026-09-07
Branch: `codex/computer-use-design`
Build SHA: `0ca8ea2`

Architecture under test: the `tenx-computer` daemon (ComputerKit) owns the
engine, session registry, MCP socket, and supervision event stream. Harnesses
(omp, Cursor, Claude Code, Codex) connect through the `tenx-computer mcp`
stdio shim. The 10x app connects as a supervision client and renders the menu
bar item, window overlays, and per-session chrome from the event stream.

This replaces the Agent Desktop acceptance pass (AeroSpace/Hammerspoon/
Background providers), which was deleted in Plan 2 Task 5.

## Automated checks

| Check | Evidence | Result |
|---|---|---|
| ComputerKit suite | `cd ComputerKit && swift test` — 98 tests, 0 failures | PASS |
| App suite | `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'` — TEST SUCCEEDED (165 tests) | PASS |
| Project generation | `ruby scripts/generate_xcodeproj.rb` byte-stable across runs | PASS |

## Live acceptance checklist

1. **Fresh state.** No daemon, no claims: menu bar icon absent.
   VERIFIED 2026-09-07 — app launched against an idle daemon showed no menu
   bar extra and no overlays.
2. **⇧⌘C in a 10x session.** Agent claims or launches a window. Header
   metadata item, rail badge, overlay frame + tag, menu bar listing.
   PARTIAL — overlay frame + tag and menu bar insertion verified live with a
   synthetic MCP session (labelled harness "acceptance"); header item and
   rail badge are unit- and snapshot-tested but need one live agent session
   for final sign-off.
3. **Non-interrupting.** User types into the controlled window while the
   agent works; header popover shows a fresh frame and the agent's status.
   PARTIAL — background input verified (daemon typed into the claimed probe
   window without focus theft; focus acquire/release wraps each `act`).
   Popover freshness needs a live agent session.
4. **Cursor dot.** The overlay cursor tracks agent actions.
   VERIFIED 2026-09-07 — cyan dot rendered at the last click point and moved
   with each `computer_act` click (screenshot evidence).
5. **Stop from the header popover.** Claims release, overlay vanishes, badge
   clears. PARTIAL — stop via the supervision socket verified end to end
   (windowReleased → sessionEnded → stopped; overlay removed within one poll
   interval, zero overlay pixels in post-stop capture). The popover path
   shares the same `stopComputerUse` call and is unit-tested; live click
   pending a real session.
6. **Cross-harness.** A Cursor session (config snippet from Settings) appears
   in the 10x menu bar under its harness; Stop from 10x kills its control.
   PARTIAL — a synthetic non-omp harness session appeared in the supervision
   stream with label and pid and was stoppable; menu bar grouping is
   unit-tested (`MenuBarPresentationTests`). A real Cursor MCP run is pending.
7. **Global shut-off.** Menu bar "Stop All Computer Use" and ⌃⌥⌘Esc each
   stop everything, all harnesses.
   PARTIAL — `stop_all` over the supervision socket verified (all claims
   released, overlays torn down). ⌃⌥⌘Esc not exercised live.
8. **CLI.** `tenx-computer selfcheck` passes; `stop-all` from a terminal
   works with no app running.
   VERIFIED 2026-09-07 — selfcheck: "input typed, capture 640x304px @2x".
   `stop-all` initially FAILED (fire-and-forget command swallowed; finding 1);
   re-verified after the fix: a held claim was released by terminal
   `stop-all` (zero claimed windows after), and a new session immediately
   claimed and typed into a window (finding 2 latch confirmed cleared).

## Findings from the 2026-09-07 live pass

Found by running the daemon + app against a synthetic MCP session driving a
probe window:

1. **Fire-and-forget supervision commands swallowed.** A client sending
   `{"role":"supervision"}` + `{"command":"stop_all"}` and closing
   immediately (exactly what `tenx-computer stop-all` does) lost the command:
   the ack write failed (EPIPE), the write-failure path removed the client
   before the read loop processed the buffered command, and the command line
   fell into the handshake branch, registering a phantom MCP session and
   leaking the fd. Fix: write failures now only `shutdown(SHUT_WR)`; the read
   loop remains the sole closer and drains buffered commands.
2. **Global shut-off latched forever.** `stopAllFlag` was never cleared, so
   every later session's engine work aborted with `aborted: shut-off` until
   the daemon was restarted. Fix: the latch clears when a new MCP session
   registers.
3. **MCP shim dropped in-flight responses on stdin EOF.**
   `runMCPFront` exited the moment stdin closed, before the daemon's
   responses were written to stdout. Fix: exit only after all pending
   requests are answered or the socket closes.
4. **Stale session state on daemon disconnect.** The app's supervision
   client kept sessions/frames when the socket dropped. Fix: disconnect
   clears sessions, frames, and last action; a reconnect rebuilds from the
   daemon's replay.
5. **Investigated, not reproducible:** a single `computer_act` type call
   appeared to insert its text twice into the probe field. The keyboard path
   has a single SkyLight delivery route and selfcheck asserts exact-match
   output; no second delivery path exists. Closed as not reproducible.

Fix commit: `0ca8ea2` — `fix(computer-use): daemon supervision, MCP stdin EOF, and disconnect cleanup`.
Findings 1 and 2 were re-verified live after the fix (terminal `stop-all`
releases claims; a post-shut-off session claims and types successfully).

## For the user to verify live

These need a real agent session and/or the physical desktop; everything else
is covered above or by the automated suites.

- In a 10x session: ⇧⌘C, watch the agent claim a window; confirm the header
  item, rail badge, and popover preview; type into the controlled window
  while the agent works.
- Stop from the header popover; confirm the overlay and badge clear.
- Add the Cursor/Claude Code/Codex config snippet from Settings → Computer
  Use, run a computer task there, and confirm the session appears in the 10x
  menu bar grouped under that harness; stop it from 10x.
- ⌃⌥⌘Esc global shut-off while any session is controlling.
- Menu bar "Stop All Computer Use", then start a fresh session and confirm
  computer use works again without restarting the daemon (finding 2).

# Computer Use Refinement — Design

**Status:** Pending review (design approved section-by-section during brainstorm)
**Date:** 2026-09-07
**Supersedes:** parts of `2026-08-25-computer-use-agent-desktop-design.md` — see "What changes from the prior spec."

Computer use becomes a first-party, harness-native utility: a single shared macOS engine exposed as a standard MCP server, usable by 10x sessions (via omp), Cursor, Codex, and Claude Code alike, with 10x providing live supervision UI — an on-window agent cursor, in-app indicators, and a menu bar control panel.

## Requirements (as decided)

1. **Non-interrupting shared control.** The agent works in a single window the user can steer and adjust live; user actions never stop the agent. The agent never steals focus — all input is delivered in the background.
2. **Any window, any app.** The agent can claim an existing window or launch any application (Codex-style).
3. **Visible agent cursor.** A persistent on-screen cursor shows what the agent is doing, Codex-like.
4. **Invokable by command**, with in-app indicators (top rail, side rail) and a live preview of what the model sees.
5. **Menu bar item** listing every computer-use session grouped by harness, with per-session open/stop and a global shut-off.
6. **Harness-native delivery.** The capability is a pre-installed MCP tool, usable from any MCP harness, exposing materials (preview screenshots) cleverly.
7. **Standard permission coverage.** Computer-use tool calls ride OMP's native approval modes (`always-ask` / `write` / `yolo`); bypass-style modes auto-approve. No bespoke consent flow.
8. **Multi-session.** Any number of sessions may drive windows at once; a window belongs to exactly one session at a time.

## Architecture

One Swift binary — `tenx-computer` — plays both roles: stdio MCP front (what harnesses spawn) and singleton daemon core (the registry every front proxies to).

```
                ┌──────────────────────────────────┐
                │  tenx-computer  (ONE binary,     │
                │   no runtime deps)               │
                │                                  │
                │  Engine: ScreenCaptureKit        │
                │          CGEvent (+PostToPid)    │
                │          AXUIElement             │
                │                                  │
                │  Daemon core: window claims,     │
                │  session registry, action event  │
                │  stream, screenshot store        │
                └───┬──────────────────────────┬───┘
                    │ stdio MCP                │ stdio MCP
        ┌───────────┴───┐              ┌───────┴────────┐
        │ omp (per 10x  │              │ Cursor / Codex │
        │ session)      │              │ / Claude Code  │
        └───────────────┘              └────────────────┘
                    │
                    │ Unix socket (private supervision channel)
                    ▼
        ┌────────────────────────┐
        │ 10x app                │
        │ menu bar · cursor      │
        │ overlay · rails ·      │
        │ global shut-off        │
        └────────────────────────┘
```

- **ComputerKit** — new SwiftPM package in the 10x repo (sibling of `OmpKit`) with executable target `tenx-computer`. Three layers: engine (capture/input/AX/windows), daemon core (registries, event stream, screenshot store), MCP front (JSON-RPC stdio).
- **Singleton:** first launch owns a Unix socket (`~/Library/Application Support/10x/computer.sock`); later launches proxy to it. Harnesses always see plain stdio MCP.
- **Harness labeling:** MCP `initialize.clientInfo` ("omp", "Cursor", "Codex", "Claude Code") labels each daemon session — this drives menu bar grouping.
- **10x ↔ daemon:** a private newline-JSON channel over the Unix socket (not MCP) carries the live event stream to 10x and supervision commands back.
- **10x sessions:** omp mounts `tenx-computer` as an MCP server; tools appear as `mcp__tenx_computer__*` and flow through the existing `tool_execution_*` events into the transcript.

### Lifecycle

1. User enables computer use on a session (⇧⌘C / brand menu / header item) → 10x spawns the daemon if absent → daemon marks the session active.
2. That session's omp mounts the MCP server → tools available, gated by the session's approval mode.
3. Agent calls a tool → daemon executes → action event emitted (overlay, rails, menu bar update live) → screenshots return as MCP image content (model and transcript both see them).
4. Stop: per-session stop releases that session's windows; global shut-off halts every session across every harness.

## Interaction model

- **Shared window, background input.** The agent acts on claimed windows via `CGEventPostToPid`; the window never needs focus and the user can type/click in it at any time without disturbing the agent. The prior spec's foreground-handoff machinery is dropped.
- **Claim or launch.** `computer_launch` starts any app (auto-claims its new window to the calling session); `computer_claim` takes over an existing window. Both are exec-level approvals — in `always-ask` mode the user approves each claim; in bypass-style modes everything is automatic.
- **Isolation providers shelved.** No AeroSpace/Hammerspoon Spaces, no Agent Desktop. The claimed window itself is the containment boundary.
- **V1 input is coordinate-based** (window-relative points, scale returned with each screenshot). AX element-tree targeting is the upgrade path, not V1.

## MCP surface

Seven tools. Read-side auto-approves except in `always-ask`; write-side rides exec-level approval.

| Tool | Level | Purpose |
|---|---|---|
| `computer_windows` | read | List windows: app, title, bounds, claimed-by |
| `computer_screenshot` | read | Capture a claimed window → MCP image content + dims/scale |
| `computer_status` | read | Set the agent-settable status segment of the window tag (see Overlay) |
| `computer_launch` | exec | Launch an app by name/bundle id; new window auto-claims to the caller |
| `computer_claim` | exec | Claim an existing window (the sensitive one) |
| `computer_release` | exec | Release a claim |
| `computer_act` | exec | Input at window-relative coordinates: `click` / `double_click` / `right_click` / `drag` / `scroll` / `type` / `key` |

**Materials exposure:**

- Screenshots return as standard MCP **image content** — every harness's model sees them inline; 10x renders them via the existing media tool card.
- MCP **resources**: `computer://window/{id}/screenshot` (latest capture) with resource-update notifications. omp supports injecting these into the conversation (`mcp.notifications`); harnesses that ignore resources lose nothing.

## Supervision channel (private, 10x ↔ daemon)

- **Events → 10x:** `session_started/ended` (harness label), `window_claimed/released` (bounds, app, title), `action` (window, kind, point), `screenshot_taken` (window, capture ref). Drives overlay, rails, menu bar.
- **Near-live preview frames:** the daemon pushes a fresh capture of the actively controlled window on every action, plus a ~1/s heartbeat while controlling. 10x needs no screen-recording grant of its own.
- **Commands 10x → daemon:** `stop_session`, `stop_all`. Window-frame tracking for overlays is 10x's own (`CGWindowList` polling while active); the daemon stays out of per-frame polling.
- **Dead man's switch:** a harness shim's stdio closing auto-releases that session's claims. No orphaned control.

## On-screen overlay (drawn by 10x, click-through)

- **Claimed window frame:** two-corner stroke (top-left + bottom-right — the `CornerCard` language), cyan `#00A7C4`, plus a tag.
- **Tag anatomy:** `B · Fix login flow — Running tests…`
  - **Identity segment** (`B · Fix login flow`): system-owned, never agent-settable. 10x sessions show rail letter + title (cross-references the side rail); external sessions show harness + workspace. This is the label used to open/stop the session, so it must be trustworthy.
  - **Status segment** (`— Running tests…`): agent-settable via `computer_status`, lighter weight, truncated. Fallback when unset: derived from the action stream ("Clicking", "Typing", "Reading screen") — generic but truthful.
  - Tag doubles as state: solid cyan while active, dimmed when idle, gone on release.
- **Agent cursor:** persistent cyan cursor that glides between action points, ripple on each click, labeled with the short form (rail letter, or harness name for external sessions).
- Overlay hides when the window is minimized or on another Space.

## In-app UX

- **Header (top rail):** the indicator joins the centered metadata row as a peer of branch/folder — `⎇ main · ▢ 10x · ➤ 2 windows` — mono 10, cyan when active, muted when off. No title-row buttons. Clicking opens the preview popover anchored beneath.
- **Side rail:** the computer badge sits on the tree marker itself (cyan dot + cursor glyph), surviving the collapsed 64pt rail where titles hide.
- **Preview popover — "Currently viewing":** leads with the active window's near-live capture (LIVE indicator); other claimed windows show latest captures below. Stop control lives here.
- **Invoke:** ⇧⌘C toggles computer use for the active session (hidden-shortcut pattern like ⌘K/⌘N), plus brand-menu item, plus the header item. First enable runs the setup flow (below).
- **Transcript:** computer calls render through the existing media tool card (adapted to `mcp__tenx_computer__*` names), screenshots included.

## Menu bar item

- New `MenuBarExtra` scene. Icon: cursor glyph + live session count (template monochrome — state lives in the panel).
- Panel groups sessions by harness (10X, CURSOR, CODEX, CLAUDE CODE), sorted by recency of last action.
- Rows: identity + agent-set status + controlled apps. 10x sessions get **Open** (jumps to the session in 10x); external sessions get **Stop** only.
- Footer: **Stop all computer use** — halts every session across every harness, releases all claims, dismisses all overlays.
- When 10x is not running there is no menu bar item; `tenx-computer stop-all` CLI covers Cursor-only scenarios.

## Setup & permissions

- Screen Recording + Accessibility grants belong to the `tenx-computer` binary (one grant covers every harness).
- The branch's setup section is repurposed: readiness check, System Settings deep links, and a harmless probe — now probing the daemon instead of a disposable omp.
- Daemon preflights `CGPreflightScreenCaptureAccess` + `AXIsProcessTrusted` at startup and reports on the supervision channel; tools return structured `permission_missing` errors.

## What changes from the prior spec (2026-08-25)

**Reused / reshaped:** setup & probe flow (repointed at the daemon binary), computer tool card + screenshot gallery (adapted to MCP names), session-header computer controls (reshaped into the metadata-row item), menu-bar Stop scaffolding (grown into the full panel), emergency hotkey (triggers `stop_all` while 10x runs), lease/registry concepts (moved into the daemon), probe-window pattern (becomes `selfcheck`).

**Shelved:** AeroSpace/Hammerspoon/Background isolation providers, Agent Desktop launcher/manifest, `agent_desktop` host tool, foreground-handoff card and `require-handoff` policy, the `set_computer_use` RPC path, and the one-computer-session-per-Mac limit.

**Unchanged:** OMP's built-in `computer` tool stays for OMP's own TUI users; 10x sessions use the MCP server instead.

## Error handling

- **Permissions missing** → preflight at daemon start + structured tool errors + setup flow in 10x.
- **Window closes / app crashes** → auto-release, overlay dismissed, `window_gone` from tools.
- **Claim race** → serialized; loser gets `already_claimed` naming the owner.
- **Daemon crash** → claims die with it (in-memory registry: no control without a registry); shims' stdio closes; 10x clears indicators; next enable respawns.
- **Session ends mid-control** → dead man's switch releases its windows.
- **Stubborn apps ignoring background input** → known ceiling; no auto-foreground in V1; the agent notices via its own screenshots and asks the user to focus the window.
- **Global shut-off** → aborts in-flight actions, releases everything, dismisses overlays.

## Testing

- **ComputerKit unit tests:** claim exclusivity, session registry + harness labeling, MCP JSON-RPC framing, tool-arg validation, event encoding. Engine sits behind a protocol so all of it runs headless.
- **`tenx-computer selfcheck`:** real-hardware check — probe window, type, screenshot, assert pixels changed. Fails on permission or OS-behavior regressions.
- **10x unit tests:** controller state machine, daemon-event → UI reducers, menu bar grouping/sorting, header metadata insertion. Snapshot tests (`ViewSnapshotTests` pattern) for header item, rail badge, MCP computer card, popover, panel.
- **Integration:** in-process fake daemon speaking the supervision protocol — UI tested without real screen control.
- **Acceptance:** extend `docs/qa/computer-use-release-acceptance.md` — enable, claim, watch overlay, steer mid-action, per-session stop, global shut-off with a Cursor session running.

## Open verifications for the plan phase

1. **Per-session MCP mount in omp:** `.mcp.json` works today but is per-project; confirm whether omp accepts a per-process MCP flag/env. Fallback: project config + process-lineage correlation to map daemon sessions to 10x sessions.
2. **MCP tool approval mapping in omp:** confirm MCP tools receive standard read/exec approval decisions under `always-ask` / `write` / `yolo`.
3. **Cursor MCP resources:** confirm Cursor's support for MCP resources/notifications; image content in tool results is the guaranteed baseline.

## Out of scope (V1)

- AX element-tree targeting (coordinate-based input only).
- Private-API (Skylight) input fallback for stubborn apps.
- Foreground control of any kind.
- One-click "Install into Cursor / Codex / Claude Code" config writers (distribution is a binary path in MCP config for now).
- iOS/visionOS, Windows/Linux engines.

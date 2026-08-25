# 10x — Native macOS Workspace for OMP

**Status:** Draft for review
**Date:** 2026-08-24
**Tested against:** omp 18.0.4 (`@oh-my-pi/pi-coding-agent`), RPC protocol v2

## Overview

10x is a native SwiftUI macOS app that turns the [oh-my-pi](https://github.com/can1357/oh-my-pi)
coding agent into a desktop workspace: browse and resume sessions, run live
streaming chats, and see every built-in tool call rendered natively. 10x does
not reimplement the agent — it speaks omp's documented RPC protocol
(`omp --mode rpc`, JSONL over stdio) and reads omp's documented session files.

10x is its own product. It borrows the NextStep design tokens (because they're
good), but carries no NextStep branding, naming, or product coupling. The
visual language is a Bauhaus experiment wearing those tokens.

## v1 scope

**In:** session browser, live chat with streaming, rendering coverage for every
built-in omp tool (omp executes; 10x renders), extension-UI dialogs (approvals
included), model/thinking/status display, abort/steer/follow-up.

**Out (v2+):** skills/MCP management, file explorer/preview, host-tool
registration, host-URI schemes, collab sessions, session branching UI,
login flows beyond surfacing `open_url`.

## Architecture

Two targets, one repo:

```
10x/
├── OmpKit/          # SwiftPM library, zero UI — built and tested first
│   ├── RpcClient    # actor: spawn, frame codec, correlation, event stream
│   ├── SessionProcessManager
│   └── SessionLibrary
├── App/             # SwiftUI app target "10x"
└── docs/
```

### OmpKit.RpcClient (the foundational unit — riskiest, built first)

- Spawns `omp --mode rpc` via `Foundation.Process`, owns stdin/stdout pipes.
- Frame codec: one JSON object per line out; inbound `ready` frame, then
  v2 negotiation (`negotiate_protocol`), `rpc_chunk` reassembly (1 MiB
  physical frames, 64 MiB reassembly cap, strict UTF-8, validate
  `chunkId`/`index`/`count`/`byteLength`, reject interleaved sequences).
- Request/response correlation by `id` (responses match on `id`, never on
  emission order — `bash` responses interleave).
- `AgentSessionEvent`s exposed as an `AsyncStream<Event>`.
- `prompt` ack ≠ completion: turns complete on `agent_end` with
  `isTerminal !== false`; local-only prompts complete via
  `agentInvoked: false` or `prompt_result`.
- Ported from the bundled Python reference (`python/omp-rpc/src/omp_rpc/client.py`);
  its test cases are mirrored in Swift.

### OmpKit.SessionProcessManager

One child process per open live session (the lifecycle the RPC server is
designed around: one session, dispose on stdin close). **Each child is spawned
with cwd = the session's project directory** (decoded from the session bucket;
chosen by the user for new sessions) — sessions are bucketed by cwd and every
`bash`/`read`/`edit` executes relative to the child's cwd, so a wrong spawn
directory silently points tools at the wrong workspace. Terminate on tab close.
Crash → visible banner with relaunch button; never silent respawn mid-turn.

### OmpKit.SessionLibrary

Browsing needs no process. Scans
`~/.omp/agent/sessions/<encoded-cwd>/<timestamp>_<sessionId>.jsonl`
(documented in omp's session.md), parses headers only for list metadata
(title, cwd, timestamps), watches the tree with DispatchSource/FSEvents.
Full transcripts for closed sessions are read from the JSONL entry tree
(`id`/`parentId` + leaf pointer semantics).

### App

`NavigationSplitView`: sidebar (projects → sessions, live-updating), detail
(transcript + composer + status bar). Status bar shows model, thinking level,
context %, streaming state, tokens/sec from `get_state` and
`session_info_update`/`config_update` frames.

## Data flow

Open session → spawn child → `switch_session` to its JSONL path →
`get_state` + `get_messages_page` (paged; handle `session_busy` and
`stale_cursor` by falling back to the legacy snapshot, mirroring the
reference clients) → subscribe events → composer sends `prompt`
(`streamingBehavior: "steer" | "followUp"` required while streaming; abort
button sends `abort`) → `message_update` deltas and `tool_execution_*`
events drive the transcript.

## Tool cards — the "all tools in v1" contract

Two-tier, mirroring upstream collab-web's own architecture (30 per-tool React
renderers + `generic.tsx` fallback):

1. **Generic card** (day one): renders any tool call — name, arguments,
   streamed output, running/success/error status, duration. Every tool is
   covered by this from the first build.
2. **Bespoke SwiftUI cards**, replacing generic per-tool in priority order:
   `read`, `bash`, `edit` (diff view), `write`, `grep`, `glob`,
   `task` (subagents), `todo`, `web_search`, `browser`, then the remaining
   built-ins (`ask`, `ast-edit`, `ast-grep`, `checkpoint`, `computer`,
   `debug`, `eval`, `generate_image`, `github`, `hub`, `inspect_image`,
   `learn`, `lsp`, `manage_skill`, `memory_edit`, `recall`, `reflect`,
   `retain`, `rewind`, `security_scan`, `tts`).
   `packages/collab-web/src/tool-render/tools/*.tsx` is the visual spec where
   one exists. Eight built-ins have **no upstream renderer** (`checkpoint`,
   `computer`, `learn`, `manage_skill`, `memory_edit`, `rewind`,
   `security_scan`, `tts`; collab-web's memory-recall/reflect/retain cover
   `recall`/`reflect`/`retain`) — those ship v1 on the generic card, with
   original bespoke designs as follow-ups.

A registry maps tool name → card view; unknown/custom/MCP tools fall through
to generic. This is what "all harness native tools built out" means for v1
ship: everything renders well generically, bespoke cards cover the tools seen
daily, and the registry makes adding the rest mechanical.

## Host duties (core loop, not a feature)

The app answers `extension_ui_request` frames natively:

| Method | Surface |
|---|---|
| `confirm` | alert sheet on the session window |
| `select` (+ `optionDetails`) | inline option card in the transcript (Cofounder-style), modal only if blocking |
| `input`, `editor` | text sheet |
| `notify` | macOS UserNotification (+ in-transcript notice) |
| `setStatus`, `setWidget` | session status bar area |
| `set_editor_text` | composer text replacement |
| `open_url` | open in default browser (login flows) |

Tool approvals arrive through this channel when `tools.approvalMode` isn't
`yolo`. Dialogs with timeouts resolve to protocol defaults — nothing
hard-hangs. Host-tool (`set_host_tools`) and host-URI registration: none in v1.

## Visual design — Bauhaus × NextStep tokens

Design language: Bauhaus. Geometry-first composition, flat unbordered color
planes, a strict grid, functional asymmetry, bold geometric type, no
gradients, no soft shadows, near-zero corner radius. Color is used
structurally (to mark zones and states), not decoratively.

Palette and type ramp come from the NextStep design tokens (vendored, see
below). Bauhaus's traditional red/yellow/blue triad is replaced by the
NextStep brand triad; neutrals and semantic states (success/warn/error) map
1:1 from the NextStep semantic tokens.

### Token sources (scanned 2026-08-24 across 8 NextStep repos)

Authority chain, per the repos' own declarations:

- **Light values + accessibility grades:** `NextStep-Platform/packages/design-tokens`
  (`@nextstep/design-tokens`) — WCAG 2.2 AA-hardened port of the LMS palette,
  contrast-verified on every build. Copy interactive/text accent grades from
  here (`orangeUi #c97116`, `orangeText #a05a00`, `greenUi #0ea472`,
  `redText #d8231b`, `borderInput #868584`).
- **Dark ramp:** `NextStep LMS/src/app/globals.css` — the only full dark token
  set (Platform is light-pinned). Warm charcoal, not neutral black.
- **Swift transcription pattern:** `NextStep-Workspace-iOS/NextStepWorkspace/DesignSystem/`
  (`WSPalette/WSType/WSRadius/WSSpacing.swift`) — token names and order kept
  diffable against the CSS sheet. 10x copies this pattern exactly.

Core palette (light / dark):

| Token | Light | Dark | Role in 10x |
|---|---|---|---|
| `bg` | `#f9f9f8` | `#1a1917` | window ground |
| `surface` | `#ffffff` | `#242220` | cards, transcript blocks |
| `elevated` | `#f4f3f2` | `#2c2a27` | sidebar, status bar |
| `muted` | `#f0efee` | `#2c2a27` | tool-card argument wells |
| `textPrimary` | `#111111` | `#f0efed` | |
| `textSecondary` | `#555555` | `#8a8681` | |
| `textMuted` | `#696969` | `#a1978c` | timestamps, meta |
| `border` / `borderStrong` | `#f0efee` / `#d1d0cf` | `#33312e` / `#4a4743` | Bauhaus rules use borderStrong |
| `orange` | `#f2a65a` | `#f2a65a` | signature hue — decorative fills only (graded ~2:1 on white) |
| `orangeUi` / `orangeText` | `#c97116` / `#a05a00` | `#f2a65a` | running state, active session, orange text (AA-graded) |
| `blue` | `#4b6bfb` | `#4b6bfb` | interactive, focus, links |
| `green` | `#10b981` | `#10b981` | tool success |
| `red` | `#e65c55` | `#e65c55` | errors, abort |
| `purple` | `#a855f7` | `#a855f7` | subagent identity |

The Bauhaus triad (red/yellow/blue) maps to orange/blue/red above: orange is
the structural accent (Bauhaus yellow's job), blue marks interaction, red is
reserved for error/abort. Purple marks subagents only.

Type: **Inter** (400/500/600) for UI, per the token sheet. Code and tool
output need a mono face — no NextStep mono token exists, so 10x adopts the
HQ system stack (`ui-monospace / SF Mono / Menlo`) and records it as a 10x
addition, not a NextStep value. Type scale follows the LMS composite tokens
(12–18px UI ramp).

Spacing: the NextStep base-4 scale (4/8/12/16/24/32/48/64) unchanged.

**Where the Bauhaus experiment deliberately diverges:** radius. The NextStep
scale (2–14px) is replaced by 0px everywhere except `full` for status dots.
Sharp corners, thick `borderStrong` rules as zone separators, flat unshadowed
planes. This divergence is the experiment; color/type/spacing stay faithful
to the tokens. Dark/light follows the macOS system appearance (the dark ramp
is the LMS class-based dark set).

**Token discipline:** all values live in one generated layer
(`App/Design/Tokens.swift` + asset catalog for light/dark pairs), vendored
one-time from the NextStep source with a provenance header naming the source
repo, file, and commit. Views never hardcode a color/radius/spacing value —
the token layer is the single altitude for fixes. 10x is not a NextStep
product; tokens are copied values, not a live dependency.

### Reference patterns (Mobbin)

- Session sidebar with per-session status: [Devin](https://mobbin.com/screens/18d1bd78-44e9-45b6-bd04-ac48dbf7244a)
- Collapsed tool-step chips in transcript ("Read File +1 more"): [LangChain Fleet](https://mobbin.com/screens/4dfdf26e-ce6f-4c06-a1e3-6015025fdd77), [Emergent](https://mobbin.com/screens/e123876d-56ef-4731-aa60-d8e6a4c05ec4)
- Per-step expandable checklist while agent works: [Lindy](https://mobbin.com/screens/9f4affd5-f387-4149-860e-95c83f9bbba5)
- Per-turn checkpoint/duration cards: [Google AI Studio](https://mobbin.com/screens/915541ca-412a-436f-8632-fb2e22c2bd71)
- Inline question/approval card with option list: [Cofounder](https://mobbin.com/screens/52d55c74-ed5e-4f4f-adbf-40715cb4bb66)
- Per-file diff cards with +N/−N chips: [Cursor](https://mobbin.com/screens/d744068a-1835-4c35-afa2-e560ccbe565d), side-by-side review: [Devin](https://mobbin.com/screens/e48cb198-fd26-4a92-b17a-a988aa5cbef8)
- Composer with model picker inline: [Cursor](https://mobbin.com/screens/798473c7-a541-496d-9e99-bf9b6a946d27)

These are pattern references for structure; all styling passes through the
Bauhaus + token layer above.

## Error handling

- Child crash/exit: banner in the session view + relaunch; transcript
  preserved (it's on disk).
- Malformed inbound frames: recoverable per protocol (`command: "parse"`);
  logged, surfaced in a debug drawer, never fatal.
- Paging: `session_busy`/`stale_cursor` → discard partial pages, legacy
  snapshot fallback.
- Strict UTF-8/chunk validation failures: visible error state, not silent drop.
- Version drift: on connect, compare `omp --version` to the pinned tested
  version (18.0.4); warn on newer major, never block. Wire contracts are
  versioned in `@oh-my-pi/pi-wire`; the ready frame's
  `supportedProtocolVersions` governs negotiation.

## Testing

- **Gate:** OmpKit ships with fixture-driven unit tests for the frame codec
  (ports of `python/omp-rpc/tests/test_client.py` cases: chunk reassembly,
  correlation, malformed frames) plus one integration smoke test against a
  real `omp --mode rpc` child (session-level commands need no model) —
  **before any UI work starts**.
- Tool cards: snapshot tests as bespoke views land.
- UI verification per house standard: screenshots of the real build.

## Dependencies

- One UI dependency: a Swift markdown renderer (MarkdownUI or equivalent).
- Everything else: Foundation, SwiftUI, AppKit bridges as needed.
- Requires `omp` on PATH (or a configurable binary path), Bun installed —
  10x does not bundle omp.

## Milestones

1. **OmpKit RPC client + tests** (gating)
2. Session library + browser UI
3. Live chat core: transcript, composer, streaming, abort/steer
4. Generic tool card + extension-UI dialogs (approvals)
5. Bespoke tool cards in priority order
6. Status bar, notifications, polish pass

## Decisions log

- SwiftUI over Tauri: user choice, accepts hand-rolled UI for native feel.
- Child-per-session over shared child: documented lifecycle, no switching
  state machine, concurrent sessions, crash isolation.
- First-party RPC over third-party (ompweb/omp-web) internals: versioned
  documented contract beats undocumented API drift.
- Repo name **10x**; no GitHub remote yet — created (private) when the first
  draft PR opens, unless directed otherwise.

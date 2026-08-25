# 10x — Native macOS Workspace for OMP

**Status:** Approved for implementation
**Date:** 2026-08-24
**Tested against:** OMP 18.0.4 (`@oh-my-pi/pi-coding-agent`), RPC protocol v2
**Platform:** macOS 15+, Swift 6.1, SwiftUI

## Product goal

10x is a native macOS workspace for OMP. It adopts the useful information
architecture of the Codex desktop app—projects containing sessions, a focused
agent transcript, a persistent composer, and native approvals—but gives that
structure its own graphic-modernist visual system.

10x does not reimplement the agent. `OmpKit` owns OMP RPC and session-file
integration; the app target presents that capability as a complete desktop
workflow.

The V1 must prove this loop end to end:

1. Locate OMP and a project directory.
2. Find, open, or create a session from the floating rail.
3. Prompt the agent and stream its response.
4. Inspect tool activity and answer native approval/UI requests.
5. Steer, follow up, abort, stop, and resume without leaving the workspace.
6. Search prior work and configure OMP without opening a separate utility.

## V1 scope

### Included

- Native macOS shell and supplied 10x branding.
- Project-grouped session hierarchy in the expanding rail.
- New-session and active-session canvases.
- Streaming transcript, composer, abort, steer, and follow-up behavior.
- Generic native rendering for every OMP tool, plus priority bespoke cards.
- OMP extension UI requests, including approvals.
- Modal search across sessions, messages, and tool activity.
- Searchable native Settings workspace backed by `omp config`.
- First-launch OMP discovery, manual executable selection, and runtime recovery.
- Light appearance using the approved pure-white visual target.

### Excluded

- Codex-only destinations and product features: pull requests, plugins, sites,
  scheduled tasks, automations, and cloud account surfaces.
- Dedicated Projects, Sessions, or Search pages.
- Skills/MCP management, host-tool registration, host URI schemes, collaborative
  sessions, and session-branching UI.
- A file explorer or persistent source preview pane.
- A separate macOS Settings window.
- Dark appearance. It requires its own visual pass after the V1 light shell is
  proven rather than an automatic color inversion.

## Information architecture

The app has three persistent destinations and one primary hierarchy:

```text
Floating rail
├── New session
├── Search (modal)
├── Settings
└── Projects
    ├── 10x
    │   ├── Bauhaus macOS interface
    │   └── OMPKit lifecycle contracts
    └── NextStep LMS
        └── Review LMS navigation

Main canvas
├── New session
├── Active session
├── Settings document
└── Contextual setup, empty, approval, and recovery states
```

Projects and sessions are not separate pages. Search is not a page. These
choices keep project selection, session selection, and retrieval close to the
work instead of creating multiple index layers.

## Shell and navigation

### Floating rail

The shell uses a custom transparent rail, based on the interaction already
used in the NextStep LMS shell:

- Collapsed width: 64 points.
- Expanded width: 220 points.
- It floats directly on the white window canvas: no rail fill, material,
  divider, blur, or shadow.
- The wordmark is anchored at the top. A compact provider-allowance ledger may
  occupy the bottom when provider adapters have current quota data; there is no
  user profile control because usage belongs to each connected provider.
- New Session, Search, Settings, project markers, and session markers form one
  vertically centered stack. Every interactive item has a tooltip and
  accessibility label.
- The collapsed stack uses a typographic index for every project and session.
  Projects use a two-character workspace code. Numbered sessions sit beneath
  their project on a thin indented connector spine. The selected session uses
  cyan instead of adding a container.
- Hover or keyboard focus expands the same stack horizontally, keeping each
  marker in place while its label appears.
- The rail floats over the shared white canvas. Expanding it never creates a
  full-height panel, background, focus enclosure, or shift in the main canvas.
- Expansion uses a short native ease. Collapse waits 300 ms so crossing from
  the icon rail into a session row does not dismiss it.
- The expanded hierarchy is scrollable. “Show all projects” expands or scrolls
  this hierarchy; it never navigates to a Projects page.
- The selected project/session is indicated with cyan text plus selection
  semantics, not a status dot or a large filled tile.
- Each provider allowance is one compact unit: allowance name, percentage, and
  reset window share one line directly above a three-point usage bar. The UI
  supports any number of named limits per provider, including five-hour,
  weekly, Spark, and model-family limits. “Left” is not repeated beside the
  percentage. OMP does not expose account-wide provider quotas, so normal builds
  show this ledger only when provider-specific adapters supply real values.

The supplied `/Users/tannerpham/Downloads/10x.svg` is the rail wordmark. The
supplied `/Users/tannerpham/Documents/10x Logo.icon/` package is the canonical
application icon source. Implementation copies both into versioned app assets
so builds do not depend on those external paths.

### Keyboard routes

| Shortcut | Action |
|---|---|
| `⌘N` | New session |
| `⌘K` | Open modal search |
| `⌘,` | Open Settings |
| `⌘F` | Focus Settings search while in Settings |
| `Esc` | Close the top modal or cancel the active transient state |

## Main surfaces

### New session

The new-session canvas is intentionally sparse:

- A centered Chillax title asks what to build.
- A single isolated composer is the primary object.
- Project, execution mode, model, and thinking controls live as borderless
  ghost actions in the composer footer.
- The send control is the only filled black action.
- Recent sessions are not repeated below the composer; they already live in
  the rail.

If no project has been selected, the same canvas asks the user to choose a
folder. It does not open a multi-step onboarding flow.

### Active session

The active-session canvas has four zones:

1. **Session header**
   - Center: session title.
   - Subline: `branch | repo | worktree location`.
   - Omit the worktree segment when the session uses the project root.
   - Right: running/stopped state, model, thinking level, context percentage,
     overflow, and Stop. These are plain or ghost controls, not pills.
   - Stop and failure states use signal red. Running and interactive state use
     cyan. There are no decorative status dots.

2. **Transcript**
   - A centered readable column with symmetrical whitespace.
   - User messages use a near-black fill with white text.
   - Assistant text remains unboxed on white.
   - SF Mono is used for code, paths, diffs, commands, and tool output.
   - Timestamps and metadata stay quiet and never become gray accent panels.

3. **Tool and approval activity**
   - Tool cards are frameless: only the top-left and bottom-right corners receive
     short strokes.
   - No full card perimeter, gray fill, shadow, or decorative stripe.
   - Corner color communicates the state: cyan for active/complete interactive
     work, red for failure, yellow for attention.
   - Approvals use a near-black isolated surface. Preferred actions are colored
     ghost buttons: Run in cyan, Always Allow in yellow, Cancel neutral.

4. **Composer**
   - Centered and pinned near the bottom of the canvas.
   - A thin border is allowed because the composer requires component isolation.
   - Tight radius, no shadow.
   - During streaming it offers steer/follow-up behavior and queued-state text.
   - If the runtime stops, the composer preserves draft text but clearly becomes
     unavailable until the session restarts.

### Search modal

Search opens over the current canvas from the rail or `⌘K`:

- It never replaces the current session or creates a navigation destination.
- A thin near-black perimeter isolates the modal; there is no shadow.
- Results and preview share the modal in a master-detail arrangement.
- Filters cover all results, messages, tools, and project.
- Return opens the selected result. Escape closes and restores the untouched
  workspace.

### Settings workspace

Settings uses the approved **continuous form** organization:

- One scrollable document, not a category landing page and not a nested sidebar.
- Persistent global search at the top.
- Horizontal category anchors jump to sections in the same document.
- Search filters the same document in place and may match display name,
  description, or exact OMP key.
- Changes save immediately. Reset is available per setting and per section.
- Restart requirements are shown inline in yellow before the user leaves the
  relevant setting.

The stable categories are:

1. General
2. Appearance
3. Models
4. Agent
5. Tools
6. Subagents
7. Memory
8. Integrations
9. Safety
10. Advanced

The catalog is generated at runtime from `omp config list --json` (477 keys in
OMP 18.0.4). A category rule table maps known key prefixes and exceptions.
Unmapped keys remain reachable in Advanced; categorization never hides data.

Control selection follows OMP metadata:

| OMP type | Native control |
|---|---|
| `boolean` | Switch |
| `number` | Numeric field; stepper where a useful step is known |
| `enum` | Menu when allowed values are known; validated text otherwise |
| `string` | Text field; secure field for known secret keys |
| `array` | Add/remove list editor |
| `record` | Key/value editor with a raw JSON fallback |

Reads use `omp config list --json`; writes use `omp config set KEY VALUE...`;
resets use `omp config reset KEY`. The service also exposes `omp config path`
so the UI can show which configuration root is active.

### Setup and recovery

Setup and errors reuse the main canvas:

- **OMP found:** show version and resolved executable path, then select a project.
- **OMP missing:** show checked locations, Locate OMP, setup instructions, and
  Recheck. The rest of the shell remains visible.
- **Process exit:** preserve the transcript, show the exit status in an inline
  red-corner recovery card, and offer Restart Session and Open Log.
- Relaunch creates a new runtime against the saved session. The app never
  silently respawns during a turn.

## Visual system

The design is **graphic modernist**, not neobrutalist and not warm “soft
Bauhaus.” Symmetry, typography, and whitespace carry the composition. V1 has
no decorative background shapes, dots, stripes, or line art.

### Palette

| Token | Value | Role |
|---|---|---|
| Canvas | `#FFFFFF` | Entire V1 window background |
| Near black | `#0C0C0B` | Primary type, wordmark, user messages, structural actions |
| Cyan | `#00A7C4` | Running, selection, links, focus, preferred actions |
| Signal red | `#FF3B24` | Abort, failure, destructive actions |
| Yellow | `#FFC400` | Warnings, attention, expanded permission scope |
| Muted text | `#6B6B66` | Secondary copy and metadata only |
| Separator | `#E5E5E1` | Necessary rules and boundaries only |
| Hover neutral | `#F7F7F5` | Temporary hover feedback only, never an accent block |

Color is functional. State must also be communicated by text, icon, or control
label so color is never the only signal.

### Typography

- **Chillax:** major page titles, product moments, and selective accents only.
- **SF Pro:** shell, transcript, controls, labels, settings, and supporting copy.
- **SF Mono:** paths, branches, repositories, worktrees, commands, code, diffs,
  logs, and tool output.

The implementation bundles the required Chillax faces used by the app and
registers them in the target. Every Chillax use has the system sans-serif stack
as a fallback.

### Shape and elevation

- Actions are borderless by default.
- Preferred actions use accent-colored ghost text, not filled rounded pills.
- Borders appear only when component isolation or comprehension requires them:
  composer, modal, input, and selected native controls.
- Internal radii stay tight (generally 0–7 points). The system window keeps its
  native macOS shape.
- There are no application drop shadows.
- Gray is not a branded accent or large surface fill.

## Application architecture

The repository gains a native application target alongside the existing
package:

```text
10x/
├── OmpKit/                         # Existing tested Swift package
├── 10x.xcodeproj
├── App/
│   ├── Application/               # App entry, scene, app model
│   ├── Design/                    # Tokens, type, reusable visual primitives
│   ├── Shell/                     # Floating rail and canvas routing
│   ├── Sessions/                  # Library adapter, transcript, composer
│   ├── Search/                    # Search index and modal
│   ├── Settings/                  # Catalog, categorization, controls
│   ├── Tools/                     # Registry, generic and bespoke cards
│   ├── ExtensionUI/               # Native OMP UI requests
│   └── Resources/                 # Wordmark, icon source, fonts, assets
└── docs/
```

### App state

One `@MainActor` application model owns:

- selected project and session;
- rail expansion/focus state;
- modal presentation;
- session library snapshots;
- active process handles exposed by `SessionProcessManager`;
- settings catalog and write state;
- recoverable application-level errors.

Views receive narrow feature models or bindings rather than reaching through a
global singleton. OMP processes and filesystem work remain in `OmpKit` actors;
SwiftUI state changes remain on the main actor.

### OMP process and session flow

One child process is used per open live session:

1. Spawn `omp --mode rpc` with cwd equal to the session project directory.
2. Negotiate RPC protocol v2.
3. For an existing session, send `switch_session` to its JSONL path.
4. Load state and paged messages, using the existing fallback behavior for
   `session_busy` and `stale_cursor`.
5. Reduce `message_update`, `tool_execution_*`, and session-info events into the
   visible transcript.
6. Treat prompt acknowledgement as acknowledgement only; terminal `agent_end`
   or `prompt_result` completes a turn.
7. Close stdin and terminate the child when its live session is closed.

Session browsing does not require a child process. `SessionLibrary` reads the
documented JSONL session tree and publishes metadata snapshots.

### Search data

V1 search stays local and avoids a second persistence system. A cancellable
`SessionSearchService` scans the saved JSONL files exposed by `SessionLibrary`
and returns typed session, message, and tool matches. Each result carries its
project, session path, entry identity, result kind, and a short excerpt. Opening
a result selects that session and scrolls to the matching entry after the
transcript loads. A database-backed index is deferred until real session volume
proves the on-demand scan insufficient.

### Tool rendering

Tool coverage is registry-based:

1. A generic card renders every tool name, arguments, streamed output, status,
   duration, and error.
2. Bespoke cards replace the generic card for daily tools in this order:
   `read`, `bash`, `edit`, `write`, `grep`, `glob`, `task`, `todo`,
   `web_search`, and `browser`.
3. Unknown, custom, MCP, and remaining built-in tools continue through the
   generic renderer without losing information.

All cards use the same frameless corner primitive, so bespoke rendering changes
content hierarchy without forking visual treatment.

### OMP extension UI

The app answers `extension_ui_request` frames natively:

| Method | Surface |
|---|---|
| `confirm` | Inline approval card; sheet only when blocking context requires it |
| `select` with `optionDetails` | Inline option card |
| `input`, `editor` | Text sheet |
| `notify` | macOS notification plus transcript notice |
| `setStatus`, `setWidget` | Session header/status area |
| `set_editor_text` | Composer replacement |
| `open_url` | Default browser |

Timed requests resolve to protocol defaults so the session cannot hang
indefinitely.

## Accessibility and motion

- Full keyboard access for the rail, modal search, transcript actions, Settings,
  approvals, and composer.
- VoiceOver names include project, session, state, and keyboard shortcut where
  useful.
- Focus order follows the visible reading order after the rail expands.
- Reduced Motion disables rail interpolation and other nonessential transitions;
  the 300 ms collapse grace period remains as interaction protection.
- Minimum hit areas follow macOS guidance even when the visible icon is smaller.
- Cyan, red, and yellow always have a textual or symbolic companion.

## Error handling

- OMP version mismatch warns on a newer major but does not block when protocol
  negotiation succeeds.
- Malformed inbound frames are logged with sanitized context and surfaced as
  recoverable diagnostics.
- Strict UTF-8 or chunk validation failures become visible session errors; they
  are never silently dropped.
- Settings writes show the failing key and retain the prior displayed value.
- Secret setting values are never logged or echoed into error copy.
- Session paging failure discards partial pages before falling back to the legacy
  snapshot.

## Verification strategy

The OmpKit foundation is already complete and remains the gate for UI work.
The GUI implementation adds:

- unit coverage for settings categorization and control selection;
- reducer tests for streaming transcript and tool states;
- tests for rail expansion/collapse timing and route invariants;
- tests proving Search, Projects, and Sessions do not become standalone routes;
- snapshot coverage for the generic card, corner treatment, approval state,
  OMP-missing state, and runtime recovery;
- a real Release build launched as a macOS app;
- user-level QA: create a session, stream a response, approve a command, steer,
  abort, reopen the session, search it, change and reset a harmless setting, and
  verify the project/session rail hierarchy.

## Implementation slices

1. App target, assets, tokens, fonts, and shell primitives.
2. Floating rail with project/session hierarchy and modal search shell.
3. New-session and active-session core against OmpKit.
4. Transcript reducer, composer streaming behavior, and generic tool card.
5. Extension UI approvals and recovery states.
6. Continuous-form Settings workspace backed by `omp config`.
7. Priority bespoke tool cards, accessibility, and final Release-build QA.

## Decisions log

- SwiftUI over Tauri for native macOS behavior.
- Custom floating rail over `NavigationSplitView`; projects and sessions remain
  in the rail instead of becoming pages.
- Search modal over a search destination.
- Continuous Settings form over a category landing page, search-only command
  center, or expandable ledger.
- Pure white plus near-black/cyan/red/yellow over the rejected warm cream/orange
  and gray-accent directions.
- Chillax accents with SF Pro throughout the shell, not Chillax everywhere.
- No decorative background art in V1; the system can add restrained graphic
  texture later after the functional shell is stable.
- Child-per-session over a shared OMP child for documented lifecycle and crash
  isolation.
- First-party RPC contracts over undocumented third-party internals.
- No Git remote exists yet. A draft PR cannot be opened until a remote is added.

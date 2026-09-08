# Composer Command Browser

**Status:** Approved design, pending written-spec review

**Date:** 2026-08-31

**Platform:** macOS 15+, Swift 6.1, SwiftUI

**OMP contract:** 18.0.4+

## Goal

Typing `/` as the first non-whitespace character in either 10x composer opens a
keyboard-complete command browser. The browser discovers the commands, skills,
extensions, and prompt workflows that the current OMP runtime actually exposes.
It also provides native Model, Effort, and Fast controls without sending fake
chat messages.

The browser must support discovery, filtering, inspection, configuration,
argument entry, execution, cancellation, and recovery without a pointer. Pointer
input and VoiceOver expose the same behavior. Native controls and local-only
commands do not synthesize user or assistant turns; existing OMP-authored
metadata annotations remain unchanged.

## Approved product decisions

- `/` opens a large command browser attached above the composer.
- The trigger is active only when `/` is the first non-whitespace character.
  Slashes in prose, paths, and URLs do not open it.
- The browser combines six user-facing sources: App, Commands, Skills,
  Extensions, Prompts, and a conditional Other source for future OMP values.
- OMP remains authoritative for built-ins, skills, extensions, custom commands,
  MCP prompts, and file commands. 10x does not maintain a fallback copy.
- 10x owns exactly three static command descriptors:
  - `/model`: switch the starting or active model.
  - `/effort`: change the starting or active reasoning effort.
  - `/fast`: set Fast mode for the session.
- Selecting those three commands opens native controls immediately. Applying a
  value updates the existing composer controls, sends no prompt, and creates no
  synthetic user or assistant turn. Existing OMP-authored metadata annotations
  remain unchanged.
- Selecting a complete, no-argument OMP command runs it. A command with input or
  subcommands enters argument mode first. Skills and prompt workflows always
  enter argument mode so the user can add a task before sending.
- The root list has stable ordering. It does not use recents or favorites in v1.
- While a response is running, native controls apply to the next request and
  every OMP command or workflow is sent as Follow up. Slash text never becomes
  accidental steering input.
- New Session exposes App controls, Skills, and Prompts. Session Commands and
  Extensions remain discoverable as unavailable sources with an explanation,
  but their rows do not appear until a live session exists.
- If command discovery is unsupported or fails, App controls remain available
  and the browser states the limitation. No static OMP list is substituted.

## Source contract

OMP already supplies the required discovery contract through:

- `get_available_commands`, whose response carries a complete command snapshot;
- `available_commands_update`, emitted at startup and whenever metadata changes.

Each advertised command may include:

```text
name
aliases[]
description
input.hint
subcommands[] { name, description, usage }
source
```

OMP 18.0.4 currently defines these source values:

| OMP source | Browser source |
|---|---|
| `builtin` | Commands |
| `skill` | Skills |
| `extension` | Extensions |
| `custom` | Prompts |
| `mcp_prompt` | Prompts |
| `file` | Prompts |
| unknown future value | Other |

A live probe on 2026-08-31 confirmed built-ins including `model`, `fast`,
`tools`, `context`, `usage`, `compact`, `session`, `mcp`, `plugins`, `retry`,
and other session controls. The same response included skills, one extension,
custom commands, and a file command. Effort was not advertised as a slash
command, but 10x already has the typed `set_thinking_level` RPC and native
composer control required to provide `/effort` safely.

### Identity and collisions

The stable identity of an advertised row is `(raw source, canonical name)`. App
commands use the synthetic source `app`.

The App versions of `model`, `effort`, and `fast` replace any same-name OMP row
throughout the browser. Their native behavior is a strict UI superset and avoids
showing two rows with different outcomes. Other duplicate canonical names remain
separate and show their source label. Aliases affect matching but do not hide a
canonical row.

Malformed individual entries are dropped without discarding valid siblings.
Unknown sources remain visible under Other. A malformed top-level response or
transport failure moves the catalog to its explicit unavailable state.

## Visual structure

The command browser uses the existing square-edged composer and shelf language:
white or canvas fill, one-pixel near-black outer stroke, existing separator and
hover colors, cyan for active source accents, SF Pro for interface text, and SF
Mono for command names and usage.

The panel is an overlay attached to the composer's top edge. It does not resize
the transcript or push the composer. Its width follows the composer up to the
existing 780-point maximum. Its height is capped by available space and a
bounded design maximum; only the results column scrolls. The source rail and
detail pane remain fixed.

```text
┌──────────────────────────────────────────────────────────────────────┐
│ COMMANDS                         ↑↓ move  ⌃⇥ source  ↵ open  Esc close│
├──────────────┬──────────────────────────┬────────────────────────────┤
│ All       82 │ /model      Switch model │ APP CONTROL                │
│ App        3 │ /effort     Change effort│ /model                     │
│ Commands  36 │ /fast       Toggle Fast  │ Choose an available model. │
│ Skills    40 │ /compact    Compact      │                            │
│ Extensions 1 │ /tools      Show tools   │ Enter  Open model list     │
│ Prompts    2 │ ...                      │ Tab    Complete in prompt  │
└──────────────┴──────────────────────────┴────────────────────────────┘
┌──────────────────────────────────────────────────────────────────────┐
│ /|                                                                   │
│ model · effort                                               Send    │
└──────────────────────────────────────────────────────────────────────┘
```

The detail pane shows full description, aliases, source, input hint, and
subcommands for the highlighted row. It adds no pointer-only action. At the
760 by 560 minimum window, the three columns still fit. If future localization
or accessibility text sizing makes that impossible, the detail pane collapses
before the source rail or results list.

The panel uses the existing 160 ms shelf insertion and removal transition.
Reduce Motion uses an identity transition. Filtering and highlight movement do
not animate the transcript or resize the composer.

## Discovery and ranking

### Root state

An empty slash query uses fixed source order:

1. App controls, in the fixed order Model, Effort, Fast.
2. OMP Commands, alphabetical by canonical name.
3. Skills, alphabetical by canonical name.
4. Extensions, alphabetical by canonical name.
5. Prompts, alphabetical by canonical name.
6. Other, alphabetical by canonical name, only when needed.

The source rail follows `All, App, Commands, Skills, Extensions, Prompts,
Other`. A selected source shows only its rows while preserving alphabetical
order. Unavailable New Session sources remain navigable and display their
explanation instead of an empty list.

### Typed query

The query is the first slash token, excluding the leading slash and stopping at
the first whitespace. Matching is case-insensitive and ignores `:`, `_`, and
`-` separators for comparison. This makes `/adddir` find `/add-dir` and lets
`/brainstorming` find the canonical `/skill:brainstorming` without changing the
command sent to OMP.

Results are ranked deterministically:

1. exact canonical name or alias;
2. canonical or alias prefix;
3. word-boundary match inside the canonical name or alias;
4. other canonical-name or alias substring;
5. subcommand-name match;
6. description or usage match.

Equal scores use App, Commands, Skills, Extensions, Prompts, Other, then
alphabetical canonical name. Matching text is highlighted visually but the
accessible label remains a natural command name and description.

A small bounded edit-distance pass provides close results only when there is no
direct match. Close results are never preselected. Enter therefore submits the
typed command unchanged unless the user moves the highlight to a correction.
The no-match copy is `No commands match “/<query>”.` The close-result heading is
`Close results`.

No recents, usage ranking, pinning, or favorites are included in v1. Stable row
placement is more valuable than adaptive ordering until real usage data shows a
problem.

## Trigger and text editing

Typing or pasting opens the browser when the draft, after removing leading
whitespace, begins with `/`. Leading whitespace is allowed in the editor, but a
selected command is sent in canonical form without that whitespace so OMP sees
the slash at byte zero.

The browser does not open for:

- a slash after any non-whitespace character;
- a slash on a later line;
- a path, URL, or prose fragment that does not begin the message;
- a disabled composer in loading, stopped, or failed runtime state.

The editor remains the real text focus while the root browser is open. Typing,
pasting, selection replacement, and Backspace update presentation from the
current draft. Removing the leading slash closes the browser and leaves the
remaining text unchanged. Left and Right retain normal caret behavior.

Opening the browser closes the Project and Model shelves. Opening either shelf
closes the command browser. Only one composer flyout may be active.

## Keyboard and pointer model

The browser is fully usable without a pointer:

| Input | Root behavior |
|---|---|
| Type or paste | Update the slash query and results |
| Up / Down | Move one visible result |
| Home / End | Move to first / last visible result |
| Page Up / Page Down | Move by one visible result page |
| Control-Tab / Control-Shift-Tab | Cycle browser sources forward / backward |
| Command-1 through Command-7 | Select that visible rail index; ignore indices beyond the current rail |
| Enter | Activate the highlighted row, or submit typed text if none is highlighted |
| Tab | Complete the highlighted canonical name without running it |
| Escape | Back out one child level, or close root and preserve the draft |

Tab on a complete no-argument command writes the canonical name and closes the
browser, leaving the command staged. Tab on an item with input, subcommands, or
a prompt workflow writes the canonical name plus a space and enters argument
mode.

Clicking a source, result, or child option performs the same transition as its
keyboard equivalent. Single-clicking a row activates it. Hover affects only
the row background and never changes keyboard selection. Scrolling affects the
results list only. Clicking outside closes the entire browser and preserves the
draft; Escape from a child instead returns to the parent first.

## Selection and execution routes

### Route A: native App controls

`/model`, `/effort`, and `/fast` replace the result browser with a native child
inside the same panel.

- Model reuses extracted content from the existing searchable model flyout.
- Effort lists only values supported by the selected model, including Auto when
  the current control model allows it.
- Fast lists On, Off, and Status only when the selected model supports Fast.

Enter applies the highlighted value. Success clears only the slash draft,
preserves staged attachments, closes the browser, updates the existing footer
control, and restores prompt focus. Escape restores the original query and root
highlight. A failed mutation keeps the child open, restores the prior value,
shows one inline error, and announces it.

During a running response, App control changes apply to the next request. They
do not alter the request already in flight.

### Route B: complete OMP command

A highlighted OMP command with no input hint and no subcommands runs on Enter.
The browser sends the canonical slash text through OMP's existing `prompt`
contract. When idle it uses ordinary prompt behavior. While streaming it always
uses `streamingBehavior: followUp`, regardless of the visible Steer or Follow up
selection.

Local-only command completion uses the prompt response and `prompt_result`
event to return the runtime to idle without adding a user or assistant message.
If OMP reports that the agent was invoked, the normal transcript pipeline owns
the resulting turn.

### Route C: arguments, subcommands, skills, and prompts

A command with advertised subcommands replaces the result list with those
subcommands. Selecting a subcommand inserts its canonical text and usage hint.
A command with an input hint but no subcommands enters argument mode directly.
The editor remains the input surface; the detail pane shows the usage string.

Skills and prompt workflows always enter argument mode, even if OMP marks their
input as optional. The first Enter selects the workflow; the next Enter sends
the completed slash text. This prevents an exploratory selection from launching
a workflow before the user can add its task.

OMP retains authority for validation and confirmation. Missing or invalid
arguments may produce OMP's own usage response. Destructive or privileged
commands continue into OMP's existing extension UI or approval surface. The
browser neither bypasses nor duplicates those checks.

## Attachments

Native App controls never consume staged attachments.

For an OMP slash prompt, the command path sends staged images but keeps their
identities pending until OMP indicates whether the agent was invoked:

- agent invoked or queued: clear the exact staged attachment identities accepted
  with the command;
- local-only command: leave attachments staged;
- transport failure: restore the slash draft and leave attachments staged.

This avoids guessing from command source. A built-in may schedule agent work,
and an extension may stay local. OMP's result is the authority.

New Session skills and prompts use the existing initial-prompt path, including
the existing project selection and attachment gates.

## Availability by composer state

### New Session

The catalog comes from the existing warm no-session composer RPC client for the
selected project.

- App, Skills, and Prompts appear in All.
- Commands and Extensions remain selectable source destinations but show
  `Start a session to use OMP commands.` and no rows.
- App controls can apply before a project is selected.
- A skill or prompt can be composed without a project, but the existing Start
  session action remains disabled until a project is selected.

### Active and idle

The command model switches to the active `SessionController` catalog. All
advertised sources are available. Switching sessions swaps the source using the
same generation checks as session metadata, so a late update from the prior
session cannot replace the new catalog.

### Active and streaming

All App controls remain available with `Applies to the next request` in the
detail pane. Every OMP row shows `Runs after the current response` and executes
as Follow up.

### Loading, stopped, or failed

The existing disabled composer remains authoritative. Typing cannot open the
browser. Recovery UI behavior is unchanged.

### Discovery loading or unavailable

App controls render immediately. While discovery is in flight, other source
areas say `Loading session commands…`. If discovery is unsupported, malformed,
or disconnected, the browser says:

```text
Session commands unavailable
Model, Effort, and Fast remain available. Retry after the session reconnects.
```

Refresh occurs on project change, active-session attachment, foreground refresh,
runtime reconnection, and a new `available_commands_update`. No static list is
used.

## Live update behavior

Each OMP update is a complete replacement snapshot, not a patch. The command
model merges the three App descriptors after decoding and then reapplies current
session availability.

While the browser is open:

- retain selection by stable row identity;
- if the selected row disappears, select the nearest surviving row;
- if the active source becomes empty, show its honest empty state;
- if an active child command disappears, return to root and show
  `This command is no longer available.`;
- ignore updates from detached projects or sessions by generation;
- preserve the typed query and source selection across valid replacements.

## Accessibility

The browser is one named accessibility container. It announces:

- `Commands` when opened;
- active source and result count;
- highlighted command, description, source, position, and queued state;
- source changes, loading completion, apply success, and errors;
- expanded or parent state for child controls.

Every source and result is a separate accessible element. Full Keyboard Access
can traverse them even though ordinary typing focus remains in the editor.
VoiceOver adjustable actions mirror Up and Down selection. Escape and outside
dismissal always restore editor focus. The placeholder, footer labels, and
existing composer accessibility hints remain unchanged.

Long names and descriptions truncate visually in rows but remain complete in
the detail pane, tooltip, and accessibility value. The browser uses existing
palette contrast tokens and does not rely on color alone for source or queued
state.

## Architecture

```text
SwiftUI
├── ComposerView
│   ├── prompt focus and slash key forwarding
│   └── CommandBrowserView
│       ├── source rail
│       ├── result list
│       ├── detail pane
│       └── native child controls
└── extracted ModelPicker content shared with existing footer shelf
        |
        v
Presentation
├── ComposerCommandModel
│   ├── browser state machine
│   ├── attached catalog source
│   ├── query / source / highlight / child route
│   └── execution routing
├── CommandBrowserPresentation
│   └── pure matching, ordering, source mapping, and availability
└── ComposerControlsModel
    └── existing Model, Effort, and Fast authority
        |
        v
Session
├── ComposerCatalogService
│   └── warm no-session command snapshot and updates
├── SessionController
│   ├── active command snapshot and updates
│   └── slash prompt execution
└── TranscriptEventProcessor
    └── forwards command metadata as control traffic
        |
        v
OmpKit
├── AvailableSlashCommand and subcommand values
├── shared response / update decoder
├── existing get_available_commands request
└── existing RpcClient response and event streams
```

### OmpKit

Add a public, Sendable, Equatable command value with a forward-compatible source
representation. One decoder parses both the response payload and event payload.
The decoder never changes transport semantics and does not make unknown event
types fatal.

### Composer catalog service

Generalize the existing warm `OmpModelCatalogService` into the composer catalog
service rather than spawning another no-session OMP child. `AppModel` owns this
service lifecycle and injects the same actor into `ComposerControlsModel` and
`ComposerCommandModel`.

The service continues to load state and models and additionally requests
available commands. It consumes `available_commands_update` from its existing
client event stream and publishes complete command snapshots. Shutdown remains
single-owner and idempotent.

### ComposerCommandModel

This MainActor observable is the only owner of browser interaction state. Its
public interface is presentation values plus intent methods such as update
draft, move highlight, cycle source, activate, complete, back, and dismiss.
`ComposerView` does not implement ranking or execution decisions.

The model attaches either the warm composer catalog or the active controller's
catalog. It delegates App controls to `ComposerControlsModel`, active OMP
execution to `SessionController`, and New Session workflow submission to the
existing `AppModel.startNewSession` closure.

### SessionController and transcript pipeline

`TranscriptEventProcessor` adds `available_commands_update` to control traffic.
The transcript reducer continues to return no mutation for this event.

`SessionController` requests an initial command snapshot after opening and
publishes later complete updates. Its slash execution method reuses the existing
prompt send core but accepts explicit text, streaming policy, and delayed
attachment disposition. The ordinary prompt path remains unchanged.

The existing reducer already treats `prompt_result` as an immediate return to
idle. When the prompt response includes `agentInvoked`, the slash path clears
accepted attachment identities only when that value is true. If an older
response omits the field, the runtime may retain its normal optimistic streaming
behavior, but attachment identities remain pending: the first agent lifecycle
event clears them, while a local-only `prompt_result` preserves them.

### SwiftUI

`ComposerFlyout` gains the command browser as another mutually exclusive state.
Draft changes open or close it from the trigger parser. Slash-specific key
handling precedes the existing Return-to-send handler only while the browser is
open.

The existing model flyout body is extracted into reusable content rather than
forked. `/model`, the footer trigger, and future surfaces therefore share model
rows, search, loading, empty, mutation, and error behavior.

## Error handling

| Failure | Behavior |
|---|---|
| Catalog command unsupported | App-only browser with unavailable explanation |
| Malformed top-level catalog | App-only browser; retry on the next lifecycle trigger |
| Malformed command entry | Drop that entry; keep valid siblings |
| Warm catalog disconnect | Keep App controls; mark OMP sources unavailable |
| Active session disconnect | Browser closes when the composer becomes unavailable |
| Native mutation failure | Keep child open, restore prior value, show sanitized inline error |
| OMP transport failure | Restore slash draft, preserve attachments, show existing recovery/error path |
| Selected command removed | Return to root with `This command is no longer available.` |
| No query match | Honest no-match or unselected close results; never silently correct |

All new internal errors follow the repository's trace format. User-facing copy
remains short and strips internal command envelopes, absolute paths, and schema
names.

## Testing

### Pure behavior

- Decode every command field and retain an unknown source.
- Skip malformed siblings without invalidating the snapshot.
- Trigger table: empty, slash, leading whitespace, pasted command, later-line
  slash, URL, path, and ordinary prose.
- Stable root ordering and source counts.
- Exact, alias, prefix, separator-insensitive, namespace-suffix, subcommand,
  description, and close-result ranking.
- No direct match leaves selection empty until explicit navigation.
- Up, Down, Home, End, Page Up, Page Down, source cycling, direct source keys,
  Enter, Tab, Escape, and outside dismissal.
- Child cancellation restores original query, source, and row identity.
- New, idle, streaming, unavailable, and detached-session availability.
- Live add, replace, remove, removed-child, stale-generation, and source-empty
  updates.

### Integration

- Exact `get_available_commands` response and update decoding.
- Warm catalog reuses the existing no-session client and shuts down once.
- Active session initial request plus live replacement.
- `/model`, `/effort`, and `/fast` delegate to existing controls and never send
  a prompt.
- Idle slash command uses ordinary prompt behavior.
- Streaming slash command uses Follow up even when the visible mode is Steer.
- A local-only result returns idle without synthesizing a user or assistant turn.
- An agent-invoking workflow follows the ordinary transcript path.
- Attachments remain for native and local-only commands, clear for accepted
  agent work, and survive transport failure.
- Project and Model shelves are mutually exclusive with the command browser.
- Unsupported discovery never produces a static OMP fallback.

### Snapshots

At minimum and standard window sizes:

- root browser;
- filtered direct match;
- unselected close results;
- source-specific view;
- Model, Effort, and Fast child states;
- subcommand and free-input states;
- New Session unavailable source;
- streaming queued rows;
- loading, unavailable, no-match, removed-command, and mutation-error states;
- long command names and descriptions.

### Release-build user verification

Build the generated Xcode project in Release and drive the real application:

1. Invoke a New Session skill with a project and optional image.
2. Change Model, Effort, and Fast from slash children without creating transcript
   messages.
3. Run one local command and one command requiring arguments.
4. Queue a slash workflow while a response is running with Steer selected.
5. Complete the entire flow without pointer input.
6. Repeat activation, scrolling, selection, and dismissal with the pointer.
7. Run VoiceOver and Full Keyboard Access through root, source, result, child,
   error, and dismissal states.
8. Resize continuously from 760 by 560 through a large window and verify no
   clipping, collisions, or transcript relayout.
9. Repeat open and close with Reduce Motion enabled.
10. Add or reload a command source while the browser is open and verify stable
    selection or the specified removal recovery.

New Swift files go under `App/`, `OmpKit/Sources/`, or `Tests/`. Regenerate
`10x.xcodeproj` with `ruby scripts/generate_xcodeproj.rb`; never edit the project
file by hand.

## Acceptance criteria

- `/` at the start of a prompt opens the browser in New Session and active
  composers; unrelated slashes do not.
- The displayed non-App catalog matches current OMP metadata and updates live.
- A user can reach every source, result, detail, child option, execution path,
  and dismissal path using only the keyboard.
- Pointer and VoiceOver input expose equivalent actions.
- Model, Effort, and Fast reuse existing state and mutation behavior, send no
  prompt, and synthesize no user or assistant turn.
- OMP commands preserve canonical names, argument hints, subcommands, approval,
  and local-versus-agent lifecycle.
- Commands selected during streaming cannot become steering input.
- Attachments are removed only when accepted agent work will use them.
- Unsupported discovery yields an honest App-only browser, not stale commands.
- The panel is unclipped and stable at the minimum and larger window sizes.
- The Release-build verification flow passes with recorded visual evidence.

## Out of scope

- Direct invocation of model tools such as `read`, `bash`, or `edit` as slash
  commands. `/tools` may inspect them, but tools remain agent capabilities.
- A second app-maintained catalog of OMP built-ins.
- Favorites, pins, recency ranking, usage analytics, or command history.
- Editing, installing, enabling, or disabling skills and extensions from the
  browser itself.
- Rich argument completion for arbitrary paths, accounts, plugin names, or MCP
  servers unless OMP later advertises a typed completion contract.
- Multiple slash commands in one message or slash triggers on later lines.
- Changes to transcript card rendering, OMP approval surfaces, or settings.

# Rich Chat and OMP Tool Surfaces Design

**Status:** Approved for implementation
**Date:** 2026-08-26
**Builds on:** `docs/superpowers/specs/2026-08-24-chat-transcript-experience.md`

## Goal

Make 10x practical for day-to-day development by turning the transcript into a
readable semantic document and every OMP tool call into a compact, consistent,
expandable work record. Long prose, source, diffs, terminal output, structured
data, media, and references must stay inside the transcript width without
hiding useful detail.

This change improves the existing transcript system. It keeps the current
white document layout, unboxed assistant responses, black user messages, and
two-corner activity cards.

## Approved experience

The transcript is one continuous document. It does not split conversation and
activity into separate lanes, generate summaries, or automatically collapse
sections of an assistant response.

- Assistant responses use semantic typography and block structure.
- Tool calls retain the current two-corner card frame and become more compact
  when collapsed.
- Expanded tool bodies use purpose-built source, console, collection, media,
  progress, and structured-data surfaces.
- Code and diff surfaces wrap by default while preserving indentation and line
  structure. A per-surface control can turn wrapping off for exact horizontal
  inspection.
- File and web references appear where they are written. A duplicate reference
  tray is not rendered below assistant messages.
- Every canonical OMP tool has an explicit card mapping. Compatibility, MCP,
  extension, and unknown tools use bounded structured fallbacks rather than raw
  JSON walls.

## Architecture

### Normalize once

The existing `TranscriptEventProcessor` actor remains the transcript owner. The
flow becomes:

```text
live RPC or JSONL history
    -> existing transcript reduction and stable identity
    -> presentation normalization
    -> immutable TranscriptSnapshot
    -> SwiftUI composition only
```

Presentation normalization produces `Sendable`, `Equatable` values before a
snapshot reaches the main actor. Views do not parse Markdown, search strings
with regular expressions, or format arbitrary JSON in `body`.

The normalized message model is a `ContentDocument` with ordered blocks:

- paragraph and heading;
- nested ordered, unordered, and task lists;
- quote, divider, and table;
- fenced source block;
- media or an explicit unsupported-block placeholder.

Inline content preserves plain text, emphasis, strong text, strike-through,
inline code, web links, file references, and hard line breaks. The original
source remains available for selection and copying.

Tool results normalize into a `ToolResultEnvelope` containing ordered text,
image, resource, structured-detail, and error content. A tool-specific
presentation then extracts the compact summary, primary object, semantic body
data, and available actions. Structured details win when result text merely
duplicates them.

Normalization is deterministic, so the same payload has the same presentation
in live streaming and restored history. Message identity plus content revision,
and tool identity plus result revision, allow unchanged normalized values to be
reused while neighboring rows stream.

### Component boundary

`ToolCardRouter` canonicalizes the tool name and selects an explicit card. Each
tool card owns:

- field extraction;
- collapsed wording;
- semantic body order;
- tool-specific actions.

The shared `ToolCard` contract owns:

- the two-corner frame;
- disclosure and lifecycle styling;
- full-width containment and wrapping;
- common actions, keyboard order, and accessibility labels;
- empty and error treatment.

Cards compose these reusable surfaces:

- `ContentDocumentView`: prose, headings, lists, tables, quotes, links, and
  inline references.
- `SourceSurface`: syntax-highlighted source and diffs with line gutters,
  preserved indentation, wrapping, context folding, and copy actions.
- `ConsoleSurface`: command, standard output/error, exit state, ANSI-safe text,
  wrapping, follow state, and bounded disclosure.
- `CollectionSurface`: files, matches, diagnostics, symbols, URLs, todos, and
  labeled values.
- `MediaSurface`: images and screenshots with metadata and open/save actions.
- `ProgressSurface`: current stage, history, agent or job identity, counts,
  completion, and cancellation.
- `DataTreeSurface`: typed, depth-limited, recursively disclosed arguments and
  structured results.
- shared reference and error treatments used by every surface.

One component owns transcript width. Child surfaces must accept that width and
must not introduce nested vertical scrolling. Source and console surfaces wrap
by default; disabling wrap may introduce a local horizontal scroll view.

## Message rendering

Assistant content uses a 15-point body face with deliberate line spacing and a
clear heading scale. Paragraphs and list items size vertically, and adjacent
blocks use semantic spacing rather than one uniform gap. Lists preserve nesting
and continuation indentation. Tables retain column meaning and use a bounded
horizontal surface only when their minimum readable width exceeds the
transcript.

Fenced code uses `SourceSurface`. It shows a language label, line numbers when
there is more than one line, Copy, and Wrap/Scroll. A small native highlighter
handles comments, strings, numbers, and common language keywords. Unknown
languages remain readable monospaced source without guessed coloring.

Inline web links use the system browser. Inline file references reuse the
existing file resolution, preferred IDE, Finder, copying, accessibility, and
error behavior. Missing files remain visibly unavailable and copyable. The
inline occurrence is the only rendered occurrence unless the same reference is
semantically part of a tool header.

User messages retain their existing compact black surface. System and unknown
message blocks remain visible in a subdued technical style instead of being
dropped.

## Tool coverage contract

Every collapsed card states a specific verb, its primary object, the useful
count or outcome, lifecycle, and duration. The following canonical names must
route explicitly.

### Files and code

| Tool | Collapsed meaning | Expanded composition |
| --- | --- | --- |
| `read` | file, range/type, size | Source, collection, or media selected from the result type |
| `write` | path and lines/bytes written | Created source plus file actions |
| `edit` | path/files and additions/removals | Per-file syntax-aware diff and proposal state |
| `ast_grep` | pattern and match count | Grouped matches with source context |
| `ast_edit` | changed files and additions/removals | File collection plus per-file diffs |
| `grep` | query, matches, and files | Grouped references and matching source lines |
| `glob` | pattern and path count | File/folder collection |
| `lsp` | operation, target, and result count | Symbols, references, diagnostics, and source locations |
| `inspect_image` | file and dimensions | Media preview, metadata, and visual-analysis document |

### Execution, interaction, and services

| Tool | Collapsed meaning | Expanded composition |
| --- | --- | --- |
| `bash` | command, exit state, and duration | Command plus streaming console output |
| `eval` | language/input and outcome | Source input plus console or structured value |
| `debug` | operation, target, and result | Progress trace plus console, collection, or source evidence |
| `browser` | action and URL/title | Screenshot, readable content, links, and tab state |
| `computer` | gesture and application/target | Current frame and structured action details |
| `ask` | question count and waiting/answered state | Prompt, native controls, and persisted answer |
| `web_search` | query and source count | Ranked linked results with wrapped snippets |
| `github` | operation and repository/object | Objects, checks, diffs, logs, and native links |
| `security_scan` | target, status, and severity counts | Phase progress, grouped findings, and source evidence |

### Coordination and runtime

| Tool | Collapsed meaning | Expanded composition |
| --- | --- | --- |
| `task` | agent, objective, and status | Lifecycle, progress, final document, and produced references |
| `hub` | operation and worker/job | Worker progress, messages, and results |
| `todo` | completed and total count | Semantic checklist with active, complete, and blocked states |
| `checkpoint` | investigation goal | Goal, timestamp, and temporary-state marker |
| `rewind` | checkpoint and outcome | Retained findings and restored-state marker |
| `goal` | operation, objective, and status | Progress, token budget/usage, remaining, and completion report |
| `yield` | reason or wait target | Waiting state and bounded public context |
| `think` | private-reasoning activity only | No expandable chain-of-thought content |

### Memory and skills

| Tool | Collapsed meaning | Expanded composition |
| --- | --- | --- |
| `retain` | memory count and queued/stored state | Memories and source context |
| `recall` | query and result count | Ranked memories with identifiers and metadata |
| `reflect` | query and outcome | Synthesized content document |
| `memory_edit` | operation, memory ID, and status | Operation metadata and replacement content |
| `learn` | lesson and memory/skill outcome | Durable lesson plus optional skill source |
| `manage_skill` | operation, skill name, and status | Description, skill source, and file outcome |

Aliases route to the canonical card: `search` to `grep`, `find` to `glob`, and
`apply_patch` to `edit`. Resolution-device writes for `resolve`, `reject`, and
`propose` render as proposal resolution cards. `vibe_spawn`, `vibe_send`,
`vibe_wait`, `vibe_kill`, and `vibe_list` render as Hub variants while retaining
their historical names in metadata.

Names beginning with `mcp__` render server and tool identity, ordered typed
content blocks, resources, and a bounded structured-detail tree. Other
extension and future tool names render a labeled custom card using the same
contract. Unknown payloads never disappear and never render as an unbounded
plain JSON string.

## Lifecycle, empty, and error behavior

- Running cards update in place and start expanded. A user disclosure choice is
  never reset by later updates.
- Completed routine cards start collapsed. Completed edits, proposals, and
  results needing attention start expanded.
- Failed cards start expanded with a red corner, a plain failure summary, and
  the useful error content before arguments or technical details.
- A completed tool with no result says `Completed without output`.
- An empty search or recall names the empty result, such as `No matches` or
  `No memories found`, rather than showing a generic output label.
- Large bodies show a bounded complete-line preview and `Show all`; Copy always
  copies the complete value.
- Streaming output uses the same card and surface. It does not append temporary
  transcript rows or reset scroll/disclosure state.
- Malformed structured data falls back to a labeled, depth-limited data tree
  with Copy raw data. The UI logs a traceable sanitized diagnostic and does not
  crash.
- Unsupported message blocks become compact placeholders. Private reasoning is
  never exposed as chain-of-thought.

User-facing labels follow functional disclosure. Status uses text as well as
color. The UI does not use performed states such as `Thinking…`; the private
reasoning marker reads `Working` while active.

## Accessibility and interaction

- The collapsed header is a single keyboard target with at least a 32-point hit
  area and reports tool, object, lifecycle, and expanded/collapsed state.
- Expanded content follows source order. Disclosure comes first, then the
  primary object, status, duration, body, and actions.
- Text remains selectable. Copy, Open, Reveal, Wrap/Scroll, Show all, and result
  links have explicit labels.
- Status is never color-only. Diff markers, text labels, and accessibility
  values distinguish additions, removals, running, complete, and failure.
- Reduce Motion removes disclosure transitions. Existing near-bottom transcript
  following remains unchanged.

## Integration slices

The work merges into `main` in independently verified slices:

1. semantic content normalization, assistant rich text, inline references, and
   the shared source surface;
2. the compact two-corner contract, source/console/collection/data surfaces,
   and the high-value file, code, search, shell, and web cards;
3. exhaustive canonical tool routing, adapters, lifecycle/fallback states,
   narrow/wide visual polish, and final end-to-end verification.

Each slice must preserve live/history parity and leave the app buildable. A
slice does not merge if its targeted tests, production build, or relevant real
UI checks fail.

## Verification

### Model and parser tests

- Markdown blocks: headings, paragraphs, nested ordered/unordered/task lists,
  quotes, tables, dividers, fenced code, hard breaks, and unmatched fences.
- Inline runs: emphasis, inline code, web links, file references, punctuation,
  duplicate references, and long paths.
- Source highlighting and line modeling: known and unknown languages, comments,
  strings, numbers, indentation, empty lines, long lines, and wrap mode.
- History/live parity: equivalent payloads normalize to equal presentations and
  streaming revisions preserve stable identity.

### Tool tests

- Registry coverage asserts every one of the 32 canonical OMP names has an
  explicit mapping.
- Alias, resolution-device, Vibe, MCP, extension, and unknown routes are tested.
- Each tool family tests compact summary extraction, body composition, errors,
  empty results, partial updates, and malformed payload fallback.
- Disclosure tests prove defaults, user-choice persistence, bulk actions, and
  in-place phase changes.

### Visual and real-build checks

- Snapshot the semantic assistant document, inline references, wrapped source,
  unwrapped source, structured diff, streaming console, grouped search results,
  failed tool, MCP/custom fallback, and the full transcript at compact and wide
  window sizes.
- Build the Release configuration before handoff.
- Launch the built application, confirm it is visible, and drive a real session
  as a developer. Verify long prose, inline file references, code, a diff, a
  command with output, collapsed and expanded cards, an error, and window
  resizing.
- Acceptance requires no transcript-wide horizontal scrollbar, clipped text,
  duplicate reference tray, raw JSON wall, or disclosure reset.

## Out of scope

- Changing OMP's wire protocol or terminal renderers.
- Exposing private chain-of-thought.
- Adding a third-party Markdown or syntax-highlighting dependency.
- Generated summaries, tabs, split transcript lanes, or hidden assistant
  sections.
- Reworking the composer, session rail, or provider surfaces.

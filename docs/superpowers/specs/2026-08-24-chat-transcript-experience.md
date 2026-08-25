# 10x Chat Transcript Experience

**Status:** Approved by product direction
**Date:** 2026-08-24
**Parent spec:** `docs/superpowers/specs/2026-08-24-10x-omp-macos-gui-design.md`

## Goal

Make the active-session transcript the strongest basic agent experience in 10x:
quiet while work is routine, precise when details matter, and faithful to the
models, modes, agents, files, and tools that actually produced the work.

This is a transcript-system change, not a card restyle. The app must preserve
OMP's timeline metadata through history loading and live events, normalize it
once, and render every transcript surface from that normalized model.

## Design direction

The transcript remains a centered, white, border-light document. Assistant
responses are unboxed. User messages retain the near-black isolated surface.
Activity uses short cyan, red, or yellow corner strokes only when it needs a
boundary. Completed routine work collapses into one scan-friendly row; active,
failed, approval, and diff activity reveals the useful part immediately.

The hierarchy is:

```text
Thread start: date + time
├── User prompt
└── Agent response: model · mode/agent · time
    ├── response content
    ├── compact activity row(s)
    │   └── expanded command/output/diff/references on disclosure
    ├── model, mode, retry, or compaction annotation
    └── subagent result: agent · actual model · state
        └── progress/transcript on disclosure
```

No source event is surrounded with a gray panel by default. Color communicates
state and action, not decoration.

## Data model

### Typed session timeline

`OmpKit.SessionEntry` gains typed variants for metadata 10x needs to preserve:

- `mode_change`, including optional mode data without exposing system prompts.
- `session_init`, reduced to display-safe agent/model/read-only/advisor fields.
- `branch_summary` and the expanded compaction metadata needed for annotations.
- model role/fallback metadata and configured/effective thinking metadata.

Unknown entries remain lossless raw values. Existing session-file parsing stays
lenient and tree-aware.

### Transcript presentation

The app maps history and live RPC events into a presentation model with:

- stable identity;
- role and visible content;
- start timestamp;
- provider/model label;
- mode or agent attribution;
- final/streaming/error state;
- tool activity with compact summary and detailed payload;
- timeline annotations;
- subagent lifecycle/progress/result state.

The view never derives this semantic context independently from raw JSON.

### History and live reconciliation

When a session file is available, initial history loads from the resolved active
path in that file. This is authoritative for timestamps, model changes, mode
changes, compaction, and subagent session metadata. RPC message pagination stays
as the fallback for new or temporarily unavailable files.

Live message/tool events remain incremental. At message or turn boundaries, 10x
reloads the local session timeline and reconciles persisted metadata into the
same stable items. This avoids a new OMP protocol dependency while keeping mode
and model history accurate.

Subagent progress subscription is enabled when a session opens. Lifecycle and
progress events update one item per subagent rather than appending event spam.
Completed subagent output uses the parent task result when present; detailed
subagent messages may be fetched only when the user expands the item.

## Message rendering

Assistant content is rendered as blocks rather than one attributed text run:

- paragraphs, headings, lists, and quotes use SF Pro with readable wrapping;
- fenced code uses SF Mono, a subtle isolated surface, language label, and Copy;
- inline links are interactive and accessible;
- long unbroken strings and paths wrap or scroll inside their own code surface,
  never widening the transcript;
- error/aborted responses expose their terminal state in red metadata;
- streaming content uses a quiet cyan caret, not placeholder prose.

The response metadata line appears once at the start of an assistant response:
`GPT-5.6 · Plan · 11:42 PM`. Subagent responses use the agent name and actual
model. Provider is shown only when needed to disambiguate the model.

The thread start appears once above the first visible item, with absolute date
and time. Individual timestamps use local short time. Accessibility labels use
full dates and model/mode names.

## Activity disclosure

Every tool card shares one disclosure contract:

- **Collapsed:** disclosure glyph, verb, primary object, outcome, duration.
- **Expanded:** arguments or command, structured output, references, and errors.
- Completed read/search/write/bash/todo activity starts collapsed.
- Running tools, failed tools, approvals, and edits with a diff start expanded.
- User disclosure choice wins over later progress updates.
- `Collapse all` and `Expand active` are transcript-level ghost actions shown
  only when the transcript has enough activity to justify them.

Collapsed rows have a 32-point minimum hit target and keyboard disclosure. The
same stable row updates from running to complete without moving in the timeline.

## Diffs

Unified diffs are parsed into files, hunks, and lines. Expanded diff rendering
shows:

- file path and `+N −N` summary;
- hunk headers;
- old/new line numbers;
- unchanged context in near-black;
- additions in cyan and removals in signal red;
- long unchanged runs collapsed behind `Show N unchanged lines`;
- Copy patch and Open file ghost actions when a local path resolves.

The diff surface is horizontally scrollable and vertically bounded per file,
so it does not break transcript wrapping. It does not use green because cyan is
the product's positive/interactive color.

## References and annotations

Local paths, optional line suffixes, and web URLs are extracted into typed
references. A reference is shown as a compact borderless action with an icon,
short label, and optional line. Selecting a local reference opens it through
`NSWorkspace`; selecting a URL uses the system browser. Copy remains available
from the context menu. Missing local files stay copyable and visibly unavailable
rather than silently failing.

Timeline annotations cover model changes, mode changes, thinking changes,
compaction, retry/fallback, warnings, and errors. Routine annotations use a thin
rule and muted text. Warnings use yellow; errors use red. Repeated identical
model/thinking updates are coalesced.

## Empty, loading, and failure states

- Header-only thread: only the thread start and composer are visible.
- Loading history: stable skeleton lines in the transcript column.
- Failed history reconciliation: keep RPC messages visible and add one quiet
  warning annotation; do not replace the transcript with an error screen.
- Missing result: completed tool row reads `No output` and remains expandable.
- Very long output: bounded preview with `Show all`, preserving selection/copy.

## Accessibility and motion

- Every disclosure reports expanded/collapsed state and tool outcome.
- Status is communicated in text as well as color.
- Keyboard navigation reaches metadata actions, disclosures, references, and
  diff controls in reading order.
- Animation is limited to native disclosure and the existing transcript scroll;
  Reduce Motion removes content transitions.
- Minimum text size is 10 points for metadata and 12 points for primary content.

## Approaches considered

1. **Normalized timeline plus shared disclosure (selected).** Fixes lost history
   metadata once and gives every current/future activity type one interaction
   contract. Tradeoff: a deliberate model migration before visual polish.
2. **View-only card improvements.** Smaller diff, but cannot correctly show
   historical model/mode/subagent attribution and would keep raw JSON parsing
   duplicated across views.
3. **Expand OMP RPC first.** Could expose every entry remotely, but adds a second
   repository/protocol dependency when 10x already has safe local JSONL access.

## Acceptance criteria

- Existing and live assistant responses show their actual model and timestamp.
- Thread start date/time is visible once.
- Mode/model/thinking/retry/compaction changes appear in chronological order.
- Subagent rows show agent, actual model, status, and returned result.
- Routine completed tools are compact; running/error/diff/approval content is
  immediately useful; every activity item can expand and collapse.
- Unified diffs show structured hunks and old/new line numbers.
- Local and web references are actionable without breaking text wrapping.
- Long messages, paths, code, output, and diffs do not widen or clip the window.
- The real Release app is visually verified in compact, expanded, long-content,
  diff, error, and subagent states.


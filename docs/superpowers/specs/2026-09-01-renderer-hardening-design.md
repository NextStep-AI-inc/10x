# Renderer hardening design

Date: 2026-09-01
Status: Approved for implementation planning
Base: PR #18, `codex/fix-large-skill-freeze` at `d7a0f42`

## Goal

Prevent any single tool payload, assistant document, installation stream, media item, or activity indicator from making SwiftUI eagerly construct or repeatedly recompute an unbounded amount of work.

This is one follow-up PR stacked on PR #18. None of these changes belong in PR #18. After PR #18 merges, the follow-up PR can be retargeted to `main` without changing its implementation commits.

## Scope

The follow-up addresses all six independent risks recorded in the renderer saturation audit:

1. Large diffs that syntax-tokenize and render every changed line.
2. Tool media that repeatedly decodes base64 data and constructs images from computed view properties.
3. Provider activity wheels that drive SwiftUI at 30 frames per second.
4. Installer logs that publish and render every subprocess line individually.
5. Assistant Markdown structures that can create unbounded lists, tables, quotes, and source rows.
6. Existing `Show all` actions that remove the initial render bound in one click.

## Non-goals

- Truncating or discarding source content.
- Changing parser semantics or tool extraction contracts.
- Redesigning transcript or tool-card visual language.
- Adding a general-purpose virtualization framework.
- Optimizing provider networking, session persistence, or subprocess throughput.
- Folding these changes back into PR #18.

## Core invariant

No user action or incoming publication may cause an unbounded payload to enter the SwiftUI view tree in one update.

Every collection-like surface has:

- a finite initial render budget;
- a finite page increment;
- a visible count no larger than the current budget;
- a `Show more` action that advances exactly one page;
- a collapse action that returns to the initial budget where useful;
- a separate full-content operation such as Copy or Save when the surface already offers one.

The complete data remains in the presentation model. Pagination limits rendered views, not retained or copyable content.

## Shared progressive reveal policy

Introduce a small pure value, `ProgressiveReveal`, with no SwiftUI dependency. It stores the initial limit, page size, and current limit and provides:

- `visibleCount(total:)`
- `remainingCount(total:)`
- `canRevealMore(total:)`
- `revealNextPage(total:)`
- `collapse()`

The value clamps negative totals, never grows past the total, and never makes a one-step transition from a bounded preview to an arbitrary total. Surfaces choose their own initial and page limits because a source line, JSON child, and Markdown table row have different costs.

Buttons use concrete labels such as `Show 200 more lines` and include the remaining count when that improves clarity. The final page uses the smaller remainder. Existing full-copy actions continue to operate on the original payload.

## Data flow

```text
untrusted or unbounded payload
            |
            v
immutable presentation / retained full content
            |
            +---- media only ----> asynchronous one-time decode cache
            |
            v
pure budgeted render slice
            |
            v
bounded SwiftUI child tree
            |
       Show more
            |
            v
current budget + one finite page
```

## Surface designs

### 1. Diff rendering

`DiffView` will own an immutable render presentation prepared when the diff value enters the view. The presentation contains stable file, hunk, and line identities plus syntax spans for each line. `body` will no longer call `SourceTokenizer.spans`.

The view applies one budget across visible diff lines rather than one independent budget per hunk. This prevents a diff with many hunks or files from multiplying the ceiling. File and hunk headers appear only when at least one row from that section is in the current slice. Existing collapsed context runs remain collapsed and do not consume one view per hidden line.

Initial changed-line budget: 200 rows.
Page increment: 200 rows.

`Copy patch` always copies the complete raw diff. Horizontal scrolling and wrapping remain unchanged.

### 2. Tool-media decoding

`MediaItemView` will use a small loader with explicit loading, loaded, unavailable, and failed states. Base64 parsing, `Data` creation, file reads, and image decoding happen off the main actor. The decoded data and preview image are retained once for the immutable media item and reused by body evaluation and Save.

Changing the media identity cancels obsolete work and starts one new load. A completed or failed load is not repeated because an unrelated transcript row changes.

Remote HTTP images continue through `AsyncImage`; the new loader covers inline data and local files. Existing Open and Save behavior remains unchanged.

### 3. Provider activity animation

Remove the continuously evaluated 30 FPS `TimelineView` from provider wheels. The pulse becomes a native value animation between two visual states with a one-second ease-in-out cycle. It runs only when:

- `activeCount > 0`;
- Reduce Motion is disabled; and
- the scene is active.

When any condition becomes false, the view returns to its stable resting state. Reduce Motion retains the existing static outline. This preserves activity feedback without recomputing the view body from a wall-clock timeline.

### 4. Installer log publication

Move installer output management into a focused observable log buffer. The buffer retains the complete line sequence for diagnosis and copying, while publishing a display snapshot in batches rather than once per subprocess line.

Publication policy:

- flush at most once per 100 milliseconds while output is arriving;
- flush immediately when the stream completes or fails;
- keep the live display at the newest page by default;
- use `LazyVStack` for rendered lines;
- allow progressive reveal of older lines without exposing the full log in one action.

Initial visible tail: 200 lines.
Older-page increment: 200 lines.

Automatic scrolling happens once per published batch, not once per raw line. The full log remains available to a Copy action.

### 5. Assistant Markdown and source blocks

Add a pure depth-first render slicer for `ContentDocument`. The slicer counts render units across the complete document instead of applying unrelated limits inside every nested node. This prevents a large number of individually bounded nested lists from multiplying into an unbounded tree.

Render units are:

- one paragraph or heading;
- one list item;
- one quote child block;
- one table header or body row;
- one source line;
- one divider, image, or unsupported block.

The slicer returns a structure-preserving prefix and whether content remains. Ancestor list and quote containers are preserved when they contain visible descendants. A partially visible table retains its header. A partially visible source block retains its language and original line numbering.

Initial document budget: 160 render units.
Page increment: 160 render units.

One `Show more` control at the document boundary increases the global budget. Streaming additions do not automatically expand a budget the user previously left bounded.

### 6. Existing expansion controls

Replace Boolean `isShowingAll` state with `ProgressiveReveal` on:

- console lines: preserve the existing 10-line preview, then reveal 100 per page;
- tool collections: preserve the existing 8-item preview, then reveal 50 per page;
- source surfaces: preserve a smaller extractor-provided preview when present, then reveal 200 lines per page;
- JSON object and array children: 12 initial, 50 per page for each explicitly expanded node;
- long JSON scalar text: 2,000 characters initially, 4,000 per page;
- collapsed diff context: reveal at most 200 lines per click;
- installer history: 200-line pages as described above.

JSON remains depth-limited to six levels. Expanding one JSON node does not expand siblings or descendants. Collection and console Copy actions still use the complete payload.

## UI and accessibility

The follow-up preserves existing typography, colors, cards, and disclosure placement. New controls use the existing `GhostActionStyle`.

Every progressive control exposes:

- the quantity revealed by the next action;
- the quantity remaining when practical;
- an accessibility label that names the affected surface;
- a stable collapse action when the surface currently supports `Show less`.

Focus must remain on the activation button after a page is added. Pagination must not force the transcript to jump unless the user was already following the bottom.

## Error handling

Media decoding failures become a stable unavailable or error state and do not retry on every body evaluation. Cancellation caused by changing items is silent. Save failures keep the existing user-facing message and sanitized logger context.

Installer batching flushes pending output on normal completion, thrown failure, and task cancellation. No output already received is dropped.

Invalid pagination inputs are clamped by the pure policy. Production view code never accepts a zero or negative page size.

## Test strategy

### Pure behavior tests

- Progressive reveal never exposes more than one page per action.
- The last page clamps to the exact remaining count.
- Collapse returns to the initial budget.
- A global diff slice stays bounded across multiple files and hunks.
- A Markdown slice stays within its global budget across nested lists, quotes, tables, and code.
- Structure-preserving slices retain table headers, source numbering, and visible ancestors.
- JSON expansion remains paginated and depth-limited.
- Installer buffering retains every input line while publishing bounded snapshots.
- Media decoding performs one load per immutable identity and ignores cancelled results.
- Provider animation enablement follows activity, scene, and Reduce Motion state.

### UI verification

- Snapshot the initial and one-page-expanded states for representative large surfaces.
- Render oversized deterministic fixtures for diff, console, collection, JSON, Markdown, source, media, and installer logs.
- Confirm Copy and Save operate on complete content rather than the visible slice.
- Confirm automatic transcript following remains stable as a page is revealed.

### Release verification

- Run the full test suite.
- Build a signed Release artifact.
- Launch the exact artifact and verify it is visible.
- Exercise oversized local fixtures without a provider request.
- Sample CPU at rest and after each fixture settles.
- Capture a main-thread sample for any fixture that remains materially active.

## Acceptance criteria

1. No listed surface has a one-click path from a bounded preview to an arbitrary number of SwiftUI children.
2. Large diffs do not tokenize lines from `body` and reveal at most one finite page per action.
3. Inline and local tool media decode once per item off the main actor.
4. Provider wheels have no continuously evaluated `TimelineView`.
5. Installer output publishes in batches, renders lazily, and retains the complete log.
6. Assistant documents apply one global render-unit budget across nested content.
7. Full Copy and Save operations preserve the original payload.
8. Oversized regression fixtures, the full suite, and the signed Release build pass.
9. The follow-up PR contains these changes while PR #18 remains unchanged.

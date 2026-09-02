# Streaming Normalization Backpressure Design

## Context

Renderer hardening bounds the SwiftUI tree, syntax highlighting, accessibility text, and progressive disclosures after a tool or assistant message has been normalized. It does not bound the work required to create that normalized presentation.

A live sample of the renderer-hardening Release artifact during a large skill invocation showed sustained 107–184% CPU and RSS growth from roughly 746 MB to 763 MB in four seconds. The dominant background stack was:

`TranscriptEventProcessor.consume` → `TranscriptReducer.replaceInflightMessage` → `TranscriptMessageNormalizer.items` → `ToolContentExtractor.card`

Each `message_update` contains the current cumulative assistant message. The processor currently calls the reducer for every update, so the complete growing content is reparsed for every streamed chunk. The existing 50 ms coalescing interval only limits snapshot publication after this preprocessing has already occurred. A large cumulative payload therefore produces quadratic total parsing and allocation work.

## Goals

- Normalize cumulative `message_update` frames no more than once per existing 50 ms publication window.
- Preserve the newest complete cumulative payload without truncation.
- Keep final messages, lifecycle boundaries, control ordering, reconciliation, and explicit snapshot reads current.
- Preserve the existing maximum 20 Hz visible streaming cadence.
- Leave ordinary tool-event handling and the renderer-hardening limits unchanged.

## Non-goals

- Building an incremental JSON, Markdown, or tool-content parser.
- Changing provider protocols or assuming that deltas are independently replayable.
- Dropping final content, shortening persisted content, or adding another view-level truncation rule.
- Refactoring unrelated reducer or session-controller behavior.

## Chosen Approach

`TranscriptEventProcessor` will move newest-only coalescing ahead of `TranscriptReducer.consume` for cumulative `message_update` frames.

```text
message_update burst
        │
        ▼
newest pending frame ── replaces older pending frame
        │
        ├── 50 ms timer ──► reduce once ──► publish once
        │
        └── boundary ─────► reduce pending ──► reduce boundary ──► publish now
```

The actor will hold at most one pending `message_update`. A newer update for the same explicit message identity replaces it because those frames are canonical cumulative snapshots, not required standalone deltas. An update for a different message identity first drains the pending frame so distinct custom, skill, and assistant messages cannot replace one another. Updates without an explicit identity continue through the reducer directly. The existing publication timer will wake the processor, drain the newest pending frame through the reducer, and publish the resulting snapshot once.

This approach is preferred over reducer-level caching because comparing or hashing each complete payload still performs work proportional to payload size for every chunk. It is preferred over incremental parsing because tool boundaries and canonical provider snapshots make that substantially more complex and error-prone.

## Ordering and Snapshot Semantics

- `message_update`: when it has the same explicit message identity as the pending update, store it as the newest pending update and ensure the 50 ms timer is scheduled. Do not call the reducer immediately. Drain before accepting a different identity; reduce unidentified updates directly.
- Any subsequent transcript event that must retain event order: drain the pending update into the reducer first, then reduce the new event. Combine their mutations so an immediate boundary publishes both changes once.
- `message_end`, `turn_end`, terminal `agent_end`, and `prompt_result`: pending content is applied before the boundary is published or forwarded.
- `flush()`: drain pending content before deciding whether a snapshot is dirty.
- `currentSnapshot()`: drain pending content so explicit readers observe every frame accepted before the call. The mutation remains coalesced unless the caller explicitly flushes.
- `reconcile(...)`: drain pending content before applying history reconciliation.
- `stop()`: drain and publish pending content before finishing snapshot and control streams, so an unexpectedly ended provider stream does not discard its last cumulative update.
- Extension UI and provider-account control frames do not force preprocessing by themselves. Their consumers already request a current snapshot when transcript ordering matters.

The processor will use a private snapshot constructor that does not itself drain pending work. This prevents `publishNow()` from recursively re-entering the drain path.

## Mutation and Timer Rules

The existing mutation precedence remains:

1. `.immediate`
2. `.coalesced`
3. `.none`

Draining a pending message update and then reducing a boundary produces the stronger of their two mutations. Immediate boundaries cancel the scheduled timer and publish once. A timer wake drains the pending update before checking `isDirty`, which allows a queued message to become dirty only when its bounded processing slot arrives.

Timer generation checks continue to reject stale timer completions. At most one pending cumulative frame and one timer task are retained, so queue memory is constant with respect to chunk count.

## Testing

Tests will be deterministic and will not use wall-clock performance assertions.

- A burst of 1,000 cumulative updates followed by one manual flush reduces only the newest update once and publishes its complete content.
- A second update arriving while a timer is already scheduled replaces the first without creating another pending slot or timer.
- `message_end` applies pending content before the final boundary and publishes the final canonical payload once.
- Explicit `currentSnapshot()`, `flush()`, reconciliation, and stream shutdown each drain pending content according to the contracts above.
- Existing control-ordering, timer-generation, publication-rate, persistence, and transcript-reducer suites remain green.
- A saturation fixture uses a multi-megabyte cumulative skill/tool payload and asserts the finite normalization count and complete final retention.

The processor already exposes timer-generation helpers only in Debug builds. A matching Debug-only normalization counter will provide direct evidence that the expensive reducer path ran once, without adding release telemetry or timing-sensitive tests.

## Manual Verification

Build an optimized universal Release artifact, launch the exact artifact, invoke the local `using-superpowers` skill, and sample the process during and after the skill block appears. The app must remain interactive, CPU must return to idle after processing, and RSS must stop growing once the final cumulative message arrives.

## Success Criteria

- Large cumulative message bursts perform at most one full normalization per 50 ms window.
- Final rendered and copied skill/tool content remains byte-complete.
- No lifecycle or control event overtakes a pending message update.
- The full test suite, generated project reproducibility check, universal Release build, and real-app saturation check pass.

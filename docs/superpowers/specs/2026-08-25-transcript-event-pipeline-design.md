# Transcript Event Pipeline Design

**Date:** 2026-08-25
**Status:** Approved architecture
**Scope:** Live RPC event reduction, transcript publication, and streaming performance verification

## Problem

`SessionController` currently consumes every RPC frame on the main actor, mutates `TranscriptReducer`, assigns the reducer's complete item array, and invalidates SwiftUI. Because the controller and reducer share array storage after assignment, the next reducer mutation copies the complete transcript. During assistant streaming, OMP sends a complete growing message snapshot for each update, so this path repeats transcript copying, message parsing, Markdown conversion, reference extraction, layout, and bottom-follow animation work.

`TranscriptReducer` also stores every unsupported RPC event as an invisible `.rawEvent`. The wire contract requires unknown frame types to be skipped. Invisible rows accumulate for the session lifetime and make later copies and scans progressively larger.

The transport uses unbounded lossless streams. Raw RPC lines and lifecycle boundaries cannot be dropped safely. The design therefore drains the protocol off the main actor and bounds only complete UI snapshots, which are safe to replace.

## Goals

- Keep lossless RPC ingestion and transcript reduction off the main actor.
- Publish complete UI snapshots no more than 20 times per second during high-frequency updates.
- Flush message, tool, lifecycle, extension, and reconciliation boundaries immediately and in order.
- Retain no transcript row or payload for an unsupported event.
- Preserve history loading, live ordering, persistence reconciliation, extension UI, recovery, tool, subagent, and bottom-follow behavior.
- Prevent unchanged historical messages from repeating expensive content parsing during unrelated updates.
- Add deterministic burst tests and a reproducible Release streaming profile.

## Non-goals

- Dropping or reordering raw stdout lines.
- Changing the OMP wire protocol or accumulating provider deltas instead of accepting authoritative snapshots.
- Truncating tool output or replacing the session timeline parser.
- Changing transcript appearance, animation timing, or user-facing copy.

## Architecture

```text
RpcClient.events (lossless)
          │
          ▼
TranscriptEventProcessor actor
  ├── unsupported frame ───────────────► discard
  ├── metadata/extension/boundary ─────► controlEvents (lossless, filtered)
  └── TranscriptReducer
          │
          └── TranscriptSnapshot ──────► snapshots (newest 1, max 20 Hz)
                                                     │
                                                     ▼
                                          SessionController @MainActor
                                                     │
                                                     ▼
                                                   SwiftUI
```

`TranscriptEventProcessor` becomes the sole owner of `TranscriptReducer`. `SessionController` remains the main-actor coordinator for user commands, metadata presentation, extension responses, process recovery, and timeline reconciliation.

Each open or restarted session receives a new processor instance. Cancelling a session cancels its ingest, snapshot, control, and publication tasks. A replaced processor cannot publish into the controller for the next session.

## Processor Interfaces

The actor consumes `RpcClient.events` and exposes:

- `snapshots`: `AsyncStream<TranscriptSnapshot>` with `.bufferingNewest(1)`. A snapshot contains the complete `[TranscriptItem]` and `SessionRuntimeState`; replacing an unrendered snapshot preserves the latest semantic state.
- `controlEvents`: an unbounded but filtered `AsyncStream<RpcFrame>`. It carries only extension UI requests, session/config metadata changes, model changes, and reconciliation boundaries. Message and tool update traffic never enters this stream.
- Actor methods for history load, fallback message load, runtime changes, extension UI insertion/removal, reconciliation, notices, and a deterministic test-only flush.

The processor's long-running event loop executes on its actor, not the main actor. `SessionController` owns small main-actor tasks that install snapshots and handle the low-frequency control stream. `SessionTimelineLoader` remains the actor responsible for JSONL reconciliation reads.

## Mutation and Publication

`TranscriptReducer.consume` returns `TranscriptMutation`:

- `.none` for unsupported frames and malformed known frames that change no state.
- `.coalesced` for `message_update`, `tool_execution_update`, and `subagent_progress` replacements.
- `.immediate` for starts, ends, notices, annotations, runtime transitions, history loads, extension changes, and reconciliation.

For `.coalesced`, the processor schedules one publication after 50 ms if no publication is pending. Further frames mutate the processor's uniquely owned reducer array. This causes at most one copy-on-write cycle per UI snapshot instead of one per RPC frame.

For `.immediate`, the processor cancels the pending timer and publishes the latest complete state before forwarding a matching control boundary. A final message or tool result is therefore visible before persistence reconciliation runs. The 50 ms interval is a ceiling, not an added delay for final states.

Unsupported frames return `.none`. The `.rawEvent` case, its reconciliation retention rule, and its empty SwiftUI row are removed. Future visible protocol support requires an explicit reducer and view case.

## Controller Integration

`SessionController.finishOpening` creates the processor, loads persisted history or fallback messages through it, installs the initial snapshot, then starts event ingestion. `sendPrompt`, reconciliation, and extension UI operations call processor methods instead of mutating a main-actor reducer.

Metadata handling stays on the main actor, but only the following frames cross to it: `session_info_update`, `config_update`, `thinking_level_changed`, `model_changed`, extension UI requests, and message/turn/prompt/terminal-agent boundaries. Other transcript frames are fully handled by the processor.

Restart cancels all tasks and constructs a new processor before opening the new child process. Unexpected exit still updates controller recovery state immediately; no later snapshot from the stopped processor is accepted.

## Presentation Work

The assistant content subtree is wrapped in an equatable view keyed by message identity, visible text, and finality. Historical messages whose content did not change do not repeat `MessageContentParser`, `TranscriptReference`, or Markdown work when tool state, metadata, or another message changes.

The active assistant message may perform presentation work at the 20 Hz snapshot ceiling. Final rich text, references, selection, and accessibility remain visually and behaviorally identical to the current transcript.

## Failure Handling

- Processor cancellation cancels its publication timer and finishes its streams.
- A malformed known frame changes no reducer state and emits no snapshot.
- Unknown frames are skipped without logging payload content, preventing sensitive transcript data from entering diagnostics.
- Control events remain lossless after filtering; extension requests and reconciliation boundaries are never placed in the replaceable snapshot buffer.
- RPC termination continues through `SessionProcessManager.unexpectedExits`; draft preservation and recovery UI remain controller-owned.

## Verification

Deterministic tests cover:

- Ten thousand unsupported events leave transcript item count unchanged.
- A burst of message updates produces one coalesced snapshot when manually flushed.
- `message_end`, tool completion, and terminal agent state publish immediately.
- Extension UI and reconciliation control events remain ordered and lossless during a message burst.
- Restart cancellation prevents an older processor from updating the controller.
- Existing history/live reconciliation, tool, subagent, extension, and recovery tests remain green.
- Unchanged assistant content does not rebuild its presentation subtree.

A synthetic fake RPC server emits 1,000 realistic growing `message_update` snapshots followed by `message_end`. The baseline branch and fixed branch use the same payload, cadence, Release build, and Instruments templates.

Acceptance thresholds on the profiling machine are:

- No more than 20 non-boundary transcript snapshots per second reach the main actor.
- The final message, runtime state, and control events are delivered without loss or reordering.
- Ten thousand unsupported frames add zero transcript rows and produce no sustained memory growth after the burst.
- The app remains interactive during the 1,000-update stream.
- Idle returns to at or below 1% CPU after the stream settles.
- Existing app tests, OmpKit tests, snapshots, and the Release build pass.

Binary Instruments traces remain local. The repository records the workload generator, commands, environment, and before/after results.

## Rollout and Boundary

This change does not alter the database, JSONL, or RPC formats. If post-fix profiling shows the background processor itself cannot drain the lossless raw streams, protocol-aware transport backpressure will be a separate design. Bounding or dropping raw lines in this change could corrupt command responses or lifecycle ordering.

# Streaming Transcript Order and Performance Design

**Date:** 2026-08-31
**Status:** Approved design
**Scope:** Live transcript event ingestion, assistant/tool ordering, and grouped tool disclosure

## Problem

New sessions can become unresponsive while the model streams its first response. The transcript also loses the model's content-block order: when an assistant message contains text, tool calls, and later text, the UI renders all assistant text first and places the tool cards below it.

Users also need one control that hides a complete consecutive batch of tool calls without removing its place in the conversation. Individual tool cards already disclose their details, but that does not collapse the batch itself.

## Root Causes

### Streaming frames cross the main actor

The transcript pipeline was originally moved into `TranscriptEventProcessor`, which owns `TranscriptReducer` on an actor and publishes replaceable UI snapshots at no more than 20 Hz. A later provider-account integration replaced direct processor ingestion with a `Task` isolated to `SessionController`'s `@MainActor`. Every raw RPC frame now crosses the main actor before it reaches the processor, including every growing `message_update` snapshot.

Provider-account changes are rare control events. They do not justify routing all message and tool traffic through the controller.

### Assistant content is flattened before tools are presented

`TranscriptMessage` converts every visible assistant text block into one `ContentDocument` and deliberately skips tool-call blocks. `TranscriptHistoryMapper` and the live reducer then add tool presentations after the message. For content shaped like:

```text
text("I will inspect this")
toolCall(read)
text("The problem is in the reducer")
```

the current presentation becomes:

```text
I will inspect this
The problem is in the reducer
Read …
```

The source order is already present in the assistant message. The presentation layer discards it.

## Goals

- Keep lossless RPC ingestion and transcript reduction off the main actor.
- Preserve assistant text, image, and tool-call order during live streaming, after reconciliation, and after reopening a session.
- Present consecutive tool calls as one inline, collapsible group.
- Keep existing per-tool detail disclosures inside the group.
- Retain provider-account change delivery without adding a second consumer of `RpcClient.events`.
- Preserve the existing 20 Hz ceiling for supersedable transcript snapshots.
- Leave persisted session and RPC wire formats unchanged.

## Non-goals

- Changing OMP's event protocol.
- Hiding tool-call headers or results permanently.
- Changing tool-specific card content.
- Redesigning subagent cards or extension UI.
- Adding transcript-level preferences or persistence for disclosure choices.
- Refactoring unrelated session, provider, or composer behavior.

## Architecture

```text
RpcClient.events (one lossless consumer)
                  │
                  ▼
TranscriptEventProcessor actor
  ├── message/tool frames ───────► TranscriptReducer
  │                                  │
  │                                  └── ordered snapshot, max 20 Hz
  └── rare control frames ───────► controlEvents
                                      │
                                      ▼
                           SessionController @MainActor
                                      │
                                      ▼
                                TranscriptView
```

`TranscriptEventProcessor.run(events:)` again drains `RpcClient.events` directly on the processor actor. `providerAccountChanged` joins extension requests and metadata boundaries in the processor's filtered, lossless `controlEvents` stream. `SessionController.handleControl` applies the typed account change on the main actor.

This restores the intended isolation boundary: message and tool traffic does not execute controller work, while the one event consumer and ordered control delivery remain intact.

## Ordered Transcript Presentation

A shared transcript normalizer will convert assistant content into ordered presentation segments. It is used by both live reduction and persisted-history mapping.

The normalizer walks the assistant message's content array once and emits:

- one assistant segment for each contiguous run of visible text or images;
- a tool reference for each complete tool-call block at its original content index;
- no row for private thinking/reasoning content;
- the existing unsupported-content presentation for unknown visible blocks.

Adjacent visible blocks remain in one assistant segment until a tool call creates a boundary. Segment identities derive from the parent message identity and stable content position so a growing full-snapshot replacement updates existing rows instead of appending duplicates.

Each full assistant snapshot is authoritative for the tool name and any arguments present in its tool-call content block. When a matching execution presentation exists, the normalizer merges those current details by tool-call ID while preserving the execution phase, result, start date, and end date. If the snapshot omits arguments, the existing arguments remain available.

The live reducer retains the authoritative full-message replacement rule. A `message_update` replaces the in-flight message's normalized segment range; `message_end` finalizes that range. Tool execution events update the matching tool presentation by tool-call ID without moving it. Persisted history uses the same normalization before merging tool results, so reopening and reconciliation cannot produce a different order.

For the example above, both live and reopened timelines become:

```text
Assistant: I will inspect this
Tool calls (1)
  Read …
Assistant: The problem is in the reducer
```

Response metadata appears on the first visible segment of an assistant message. A continuation segment after a tool group renders as assistant content without duplicating provider/model metadata.

## Grouped Tool Disclosure

`TranscriptView` groups consecutive tool activity rows at their ordered timeline position:

```text
Tool calls (3)  ▾
  Read Package.swift
  Edit TranscriptReducer.swift
  Run transcript tests
```

The group has a stable identity derived from its first tool call. It remains stable while tool phases and results update.

- The group disclosure starts expanded so the existing card defaults remain visible.
- Selecting the group header collapses or expands all contained rows as one section.
- Individual tool cards retain their current detail chevrons and default-expanded rules.
- A user-collapsed group stays collapsed while its tools stream updates or complete.
- The collapsed header retains the count and a concise aggregate state such as running, failed, or complete.
- A new tool appended to the same consecutive batch joins the existing group without resetting the user's choice.
- A later assistant segment ends the group; later tools create a new inline group.

The existing transcript-wide `Collapse all` and `Expand active` actions continue to control individual card details. They do not override the new group disclosure choice.

The group header uses the existing disclosure motion duration, honors Reduce Motion, provides at least a 32-point hit target, and exposes its count, aggregate status, and expanded/collapsed state to accessibility.

## Reconciliation and Identity

Live items awaiting JSONL persistence remain eligible for the existing reconciliation retention rules. Reconciliation compares the normalized persisted timeline with pending live identities, replaces equivalent finalized segments, and retains running tool presentations.

Tool IDs remain the primary identity for execution updates and result merging. Message segment IDs are presentation identities only; persistence matching continues to use parent-message content and metadata rather than treating each segment as an independent persisted message.

This avoids changing the session file schema and prevents stale history from moving a running tool group below a later assistant segment.

## Failure Handling

- Malformed tool calls without an ID or name do not create a group row.
- A tool execution event without a matching message block is appended at its live event position, preserving the current fallback behavior.
- Unknown RPC frames remain discarded without main-actor publication.
- Provider-account changes stay ordered and lossless in the control stream.
- A stopped or replaced processor finishes both snapshot and control streams and cannot publish into a later session.
- Failed tool groups remain collapsible and keep an error state visible in the collapsed header.

## Verification

### Deterministic tests

- A live assistant snapshot containing `text → toolCall → text` reduces into that exact presentation order.
- Tool start, update, end, and paired tool-result events update the inline tool without moving or duplicating it.
- A second assistant message remains below the preceding tool group.
- Persisted history and live reduction produce equivalent ordered rows.
- Reconciliation preserves a live tool between the correct assistant segments.
- Consecutive tools form one group; assistant content splits groups.
- Collapsing a group survives tool phase updates and newly appended tools.
- Provider-account changes reach `SessionController` through the filtered control stream.
- A 1,000-update message burst still installs no more than 20 supersedable snapshots per second.
- Raw streaming message frames do not execute the controller's main-actor event-forwarding path.

### Product verification

Use a Release build and a real or deterministic OMP session that emits assistant text, multiple tool calls, and follow-up text.

- Send the first prompt through the real composer and confirm the window, composer, and scrolling remain responsive during streaming.
- Confirm tool groups appear between the response segments that surround them.
- Collapse and expand a running group and a completed group.
- Reopen the session and confirm ordering remains identical.
- Capture the completed expanded and collapsed states from the real build.
- Run the relevant app tests, full OmpKit tests, generated-project reproducibility check, and Release build.

## Rollout Boundary

This change is local to the macOS app's transcript pipeline and presentation. It requires no OMP, database, migration, or session-format rollout. If profiling still shows first-response stalls after raw frames are removed from the main actor, further parser/layout profiling will be a separate evidence-driven follow-up rather than scope added to this fix.

# Native Question Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render OMP RPC question requests inline with exact responses, retryable failures, duplicate-submit prevention, and an explicit pending-input signal.

**Architecture:** Keep OMP's real generic `select` then `editor` RPC sequence as the source of truth. Route session input requests into transcript items, render those transient requests with a focused SwiftUI card, and use the persisted OMP `ask` tool result as the durable answered record. Derive attention state only from parsed outstanding response-bearing extension requests.

**Tech Stack:** Swift 6, SwiftUI for macOS 15+, Observation, OmpKit newline JSON RPC, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-04-interaction-improvements.md`, lines 58-64.

---

## Wire contract and scope

OMP 18.0.4 installs an RPC UI context with `hasUI: true`, so `ask` is available. RPC does not expose OMP's rich `askDialog`. It emits a generic flat request:

```json
{"type":"extension_ui_request","id":"request-id","method":"select","title":"Question","options":["A","Other (type your own)"],"optionDetails":[{"description":"Detail"},{}],"timeout":30000}
```

The host answers with a flat frame, without a body wrapper:

```json
{"type":"extension_ui_response","id":"request-id","value":"A"}
```

Choosing `Other (type your own)` must send that exact value. OMP then emits a separate `editor` request with `promptStyle: true`; the editor answer also uses `value`. Cancelling uses `{"cancelled":true}` and timeouts add `"timedOut":true`.

The RPC request omits tool-call ID, question ID, `multi`, and `recommended`. Do not infer them from prose or fabricate a rich multipart card. Provider setup keeps using `ExtensionInputSheet`; only active-session input moves inline.

## File structure

| File | Responsibility |
| --- | --- |
| `App/ExtensionUI/ExtensionUIState.swift` | Identify requests that explicitly require user input and keep exact response bodies |
| `App/ExtensionUI/ExtensionQuestionCardView.swift` | Render select/input/editor requests inline and serialize local interaction |
| `App/Sessions/SessionController.swift` | Route active-session inputs inline, serialize writes per request, report failures, and publish pending-input state |
| `App/Sessions/ActiveSessionView.swift` | Remove the active-session input sheet |
| `App/Sessions/TranscriptView.swift` | Parent-owned renderer integration only |
| `Tests/TenXAppTests/ExtensionUIRouterTests.swift` | Request classification and wire-body regression tests |
| `Tests/TenXAppTests/SessionControllerQuestionTests.swift` | End-to-end request routing, response, failure, timeout, and pending-state tests |
| `Tests/TenXAppTests/ExtensionQuestionCardTests.swift` | Pure card interaction-state tests |

### Task 1: Classify explicit user-input requests

**Files:**
- Modify: `App/ExtensionUI/ExtensionUIState.swift`
- Modify: `Tests/TenXAppTests/ExtensionUIRouterTests.swift`

- [ ] Write tests proving confirm/select/input/editor/openURL require user action while notify/status/widget/title/editor-text/cancel do not.
- [ ] Run the focused router tests and confirm the new property is missing.
- [ ] Add `requiresUserInput` and `isQuestionInput` computed properties on `ExtensionUIState`.
- [ ] Re-run the focused router tests.

### Task 2: Route active-session inputs inline and serialize responses

**Files:**
- Create: `Tests/TenXAppTests/SessionControllerQuestionTests.swift`
- Modify: `App/Sessions/SessionController.swift`
- Modify: `App/Sessions/ActiveSessionView.swift`

- [ ] Add a fake RPC process that emits select, editor, cancellation, timeout, and a deliberately failed response channel.
- [ ] Write tests proving select/input/editor are transcript items, `hasPendingUserInput` follows only outstanding parsed requests, and nonblocking requests never set it.
- [ ] Write tests proving concurrent responses for one request produce one frame, successful writes remove the card, failed writes retain it, and retry is allowed.
- [ ] Run the focused tests and confirm they fail for missing inline routing, property, and return value.
- [ ] Add stored observable `hasPendingUserInput`, refreshed after router consume/remove/reset.
- [ ] Route `.input` and `.editor` through `TranscriptEventProcessor.upsertExtensionUI` for active sessions.
- [ ] Make `respond(to:with:)` return `Bool`; reserve the request ID before writing, reject a concurrent duplicate, clear the reservation after failure, and remove the request after success.
- [ ] Ensure timeout, cancel, stop, and restart cancel pending timeout tasks and response reservations without sending duplicate frames.
- [ ] Remove `ActiveSessionView`'s input sheet and binding; leave provider sheets unchanged.
- [ ] Re-run focused tests.

### Task 3: Render the native inline question card

**Files:**
- Create: `App/ExtensionUI/ExtensionQuestionCardView.swift`
- Create: `Tests/TenXAppTests/ExtensionQuestionCardTests.swift`
- Parent modifies: `App/Sessions/TranscriptView.swift`

- [ ] Write pure state tests for pending, submitting, failed/retry, and duplicate submission.
- [ ] Run the focused tests and confirm the state type is missing.
- [ ] Implement a small `ExtensionQuestionSubmissionState` state machine.
- [ ] Implement `ExtensionQuestionCardView` for `.select`, `.input`, and `.editor`, using existing typography, palette, card, and button styles.
- [ ] Keep all controls disabled while submitting. Show `Couldn’t send response. Try again.` after a failed write and re-enable the relevant actions.
- [ ] Give select options keyboard focus, Enter submission, Escape cancellation, TextField Enter submission, and TextEditor Command-Enter submission.
- [ ] Re-run focused tests.
- [ ] Hand the parent the exact `TranscriptView` switch snippet that supplies the async `Bool` response closure.

### Task 4: Source verification and handoff

**Files:**
- All files above, excluding parent-owned `TranscriptView.swift` and generated `10x.xcodeproj`

- [ ] Run the focused tests with a nonzero Swift Testing count.
- [ ] Run router/controller/card test suites together and inspect failures.
- [ ] Review the diff for out-of-scope edits, response-body changes, and prose-based detection.
- [ ] Commit the implementation atomically with a conventional commit.
- [ ] Tell the parent which source files are ready, the exact renderer snippet, test selectors, and any build or live-UI work still required.

## Acceptance scenarios

1. A select request renders inline; choosing an option sends its exact label once and the transient card disappears only after a successful write.
2. Choosing OMP's exact `Other (type your own)` value produces a later inline editor request; Command-Enter submits free text.
3. Cancelling select aborts the ask. Cancelling editor allows OMP to reissue its select request.
4. A failed response write leaves the card actionable, shows a visible error, and allows one retry.
5. Timeout sends one cancelled/timed-out response and clears pending attention.
6. `hasPendingUserInput` is true only while an explicit confirm/select/input/editor/openURL request is outstanding; visible prose never affects it.
7. OMP's completed `ask` tool result remains the durable answered presentation. No transient extension request is fabricated into session history.

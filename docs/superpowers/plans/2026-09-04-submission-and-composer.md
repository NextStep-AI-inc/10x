# Submission and composer interactions

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Preserve drafting context and make submission, queued work and cancellation immediately understandable.

**Architecture:** AppModel owns the new-session draft. SessionController owns submitted/pending messages and runtime reconciliation. The composer owns focus and native text editing; app-local settings own shortcut mapping. Runtime state and local receipts remain separate.

**Tech Stack:** SwiftUI/AppKit, Observation, OmpKit RPC, Swift Testing.

## Draft lifetime and focus (B02/B16)

- [ ] Move `NewSessionView` draft/attachments from view-local State to AppModel's `newSessionDraft`/`newSessionAttachments`. Bind the same values after Settings/Back or session navigation. Only clear them after `startNewSession` passes its guards and captures the submission.
- [ ] Add `newSessionFocusRequest` to AppModel, incremented by Command-N/openNewSession. Pass it into ComposerView; focus on first presentation and on changed focus requests after dismissing the new-session flyout. Preserve command-browser keyboard handling.
- [ ] Verify real typing immediately after Command-N and unchanged draft/attachments through both navigation routes. A blocked session creation must keep the draft.

## Immediate submission and title state (U01/U02/U06)

- [ ] Introduce a stable pending submission receipt in SessionController before asynchronous opening. Render it in the transcript independently of history installation. Keep text/images and explicit sending/queued/failed phase.
- [ ] Match only user-message echoes corresponding to pending accepted submissions, in submission order; consume exactly one receipt for repeated identical text. Do not duplicate on history reload. Preserve unsent newer drafts if an earlier submission fails.
- [ ] Track title generation explicitly, use one shared header/rail shimmer, and stop shimmer with a bounded prompt-derived fallback when generation ends without a name. User rename wins over automatic generation.
- [ ] Reuse managed controller identity before and after persisted path arrival. Add live session presentation to the rail, including provisional sessions.
- [ ] Present working blue, ready blue, explicit pending-input yellow, terminal failure red and user-stop neutral. Reduce Motion is static; accessible labels expose status without color.

## Right-hand actions and literal editing (U07/B03/B04/B05)

- [ ] Keep Stop independent of whether the draft is empty. Place primary send-kind menu adjacent to Send on the right.
- [ ] App-local shortcut choices map Enter, Command-Enter and Shift-Enter uniquely to primary/alternate/newline, with defaults Steer/Follow up/newline. Existing command-browser key routing keeps precedence while that browser is open.
- [ ] Disable smart dash/quote/text substitutions for the actual composer NSTextView, scoped to this editor rather than all app text fields. Preserve existing image paste and plain text input.
- [ ] Show ordered queued receipts and errors. RPC 18.0.4 exposes queue counts and steering/follow-up policy, but no per-message edit/remove API; do not render dishonest edit/cancel controls. Stop remains available as the supported cancellation action.
- [ ] Regression-check delayed startup, echo reconciliation, send failure with a newer draft, repeated identical submissions and Stop with attachments. Verify through real medium/high provider turns where queue semantics differ.

## Recovery

- [ ] Reproduce startup recovery from a controlled runtime failure. Show the actual failed step, sanitized error and available log action; preserve Continue/Retry behavior. Retest the original large-output task against main's rendering fixes to resolve B01 by evidence, not by the spinner change.

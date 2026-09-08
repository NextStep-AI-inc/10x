# Active-session queue refresh plan

> Use superpowers:subagent-driven-development for the bounded implementation task. The parent owns review and Release UI verification.

**Goal:** Keep the visible queue count equal to OMP's accepted, not-yet-consumed messages while preserving one receipt/echo per user submission.

**Base:** `9afb32452d1ba1e83e2a2ce2a41dbfc17bc77307`, stacked on recovery PR #32. Draft PR #33. Implements QUEUE and verifies existing STOP behavior from the audit roadmap.

**Design:** Reuse `SessionController`'s debounced context state request. A successful prompt acknowledgment invalidates older state reads and schedules a fresh one. Existing lifecycle boundaries already do this on consumption. Apply the queue count alongside context usage after the existing pipeline, revision, and cancellation checks. Do not apply the whole state object, which could overwrite a newer streaming state. Runtime counts are authoritative; pending receipts remain their existing independent delivery record.

**Constraints:** Swift 6.1, native macOS 15+, current OmpKit; no dependencies, schema, runtime patches, queue editor, or resend behavior. Preserve drafts and images. No changes to main checkout or another session's worktree. No merge. Production implementation stays in `App/Sessions/SessionController.swift`.

## Task 1: Queue acceptance and consumption

Files: modify `App/Sessions/SessionController.swift` and `Tests/TenXAppTests/SessionControllerTests.swift`; create `Tests/TenXAppTests/Fixtures/queue_fake_server.py`.

- [x] Add a controlled wire fixture using the same real `SessionProcessManager`/`RpcClient` path as the context fixture. It starts a streaming session, acknowledges queued prompts, answers `get_state` with the actual fixture queue length, and can consume a queued message through a test-only bash control command. Consumption emits the corresponding user message lifecycle and updates `get_messages`. Include a deterministic deferred state response and rejection mode. Keep JSON writes serialized and do not use timing races as assertions. Close every child and remove disposable project data even if test setup throws.
- [x] Add behavioral tests: two follow-ups display 2, then 1, then 0 as consumed; steering acceptance and consumption update the count; rejection preserves the staged message without increasing accepted count; a deferred older state reply cannot overwrite a later count; receipt reconciliation still gives exactly one visible user echo per accepted repeated message. Observe eventual controller output, not source text. Reuse existing captured event helpers only where wire-level control cannot express the sequence.
- [x] Run the new function selectors with `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/10x-audit-queue-tests`. Confirm a nonzero Swift Testing count and an expected stale-count failure before implementation. Free functions use parentheses, and suite-qualified selectors must match the runner.
- [x] After a successful prompt response and the `isCurrent(context)` guard, increment `contextRevision` and call `scheduleContextRefresh()`. In `refreshContextUsage()`, after the existing current/revision/cancellation guard, set `queuedMessageCount` from the state's `queuedMessageCount` using the same decoding/default as `applyState`. Keep context errors nonfatal and preserve pending-submission handling. Existing message/turn/agent boundaries remain the consumption trigger; add a missing real boundary only with runtime evidence.
- [x] Run the focused queue tests plus existing context, receipt reconciliation, delayed prompt success/failure, and session replacement cases. Fix any in-scope failure, record counts and logs, and commit the focused change with `fix(sessions): refresh accepted and consumed queue counts`.

## Task 2: Review and verify in the Release app

Files: create `docs/superpowers/evidence/2026-09-07-stop-and-queue/README.md` and actual screenshots; update this plan and the roadmap.

- [x] Parent review of the full PR diff: no inferred delivery counts, no stale full-state overwrite, no duplicate user rows, and no process leaks. Match fixture event sequencing to installed OMP 18.1.10, documenting that steering may be consumed within an existing model loop.
- [ ] Build Release with unique bundle ID `com.nextstep.tenx.auditqueue`, derived data `/tmp/10x-audit-queue-release`, and isolated app/runtime data. Confirm the window is visible through CUA. Drive actual prompt and follow-up controls, observe accepted counts and eventual consumption, and reopen history to check one copy per submitted message.
- [ ] Verify Stop with a staged draft and image, Command-period while a flyout is open, and Stop while a decision card is focused. Confirm runtime settlement and unchanged staged input. Change the existing Stop implementation only if the user flow fails.
- [x] Save actual build/runtime versions, commit SHA, commands/counts, screenshots, and explicit limits. Reproduce controlled rejection/late-response cases with the fixture and label them separately from real-runtime QA.
- [ ] Update the draft PR with evidence, check base compatibility and review. Keep draft while required checks remain red or unverified. No merge; continue the next roadmap slice.

## Execution record

- Queue production change and final fixture are committed at `d33c937`. Final 5 queue and 11 nearby tests pass.
- Release UI evidence and exact limits are recorded in [the evidence README](../evidence/2026-09-07-stop-and-queue/README.md). Both queue modes, staged text/images, authoritative counts, and controlled rejection were driven through the app. Persisted marker counts are exactly one per submitted message.
- STOP is incomplete: the controls abort and preserve input, but a Cursor background job can later resume the agent. A stale Running tool label and pending-decision focus remain open. Trace and correct supported cancellation before closing STOP.
- PR stays draft on the known baseline failures and newer-main integration gate.

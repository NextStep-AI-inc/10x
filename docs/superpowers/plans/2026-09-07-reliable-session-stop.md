# Reliable Stop and interrupted activity

> Use superpowers:subagent-driven-development. The implementation worker owns Tasks 1–2; the parent reviews and drives the Release app for Task 3.

**Goal:** Stop must prevent a session's background work from starting another response. Preserve saved history, staged input, and an explicit way to continue.

**Evidence:** Queue Release `d33c937` aborted through Stop and Command-period, then OMP 18.1.10 delivered a completed background bash job and restarted the agent. Its RPC `abort` omits owner-scoped async-job cancellation, and current RPC exposes no job-list/cancel operation. `abort_bash` affects foreground work only. Installed runtime files and dependencies are outside this correction.

**Decision:** Use the existing managed-process shutdown and an explicit Restart. The parent offered a choice and proceeded with this recommended app-side fallback after the optional response window. A normal Stop will disconnect the runtime; Restart opens the same saved session without sending anything. Use calm intentional-stop copy. Unexpected exits retain their existing error/recovery behavior. This is a bounded correction to STOP, not a runtime patch or a new task manager.

**Base:** `19ee7b7`, draft PR #36 stacked on readable-turn PR #35. Keep this isolated worktree and do not merge or modify another checkout.

## Task 1: Fence and close the stopped runtime

Owned files: `App/Sessions/SessionController.swift`, `App/Sessions/ActiveSessionView.swift`, `App/Sessions/RuntimeRecoveryView.swift`, `Tests/TenXAppTests/SessionControllerTests.swift` or a focused `SessionStopTests.swift`, and `Tests/TenXAppTests/Fixtures/stop_fake_server.py`. Generate project changes only with pinned `bundle exec ruby scripts/generate_xcodeproj.rb`.

- [ ] Add a controlled RPC regression that opens an active session, preserves staged text and a PNG, accepts abort but emits a late agent-start/completion, and keeps an owned child alive until shutdown. Assert Stop leaves no current handle, a stopped session, preserved inputs and saved path, no late activity revival, and no owned child. Use deterministic control points and bounded waits; clean up fixture children on failure. Existing transport shutdown tests may cover descendant reaping if duplicating that harness would be larger than the feature.
- [ ] Reuse `stopAndDetachCurrentSession`/pipeline generations to fence old snapshots and commands immediately. Keep the old client locally for a best-effort abort with a short explicit timeout, then always close the managed session even after an abort failure. Preserve items, the saved session path, and current draft/images. Mark outstanding receipts unconfirmed rather than claiming that a dead runtime still has a queue; clear its authoritative queue count. Do not resend any receipt.
- [ ] Keep shutdown and Restart serialized: while the old child is closing, disable Restart and show the stopping state. A stale close completion must not detach or close a newly opened session. Reuse existing opening-close serialization where it fits; avoid a general lifecycle refactor. Cover rapid Stop/Restart/replacement and the existing stop-during-open path.
- [ ] Intentional Stop shows “Response stopped” with “Restart session” and preserved-input copy. It must not claim a crash or require the user to inspect logs. Unexpected exits and failed commands retain their current diagnostics. Dismissing a stopped card must still leave a discoverable Restart action so the composer cannot become a dead end.
- [ ] Verify Restart opens the same history without a provider prompt and retains the draft/image. Keep pending decisions inaccessible after their runtime closes; dispose their timeouts through the existing pipeline cleanup.

## Task 2: Settle interrupted tool presentation

Owned files: `App/Tools/ToolPresentation.swift`, `ToolEventReducer.swift`, `ToolContentExtractor.swift`, `ToolCallGroupView.swift`, `ToolCardScaffold.swift`, `App/Sessions/TranscriptReducer.swift`, `TranscriptEventProcessor.swift`, `TranscriptHistoryMapper.swift`, `TranscriptPresentationRow.swift`, and focused tests for those types. Add another direct exhaustive `ToolPhase` switch caller only if compilation requires it; report the path. Do not change unrelated tool content, diff opening, or output layout.

- [ ] Add an explicit interrupted tool phase with a truthful label and neutral styling. A user-stop or terminal aborted boundary must freeze still-running tool presentations using the stop/end time. Completed/failed tools keep their results. Cover start → abort without tool-end, parallel tools, and a late stale update that must not revive the stopped tool.
- [ ] Reopened history with an aborted assistant and unresolved tool calls must not show permanently Running tools. Infer interruption from persisted terminal evidence only; incomplete history without that evidence remains unknown/unfinished. Do not fabricate persisted timestamps or rewrite the JSONL.
- [ ] Ensure group phase, whole-turn activity, disclosure, and summaries agree with the interrupted state. A later explicit Restart/new turn may start new tool identities normally. Keep source-order and existing render IDs stable.
- [ ] Native QA found that fencing before the final abort event leaves the current assistant presentation labeled Streaming and suppresses its Stopped footer. Extend ownership to `TranscriptMessage.swift`/`TranscriptTurnProjection.swift` if needed: settle only current live presentation and stale pending decisions after local Stop, preserve completed older turns and all content/IDs, and do not rewrite stored JSONL. Add focused coverage for a nonfinal assistant, running tool, and pending decision at Stop.
- [ ] Run only relevant stop/restart/lifecycle, reducer/history, tool phase, and turn/disclosure regressions. Confirm nonzero Swift Testing counts. Add one intentional-stop snapshot only if needed; the parent must view its candidate before promotion. Do not rerun the entire suite or promote the six unrelated baseline failures.
- [ ] Commit the correction and record exact SHAs, test counts, and limits in the private task report. You are not alone in the repository; do not revert another agent's work. Any out-of-fence need is skip-and-flag, not a full abort.

## Task 3: Parent Release verification

- [ ] Review the final diff for bounded shutdown, stale-completion protection, preserved input/receipts, visible Restart, truthful tool phases, and no new runtime/dependency assumptions.
- [ ] Build an isolated Release app, confirm its actual window, and reproduce an auto-backgrounded command. Click Stop with staged text and a PNG, wait beyond the command's original completion time, and verify no new response. Record owned process/child cleanup separately from the UI evidence.
- [ ] Exercise Command-period with the model flyout open and a pending decision focused. Restart must load the same saved conversation and inputs without sending. Verify stopped tool labels both immediately and after reopening. Keep fixture-driven decisions labeled separately from real runtime background work.
- [ ] Save screenshots, source/executable hashes, actual runtime version, test counts, and remaining limits. Update the roadmap and draft PR. No merge or deployment.

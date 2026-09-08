# Readable response turns

The approved audit roadmap calls for stable response boundaries, completed status/duration, and activity based on the whole active response. Source normalization already preserves text/tool/text order; this slice keeps that machinery and verifies it in the real app. A per-turn changed-file index follows in its own PR.

## Design

Add a pure `TranscriptTurnProjection` over existing `[TranscriptItem]`, with no new mutable transcript cases or persistence. A response turn contains a batch of consecutive user inputs and the full assistant/tool response. The first user opens the batch; further users join until an assistant message, tool, subagent, or extension request supplies response evidence. The next user after that evidence opens a new turn. Notices/annotations between inputs do not invent extra turns; preamble before the first user remains standalone. Pending receipts are not consumed user inputs and stay outside this projection.

Use `turn:` plus the first user's `renderLineageKey.baseMessageID` as the stable ID. Keep all existing item, tool-group, disclosure, search, and scroll-target IDs. Build the existing presentation rows within each projected section; add a compact completed summary after its content. Prefer a flat render-row list so nested layout containers do not break `scrollPosition` or existing `ScrollViewReader` anchors. Search receives only existing content rows. Do not reparse message content or recompute tool-card bodies.

Only the final section receives active runtime state. Activity priority is pending input, then a streaming runtime or any running tool/active subagent anywhere in that section. A successful terminal assistant response outranks earlier recoverable tool failures; terminal `error` or `aborted` means failed or stopped. Without a terminal response, use failed if a tool failed, interrupted if a new input closed the response, otherwise leave completion unknown. An idle runtime must not make every historical user-only batch look complete.

Actual OMP 18.1.10 JSONL preserves assistant `timestamp` (response start), `completedAt` (finish), `duration` (per-call milliseconds), and `ttft` in `TranscriptMessage.raw`. The outer entry timestamp is a persistence fallback. Derive response-loop elapsed time from the earliest assistant start/tool start to the latest assistant completion/tool end; do not add per-call durations or count queued user waiting time. Deduplicate assistant segments by base message ID. Prefer explicit completion timestamps; omit duration if a reliable end is absent rather than presenting an exact-looking guess. Live quiet intervals may use `controller.turnStartedAt` until response timing exists. No new sidecar storage is needed.

The summary is a restrained status line using existing typography/palette: Completed with duration, Stopped, or Failed. It must not duplicate a spinner already shown by a running tool or live assistant. The existing quiet-period Working indicator must inspect the entire active turn, not only the last item, and stay hidden for pending decisions. Preserve the existing Expanded/Standard/Slim controls and Jump to latest behavior.

## Global constraints

- Work only in `/tmp/10x-audit-turns`, branch `codex/active-session-turns`, stacked on image history `6e3bec4`. User main checkout and other worktrees are outside ownership.
- Read `writing-ui` and `visual-ui` before implementing new UI/text. Use existing SwiftUI components and styles; one new component per file.
- No dependencies, schema, merge, deployment, shell parsing, git-change attribution, or unrelated refactors.
- Never hand-edit `10x.xcodeproj`; regenerate using `ruby scripts/generate_xcodeproj.rb` and pinned xcodeproj 1.27.0.

## Task 1: Project response turns and timing

Owned: new `App/Sessions/TranscriptTurnProjection.swift`, new `Tests/TenXAppTests/TranscriptTurnProjectionTests.swift`, and generated project file through the script.

- [ ] Write behavior tests for two consecutive user inputs sharing one turn, a later user after response evidence opening another, standalone preamble, and notices not splitting an input batch.
- [ ] Assert IDs remain stable when extra batched input arrives and when equivalent live/history message segments reconcile.
- [ ] Assert timestamps/completedAt give the same completed duration live and reopened; queued user waiting time and repeated assistant segments do not inflate it; missing completion timing produces no duration.
- [ ] Test a running tool in the middle, concurrent running/completed tools, pending extension input, active subagent, recovered tool error followed by successful final response, terminal error/abort, and incomplete history.
- [ ] Implement the minimal pure projection and run those focused tests with valid function selectors, recording a nonzero test count. Commit.

## Task 2: Render summaries without changing transcript behavior

Owned: `App/Sessions/TranscriptView.swift`, `App/Sessions/TurnActivityView.swift`, new `App/Sessions/TranscriptTurnSummaryView.swift` if needed, focused additions in existing turn/activity/disclosure/viewport tests or `TranscriptTurnProjectionTests.swift`, and targeted `ViewSnapshotTests.swift` fixtures. Regenerate the project for new Swift files.

- [ ] Render existing rows plus completed summaries with stable flat scroll targets. Keep pending receipt placement, content order, tool disclosure state, search expansion, and existing viewport behavior.
- [ ] Replace last-item quiet activity detection with active-section scanning. Leave long first-token waits visibly Working; avoid duplicate Working indicators while an earlier tool/subagent or live message is active.
- [ ] Add focused snapshots for completed, stopped/failed, and quiet/running states. Do not automatically promote changed baseline snapshots; report actual images for parent visual review.
- [ ] Run the focused projection/activity/row/disclosure/viewport checks, then the app suite once. Six activity snapshots fail identically at baseline `e60234a`; record them separately from any new mismatch. Do not repeat full runs absent a material change or unresolved failure.
- [ ] Commit implementation and report exact commands, counts, artifacts, and limitations. Parent owns visual acceptance and branch review.

## Task 3: Verify ORDER and TURNS in Release

- [ ] Build Release for the local architecture and launch an isolated native app/profile. Verify a real provider response containing text, tool activity, then final text in that order during streaming, after completion, and after relaunch/reopen.
- [ ] Exercise quiet intervals and multiple tools with out-of-order completion. Confirm one active-state indication, stable completed timing, and final-response readability.
- [ ] While reading older content, expand a tool, send new input, and switch away/back; confirm disclosure and reading position remain stable, with an explicit Jump to latest available. Test search jump into a collapsed group.
- [ ] Save screenshots, build SHA and production commit, update roadmap/PR, and keep the PR draft on unresolved baseline/base-integration gates. No merge.

## Preflight rulings

Task 1 produces immutable projected sections consumed by Task 2; Task 2 preserves original content rows consumed by Task 3's scroll/search checks. All three tasks share stable message/tool IDs, not new persisted data. Timing comes from observed runtime fields, not enqueue timestamps. This resolves the queued-input and reopening ambiguities without expanding storage scope.

## Release corrections within the stated acceptance

- `7a2e240` corrects quiet activity after a completed tool in Cursor's packed response. Earlier nonfinal text must not suppress Working once its following tool has settled; current text and any running tool/subagent still suppress duplicate activity. Behavioral RED and 8 focused GREEN tests are recorded.
- The native switch-away/back check exposed per-card/group disclosure loss because `TranscriptView` owns `ToolDisclosureState` in `@State` and the view is recreated per session. Task 2 ownership is extended to one `SessionController` property plus the existing view and focused tests: retain the existing disclosure object on the controller, as already done for its viewport. Keep choices scoped to that session and keep explicit detail-mode changes clearing overrides as before. Do not add disk persistence or a new preferences store. Verify session A/B choices remain independent and survive returning to a retained controller; parent repeats the native switch check.

# 10x Chat Transcript Experience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the raw-message transcript with a model-aware, reference-aware agent timeline that has excellent compact and expanded tool/subagent activity, rich wrapped messages, and structured diffs.

**Architecture:** Extend OmpKit's typed session entries, map persisted history and live RPC frames into one normalized `TranscriptItem` model, and render it through shared block, annotation, reference, disclosure, and diff components. The session file is authoritative for persisted model/mode timestamps; RPC remains the streaming source and fallback.

**Tech Stack:** macOS 15+, Swift 6, SwiftUI, Observation, Foundation/AppKit, Swift Testing, local OmpKit package. No new runtime dependency.

**Spec:** `docs/superpowers/specs/2026-08-24-chat-transcript-experience.md`

**Baseline:** macOS app suite passes 48/48. OmpKit has 122 passing tests, 2 intentional live skips, and one repeatable pre-existing failure in `eofFailsPendingRequests` where a fast child exit sometimes reports `nil` instead of code `5`. This plan must not change that process-lifecycle area.

## Constraints

- Work only in `codex/chat-transcript-experience` at `/Users/tannerpham/CS Projects/.worktrees/10x-chat-transcript-experience`.
- Preserve the parent pure-white, border-light visual system. No shadows, gray cards, decorative backgrounds, status dots, or pill metadata.
- Use `ruby scripts/generate_xcodeproj.rb` after adding/removing Swift files and before Xcode builds.
- Use TDD for every parser/reducer behavior. Keep user disclosure state in views, not protocol models.
- Do not modify the separate OMP configuration-default patch/worktree.
- A draft PR cannot be opened because this repository has no remote; commits are the handoff boundary.

## Task 1: Preserve session timeline metadata in OmpKit

**Files:**
- Modify: `OmpKit/Sources/OmpKit/Sessions/SessionEntry.swift`
- Modify: `OmpKit/Sources/OmpKit/Sessions/SessionFile.swift`
- Modify: `OmpKit/Tests/OmpKitTests/SessionFileTests.swift`
- Modify: `docs/contracts/session-file-contract.md`

- [x] Add failing parser tests for model role/fallback, configured thinking,
  `mode_change`, display-safe `session_init`, branch summary, and compaction counts.
- [x] Run `swift test --filter SessionFileTests` and confirm the new assertions fail.
- [x] Add the minimum typed associated values and parsing needed for those entries;
  preserve unknown raw entries and never surface `systemPrompt`.
- [x] Run the focused tests and then `swift test`; record only the known lifecycle
  baseline failure if it recurs.
- [x] Commit: `feat(ompkit): preserve transcript timeline metadata`

## Task 2: Normalize messages, annotations, and references

**Files:**
- Modify: `App/Sessions/TranscriptItem.swift`
- Create: `App/Sessions/TranscriptMessage.swift`
- Create: `App/Sessions/TranscriptAnnotation.swift`
- Create: `App/Sessions/TranscriptReference.swift`
- Create: `App/Sessions/TranscriptHistoryMapper.swift`
- Modify: `Tests/TenXAppTests/TranscriptReducerTests.swift`
- Create: `Tests/TenXAppTests/TranscriptHistoryMapperTests.swift`
- Create: `Tests/TenXAppTests/TranscriptReferenceTests.swift`

- [x] Write failing tests that map an ordered session path into thread start,
  timestamped/model-attributed messages, mode/model/thinking/compaction
  annotations, and paired tools without duplicates.
- [x] Write failing reference tests for absolute paths, `path:line`, spaces,
  URLs, punctuation trimming, duplicates, and missing files.
- [x] Run the three focused test files and confirm semantic failures.
- [x] Implement immutable presentation types and the history mapper. Use the
  assistant message's own provider/model first and folded timeline state only
  as fallback. Coalesce identical adjacent metadata annotations.
- [x] Implement deterministic reference extraction without regex backtracking
  or filesystem access in the parser.
- [x] Run focused tests and commit: `feat(chat): normalize transcript history`

## Task 3: Reconcile authoritative history with live RPC events

**Files:**
- Modify: `App/Sessions/TranscriptReducer.swift`
- Modify: `App/Sessions/SessionController.swift`
- Create: `App/Sessions/SessionTimelineLoader.swift`
- Modify: `OmpKit/Sources/OmpKit/Wire/RpcCommand.swift`
- Modify: `Tests/TenXAppTests/TranscriptReducerTests.swift`
- Modify: `Tests/TenXAppTests/SessionControllerTests.swift`
- Modify: `OmpKit/Tests/OmpKitTests/CommandEncodingTests.swift`

- [x] Add failing tests for stable live message replacement, timestamp/model
  retention, retry/fallback/compaction annotations, history fallback, and no
  duplicate persisted/live items.
- [x] Add missing typed `get_subagent_messages` command coverage if required by
  on-demand expansion; retain the existing progress subscription command.
- [x] Implement an actor-based file loader using `SessionFileParser` and
  `SessionTree.activePath`; use RPC messages only when the file is absent.
- [x] Subscribe to subagent progress during open. Reconcile the persisted
  timeline after message/turn/agent boundaries without dropping pending
  approval or active tool items.
- [x] Run app reducer/controller tests plus OmpKit command tests.
- [x] Commit: `feat(chat): reconcile live and persisted timelines`

## Task 4: Add subagent and lifecycle presentation

**Files:**
- Create: `App/Sessions/SubagentPresentation.swift`
- Create: `App/Sessions/SubagentEventReducer.swift`
- Create: `App/Sessions/SubagentCardView.swift`
- Modify: `App/Sessions/TranscriptReducer.swift`
- Create: `Tests/TenXAppTests/SubagentEventReducerTests.swift`

- [x] Add failing tests for lifecycle/progress coalescing, actual model label,
  recent tool count, completion/failure, parent task association, and
  out-of-order progress.
- [x] Implement one stable presentation per subagent. Keep only bounded recent
  progress in memory and store the session path for lazy detail loading.
- [x] Render agent/model/state in the compact row and returned result/progress in
  the expanded body; never show internal system prompts.
- [x] Run focused tests and commit: `feat(chat): present subagent activity`

## Task 5: Build rich, wrapping message blocks

**Files:**
- Replace: `App/Sessions/MessageBubbleView.swift`
- Create: `App/Sessions/MessageContentParser.swift`
- Create: `App/Sessions/MessageBlockView.swift`
- Create: `App/Sessions/CodeBlockView.swift`
- Create: `App/Sessions/ResponseMetadataView.swift`
- Create: `App/Sessions/TranscriptReferenceView.swift`
- Create: `Tests/TenXAppTests/MessageContentParserTests.swift`
- Modify: `Tests/TenXAppTests/SnapshotTests.swift`

- [x] Add failing parser tests for paragraphs, headings, lists, quotes, fenced
  code/language, unmatched fences, and long unbroken content.
- [x] Implement block parsing and native SwiftUI rendering with SF Pro/SF Mono,
  selection, code copy, links, bounded horizontal code scrolling, and local
  reference actions.
- [x] Add response metadata for model, mode/agent, timestamp, streaming, and
  terminal errors. Show it once per response.
- [x] Record focused snapshots for user, assistant, code, long wrapping, and
  references; compare them to the spec before accepting.
- [x] Commit: `feat(chat): render rich agent messages`

## Task 6: Unify compact and expanded activity

**Files:**
- Create: `App/Tools/ToolDisclosureState.swift`
- Modify: `App/Tools/ToolCardScaffold.swift`
- Modify: `App/Tools/GenericToolCardView.swift`
- Modify: `App/Tools/ReadToolCardView.swift`
- Modify: `App/Tools/BashToolCardView.swift`
- Modify: `App/Tools/WriteToolCardView.swift`
- Modify: `App/Tools/SearchToolCardView.swift`
- Modify: `App/Tools/TaskToolCardView.swift`
- Modify: `App/Tools/TodoToolCardView.swift`
- Modify: `App/Tools/WebToolCardView.swift`
- Modify: `App/Sessions/TranscriptView.swift`
- Create: `Tests/TenXAppTests/ToolDisclosureStateTests.swift`
- Modify: `Tests/TenXAppTests/SnapshotTests.swift`

- [ ] Add failing tests for initial disclosure rules and user-choice persistence
  across running-to-complete updates.
- [ ] Refactor the shared scaffold into a keyboard-accessible disclosure whose
  collapsed row contains verb/object/outcome/duration and whose expanded body
  keeps existing bespoke content.
- [ ] Add transcript-level `Collapse all` and `Expand active` ghost actions only
  above the activity-count threshold.
- [ ] Record compact/expanded/running/error/approval/subagent snapshots.
- [ ] Commit: `feat(chat): add activity disclosure`

## Task 7: Parse and render production diff views

**Files:**
- Create: `App/Tools/UnifiedDiff.swift`
- Create: `App/Tools/UnifiedDiffParser.swift`
- Create: `App/Tools/DiffView.swift`
- Modify: `App/Tools/EditToolCardView.swift`
- Modify: `App/Tools/ToolContentExtractor.swift`
- Create: `Tests/TenXAppTests/UnifiedDiffParserTests.swift`
- Modify: `Tests/TenXAppTests/ToolContentExtractorTests.swift`
- Modify: `Tests/TenXAppTests/SnapshotTests.swift`

- [ ] Add failing tests for multi-file patches, hunks, line-number progression,
  no-newline markers, malformed input, and unchanged-run compaction.
- [ ] Implement a single-pass unified diff parser and structured rows with old
  and new line numbers. Keep raw patch text for copy/fallback.
- [ ] Render file/hunk hierarchy, cyan additions, red removals, collapsed long
  context, horizontal scrolling, Copy patch, and Open file.
- [ ] Record compact/expanded/multi-file/long-line snapshots.
- [ ] Commit: `feat(chat): render structured diffs`

## Task 8: Integrate transcript states and polish accessibility

**Files:**
- Modify: `App/Sessions/TranscriptView.swift`
- Modify: `App/Sessions/ActiveSessionView.swift`
- Modify: `App/Sessions/SessionController.swift`
- Modify: `Tests/TenXAppTests/SnapshotTests.swift`
- Modify: `Tests/TenXAppTests/SessionControllerTests.swift`

- [ ] Add the single thread-start timestamp, loading skeleton, header-only empty
  state, reconciliation warning, and full accessibility labels.
- [ ] Verify keyboard traversal, focus rings, disclosure announcements, copy/open
  actions, and Reduce Motion behavior.
- [ ] Verify scrolling does not jump on in-place streaming/tool updates and only
  follows the bottom when the user is already near it.
- [ ] Record full transcript snapshots at 900×700 and 1440×900 for compact,
  expanded, streaming, failure, long content, diff, and subagent fixtures.
- [ ] Commit: `feat(chat): integrate transcript experience`

## Task 9: Full verification and review

**Files:**
- Modify only if a requirement-backed defect is found.

- [ ] Run `ruby scripts/generate_xcodeproj.rb` and confirm `git diff` contains no
  unintended project churn.
- [ ] Run `xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' test`.
- [ ] Run `swift test` from `OmpKit`; compare any lifecycle failure to baseline.
- [ ] Run a Release build with a task-specific DerivedData path.
- [ ] Load `launching-local-builds` and launch the Release app from the feature
  worktree. Confirm the exact bundle path and process are visible.
- [ ] Drive a real OMP session through user prompt, streaming response, tool
  disclosure, edit diff, local/web reference, model change, mode change, and a
  subagent return. Capture screenshots from the real build.
- [ ] Inspect screenshots at normal and narrow widths for clipping, alignment,
  contrast, density, and long-content wrapping. Fix only requirement defects.
- [ ] Run `verifying-work`, then `requesting-code-review`; address blocking
  correctness/accessibility regressions and rerun affected evidence.
- [ ] Update this plan's checkboxes and spec status with verified evidence.
- [ ] Because no remote exists, report the reviewed branch and commits instead
  of pretending a draft PR exists. Do not merge without Tanner's instruction.

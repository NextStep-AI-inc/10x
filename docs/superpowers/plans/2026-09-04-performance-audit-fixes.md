# Performance Audit Fixes Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development. Implement tasks sequentially with owned-path fences. The controller verifies the full branch and performs one consolidated review, following the user's review-depth limits.

**Goal:** Address all seven audit findings without duplicating current-main or interaction PR work.
**Architecture:** Keep the existing normalization/publication pipeline; reduce redundant work at disk, document and transport boundaries and bound idle runtimes. Make resource lifetime explicit without losing background work.
**Tech Stack:** Swift 6, SwiftUI/AppKit, Foundation, SQLite, OmpKit, Swift Testing; macOS 15+.
**Spec:** docs/superpowers/specs/2026-09-04-performance-audit-fixes.md

## Global Constraints

- Existing dependencies only. Generated Xcode project owned solely by ruby scripts/generate_xcodeproj.rb (xcodeproj 1.27.0).
- Fresh worktree based on origin/main eb95373. Never edit another worktree or the user's main checkout.
- Protect running sessions, drafts, approvals, queued prompts, provider pins and ordered terminal events.
- Separate PR against main; no merge/deploy. Record overlap with PR #22.
- Tests exercise behavior/resource budgets; do not duplicate the implementation with tautological tests.

### Task 1: Stop redundant JSON work and watcher enumeration

**Owned files:** OmpKit/Sources/OmpKit/Wire/JSONValue.swift; OmpKit/Sources/OmpKit/Sessions/SessionLibrary.swift; corresponding OmpKit tests only.
**Interface:** Keep JSONValue decoding and SessionLibrary public API stable. File callback internals may carry URL/event classification.

- [ ] Record baseline OmpKit tests and transport benchmark results.
- [ ] Add regression coverage for malformed JSON fallbacks and watcher behavior. A repeated-write probe must demonstrate watcher topology enumeration is bounded, while a newly created/renamed/deleted session remains discoverable. Use a narrow observer/injected enumerator only if necessary to measure actual filesystem work.
- [ ] Make JSON decoding's first operation `try JSONDecoder().decode(JSONValue.self, from: data)`; prepare surrogate/lossy candidates only on failure. Preserve first-error and repair ordering.
- [ ] Move watcher topology refresh behind debounce and distinguish directory/structural events from content-only writes; preserve append detection. Replace whole-cache filtering on a changed path if profiling confirms it contributes within this task.
- [ ] Run swift test --package-path OmpKit; rerun the 100/1000-file append workload; commit only owned files.

### Task 2: Normalize each tool update once and deduplicate history work

**Owned files:** App/Tools/ToolPresentation.swift, App/Tools/ToolEventReducer.swift, App/Sessions/TranscriptReducer.swift, App/Sessions/TranscriptHistoryMapper.swift, App/Sessions/SessionTimelineLoader.swift, reconciliation-only sections of App/Sessions/SessionController.swift; directly corresponding Tests/TenXAppTests files; OmpKit SessionFile/SessionTree cancellation checks only if needed.
**Interface:** Keep ToolPresentation readable semantics and renderer content-ID reuse. SessionTimelineLoader.load(path:) remains throwing/actor-isolated. Do not change composer/context/search interaction behavior.

- [ ] Add failing tests that identical tool updates preserve normalized content identities and a multi-field update normalizes once with the correct final presentation.
- [ ] Introduce an atomic tool update operation; preserve individual-property semantics for callers/tests, but route reducer/history mutation groups through it. Check every mutation caller.
- [ ] Add a file-read seam or injectable loader for tests and prove repeated unchanged history loads perform one full read/map; changed and replaced paths reload and canceled requests throw without installing stale state.
- [ ] Cache at most one history per loader by path/mtime/size plus replacement identity, with stable-source checks before caching. Add cancellation inside long parse/map/tree loops without changing the synchronous API contract.
- [ ] Debounce adjacent reconciliation boundaries (50 ms) before history load; preserve final content, stale-generation rejection and warnings. Do not delay unrelated metadata or approval handling.
- [ ] Run targeted app tests, then commit owned files. Record normalized call-count and history-read evidence.

### Task 3: Bound eligible idle session retention

**Owned files:** App/Application/AppModel.swift; eviction/lifetime-only additions to App/Sessions/SessionController.swift; a small colocated retention policy file if needed; matching tests.
**Interface:** Existing open/reopen/close and provider activity APIs remain. Prefer AppModel-owned least-recently-used ordering and explicit eligibility from SessionController.

- [ ] Write failing behavior tests opening more than four eligible idle sessions, preserving current and streaming sessions, drafts/attachments/queued prompts/approvals, and reopening an evicted session.
- [ ] Keep at most four eligible inactive idle sessions. Reclaim all eligible inactive idle sessions on memory pressure. Revisit eligibility on session state/activity changes so finished background turns can eventually be reclaimed.
- [ ] Mark recency on navigation; remove/index-detach before awaiting close; guard navigation and runtime replacement races. Do not close a session that became active or acquired new work. Use exact controller/process ownership when closing.
- [ ] Cancel retention callbacks on teardown, preserve provider account locks and draft content, and test memory-pressure/current-session safety.
- [ ] Run targeted navigation/activity/startup tests; commit owned files.

### Task 4: Bound transport backlogs without response deadlocks

**Owned files:** OmpKit/Sources/OmpKit/Wire/LineTransport.swift, OmpKit/Sources/OmpKit/RpcClient.swift, new colocated bounded queue types, relevant OmpKit tests/fixtures. App changes only where needed to report the existing recoverable runtime-error channel.
**Interface:** Preserve public AsyncStream<Data>/AsyncStream<RpcFrame> consumers if possible using pull-driven stream construction. Responses must progress independently of slow event consumption.

- [ ] Add deterministic producer-faster-than-consumer tests, mixed response/event ordering, cancellation/EOF/drain, large single frames, cleanup and overflow failure. Reproduce unbounded retained memory using a small injectable queue budget, not unstable RSS assertions.
- [ ] Bound queued memory to 4 MiB per raw/event queue, accounting for encoded payload sizes; preserve FIFO and one-consumer semantics. An individual accepted frame can transiently exceed the in-memory budget only while being decoded/delivered; store oversized queued frames off-heap.
- [ ] If response-safe backpressure requires spooling, use private temporary length-prefixed storage capped at 64 MiB per queue, reclaim on drain/cancel/shutdown, and fail the runtime explicitly at the cap. No silent drops or unlimited metadata arrays; document storage and recovery. Keep unrelated lifecycle queues unchanged.
- [ ] Preserve exit/stderr arbitration, protocol limits, ready negotiation and cancel behavior. Test that a stalled event consumer can still await an RPC response.
- [ ] Run OmpKit tests and a sustained burst through the actual pipeline; commit owned files.

### Task 5: Integrate, measure and open for review

**Owned files:** generator output, performance report/fixtures, plan/spec verification additions; fixes only for regressions in this branch.

- [ ] Regenerate Xcode project once new files settle; resolve any project conflicts by regeneration.
- [ ] Verify existing merged streaming-normalization tests and enumerate every original audit item as fixed here or already fixed in main. Check latest PR #22 changes without touching its worktree.
- [ ] Build Release and run full app/OmpKit suites; assert nonzero executed counts. Repeat current-base/final benchmarks with identical fixtures.
- [ ] Launch an isolated identifiable Release app and drive real controls for a normal development change, session switches, history opening and streaming. Save screenshot/profiling evidence and clean owned processes. If environment blocks real verification, keep the PR draft and state the exact blocker.
- [ ] Perform one consolidated correctness/security/concurrency review, fix accepted findings, and run only affected checks afterward.
- [ ] Sync with origin/main, finish PR body with actual evidence and remaining constraints, push and mark ready only with green required checks. Do not merge.

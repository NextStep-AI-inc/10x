# Performance audit follow-through

User approved fixing all seven reported findings and opening a PR, after checking the interaction task. Base: origin/main eb95373. The original local audit used e178acb; its timings are historical and must not be presented as current-main measurements.

## Scope reconciliation

1. Streaming normalization: already merged in PR #20 (6fff753); preserve and rerun coverage rather than duplicate it.
2. Watcher rescans: still present. Coalesce structural enumeration; file-content writes must not rescan watcher topology.
3. History reloads: still present. Fingerprint/cache unchanged history, cancel abandoned work, and combine adjacent reconciliation boundaries.
4. Idle runtime retention: still present. Retain active/current/draft/approval sessions; cap eligible idle history/runtime retention and reclaim under memory pressure.
5. Tool normalization: still present. Apply related mutations once, preserve renderer IDs, and avoid work for identical updates.
6. JSON repair: still eager. Decode valid JSON first and preserve all fallback compatibility.
7. Incoming queues: still unbounded. Bound memory and preserve event/response order, without blocking RPC responses behind a stalled event consumer.

PR #22, codex/interaction-improvements, is actively adding question/context UI, composer controls, navigation/search/rename and activity feedback. Do not import or modify that worktree. Keep this PR against current main, with small integration points in SessionController/AppModel. Its UI changes do not implement the remaining six findings. Media loading, progressive source/diff rendering and incoming normalization are already improved in current main.

## Design constraints

Swift 6, macOS 15 minimum; existing dependencies only. Never hand-edit the generated Xcode project; run ruby scripts/generate_xcodeproj.rb with xcodeproj 1.27.0. No schema changes. No merge, deployment, release or user-data mutations. Use disposable session roots and verification projects. Existing active background work, provider pinning, pending approvals, drafts, cancellation and final-event ordering are load-bearing behavior. Runtime eviction must protect them.

Prefer a bounded channel with flow control wherever that cannot deadlock. RPC response reading cannot wait for an event consumer that is itself waiting for a response. For that boundary, an ordered bounded-memory overflow store is acceptable only with private temporary files, bounded disk usage, complete cleanup, and an explicit recoverable overload error instead of silent event loss. Document chosen budgets and why. Do not claim infinite lossless buffering or add blanket newest-one policies.

## Acceptance

Behavioral regression tests for each changed flow; Release build and full app/OmpKit suites; repeat realistic synthetic performance probes against current base and final source; real Release UI exercise with normal development workflow, long histories and multiple sessions where environment permits. Record exact limits honestly. Full source changes must survive companion-branch integration checks. Deliver a reviewable PR, not a merge.

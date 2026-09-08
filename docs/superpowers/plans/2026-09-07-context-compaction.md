# Context compaction with known recovery

> Use superpowers:subagent-driven-development. One worker owns Tasks 1–2; the parent reviews and drives the Release app for Task 3. Do not spawn nested workers.

**Goal:** Offer compaction from the existing context popover, report progress and failures honestly, and reload authoritative saved history before returning control.

**Runtime evidence:** Installed OMP 18.1.10 advertises builtin `compact`; typed RPC already exists. Its `RpcInputDispatcher` serializes ordinary commands behind compact, including `get_state`, prompt, and abort. Manual compact emits no auto-compaction boundary events. A local RPC timeout does not cancel the remote operation. Therefore no polling, blind retry, or sending behind an unknown result is safe. Use the existing bounded managed-process close and Restart path when status is unknown.

**Base:** `4503f0b`, stacked on reliable-Stop PR #36. No dependency or installed runtime edits, no branch merges. This branch will need the later Stop presentation and turn-scrolling corrections during integration.

## Task 1: Coordinate the compaction operation

Owned files: `App/Sessions/SessionController.swift`, focused `SessionControllerTests.swift` or `SessionContextCompactionTests.swift`, and `Tests/TenXAppTests/Fixtures/context_fake_server.py` or a dedicated compaction fixture. Generate the project only using pinned `bundle exec ruby scripts/generate_xcodeproj.rb`.

- [ ] Add a controlled regression for capability availability, successful compaction, explicit unsuccessful RPC response, and a serial server that never replies before a short injected test timeout. Production timeout is explicitly 600 seconds. The fixture must record which commands were received and close owned children on failure.
- [ ] Enable only when a connected idle session has a successful command catalog containing builtin `compact`, no send in flight, no pending submission/queue/input decision, and no compaction already running. An extension command named compact does not establish typed capability. An unsupported-command response disables further offers for that runtime.
- [ ] Set local busy state synchronously. Preserve staged input; keep it editable. Block Send, slash sends, model RPC changes, context refreshes, and idle eviction while compacting. Reserve/release the provider through the existing managed-turn coordinator. Reuse the shared Working activity state where appropriate, without pretending the agent is streaming text.
- [ ] Send typed `.compact` through `sendWithEventFence`, wait for its fence, and explicitly require `response.success`. Reload through `historyLoader` and processor reconciliation with the existing generation/handle guards, then refresh authoritative runtime/context usage. Do not wait for auto-compaction events, sum estimates, or fabricate a token reduction. Keep loading/failure channels for reading context separate from compaction errors.
- [ ] A known unsuccessful response leaves the session usable with an inline compaction error. A timeout, cancellation, or uncertain disconnect closes that runtime through the existing bounded shutdown/Restart serialization; clear queue claims, preserve input, and offer Restart after close. Copy must say the compaction result is unknown and saved history will reload on Restart. Never retry compact or resend a prompt automatically.
- [ ] Keep the existing Stop button and Command-period usable during compaction by extending their busy guard. Stop closes the runtime; ordinary queued RPC abort alone is insufficient. A stale compaction completion must not clear a replacement session's busy/error state or mutate its transcript. Cover Stop during compact, timeout closure, no prompt queued while busy/unknown, and late response after replacement.

## Task 2: Expose an honest action in context details

Owned files: `App/Sessions/ContextUsageControl.swift`, `ComposerView.swift`, `ActiveSessionView.swift`/`RuntimeRecoveryView.swift` only for context-specific recovery copy and the existing Stop guard, related focused state/render tests, and targeted `ViewSnapshotTests.swift`/references. Do not change provider settings, quotas, general composer layout, or approval policy.

- [ ] Add `Compact context` with brief copy explaining that older conversation is summarized to free context. Show availability/disabled reason, `Compacting context…`, and a separate error. The context meter remains an estimate and account quota stays separate.
- [ ] Preserve popover close and explicit Stop access. Do not show a successful reduction until the authoritative reload succeeds. If close/timeout is required, use the existing recovery card with an accurate compaction message and discoverable Restart, including after dismissal; do not mislabel an unknown result as a failed rewrite.
- [ ] Run focused operation/lifecycle/context and targeted snapshots only. Parent must view candidates before promotion. Do not run the full suite or promote six unrelated baseline snapshot failures.
- [ ] Commit atomic changes and record exact SHAs, nonzero test counts, and limits in `.superpowers/sdd/context-compaction/report.md` (private, not tracked). You are not alone; do not revert other changes. Out-of-fence needs are skip-and-flag.

## Task 3: Parent Release verification

- [ ] Review final timeout/Stop fencing, protocol capability detection, failure copy, and history/context refresh behavior.
- [ ] Build and visibly launch an isolated Release app. Drive the popover action with staged text and a PNG, observe busy feedback/disabled send and model controls, then authoritative before/after context and preserved input. Exercise one real installed-runtime/provider compaction; record any unsupported provider response honestly.
- [ ] Drive controlled failure/timeout/Stop recovery separately, verify no automatic send/retry, and confirm Restart loads persisted history. Keep deterministic RPC evidence distinct from real runtime behavior.
- [ ] Save screenshots, source/executable hashes, runtime version, test counts, and explicit limits. Update roadmap and draft PR. No merge or deployment.

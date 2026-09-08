# Context compaction acceptance

Status: **DONE_WITH_CONCERNS** for the feature branch. The core compaction action passed real-runtime and controlled native acceptance. Final wording was verified through the native accessibility tree and final screenshot; the isolated QA app was then quit with Command-Q. Stack integration remains outstanding. No merge or deployment occurred.

## Verified

- Final production commit `d20ff7ca2d1e9a8821c85f4bffd8ee0d8e457b1b`; final arm64 Release build passed in `/tmp/10x-context-copy-final-release.log`.
- Final native bundle `/tmp/10x-context-final-build/10x-context.app`, ID `com.nextstep.tenx.contextfinalqa`, executable SHA-256 `c67855fd4b80e0381e0e33751e6c8bf578b83543598e130807f36aca93ad3618`. The main behavior captures use the earlier `e8240be` build, whose executable SHA-256 is `6623f479eb0c6b86fed52941fed17ac88d73de4f392ac56b06b70003c8565690`.
- Controlled controller checks covered capability, busy gating, event fences, successful history reload, explicit RPC failure, unsupported command, timeout/disconnect/cancellation closure, stale completion, Stop, and failure after acknowledged compaction. The worker's final controller selection passed 53 tests. A parent 53-test run passed 52 with one existing stop-fixture PID assertion failing during disk exhaustion; that exact test passed after space became available. Final approved context snapshot test passed all four states; the copy/dedup follow-up also passed the same targeted snapshot test.
- Actual installed OMP 18.1.10 compacted 160 neutral synthetic messages through its native `snapcompact` method. The existing context meter went from an estimated 94,526/200,000 (47%) to 71,401 (36%). Reopening the popover produced the same authoritative 71,401 estimate. Conversation contribution changed from 75,911 to 52,786; other reported categories stayed unchanged.
- The real-runtime action preserved the unsent `CONTEXT-PRESERVES-UNSENT-DRAFT`. The JSONL retained 80 user entries, contained one compaction entry, and did not contain the staged marker. The runtime did not invoke a summarizing model for this native method. These synthetic-history values demonstrate the flow, not a provider benchmark.
- A controlled serial RPC server stalled inside compact. The popover displayed Compacting context, Send/Model were disabled, the draft stayed editable, and Stop remained available. Command-period from the open popover closed the runtime and exposed Restart with the draft intact. No fixture process remained after this check.
- A controlled unsuccessful response showed a separate compaction error while retaining usable Send/Model controls and staged input. A runtime that advertised compact then returned unsupported disabled further attempts with an explicit explanation.
- The final native accessibility tree displayed `Compresses older conversation to free context space.` and exactly one `Context compaction isn’t supported by this runtime.` message below a disabled Compact context button. `final-unsupported-feedback.jpg` captures the same state, and `final-native-copy-verification.json` records both observations and the completed QA-app shutdown.

## Evidence and limits

`before-compaction.png`, `after-compaction-state.png`, and `after-compaction-refreshed.png` capture the actual runtime flow. The middle image was captured after compaction had already finished; it is not a progress capture. Controlled screenshots are separately named. Their earlier explanatory wording was corrected in the final build because snapcompact does not necessarily summarize older messages.

The synthetic history has no usage field for its compaction boundary's `tokensBefore`, so the persisted boundary shows 0 → 71,401. The meaningful before/after evidence is the actual context report, 94,526 → 71,401. No token reduction is inferred from the missing boundary value.

Native acceptance used staged text. Preservation of staged image data during compaction is covered by the focused controller regression; the added native PNG repetition was not run. Short controlled timeout and failed-reload paths were verified in controller tests rather than waiting for the production ten-minute timeout in the UI. Other providers and distribution signing were not tested.

## For Tanner to test

After stack integration, exercise the action in an ordinary long session on your preferred provider. The branch's runtime capability and failure handling remain explicit when that provider cannot compact.

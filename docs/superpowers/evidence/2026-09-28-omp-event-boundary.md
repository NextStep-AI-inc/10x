# Event boundary execution evidence

Status: IN PROGRESS. Branch `codex/omp-event-boundary`, draft PR #50.
Implementation checkout: `/Users/tannerpham/CS Projects/.worktrees/10x-omp-event-boundary-design`.
Models: authenticated Cursor CLI `composer-2.5-fast` implements; `grok-4.7-xhigh-fast` reviews. Main session coordinates and verifies native UI.

## Completed code and checks

| Task | Commit | Evidence |
| --- | --- | --- |
| 1 classifier | `e02c9e4` | Runtime RED: 1 test / 4 issues; GREEN and independent review: 7 tests pass. Grok approved. |
| 2 live/history | `5849bc1`, corrected by `040f0a6` | Fixed omission count, live/history duplication, identity promotion, and aborted tools. 26 focused implementation tests pass; independent re-review: 10 pass including 2 suite-qualified controller tests. Grok approved. |
| 3 setting/card | `8d4487e`, copy fix `0825eaa` | 11 scoped tests pass independently; copy-fix RED 1 test / 3 issues, GREEN and re-review 2 pass. Grok approved. No runtime RED captured for original Task 3. |

Task 2 original RED was a build failure with zero executed tests; subsequent fix rounds captured runtime failures. Do not describe it as a passing TDD gate.

## Built app and current GUI checkpoint

Release built successfully from `0825eaa` using:

```sh
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/10x-event-boundary-release PRODUCT_BUNDLE_IDENTIFIER=com.nextstep.tenx.eventboundary CODE_SIGNING_ALLOWED=NO
```

App: `/tmp/10x-event-boundary-release/Build/Products/Release/10x.app`.
Bundle ID checked: `com.nextstep.tenx.eventboundary`.
Final checkpoint build includes the wording fix. Log: `task-3-final-release-build.log`, BUILD SUCCEEDED.

Native CUA observation after Tanner made the window visible: 10x General shows the approved Show agent guidance setting and supporting text; initial state off, switches on and back off. Real screenshot inspected. No clipping seen. The test project `/tmp/10x-event-boundary-qa` ran two real Composer 2.5 Fast turns through OMP. Advisor notes (fixture and an actual advisor correction) and hidden custom guidance appeared as compact cards with the switch on. With it off, guidance disappeared, the referenced file remained without its injected body, and both OK-TURN replies remained. Toggling from a scrolled-up transcript preserved the earlier position and Jump to latest control. Real running-turn and completed-turn screenshots were inspected. After quit/rebuild/relaunch, the session restored both advisor cards, hidden custom guidance, referenced file, and conversation. The on preference persisted; switching off again removed guidance and retained the referenced file. Checkpoint 1 passed; Task 4 may begin.

The disposable project contains a project-local OMP extension emitting an advisor on first turn and hidden custom guidance on second. Static discovery and two real UI turns verified. Fixture and detailed runbook are in the local scratch directory.

## Known limitations and pending triage

- Full suite on an intermediate Task 2 tree: 1616 tests, 194 issues. Cause not established; do not call these all pre-existing.
- Only `richAssistantMessageSnapshot` and `fullTranscriptCompactWindowSnapshot` failures were reproduced on both Task 1 base and Task 2 head.
- `continuousSettingsSnapshot()` fails its reference comparison. Actual frame shows OMP General, not the new 10x General row; no reference was promoted and no baseline attribution is claimed.
- Task 2 review NIT: message_update real-ID promotion leaves inflightGuidanceID on removed synthetic ID (`TranscriptReducer.swift`, around line 832 at `040f0a6`). Final review must triage reconciliation before message_end.
- No merge or deployment authorized. Main checkout remains untouched.

## Later work in progress

- Task 8 was implemented independently after checkpoint 1: `1c4a373` rejects missing/blank interactive request IDs while preserving usable IDs and unknown methods. Runtime RED: 1 test / 2 issues; independent focused 1 and companion 14 tests pass. Grok approved.
- Task 4 initial implementation `45c7b5a`, first fixes `d6e9bc1`. First review caught guessed tool ownership, recognized control events becoming diagnostics, traversal past the node budget, omission reconciliation errors, and an obsolete processor expectation. Runtime fix RED: 7 tests / 21 issues; 16 focused tests pass independently after first fixes. Re-review still found unmatched history diagnostics silently discarded and settlement poisoning an unseen worker ID. Final fix `5f38d34` passed 20 implementation tests; its runtime RED was 5 tests / 7 issues. Grok independently reran the 5 changed regressions and approved. Task 4 code review is complete; native UI remains pending.
- Controller decision for diagnostic omission reconciliation: discarded identities are not retained, so exact union counts are unavailable. Use a conservative lower bound, label it explicitly, preserve unmatched retained history until capping, and require repeated reconciliation to be idempotent. Do not add an unbounded identity cache or infer equality from payload summaries. Guidance omission behavior is unchanged.
- Release build at `d6e9bc1` succeeded (`task-4-release-build.log`). Native launch was blocked by the locked Mac; user has been asked to unlock it. No workaround attempted. Task 4 live UI remains pending.
- Disposable `/boundary-probe` command is ready in the QA project's local extension. It emits one synthetic unknown event only in RPC mode, without inference, to check hidden/on visibility, payload suppression, and duplicate-ID updates. It is test-only and not product code.

## Local detailed evidence

Ignored scratch: `.superpowers/sdd/2026-09-28-omp-event-boundary/`.
Reports: `task-1-review.md`, `task-2-rereview.md`, `task-3-review.md`, `task-3-rereview.md`.
Logs: task-prefixed RED/GREEN/review logs and `task-3-release-build.log`; status ledger `progress.md`.
These local logs do not travel with git; this document preserves their measured outcomes and outstanding work.

## Tool and interaction implementation in progress

- Task 5 initial `bc4dad4`: 14 scoped tests pass after live session-file/call-ID wiring. Runtime RED: 1 test / 9 issues. Independent review ran 19 passing tests but found array schema loss, unbounded keys/MIME labels, node-budget accounting, and duplicate terminal updates. Fix `b751a48` passes 23 tests; independent re-review pending. Only duplicate-terminal runtime RED was captured in this fix round; no runtime RED claimed for the other three fixes.
- Task 9 initial `adaba87`: 9 tests in 2 suites pass independently, Release build succeeds. Initial RED was blocked by compilation; no runtime RED claimed. Review found the delayed recovery sentence was stored but not rendered; a focused notice fix is in progress. Native UI remains pending.
- Task 7 Delegate projection and view are in progress. First snapshot showed the intended hierarchy with an invalid fixture timer; correction requested before reference approval. No native proof yet.
- An implementation worker incorrectly stashed shared WIP while attempting a snapshot baseline check. The root stopped it, restored stash `7d4c7c1` without dropping it, verified Task 5 paths against the saved tree, and committed the fixes. No changes were lost. The worker resumed with all Git mutations prohibited. The stash remains a backup and must not be reapplied.
- The earlier Task 2 full-suite log attributes 183 of 194 issues to SnapshotHarness, 7 to TranscriptReducerTests, 3 to SessionControllerTests, and 1 to TranscriptEventProcessorTests. This classifies that historical run, not the final branch status or baseline cause.

## Latest code anchors before final verification

- Task 5 `40fb4fb`: root-array omission marker uses one counted scalar. Runtime RED reproduces 258/257 retained nodes; six worker tests pass after the fix. Grok approves the code. Its final independent rerun was blocked by Task 6 WIP compilation; queued again on the stable tree.
- Task 7 `31853d4`: five independent tests pass including the visually inspected and promoted Delegate reference. Review found hidden parent errors, broken tool search targeting, an inaccessible child action, and unbounded worker summaries. Fix `ec3ffa6` is committed, with regression execution and a failed-parent snapshot pending after Task 6 compilation settles.
- Task 9 `9af918b`: delayed recovery notice now reaches the transcript. Runtime RED: one missing-notice failure; five controller tests pass after the fix. Copy correction `fdd3675` shortens the sentence to 64 UTF-8 bytes with the complete Restart instruction; the updated visible-notice regression is queued.
- Task 6 `a7f355b`: five extractor tests pass and five actual snapshots were generated. Root inspected them and did not promote references. Read/Write path/source attachment looks correct; Edit and Browser previews fall back to data trees, copy labels regressed, and Run duplicates exit status. Focused code review is in progress before correction.
- All these anchors are implementation checkpoints, not a claim that checkpoints 2–3 or Task 10 are verified. The verification app still needs a final Release rebuild and native checks after unlock.

## Stable-tree re-review

- Grok approved Task 7 fixes `ec3ffa6`. One combined Debug run executed 20 tests: 19 passed and one failed only because the new failed-Delegate snapshot reference was missing. Eight Task 7 checks passed, six queued Task 5 checks passed, and all five unsupported-extension controller tests passed, including the 64-byte visible restart instruction. Root inspected the failed-Delegate actual and promoted it unchanged; the failure is visible and the blank-card defect is gone. VoiceOver and native delegation remain unverified.
- Task 6 independent review ran 12 passing extractor/family tests, but confirmed four corrections are needed: bounded copy labels, Browser preview/web-reference semantics, preserved Run error with no repeated exit labels, and a parseable Edit snapshot fixture. Those are being corrected together.
- Deferred Task 2 guidance-ID issue reproduced: one runtime test / two issues. Fix `c94f107` retargets the active guidance ID and lets it reach the reconciliation override. Four focused tests pass; final independent verification is pending.


## Final focused approvals at `837a16c` (supersedes pending reviews above)

- Task 2 guidance-ID fix `c94f107` independently approved: four relevant identity/reconciliation tests pass.
- Task 5 root marker fix `40fb4fb` independently verified: six queued budget checks pass.
- Task 6 semantic surfaces `837a16c` independently approved: the combined final review ran **22 tests, all passing**, covering corrected tool semantics, five visually inspected tool snapshots, four guidance-ID checks, and the failed-empty Delegate snapshot.
- Task 7 `ec3ffa6` independently approved; both normal and failed-empty Delegate references were visually inspected before promotion. Task 9's five unsupported-interaction regressions also pass in that review run.
- Accepted limitation: **Copy patch copies the combined multi-file patch**, while the view selects a single file. The worker's earlier selected-only claim was incorrect.

## Task 10 full verification at `837a16c`

Grok ran the complete Debug app suite and complete OmpKit package suite, then an isolated Release build. Because the app suite failed, it ran one identical full Debug suite on clean Task 1 baseline `e02c9e40`.

| Gate | Result |
| --- | --- |
| Debug app | 1674 tests / 44 suites, **196 issues**, 185 failing functions |
| Baseline Debug app | 1612 tests / 43 suites, **191 issues**, 180 failing functions |
| OmpKit | **223 tests passed**, zero failures |
| Release | **BUILD SUCCEEDED**; bundle `com.nextstep.tenx.eventboundary` |

All 180 baseline-failing functions also fail at head. These include 176 snapshot functions with the same reference-mismatch type and snapshot names; pixel bytes were not compared, so this is not proof that every head pixel difference is pre-existing. Four functional failure names overlap: reconciliation warning timeout, provider/runtime transition timeout, archive cleanup timeout, and opening-command shutdown. Some secondary assertions differ between runs.

Five branch-only failures need correction: two outdated failed-console shape assertions, settings search assertions for retired labels, a media test helper that does not traverse the new Computer wrapper, and a real phase-only todo regression caused by depth truncation. The first Composer fix round masked the last one with an invented `details.todos` fixture field; root rejected it, restored the actual provider fixture, and required the ingestion limit correction. Initial five-selector RED: **5 tests / 6 issues**. The rejected round's 10 passing tests are not final verification.

The plan's depth cap is amended from four to six container levels to preserve OMP `details.phases[].tasks[]` task objects. Scalar, array, total-node, and media limits remain unchanged. Final correction and independent verification are pending.

## Native verification resumed on 2026-09-29

Tanner confirmed the isolated verification app was visible. Root used CUA, dismissed the updater with **Not now**, and inspected Release `837a16c`. The locked-Mac blocker is resolved.

- Restored conversation, Referenced file, and default-off guidance preference remain intact.
- `/boundary-probe` twice: off hides the diagnostic; on shows one `unknown_future_event` Additional activity card with a lower-bound byte count; fake secret and nested payload do not appear in screenshot or accessibility text. Off hides it again.
- A real Composer 2.5 Fast turn completed Read, Edit, Search, and an intentional failed Run, then returned `QA-TOOLS-DONE`. The model used shell writes instead of the requested Write tool; **native Write is not verified**. Delegate was unavailable in this client; **native Delegate is not verified**.
- Read `qa-a.txt` expanded into its filename/icon, attached folder/path strip, two numbered source lines, and divided line-count footer. **Copy preview** pasted exactly `alpha` plus `beta-edited` on separate lines into the unsent composer; root cleared it.
- Real Edit showed its filename and a visible confirmation/details fallback because the actual provider result contained no patch. This is not native multi-file diff proof.
- `/boundary-required` used real `ctx.ui.select`. With guidance off, the required Option A/B card appeared. Clicking A dismissed it and OMP emitted `QA-T10:Option A`, proving the response path.
- `/boundary-unsupported` showed its immediate warning with guidance off. The first fixture returned immediately and settled the synthetic turn, so it did not exercise the delayed recovery timer. The fixture was corrected to keep its command pending for up to 30 seconds, with an escape terminal event; retry pending.
- Local-only probe user bubbles lingered as Sending and became Delivery not confirmed after restart. Normal subsequent inference still completed. This behavior is recorded, not attributed to this branch without baseline proof.
- Root's first tool-check input accidentally contained real newlines in `typeText`, which submitted early. Root stopped it, restarted through the UI, and resubmitted one correct single-line prompt. This was an automation mistake.

### Native crash discovered

Opening edited-file details then querying accessibility crashed the isolated app (`10x-2026-09-29-010325.ips`). Expanding a failed Run caused a second crash (`010747.ips`). Both are SwiftUI accessibility-label recursion during an AX hierarchy query. The first report's binary UUID matches the isolated Release build. Earlier test-run crash reports have different bundles/stacks and are not baseline proof for this crash. Grok is tracing the shared cause; native tool verification remains blocked on this concrete defect.

CUA screenshots were emitted in the conversation. No standalone native screenshot files were saved. Component reference images are rendered snapshots, not substitutes for native interaction proof. No global OMP configuration or installed app was changed.


## Final Release native checks at `032034f`

Release build succeeded with bundle `com.nextstep.tenx.eventboundary`, arm64 UUID `B3E51771-AC9E-3218-8624-8D55849A4FAC`. Root launched this exact build through CUA.

- **Crash correction verified:** removed three redundant Text accessibility labels in `032034f`. Both previous reproductions (edited-file details and expanded failed Run, followed by AX hierarchy queries) now survive. Failed Run visibly preserves `partial stdout` and `Command exited with code 7`. The Edit fallback row was omitted from one AX tree even while visible; full VoiceOver coverage is not claimed.
- **Oversized preview verified:** `/boundary-large` produced a completed Run card. Expanding it showed a bounded progressive preview, Copy preview, Show 4,000 more characters, Open session file, and Copy call ID. It stayed responsive. Exact byte bounds are covered by automated budget tests; clipboard byte count was not measured in this native probe.
- **Malformed terminal verified:** `/boundary-large malformed` in a fresh session settled as Error with `Could not display this update`, and the session returned Ready. No spinner remained.
- **Multi-file Edit verified with synthetic frames:** expanding the Edit showed alpha/beta-edited → beta-final. Clicking `qa-b.txt` changed the header to qa-b.txt and the diff to gamma/delta-edited → delta-final. Folder strip and Copy patch were visible. These frames do not perform actual file edits.
- **Delegate layout verified with synthetic frames:** one parent displayed two nested worker rows, the successful result `Write card OK.` and failed result `Synthetic failure.`. Open session appeared only on the fixture worker with a path. It was not clicked because the fixture supplies the real parent path, not a child transcript. Real worker execution and child-session navigation remain unverified because this Cursor client did not expose delegation.
- **Unsupported recovery verified:** in a fresh session with guidance off, the unsupported warning appeared, then the waiting warning and Restart session action appeared (observed at 15 seconds, within the fixture's 30-second hold). Clicking Restart cleared recovery and returned Ready. This is synthetic fault injection; cancellation receipt is proved by controller tests, not this extension.
- **Startup observation:** one launch timed out preparing runtime. Continue opened a provider-empty onboarding view. Quitting and relaunching recovered the existing QA session without changing credentials or configuration. Cause remains unclassified.

### Synthetic fixture limitations

Use a fresh QA session for each synthetic command. Chaining synthetic `agent_start`/terminal frames without real model message lifecycle failed to display later tool cards in the same conversation; isolated sessions displayed them. Local command bubbles still read Sending despite successful command results. Neither observation is silently treated as a branch regression or as baseline behavior.

The surfaces fixture copied `result: null` from a presentation-only snapshot. At the live ingestion boundary this correctly becomes a malformed Write error, so **successful native Write remains unverified**. It is not evidence of a successful Write execution. Real Read/Edit/Search/Run and supported select were exercised separately. No real Delegate, worker Open session, VoiceOver traversal, or Browser/Computer native interaction is claimed.

Native screenshots are available inline in the task. The app was not updated, installed over the user's copy, merged, or deployed.


## Final independent correction review at `032034f`

Grok **approved** `837a16c..032034f`. All five prior branch-only failing functions passed, including the original phase-only provider fixture. The empty-phase snapshot regression and deeper-payload truncation assertions passed. No invented fixture fields or production test helper remain.

The final full Debug run was **incomplete**, not passing: 1667 tests printed results before `sessionWatcherRefreshesMetadataAfterHandoff` hung for over ten minutes. Grok stopped its own test host. Printed results contain 180 failing functions / 193 issues: 183 snapshot issues, five startup assertions, four SessionController issues, one navigation issue. 179 failing functions overlap the recorded clean baseline. `bootstrapWarmsTwoRecentProjectsBeforeHandoff` is a new failure in this run; the hanging watcher test passed in both earlier full runs. Neither startup outlier is attributed to baseline or this patch without further evidence. Concurrent Debug and Release builds may have contributed, but that remains a hypothesis. A bounded isolated rerun of only those two tests is pending.

The full OmpKit suite passed 223 tests earlier; it is unchanged by the final correction range. Release BUILD SUCCEEDED. Native crash proof after the label fix is documented above and was performed by root, not Grok.


### Bounded follow-up results

Grok reran only `bootstrapWarmsTwoRecentProjectsBeforeHandoff()` and `sessionWatcherRefreshesMetadataAfterHandoff()` with no concurrent 10x build and a 120-second execution deadline. **2 tests passed in 1.316 seconds**, with TEST SUCCEEDED. The deadline was not reached. This does not convert the incomplete full suite into a pass or establish its failure cause.

Composer corrected only the disposable Write fixture to use the real non-null OMP write-result content/details shape. Root started a fresh QA session and verified the **completed synthetic Write**: qa-a.txt filename/icon, attached folder strip, Open file / Copy preview, numbered alpha and beta-edited source plus trailing blank line, line-count footer, and session-file/call-ID actions. It remained accessible and responsive. Successful Write presentation is now verified; actual provider Write execution remains unverified because the earlier real turn used shell writes.

**Final disposition: DONE_WITH_CONCERNS.** Product code through `032034f` is independently approved and the scoped native boundary scenarios above passed. PR #50 stays draft because the complete app-suite gate is not green and actual Delegate execution/child navigation is unavailable in the selected client. No merge or deployment. The isolated Release remains open for Tanner to inspect.

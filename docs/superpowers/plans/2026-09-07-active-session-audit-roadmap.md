# Active-session audit implementation roadmap

The user authorized all actionable audit items in roadmap order. The historical report is preserved in [PR #31](https://github.com/NextStep-AI-inc/10x/pull/31). Its application baseline is `59a4ae8`; implementation was reconciled against main at `e60234a332f6fdc34f771c92f0d3852411d7fe71` before changing code.

Source inspection and existing test coverage are recorded separately from execution evidence. “Present” below does not claim fresh live verification. Larger workspace/file-explorer/terminal surfaces remain outside the approved audit recommendations.

## 1. Session continuity and recovery

[Plan](2026-09-07-session-continuity-recovery.md) · [PR #32](https://github.com/NextStep-AI-inc/10x/pull/32)

- [x] **SAVE:** Verify existing persistent warm/cold creation and actual disk recovery across relaunch. Main rejects unpersisted sessions; preserve configured extensions when appending the session directory.
- [x] **OPEN:** Verify first-action warm existing-session checkout loads and persists history. Retain the requested path when opening fails before a handle exists.
- [x] **ERROR:** Verify failed-existing Retry opening, failed-new Review prompt, rejected input, and process-exit Restart separately. Preserve drafts and avoid automatic resend after uncertain delivery.

## 2. Interrupt and acknowledge

- [x] **STOP:** Main has independent Stop beside Send and Cmd-Period. Verify staged text/images, actual runtime settling, open flyouts, and focused pending decisions; change only if the real flow fails.
- [x] **QUEUE:** Main has per-message sending/queued/unconfirmed receipts with echo reconciliation. Refresh the authoritative queue count after acceptance and consumption, without allowing older replies to overwrite newer state. Verify multiple follow-ups, steering, rejection, and exactly one echo per accepted message.

## 3. Readable turns

- [x] **ORDER:** Main normalizes contiguous text segments around inline tools for live and reopened history, retaining message identity and render lineage. Verify real provider live/completion/reopen order and parallel completions. Existing fixtures cover text/tool/text, duplicate IDs, repeated snapshots, and reconciliation.
- [x] **TURNS:** Keep existing tool grouping and disclosure. Add stable turn boundaries, completed duration/status, and activity derived from the active turn/tool set. Verify long quiet intervals, streaming text, concurrent tools, errors, completion, and preserved disclosure state.

## 4. Awareness and review

- [x] **SIGNALS:** Main's rail already exposes working, needs-input, failure, stopped, and unread completion. Use the same session status for the header/turn/composer and provide a way to reach a pending request while reading older content. Verify switching between two sessions and non-overlapping states.
- [x] **REVIEW:** Add a compact per-turn changed-file index linking to existing edit details. State its scope/completeness, deduplicate repeated paths, and avoid summed per-edit line totals. Exercise edit-tool and shell-generated files alongside pre-existing/concurrent changes. A tool-derived index may explicitly exclude shell writes; an observed git delta must not claim authorship. A full git review pane is a later product choice.
- [x] **CONTEXT:** Main has a usage meter/details, unknown/loading/failure states, and boundary refresh. Add an honest compaction action with availability/progress/failure feedback using supported runtime behavior. Verify usage before/after compaction and provider limitations; account quota remains distinct.
- [x] **TITLES:** Main has persisted automatic titles, rename, search, and previous/next shortcuts. Remember the last valid session route and refresh git metadata after relevant changes. Verify duplicate titles, missing projects, relaunch, and branch metadata without changing the user's checkout.

## 5. Input and permission decisions

- [x] **PERMISSIONS:** Main has independently addressable pending cards and rail attention. Explain the actual effective policy and its scope based on runtime evidence; do not invent a per-session mode or Always Allow response. Keep timeouts traceable. Verify confirm/select/input/cancel/timeout/multiple requests, focus during typing, Return, and Stop access.
- [ ] **INPUT:** Implemented and native-verified except live CJK composition, which awaits approval to temporarily enable Pinyin. Main preserves in-memory drafts and receipt state and offers slash-command discovery. Persist unsent text/images across relaunch; add deliberate file insertion through current transport capabilities; display attachment and model errors independently. Verify session switches, invalid images, multiple warnings, model failure, long paths, insertion while typing, and CJK composition before changing Return behavior.
- [x] **DETAILS:** Preserve the existing reading-position and Jump to latest policy. Make running durations update, show useful current output during long commands, honor the preferred editor for diff paths including multi-file results, and expose supported child-session links/recent tool details. Verify send while scrolled up and switching sessions. Additional lower-priority observations from the 90-item coverage ledger are triaged only when they are required by these concrete acceptance criteria.

## Existing implementation evidence to reuse

| Item | Current-main source / regression anchors |
| --- | --- |
| SAVE / OPEN | `SessionProcessManager.openNew`, `warm`; `openNewRejectsAnUnpersistedSession`, `twoColdSessionsInOneProjectKeepDistinctRuntimeOwners` |
| STOP | `ComposerView.actionControls`, `TenXCommands`; `composerStillSendsAStagedImageMidRunSnapshot` |
| QUEUE | `PendingUserSubmission.reconcile`; `oneEchoConsumesOnlyOneRepeatedPendingSubmission`, `outOfOrderQueueEchoesConsumeTheirMatchingReceipts` |
| ORDER | `TranscriptMessageNormalizer`, `TranscriptRenderLineageKey`; `normalizerPreservesTextToolTextOrder`, `liveAssistantToolSegmentsStayInSourceOrderAndUpdateInPlace`, `historyMapperPreservesThreadModelModeAndToolOrder` |
| TURNS | `TranscriptPresentationRow`, `ToolDisclosureState`; `collapsedToolGroupStaysCollapsedAsToolsUpdateAndAppend`, `slimVisibleRowsHideGroupedToolsUntilTheGroupIsOpened` |
| SIGNALS | `SessionController.activityState`, `RailSessionReadState`; `backgroundCompletionStaysUnreadUntilAcknowledged`, `actionableAndLiveStatesKeepTheirIndicators` |
| CONTEXT | `ContextUsageControl`, `SessionContextUsage`; `contextDetailsDoNotSubmitOrAlterTheConversation`, `contextRefreshesAfterCompactionBoundary` |
| TITLES | `OmpSessionTitleGenerator`, `AppModel.confirmRename`; `firstSuccessfulPromptPersistsGeneratedSessionTitleExactlyOnce`, `coldRenameUsesOneTemporaryRuntimeAndClosesItAfterSave` |
| PERMISSIONS | `ExtensionUIRouter`, `ExtensionQuestionCardView`; `selectionThenEditorUsesExactFlatResponsesAndGuardsDuplicateSubmission`, `concurrentInputAndEditorRequestsRemainIndependentlyAddressable` |
| INPUT | `ComposerCommandModel`, controller draft retention; `rejectedInitialSendPreservesInitialAndNewerComposerContent`, `idleEvictionEligibilityRequiresAnIdleSessionWithNothingUnsaved` |
| DETAILS | `TranscriptViewportState`, `TranscriptView`; `userScrollingUpReleasesTranscriptFollowing`, `automaticTranscriptFollowingNeverStacksAnimations`, `followObservationTracksMiddleToolGroupChangesWhenLaterMessageIsLast` |

## Execution record

- Baseline OmpKit suite: 217 tests passed before application changes (`/tmp/10x-recovery-ompkit-baseline.log`).
- SAVE / OPEN / ERROR acceptance is recorded in the [Release evidence](../evidence/2026-09-07-session-continuity-recovery/README.md), including real warm/cold persistence and fixture-driven rejection. PR #32 stays draft on the documented baseline/base gates.
- QUEUE is verified in [PR #33](https://github.com/NextStep-AI-inc/10x/pull/33): native follow-up and steering counts, consumption, rejected-input retention, one persisted echo, and reopened history. [Release evidence](https://github.com/NextStep-AI-inc/10x/blob/codex/active-session-queue/docs/superpowers/evidence/2026-09-07-stop-and-queue/README.md). STOP is now verified in [PR #36](https://github.com/NextStep-AI-inc/10x/pull/36): actual background/foreground work stops, staged text/images remain, and Command-period works from model and pending-input fields.
- Image history restoration is verified in [PR #34](https://github.com/NextStep-AI-inc/10x/pull/34): saved pixels, one new image prompt/receipt, and quit/relaunch/reopen all passed in Release. Unsent disk drafts remain INPUT.
- ORDER / TURNS passed final native acceptance in [PR #35](https://github.com/NextStep-AI-inc/10x/pull/35): actual parallel completion and reopened source order, quiet intervals, session switching, disclosure, search, Jump to latest, and sending while reading older content. Final production `b4bf0b0`, 33 affected regression checks, with approved summary snapshots and earlier focused checks.
- Keep each item unchecked until this run has evidence for its full stated scope, or explicitly record the remaining limitation beside it.


## Implementation rollup, September 8

Status: **DONE_WITH_CONCERNS** for the implemented feature branches; **BLOCKED** at final combined acceptance. All 14 audit items are implemented or covered by verified existing behavior. Thirteen have completed their recorded native feature acceptance. INPUT passed native file insertion, Undo/Redo, image staging, independent warnings, and separate draft/relaunch acceptance; live CJK candidate composition remains unverified. All PRs remain drafts, and the complete stack has not been integrated.

| Audit item | PRs | Native evidence | Remaining |
| --- | --- | --- | --- |
| SAVE / OPEN / ERROR | [32](https://github.com/NextStep-AI-inc/10x/pull/32) | Real warm/cold disk persistence, reopen, and distinct recovery paths | Stack integration |
| STOP | [36](https://github.com/NextStep-AI-inc/10x/pull/36) | Real background/foreground termination, staged text/images retained, Command-period from model and pending-input fields | Stack integration |
| QUEUE | [33](https://github.com/NextStep-AI-inc/10x/pull/33) | Follow-up/steering acceptance, decrement, rejection, exactly one persisted echo | Stack integration |
| ORDER / TURNS | [35](https://github.com/NextStep-AI-inc/10x/pull/35) | Actual parallel tools, live/reopened source order, quiet work, disclosure, reading position, search, Jump, and send while reading older content | Stack integration |
| SIGNALS | [37](https://github.com/NextStep-AI-inc/10x/pull/37) | Request arrival preserves typing/scroll; explicit jumps; confirm/select/input; separate cancel/timeout; two-session unread state | One initial unexplained clean app exit is recorded; stack integration |
| REVIEW | [38](https://github.com/NextStep-AI-inc/10x/pull/38) | Real edit/write and multi-file results, deduplicated paths, correct Slim navigation, excluded shell/pre-existing changes | Stack integration |
| CONTEXT | [39](https://github.com/NextStep-AI-inc/10x/pull/39) | Actual OMP compaction 94,526 → 71,401 estimated tokens; controlled native busy/Stop/failure/unsupported; final wording/capture | PNG preservation and short timeout are regression-only; stack integration |
| TITLES | [42](https://github.com/NextStep-AI-inc/10x/pull/42), [44](https://github.com/NextStep-AI-inc/10x/pull/44) | Generated/fallback/manual duplicate names, relaunch, missing-project recovery, actual tool and retained-session branch refresh | Stack integration |
| PERMISSIONS | [37](https://github.com/NextStep-AI-inc/10x/pull/37), [45](https://github.com/NextStep-AI-inc/10x/pull/45) | Real Settings scope copy plus the native request matrix; no policy value changed | Runtime exposes no active effective-policy field or Always Allow; stack integration |
| INPUT | [34](https://github.com/NextStep-AI-inc/10x/pull/34), [42](https://github.com/NextStep-AI-inc/10x/pull/42), [43](https://github.com/NextStep-AI-inc/10x/pull/43) | Text/images and separate drafts survive relaunch; one unconfirmed prompt restores without replay; picker inserts at caret; Undo/Redo, valid/invalid image and independent errors pass | Live CJK requires pending Pinyin approval; native drag/drop was not separately repeated; stack integration |
| DETAILS | [41](https://github.com/NextStep-AI-inc/10x/pull/41) | Advancing timer/latest output, Show more/Copy, both real multi-file paths open in Cursor, child transcript and retained recent tools | Controlled fixture supplies timed output/child progress; stack integration |

## Corrections found during native acceptance

- PR #38 now consumes authoritative `perFileResults`, fixing real multi-file edits that previously appeared as an unavailable “Changed file.” PR #41 reuses that correction.
- PR #41 retains live recent tools/output when final history for the same child omits those arrays. Recorded status, result, and model still win.
- PR #42 restores the saved route after optional startup preloading times out and Continue is chosen. The new guarded Continue regression and adjacent guards pass; final native relaunch exercised the normal prepared path.
- PR #43 uses an asynchronous native picker completion. The former blocking modal loop let SwiftUI restore the old draft during insertion. Real picker insertion and native Undo/Redo now pass; all 11 focused checks are green.

Each PR links its committed evidence with screenshots, exact source/build hashes, commands, pass counts, and exclusions. The latest resumed acceptance builds are indexed in [native-feature-builds.json](../evidence/2026-09-08-audit-acceptance/native-feature-builds.json). Earlier packages in `remaining-release-builds.json` are historical and may predate these native corrections.

## Acceptance handoff

The Mac was unlocked and all remaining feasible native flows were exercised. Every isolated QA app used for this acceptance was closed. Two neutral fixture files remain open in Cursor from editor navigation; the user's Cursor app was not quit. No user checkout, installed 10x application, provider policy, keyboard source, dependency, or deployment was changed.

Only the U.S. keyboard is enabled. A request to temporarily enable Apple Pinyin, perform the native composition/Return check, and remove it is pending because computer-use policy requires confirmation for that system-preference change. The existing AppKit marked-text and command-flyout checks passed. Elapsed time and a general “continue” were not treated as approval for changing the preference.

The complete audit stack remains separate feature branches. Final integration must carry forward the later durable Stop behavior, controller-owned disclosure, passive visible scroll targets, durable draft-send barrier/Continue correction, real multi-file extraction, child-detail reconciliation, and asynchronous picker. The original local base-merge action was rejected by automatic approval review and was not retried through another mechanism. No ready/merge/deploy claim is made. Merge is Tanner's decision.

Six original activity snapshot failures were reproduced at baseline and remain explicit readiness gates. One early SIGNALS instance exited cleanly after a response; no crash or cause was established, and a fresh controlled run completed the matrix. Intermittent optional startup warm-up timeouts are documented in the affected evidence. The invalid-image warning still mentions the generic eight-image limit; better failure-specific wording is a follow-up. These concerns were not expanded into unrelated implementation work.

The earlier completed-cache deletion was also rejected by automatic approval review. No listed cache was deleted; the OS later reclaimed enough space, so cache cleanup is no longer a prerequisite. All implementation and evidence work is committed on the branch refs below. No history was force-pushed.

## Branch handoff

| PR | Branch | Handoff commit |
| --- | --- | --- |
| [#32](https://github.com/NextStep-AI-inc/10x/pull/32) | `codex/active-session-recovery` | This roadmap commit / current branch HEAD |
| [#33](https://github.com/NextStep-AI-inc/10x/pull/33) | `codex/active-session-queue` | `7ae5f805661122016f538645650fe8632c672d2b` |
| [#34](https://github.com/NextStep-AI-inc/10x/pull/34) | `codex/active-session-images` | `96f6a7c17e9731cc3cef1b6ee6e6002ab9de6ebc` |
| [#35](https://github.com/NextStep-AI-inc/10x/pull/35) | `codex/active-session-turns` | `32349d23dd0260953b77aae8a247b83533bdd9d1` |
| [#36](https://github.com/NextStep-AI-inc/10x/pull/36) | `codex/active-session-stop` | `a026eb5756b85ff4f4668c574ced36d2f840a0fe` |
| [#37](https://github.com/NextStep-AI-inc/10x/pull/37) | `codex/active-session-signals` | `ab466c353b9531bad1098ef64e88ec4ff2cecb0f` |
| [#38](https://github.com/NextStep-AI-inc/10x/pull/38) | `codex/active-session-review` | `dcc2585ac5042a4c434d16d4cb776bcae023b13b` |
| [#39](https://github.com/NextStep-AI-inc/10x/pull/39) | `codex/active-session-context` | `4f9880f7b13192d8663a4d2180e73939d1cfa018` |
| [#41](https://github.com/NextStep-AI-inc/10x/pull/41) | `codex/active-session-details` | `e0c4b168c069b23e1fd6f7fdd9356622b6fced5c` |
| [#42](https://github.com/NextStep-AI-inc/10x/pull/42) | `codex/active-session-drafts` | `7eb79918435efca9fd66cdbcd6d706b097fb6e9c` |
| [#43](https://github.com/NextStep-AI-inc/10x/pull/43) | `codex/active-session-input` | `998d753b9e6d7974d99cab5d4ccc28d82eb20f88` |
| [#44](https://github.com/NextStep-AI-inc/10x/pull/44) | `codex/active-session-titles` | `64b67e4ce466ffc4cd4d0d8c319f1e285f987503` |
| [#45](https://github.com/NextStep-AI-inc/10x/pull/45) | `codex/active-session-permission-scope` | `aa312ed80ff9bac39bfa3abc468c3eb181c71229` |

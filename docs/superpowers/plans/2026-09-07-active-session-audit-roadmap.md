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

- [ ] **SIGNALS:** Main's rail already exposes working, needs-input, failure, stopped, and unread completion. Use the same session status for the header/turn/composer and provide a way to reach a pending request while reading older content. Verify switching between two sessions and non-overlapping states.
- [ ] **REVIEW:** Add a compact per-turn changed-file index linking to existing edit details. State its scope/completeness, deduplicate repeated paths, and avoid summed per-edit line totals. Exercise edit-tool and shell-generated files alongside pre-existing/concurrent changes. A tool-derived index may explicitly exclude shell writes; an observed git delta must not claim authorship. A full git review pane is a later product choice.
- [x] **CONTEXT:** Main has a usage meter/details, unknown/loading/failure states, and boundary refresh. Add an honest compaction action with availability/progress/failure feedback using supported runtime behavior. Verify usage before/after compaction and provider limitations; account quota remains distinct.
- [ ] **TITLES:** Main has persisted automatic titles, rename, search, and previous/next shortcuts. Remember the last valid session route and refresh git metadata after relevant changes. Verify duplicate titles, missing projects, relaunch, and branch metadata without changing the user's checkout.

## 5. Input and permission decisions

- [ ] **PERMISSIONS:** Main has independently addressable pending cards and rail attention. Explain the actual effective policy and its scope based on runtime evidence; do not invent a per-session mode or Always Allow response. Keep timeouts traceable. Verify confirm/select/input/cancel/timeout/multiple requests, focus during typing, Return, and Stop access.
- [ ] **INPUT:** Main preserves in-memory drafts and receipt state and offers slash-command discovery. Persist unsent text/images across relaunch; add deliberate file insertion through current transport capabilities; display attachment and model errors independently. Verify session switches, invalid images, multiple warnings, model failure, long paths, insertion while typing, and CJK composition before changing Return behavior.
- [ ] **DETAILS:** Preserve the existing reading-position and Jump to latest policy. Make running durations update, show useful current output during long commands, honor the preferred editor for diff paths including multi-file results, and expose supported child-session links/recent tool details. Verify send while scrolled up and switching sessions. Additional lower-priority observations from the 90-item coverage ledger are triaged only when they are required by these concrete acceptance criteria.

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

This is a progress record, not a claim that the entire stack is ready to merge. Native checks paused when the Mac locked; code review and focused tests continued. All PRs remain draft pending their stated acceptance and integration gates.

| Audit item | PRs | Current evidence | Remaining |
| --- | --- | --- | --- |
| SAVE / OPEN / ERROR | [32](https://github.com/NextStep-AI-inc/10x/pull/32) | Real warm/cold disk persistence, reopen, and distinct recovery paths verified | Stack integration |
| STOP | [36](https://github.com/NextStep-AI-inc/10x/pull/36) | Real background/foreground termination, preserved staged input, pending/model keyboard focus verified | Stack integration |
| QUEUE | [33](https://github.com/NextStep-AI-inc/10x/pull/33) | Follow-up/steering acceptance, decrement, rejection, and exactly one echo verified | Stack integration |
| ORDER / TURNS | [35](https://github.com/NextStep-AI-inc/10x/pull/35) | Final native acceptance and 33 affected regressions passed | Stack integration |
| SIGNALS | [37](https://github.com/NextStep-AI-inc/10x/pull/37) | Shared attention control, explicit jump, focus correction; 31 focused checks and approved snapshots | Native arrival/two-session acceptance |
| REVIEW | [38](https://github.com/NextStep-AI-inc/10x/pull/38) | Scoped tool-reported file list/navigation; 14 focused checks and approved snapshot | Native edit/write/multi-file navigation |
| CONTEXT | [39](https://github.com/NextStep-AI-inc/10x/pull/39) | Actual OMP snapcompact, controlled native busy/Stop/failure/unsupported, controller regressions | Final capture/QA close after unlock; integration. PNG and short timeout are regression-only |
| TITLES | [42](https://github.com/NextStep-AI-inc/10x/pull/42), [44](https://github.com/NextStep-AI-inc/10x/pull/44) | Last-valid-route regressions passed; fallback persistence/git refresh in implementation | Final review and native naming/metadata/route checks |
| PERMISSIONS | [37](https://github.com/NextStep-AI-inc/10x/pull/37), [45](https://github.com/NextStep-AI-inc/10x/pull/45) | Existing one-call card behavior retained; global-default scope plan committed | Scope copy and native request matrix. RPC has no active effective-policy field or Always Allow |
| INPUT | [34](https://github.com/NextStep-AI-inc/10x/pull/34), [42](https://github.com/NextStep-AI-inc/10x/pull/42), [43](https://github.com/NextStep-AI-inc/10x/pull/43) | Image history verified in Release; draft lifecycle and file/IME/error focused checks passed | Review corrections at disk-write/command-menu boundaries; native relaunch/picker/IME |
| DETAILS | [41](https://github.com/NextStep-AI-inc/10x/pull/41) | Reliable tool timing, running output tail, preferred editor, child links; focused checks and Release build passed | Native output/editor/child navigation |

The original six activity snapshot failures were reproduced at the baseline and remain explicit. Build/cache execution approval and Mac-lock limitations are recorded separately from code failures. No merge, deployment, actual user-policy change, or main-checkout edit has been performed.

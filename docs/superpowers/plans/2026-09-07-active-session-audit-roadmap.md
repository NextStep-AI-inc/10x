# Active-session audit implementation roadmap

The user authorized all actionable audit items in roadmap order. The historical report is preserved in [PR #31](https://github.com/NextStep-AI-inc/10x/pull/31). Its application baseline is `59a4ae8`; implementation was reconciled against main at `e60234a332f6fdc34f771c92f0d3852411d7fe71` before changing code.

Source inspection and existing test coverage are recorded separately from execution evidence. “Present” below does not claim fresh live verification. Larger workspace/file-explorer/terminal surfaces remain outside the approved audit recommendations.

## 1. Session continuity and recovery

[Plan](2026-09-07-session-continuity-recovery.md) · [PR #32](https://github.com/NextStep-AI-inc/10x/pull/32)

- [ ] **SAVE:** Verify existing persistent warm/cold creation and actual disk recovery across relaunch. Main rejects unpersisted sessions; preserve configured extensions when appending the session directory.
- [ ] **OPEN:** Verify first-action warm existing-session checkout loads and persists history. Retain the requested path when opening fails before a handle exists.
- [ ] **ERROR:** Verify failed-existing Retry opening, failed-new Review prompt, rejected input, and process-exit Restart separately. Preserve drafts and avoid automatic resend after uncertain delivery.

## 2. Interrupt and acknowledge

- [ ] **STOP:** Main has independent Stop beside Send and Cmd-Period. Verify staged text/images, actual runtime settling, open flyouts, and focused pending decisions; change only if the real flow fails.
- [ ] **QUEUE:** Main has per-message sending/queued/unconfirmed receipts with echo reconciliation. Refresh the authoritative queue count after acceptance and consumption, without allowing older replies to overwrite newer state. Verify multiple follow-ups, steering, rejection, and exactly one echo per accepted message.

## 3. Readable turns

- [ ] **ORDER:** Main normalizes contiguous text segments around inline tools for live and reopened history, retaining message identity and render lineage. Verify real provider live/completion/reopen order and parallel completions. Existing fixtures cover text/tool/text, duplicate IDs, repeated snapshots, and reconciliation.
- [ ] **TURNS:** Keep existing tool grouping and disclosure. Add stable turn boundaries, completed duration/status, and activity derived from the active turn/tool set. Verify long quiet intervals, streaming text, concurrent tools, errors, completion, and preserved disclosure state.

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
- No current-main live acceptance is claimed yet.
- Keep each item unchecked until this run has evidence for its full stated scope, or explicitly record the remaining limitation beside it.

- CONTEXT: implemented and verified on the feature branch; [PR #39 evidence](../evidence/2026-09-08-context-compaction/README.md) records actual native compaction, controlled failure/Stop, and the final lock-related capture/cleanup limit.

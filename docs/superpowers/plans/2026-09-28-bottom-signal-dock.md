# Shared Bottom Signal Dock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the centered composer card with a fixed borderless prompt and a persistent workspace line that shows measured session context and activity.

**Architecture:** `AppShellView` reserves bottom space for one dock on post-setup routes. The existing `ComposerView` remains the single owner of editor, attachment, flyout, and send behavior; a reusable signal view draws the line in composer and non-composer states. `SessionController` supplies measured context and transient event facts, while a pure presentation mapper resolves priority and copy.

**Tech Stack:** macOS 15+, SwiftUI, Swift Testing, existing OMP RPC and snapshot harness. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-28-bottom-signal-dock-design.md`

## Global Constraints

- Use a worktree; leave the main checkout untouched. The draft PR is #49 on `codex/bottom-dock-design`. Do not merge without Tanner's instruction.
- Preserve current New Session draft, active-session draft, keyboard, paste/drop, command browser, model/project, queue, transcript, tool-card, and manual-compaction recovery behavior.
- Reuse `StartupSignalGeometry` and the same complete path; only its last approximately 175 points wave. Do not alter the splash presentation.
- The editor viewport is about 106 points high; only its upper roughly 24 points fade, and only when text scrolls. The line never fades under typing.
- Context comes only from `get_state.contextUsage`. The threshold is 95%; post-compaction reveal is about 750 ms. No simulated context values or numeric compaction progress.
- Regenerate `10x.xcodeproj` with `bundle exec ruby scripts/generate_xcodeproj.rb` when adding Swift files; never edit `project.pbxproj` manually. Check the generated diff for unrelated churn.
- Use function selectors in `xcodebuild test`, including `()`. A red run may stop at compilation; every green run must report a nonzero Swift Testing count (`docs/testing.md`). Verify a production build and the real app before claiming the UI works.

## Review Focus

1. A delayed `get_state` from before send or session replacement must not roll back optimistic Working, context, or queue. Task 2 adds fixture-backed tests.
2. Missing context and measured 95–100% context must keep the exact number/endpoint visible while the warning remains legible. Tasks 1 and 3 add mapping and rendering tests.
3. Automatic compaction end, abort, skip, delayed refresh, and failed refresh must settle without a cyan jump; manual compaction must retain its existing recovery. Task 5 tests both paths.
4. Search, rename/deletion, extension sheets, route switches, and an IME composition must not steal or misroute editor focus or submission. Task 4 adds interaction tests.
5. A narrow window with an expanded rail and provider wheels must preserve Send, status, context, and wheel hit targets without overlap. Task 6 adds layout tests and snapshots.

---

## File map and ownership

| File | Responsibility |
| --- | --- |
| `App/Shell/WorkspaceSignalPresentation.swift` (new) | Pure session/workspace status priority, exact labels, context display inputs. |
| `App/Shell/WorkspaceSignalView.swift` (new) | Shared path paint, shimmer, reverse sweep, reveal, Reduce Motion, and accessibility. |
| `App/Shell/WorkspaceDockView.swift` (new) | Route-specific composer or quiet footer, below-line zones, provider slot. |
| `App/Startup/StartupSignalView.swift` | Expose its existing path shape internally for reuse; splash output stays the same. |
| `App/Sessions/SessionController.swift` | Event facts, guarded context/queue refresh, automatic-compaction visual phase. |
| `App/Sessions/TranscriptEventProcessor.swift` | Forward retry events in the existing ordered control stream. |
| `App/Sessions/ComposerView.swift`, `App/Sessions/ComposerTextViewConfigurator.swift` | Fixed borderless editor, scroll-aware top text mask, line seam, below-line controls. |
| `App/Sessions/ActiveSessionView.swift`, `App/Sessions/NewSessionView.swift` | Leave transcript/recovery or new-session content above the shell dock. |
| `App/Shell/AppShellView.swift`, `App/Providers/ProviderUsageDockLayout.swift`, `App/Providers/ProviderAccountCoordinator.swift`, `App/Application/AppModel.swift` | Reserve shell height, make provider placement responsive, expose aggregate work count. |
| `Tests/TenXAppTests/*` | Focused Swift Testing functions and reviewed snapshots beside existing fixtures. |

## Task 1: Signal meaning and precedence

**Files:** Create `App/Shell/WorkspaceSignalPresentation.swift`; test `Tests/TenXAppTests/WorkspaceSignalPresentationTests.swift`.

**Interfaces:** Produce `enum WorkspaceSignalStatus: Equatable` with `opening`, `ready`, `working`, `needsInput`, `retrying`, `compacting`, `refreshingContext`, `nearLimit`, `failed`, `responseStopped`, `backgroundWorking(Int)`, `workspaceReady`; `enum SessionCompactionSignalPhase: Equatable` with `none`, `sweeping`, `refreshing`, `revealing(generation: UInt64, percent: Int)`; and `WorkspaceSignalPresentation.session(runtimeState: SessionRuntimeState, contextPercent: Int?, hasPendingUserInput: Bool, isRetrying: Bool, hasTerminalRetryFailure: Bool, compactionPhase: SessionCompactionSignalPhase, isRecoveryPresented: Bool, isIntentionallyStopped: Bool) -> Self`, plus `.workspace(generatingCount: Int) -> Self`. Presentation exposes `status`, measured `contextPercent`, `label`, and one combined accessibility label; `contextPercent` is nil if unavailable. Terminal failure > input > retry > compaction > >=95% warning > working > ready. Opening and intentional Stop are explicit exceptions; `.revealing` shows underlying Working/Ready while its measured fill animates.

- [ ] **Step 1: Write failing tests and regenerate the project** for `signalPriorityKeepsInputAboveRetryAndCompaction()`, `nearLimitKeepsMeasuredNinetyFiveAndHundredPercent()`, `unavailableContextHasNoFillOrInventedNumber()`, `workspaceCountNeverShowsSessionContext()`. Assert each exact status and label (`Needs input`, `Near limit`, `Context —`, `2 working`); intentional Stop stays neutral until restart.
- [ ] **Step 2: Run those functions** with `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:'TenXAppTests/signalPriorityKeepsInputAboveRetryAndCompaction()'` (and the other exact function selectors). Confirm the expected missing-type compile failure or failing assertion, never a vacuous green run.
- [ ] **Step 3: Implement the pure mapper and regenerate the project**; keep color and animation timing in the view, not in controller state. Clamp only paint fraction to 0…1; retain the exact measured percent for copy.
- [ ] **Step 4: Repeat the selected tests**; expect each PASS and nonzero test count.
- [ ] **Step 5: Inspect the generated diff and commit** `feat: define workspace signal presentation`.

## Task 2: Current measured facts across asynchronous boundaries

**Files:** Modify `App/Sessions/SessionController.swift`, `App/Sessions/TranscriptEventProcessor.swift`, `Tests/TenXAppTests/SessionControllerTests.swift`, `Tests/TenXAppTests/TranscriptEventProcessorTests.swift`, and `Tests/TenXAppTests/Fixtures/context_fake_server.py` only if its existing modes cannot express a delayed reply.

**Interfaces:** Consume `SessionCompactionSignalPhase` from Task 1. Produce observable `private(set) var signalCompactionPhase: SessionCompactionSignalPhase`, `private(set) var isSignalRetrying: Bool`, and `private(set) var hasTerminalRetryFailure: Bool` on `SessionController`; preserve existing `contextPercentage`, `queuedMessageCount`, `runtimeState`, and `turnStartedAt` interfaces. Keep `scheduleContextRefresh()` as the single coalesced context/queue read path; mark accepted sends as a newer context revision and guard `refreshState()` against stale streaming-state replies. Do not make a context-only read failure call `fail()`.

- [ ] **Step 1: Write failing tests** `retryStartAndEndReachOrderedControls()` for both events; `acceptedSendRejectsOlderStateReply()` for optimistic Working/context/queue; `replacementSessionRejectsDelayedContextReply()` for pipeline generation; `failedContextReadKeepsRuntimeHealthy()` for unchanged runtime and an error fact. Assert automatic compaction controls already reach the controller, so the forwarding change is limited to retry.
- [ ] **Step 2: Run exact function selectors** with the `xcodebuild test` command above; confirm expected compile failure or failing assertions, never a vacuous green run.
- [ ] **Step 3: Implement event forwarding and revision guards** using existing `contextRevision`, `contextRefreshTask`, and `PipelineContext`; refresh context and queue after accepted send and turn boundaries. A stale general state reply must never set a new `.streaming` turn back to `.idle`. Preserve manual compaction's authoritative history reload and recovery.
- [ ] **Step 4: Re-run those functions** and the existing `contextRefreshRecoversFromATransientReadFailure()` and `successfulManualCompactionReloadsHistoryAndPreservesStagedInput()`; expect PASS and nonzero counts.
- [ ] **Step 5: Commit** `fix: guard live context and retry state updates`.

## Task 3: One full-width path and deterministic motion

**Files:** Create `App/Shell/WorkspaceSignalView.swift`; modify `App/Startup/StartupSignalView.swift`; test `Tests/TenXAppTests/WorkspaceSignalViewTests.swift` and `Tests/TenXAppTests/ViewSnapshotTests.swift` (new signal-only references).

**Interfaces:** Consume `WorkspaceSignalPresentation`, `SessionCompactionSignalPhase`, and `StartupSignalGeometry`. Produce `WorkspaceSignalView(presentation: WorkspaceSignalPresentation, compactionPhase: SessionCompactionSignalPhase, onRevealComplete: @escaping (UInt64) -> Void)`. Expose the existing `StartupSignalShape` internally (or rename in the same file) so the workspace view uses exactly the same path. `WorkspaceSignalMotion` supplies testable `sweepCoverage(elapsed: TimeInterval, reduceMotion: Bool) -> CGFloat` (approaches a visual cap, never reaches full coverage before end; zero when motion is reduced), `revealFraction(progress: Double, target: CGFloat) -> CGFloat` (zero at start, target at completion), `revealDuration = 0.75`, and `shimmerRange(status: WorkspaceSignalStatus, contextFraction: CGFloat) -> ClosedRange<CGFloat>?` for the available status span.

- [ ] **Step 1: Write failing tests and regenerate the project** for `signalWaveUsesTheLast175PointsAtAnyWidth()`, `workingShimmerStaysOnRemainderAndOpeningUsesWholePath()`, `reverseSweepCapsWhileWaitingAndRevealStartsAtZero()`, `reduceMotionRemovesTravel()`, plus signal-only snapshots at 50% and measured 98% with endpoint marker/amber right mark.
- [ ] **Step 2: Run each exact test selector**; confirm expected missing-type failure or missing reference, never a vacuous green run.
- [ ] **Step 3: Implement the path and motion, then regenerate the project**: cyan `.trim(from: 0, to: measuredFraction)` over the same near-black shape; warning/error can paint the final ~80 points without changing the true marker. Opening shimmer covers the full path, Working shimmers only over the remainder. Compaction covers from right to left; on measured completion paint cyan from zero to the new endpoint over 0.75 seconds, then call `onRevealComplete(generation)`. Keep the line still for typing/idle and Reduce Motion.
- [ ] **Step 4: Run tests, inspect generated `.actual.png`, promote only approved references, then rerun**; expect PASS and nonzero count. Confirm splash signal snapshots are byte-identical.
- [ ] **Step 5: Inspect the generated diff and commit** `feat: draw shared workspace signal line`.

## Task 4: Working shell slice and borderless composer

**Files:** Create `App/Shell/WorkspaceDockView.swift`; modify `App/Shell/AppShellView.swift`, `App/Sessions/ComposerView.swift`, `App/Sessions/ComposerTextViewConfigurator.swift`, `App/Sessions/ActiveSessionView.swift`, `App/Sessions/NewSessionView.swift`; test `Tests/TenXAppTests/ComposerInteractionRoutingTests.swift`, `Tests/TenXAppTests/ExtensionUIRouterTests.swift`, and `Tests/TenXAppTests/ViewSnapshotTests.swift`.

**Interfaces:** Consume Tasks 1–3. `WorkspaceDockView(model: AppModel, isFocusBlocked: Bool)` selects `.newSession` or the matching `activeSession` composer, otherwise the neutral workspace footer. `ComposerView` keeps its existing bindings and callbacks; add `signalPresentation: WorkspaceSignalPresentation = .workspace(generatingCount: 0)` for standalone previews, `signalCompactionPhase: SessionCompactionSignalPhase = .none`, `onSignalRevealComplete: @escaping (UInt64) -> Void = { _ in }`, `isFocusBlocked: Bool = false`. Its outer view fills the shell width so `WorkspaceSignalView` spans beneath the rail; only editor/controls are capped at 780 points and centered. Add `ComposerFocusRouting.shouldFocusEditor(isAvailable: Bool, isFocusBlocked: Bool, hasBlockingSheet: Bool) -> Bool` and use it for initial and restored focus. `ComposerTextEditorBridge.onScrollStateChange: ((Bool) -> Void)?` reports whether the text viewport has scrolled; the shell passes search/modal state and the composer also respects active extension sheet focus. Keep one route-specific `@State` flyout in the dock, reset on route or controller identity changes; drafts remain in `AppModel`/`SessionController`.

- [ ] **Step 1: Write failing interaction and snapshot tests** `blockedComposerDoesNotReclaimFocus()` for search/sheet/mutation cases, `routeSwitchClosesFlyoutWithoutLosingDraft()`, `passiveExtensionNoticeDoesNotBlockComposer()`, and full-shell New Session/active/Archived snapshots. Re-run existing Return/IME routing tests as regressions. Assert one line, 106-point editor height, a top-only 24-point scroll mask only after scrolling, no card border, and below-line model/thinking/context/timer plus Steer/Follow up/Send/Stop and existing `n queued` copy.
- [ ] **Step 2: Run exact selectors** and confirm expected compile/assertion failures or missing references, never a vacuous green run.
- [ ] **Step 3: Move composer placement to the shell and regenerate the project** using a vertical route/rail region followed by the dock. Keep RuntimeRecoveryView and New Session recovery above it, and the rail's Archived action above the line. Move New Session's `NSOpenPanel` project callback into the dock. Remove dynamic hidden-text editor sizing and card fill/border; preserve existing text editor bridge, keyboard routing, paste/drop, attachments, controls, and flyouts. Observe the AppKit text viewport's scroll position through the existing bridge and mask only its top 24 points after it scrolls; use `turnStartedAt` for the working timer. Retain the current provider anchor temporarily until Task 6 moves the wheels into layout.
- [ ] **Step 4: Test the selected interactions and review/promote affected snapshots** at 760×560 and 1280×760. Build with `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS'`; expect BUILD SUCCEEDED and nonzero selected tests.
- [ ] **Step 5: Inspect the generated diff and commit** `feat: place borderless composer in shared dock`.

## Task 5: Automatic compaction, retry, and end transitions

**Files:** Modify `App/Sessions/SessionController.swift`, `App/Shell/WorkspaceSignalView.swift`, `Tests/TenXAppTests/Fixtures/context_fake_server.py` if needed; test `Tests/TenXAppTests/SessionControllerTests.swift` and `Tests/TenXAppTests/WorkspaceSignalViewTests.swift`.

**Interfaces:** Consume Task 2's observable event facts and Task 3's `onRevealComplete`. Add `SessionController.completeSignalReveal(generation: UInt64)`; it only clears a matching `.revealing` phase. A new compaction increments the generation. Successful automatic end enters `.refreshing`, then existing guarded context refresh yields `.revealing(generation:percent:)`; the signal view performs the visual reveal. Failed refresh sets context unavailable and resumes the underlying Working/Ready status. Manual compaction continues its existing authoritative workflow.

- [ ] **Step 1: Write failing tests** `automaticCompactionWaitsForMeasuredStateBeforeReveal()`, `delayedRefreshCannotCompleteAnOlderCompaction()`, `abortedAndSkippedCompactionsDoNotReveal()`, `terminalRetryFailureOutranksWorkingUntilNextTurn()`, `manualCompactionReadFailureStillShowsRecovery()`, and `toolErrorDuringOngoingTurnLeavesWorkingSignal()`.
- [ ] **Step 2: Run exact selectors**; confirm expected compile/assertion failures, never a vacuous green run.
- [ ] **Step 3: Implement the state transitions** for `auto_compaction_start/end`, `auto_retry_start/end`, accepted new turn, and post-compaction refresh. For aborted `willRetry`, show Retry; for terminal abort/final retry failure, show failure. Hold covered line with `Refreshing context` until measured reply. Never expose a new number before that reply. Preserve last measured context on abort and clear it on failed successful-refresh. While manual compaction is active, use its existing authoritative state read for the reveal, without a second read; retain manual recovery on authoritative read failure.
- [ ] **Step 4: Run the selected functions** and the existing manual-compaction tests; expect PASS. Inspect a 90%→30% fixture render to confirm the line completes the reverse sweep, holds, then reveals from zero to exactly 30% without a jump; Reduce Motion switches directly to 30%.
- [ ] **Step 5: Commit** `feat: animate measured context after compaction`.

## Task 6: Provider placement, workspace activity, and final experience

**Files:** Modify `App/Providers/ProviderAccountCoordinator.swift`, `App/Application/AppModel.swift`, `App/Providers/ProviderUsageDockLayout.swift`, `App/Shell/WorkspaceDockView.swift`, `App/Shell/AppShellView.swift`, `App/Sessions/ComposerView.swift`; test `Tests/TenXAppTests/ProviderUsageDockLayoutTests.swift`, `Tests/TenXAppTests/ProviderAccountCoordinatorTests.swift`, `Tests/TenXAppTests/ViewSnapshotTests.swift`.

**Interfaces:** Produce `ProviderAccountCoordinator.generatingSessionCount: Int` from all managed generating sessions, including those with nil provider ID; expose it through `AppModel` for `.workspace(generatingCount:)`. Replace `ProviderUsageDockLayout.compact(shellSize:footerFrame:)` and the composer anchor/width environment with `ProviderUsageDockLayout.placement(availableWidth: CGFloat, factsMinWidth: CGFloat, actionsMinWidth: CGFloat, providerWidth: CGFloat) -> ProviderUsageDockPlacement` (`.belowLine` or `.aboveLine`). Use the existing `footerWidth(providers:)` for `providerWidth`. `ProviderUsageDockView` and its expanded panel retain existing actions and data.

- [ ] **Step 1: Write failing tests** `backgroundCountIncludesUnknownProvider()`, `narrowDockMovesProviderGroupAboveWithoutCoveringEditor()`, `minimumWidthPreservesSendStatusAndWheelHitTargets()`, and wide/narrow full-shell snapshots with expanded rail and provider wheels.
- [ ] **Step 2: Run exact selectors**; confirm expected compile/assertion failures or missing references, never a vacuous green run.
- [ ] **Step 3: Implement three flexible dock zones**: facts left, message actions near center, provider group right. At narrow width, wrap/collapse low-priority facts and move wheels above the line on the right; the expanded provider panel opens upward. Remove the old anchor/offset infrastructure and keep the line at a fixed vertical position across route changes. Keep provider wheel hit targets at least 44 points.
- [ ] **Step 4: Run selected tests, inspect/promote snapshots, and run the full suite** with `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'`; require nonzero Swift Testing count and no unreviewed `.actual.png` files. Rebuild Release. Drive the built app through typing/scrolling, paste/drop, model/project, send, Steer, Follow up, Stop, input, compaction, retry, failure, route changes, keyboard order, VoiceOver, and Reduce Motion. Capture real screenshots for ready, working, near-limit, compacting, input, failure, and non-session routes. Follow `launching-local-builds` and `verifying-work` before the live run.
- [ ] **Step 5: Regenerate project, inspect diff, commit** `feat: integrate provider usage into workspace dock`; then report Verified / Not verified / For Tanner to test with screenshots and exact build/test counts. Keep PR draft until live evidence is complete, then follow `writing-prs` and `reviewing-code` before requesting merge; never merge without Tanner's instruction.

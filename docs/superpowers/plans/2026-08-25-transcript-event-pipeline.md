# Transcript Event Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Drain and reduce lossless RPC traffic off the main actor, discard unsupported frames, publish replaceable transcript snapshots at no more than 20 Hz during streaming, and prove the real Release UI remains responsive and settles after a deterministic 1,000-update workload.

**Architecture:** A TranscriptEventProcessor actor becomes the sole TranscriptReducer owner. It consumes RpcClient.events, yields complete TranscriptSnapshot values through a newest-one stream, and forwards only low-frequency metadata, extension, and persistence boundaries through a lossless filtered control stream. SessionController installs snapshots on the main actor and coordinates commands, metadata, extensions, recovery, and reconciliation.

**Tech Stack:** macOS 15+, Swift 6 actors and AsyncStream, SwiftUI Observation, OmpKit RPC, Swift Testing, Python fixture server, xcodebuild, Instruments. No new runtime dependency.

**Spec:** docs/superpowers/specs/2026-08-25-transcript-event-pipeline-design.md

**Static baseline evidence:** SessionController currently consumes every RpcFrame on MainActor, assigns the reducer's complete item array on every frame, and shares array storage so the next reducer mutation performs copy-on-write. Complete growing message snapshots repeatedly invalidate rich SwiftUI content. Unsupported events accumulate as invisible TranscriptItem.rawEvent rows. Settled app idle is about 0% CPU; Task 1 captures the missing controlled streaming baseline before changing this path.

## Constraints

- Work only in codex/performance-runoff at /Users/tannerpham/CS Projects/.worktrees/10x-performance-profile.
- When both approved plans are executed, complete Task 1 here before Persistent Session Search Task 1; the plan-only commits do not affect the baseline binary.
- Complete Task 1 and record the baseline before modifying TranscriptReducer, SessionController, or transcript views.
- Keep LineTransport and RpcClient streams unbounded and lossless. Bound only complete UI snapshots with bufferingNewest(1).
- Preserve frame order, final message/tool state, extension requests, reconciliation boundaries, recovery, draft preservation, and existing transcript appearance.
- Unsupported payloads are discarded silently and never logged.
- Use test-driven-development for every reducer/processor/controller behavior.
- Before Task 5, load writing-ui and visual-ui. No copy or visual change is intended; snapshots must remain unchanged.
- Run ruby scripts/generate_xcodeproj.rb after adding or removing Swift files.
- Verify a Release build. Load launching-local-builds before launching it and verifying-work before claiming completion.
- A draft PR cannot be opened because this repository has no remote; atomic commits are the handoff boundary.

## Task 1: Create one repeatable burst and capture the pre-fix baseline

**Files:**
- Modify: OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py
- Modify: OmpKit/Tests/OmpKitTests/ProcessManagerTests.swift
- Create: scripts/performance/omp
- Create: docs/performance/2026-08-25-transcript-streaming.md

- [ ] Add transcript-burst mode to fake_server.py. After a prompt acknowledgement, emit agent_start, message_start for assistant id burst-message, 1,000 message_update frames containing the complete growing message snapshot, message_end with the final identical snapshot, and terminal agent_end. Append one deterministic token per update and sleep 2 ms between updates so the workload lasts about two seconds.
- [ ] Keep the existing burst mode unchanged. Add a ProcessManager test named managerPreservesThousandGrowingMessageSnapshots. Drive one prompt, consume events until terminal agent_end, and assert exactly 1,000 updates, monotonically growing visible text, one final message, and the terminal boundary.
- [ ] Run the focused OmpKit test and confirm failure before adding the fixture mode:

      swift test --package-path OmpKit --filter managerPreservesThousandGrowingMessageSnapshots

- [ ] Implement the fixture mode and add scripts/performance/omp as an executable Python wrapper. With --version it prints a fixed non-empty version and exits zero. For all RPC arguments it runs fake_server.py in transcript-burst mode. Resolve the fixture path relative to the wrapper so it works from any current directory.
- [ ] Mark only the wrapper executable, rerun the focused test, and verify the app locator contract manually:

      chmod +x scripts/performance/omp
      scripts/performance/omp --version
      swift test --package-path OmpKit --filter managerPreservesThousandGrowingMessageSnapshots

- [ ] Build the unmodified app pipeline in Release with task-specific DerivedData:

      xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-transcript-baseline-release build

- [ ] Load launching-local-builds. Launch the exact baseline bundle executable with a disposable home and the fixture first on PATH, preserving system paths:

      mkdir -p /private/tmp/tenx-transcript-profile-home /private/tmp/tenx-transcript-profile-project
      CFFIXED_USER_HOME=/private/tmp/tenx-transcript-profile-home PATH="$PWD/scripts/performance:/usr/bin:/bin:/usr/sbin:/sbin" /private/tmp/tenx-transcript-baseline-release/Build/Products/Release/10x.app/Contents/MacOS/10x

- [ ] Provenance amendment (Tanner-approved): the production UI has no consumer of `OmpInstallation.version`, so do not add product UI solely for benchmark provenance. Prove fixture selection with the exact `scripts/performance/omp --version` output and the profiled app's recursively verified owned child executable path and `fake_server.py transcript-burst` argv. Through the real UI choose /private/tmp/tenx-transcript-profile-project, start a session, type burst into the composer, and click Send. Do not invoke the RPC endpoint directly.
- [ ] Record the exact app PID with Time Profiler plus one-second process CPU/RSS/physical-footprint samples from five seconds before Send until five seconds after terminal agent_end. Store binary traces only under /private/tmp/tenx-performance-recordings/baseline-transcript.
- [ ] In docs/performance/2026-08-25-transcript-streaming.md record commit SHA, OS/machine, Release bundle path, workload/cadence, commands, peak CPU, peak RSS, peak physical footprint, main-thread CPU time, visible responsiveness, post-burst idle, and the hottest SessionController/TranscriptReducer/SwiftUI/MessageContentParser stacks. Label this table Baseline and leave Fixed pending.
- [ ] Stop only the exact baseline PID. Confirm no child fake OMP process remains.
- [ ] Commit: test(perf): add transcript burst baseline

## Task 2: Make reducer mutations explicit and delete invisible retention

**Files:**
- Modify: App/Sessions/TranscriptReducer.swift
- Modify: App/Sessions/TranscriptItem.swift
- Modify: App/Sessions/TranscriptView.swift
- Modify: Tests/TenXAppTests/TranscriptReducerTests.swift

- [ ] Add this result type beside TranscriptReducer:

      enum TranscriptMutation: Equatable, Sendable {
          case none
          case coalesced
          case immediate
      }

- [ ] Add failing tests named unknownEventsAreDiscardedWithoutMutation, tenThousandUnknownEventsAddNoRows, malformedKnownEventsDoNotPublish, messageAndToolUpdatesAreCoalesced, and boundariesAndVisibleChangesAreImmediate.
- [ ] Assert exact classifications: non-event/unknown/malformed known frames are .none; message_update, tool_execution_update, and subagent_progress are .coalesced only when they changed state; starts, ends, notices, annotations, runtime transitions, tool completion, subagent lifecycle, history load, extension changes, and reconciliation are .immediate.
- [ ] Run the five tests and confirm the current Void return and rawEvent accumulation fail:

      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-transcript-reducer-tests test '-only-testing:TenXAppTests/unknownEventsAreDiscardedWithoutMutation()' '-only-testing:TenXAppTests/tenThousandUnknownEventsAddNoRows()' '-only-testing:TenXAppTests/malformedKnownEventsDoNotPublish()' '-only-testing:TenXAppTests/messageAndToolUpdatesAreCoalesced()' '-only-testing:TenXAppTests/boundariesAndVisibleChangesAreImmediate()'

- [ ] Change consume to @discardableResult mutating func consume(_ frame: RpcFrame) -> TranscriptMutation. Return .none before every malformed guard, .coalesced only for valid replacement updates, and .immediate for every valid visible/boundary mutation.
- [ ] Make load(messages:), load(history:), ensureThreadStart, setReconciliationWarning, reconcile, upsertExtensionUI, removeExtensionUI, and appendNotice return .none when identical state is retained and .immediate when their state changes.
- [ ] Delete TranscriptItem.rawEvent, the default append in TranscriptReducer, the reconciliation retention case, and the EmptyView switch case in TranscriptView. The default reducer branch returns .none.
- [ ] Run all TranscriptReducerTests and the complete app suite. Regenerate no snapshots; this removes only invisible rows:

      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-transcript-reducer-tests test '-only-testing:TenXAppTests/unknownEventsAreDiscardedWithoutMutation()' '-only-testing:TenXAppTests/tenThousandUnknownEventsAddNoRows()' '-only-testing:TenXAppTests/malformedKnownEventsDoNotPublish()' '-only-testing:TenXAppTests/messageAndToolUpdatesAreCoalesced()' '-only-testing:TenXAppTests/boundariesAndVisibleChangesAreImmediate()'
      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-transcript-reducer-tests test
      git diff --exit-code -- Tests/TenXAppTests/ReferenceImages

- [ ] Commit: fix(transcript): discard unsupported events

## Task 3: Add the off-main event processor and bounded snapshots

**Files:**
- Create: App/Sessions/TranscriptSnapshot.swift
- Create: App/Sessions/TranscriptEventProcessor.swift
- Modify: App/Sessions/SessionRuntimeState.swift
- Modify: App/Sessions/TranscriptHistoryMapper.swift
- Modify: App/Sessions/TranscriptItem.swift
- Modify: App/Sessions/TranscriptMessage.swift
- Modify: App/Sessions/TranscriptAnnotation.swift
- Modify: App/Sessions/SubagentPresentation.swift
- Modify: App/Tools/ToolPresentation.swift
- Modify: App/ExtensionUI/ExtensionUIState.swift
- Create: Tests/TenXAppTests/TranscriptEventProcessorTests.swift

- [ ] Add Sendable to every value crossing the actor boundary: SessionRuntimeState, TranscriptHistory, TranscriptItem, TranscriptMessageRole, TranscriptResponseAttribution, TranscriptMessage, TranscriptAnnotation and its nested enums, ToolPhase, ToolPresentation, SubagentStatus, SubagentRecentTool, SubagentPresentation, ExtensionSelectOption, and ExtensionUIState. Do not use @unchecked Sendable.
- [ ] Define the processor data contract:

      struct TranscriptSnapshot: Equatable, Sendable {
          let processorID: UUID
          let revision: UInt64
          let items: [TranscriptItem]
          let runtimeState: SessionRuntimeState
      }

      enum TranscriptInitialContent: Sendable {
          case history(TranscriptHistory)
          case messages([JSONValue])
      }

- [ ] Add failing processor tests named burstUpdatesCoalesceIntoOneManualFlush, coalescedPublicationNeverExceedsTwentyPerSecond, immediateBoundaryFlushesBeforeControlForwarding, extensionAndReconciliationControlsRemainOrdered, malformedAndUnknownFramesProduceNoSnapshot, stoppingProcessorFinishesStreams, and latestSnapshotBufferDropsOnlySupersededSnapshots.
- [ ] In the burst test, feed 1,000 valid growing message_update frames after one start, use an interval longer than the test plus flush(), and assert one coalesced publication contains the complete final text. In the rate test, feed continuously for one measured second and assert at most 20 non-boundary snapshots. Avoid timing sleeps in semantic tests by using the explicit flush method.
- [ ] Run the focused tests and confirm TranscriptEventProcessor is missing:

      ruby scripts/generate_xcodeproj.rb
      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-transcript-processor-tests test '-only-testing:TenXAppTests/burstUpdatesCoalesceIntoOneManualFlush()' '-only-testing:TenXAppTests/coalescedPublicationNeverExceedsTwentyPerSecond()' '-only-testing:TenXAppTests/immediateBoundaryFlushesBeforeControlForwarding()' '-only-testing:TenXAppTests/extensionAndReconciliationControlsRemainOrdered()' '-only-testing:TenXAppTests/malformedAndUnknownFramesProduceNoSnapshot()' '-only-testing:TenXAppTests/stoppingProcessorFinishesStreams()' '-only-testing:TenXAppTests/latestSnapshotBufferDropsOnlySupersededSnapshots()'

- [ ] Implement this actor surface without marking it MainActor:

      actor TranscriptEventProcessor {
          nonisolated let id: UUID
          nonisolated let snapshots: AsyncStream<TranscriptSnapshot>
          nonisolated let controlEvents: AsyncStream<RpcFrame>

          init(
              id: UUID = UUID(),
              publicationInterval: Duration = .milliseconds(50)
          )

          func load(
              _ content: TranscriptInitialContent,
              threadStartDate: Date?,
              hasReconciliationWarning: Bool,
              runtimeState: SessionRuntimeState
          ) -> TranscriptSnapshot
          func run(events: AsyncStream<RpcFrame>) async
          func consume(_ frame: RpcFrame)
          func setRuntimeState(_ state: SessionRuntimeState)
          func upsertExtensionUI(_ state: ExtensionUIState)
          func removeExtensionUI(id: String)
          func appendNotice(level: String, message: String)
          func reconcile(_ history: TranscriptHistory, hasWarning: Bool)
          func currentSnapshot() -> TranscriptSnapshot
          func flush() -> TranscriptSnapshot?
          func stop()
      }

- [ ] Construct snapshots with bufferingNewest(1) and controls with unbounded buffering. The actor is the only TranscriptReducer owner. load initializes revision 1 and returns the initial snapshot without also yielding it, preventing a duplicate initial installation. A coalesced mutation schedules one 50 ms publication task; further coalesced mutations do not schedule more. An immediate mutation cancels the timer and publishes synchronously on the actor.
- [ ] Filter controls to extensionUIRequest plus event types session_info_update, config_update, thinking_level_changed, model_changed, message_end, turn_end, prompt_result, and terminal agent_end. A malformed message/tool boundary is not forwarded. For an event that is both a valid transcript mutation and control boundary, publish its immediate snapshot before yielding the control frame.
- [ ] stop cancels the timer, invalidates future consume calls, and finishes both continuations. run calls stop when the source stream terminates. flush publishes only dirty state and is deterministic for tests; it does not create duplicate revisions when nothing changed.
- [ ] Regenerate the project, run processor tests plus reducer tests, and inspect concurrency diagnostics. No unsafe isolation escape or @unchecked conformance is accepted:

      ruby scripts/generate_xcodeproj.rb
      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-transcript-processor-tests test '-only-testing:TenXAppTests/burstUpdatesCoalesceIntoOneManualFlush()' '-only-testing:TenXAppTests/coalescedPublicationNeverExceedsTwentyPerSecond()' '-only-testing:TenXAppTests/immediateBoundaryFlushesBeforeControlForwarding()' '-only-testing:TenXAppTests/extensionAndReconciliationControlsRemainOrdered()' '-only-testing:TenXAppTests/malformedAndUnknownFramesProduceNoSnapshot()' '-only-testing:TenXAppTests/stoppingProcessorFinishesStreams()' '-only-testing:TenXAppTests/latestSnapshotBufferDropsOnlySupersededSnapshots()'
      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-transcript-processor-tests test '-only-testing:TenXAppTests/unknownEventsAreDiscardedWithoutMutation()' '-only-testing:TenXAppTests/tenThousandUnknownEventsAddNoRows()' '-only-testing:TenXAppTests/malformedKnownEventsDoNotPublish()' '-only-testing:TenXAppTests/messageAndToolUpdatesAreCoalesced()' '-only-testing:TenXAppTests/boundariesAndVisibleChangesAreImmediate()'

- [ ] Commit: feat(transcript): coalesce event snapshots off main

## Task 4: Make SessionController coordinate instead of reduce

**Files:**
- Modify: App/Sessions/SessionController.swift
- Modify: Tests/TenXAppTests/SessionControllerTests.swift
- Modify: Tests/TenXAppTests/TranscriptEventProcessorTests.swift

- [ ] Add failing tests named controllerRejectsSnapshotFromReplacedProcessor, initialHistorySnapshotPreservesCurrentState, finalSnapshotPrecedesReconciliation, restartStopsThePreviousProcessor, extensionRequestsRemainLosslessDuringBurst, and unexpectedExitRejectsLaterSnapshots.
- [ ] Exercise integration with SessionProcessManager.ClientFactory configured to launch the existing fake_server.py modes and temporary JSONL history. Do not add a parallel mock RPC protocol solely for these tests.
- [ ] Expose a nonisolated internal predicate for the generation guard and test it directly:

      static func accepts(
          snapshot: TranscriptSnapshot,
          activeProcessorID: UUID?
      ) -> Bool

  It returns true only when IDs match. Every snapshot installation path must call it.
- [ ] Run focused controller/processor tests and confirm failure while SessionController owns TranscriptReducer:

      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-transcript-controller-tests test '-only-testing:TenXAppTests/controllerRejectsSnapshotFromReplacedProcessor()' '-only-testing:TenXAppTests/initialHistorySnapshotPreservesCurrentState()' '-only-testing:TenXAppTests/finalSnapshotPrecedesReconciliation()' '-only-testing:TenXAppTests/restartStopsThePreviousProcessor()' '-only-testing:TenXAppTests/extensionRequestsRemainLosslessDuringBurst()' '-only-testing:TenXAppTests/unexpectedExitRejectsLaterSnapshots()'

- [ ] Remove reducer from SessionController. Add processor, installedSnapshotRevision, eventTask, snapshotTask, controlTask, and the existing reconciliationTask. Centralize cancellation in synchronous stopEventPipeline(), which cancels all four tasks, clears the active processor and revision immediately, then starts a small Task that asks the detached processor to stop.
- [ ] In finishOpening, stop the previous pipeline, obtain get_state, load persisted history or fallback messages, create a fresh processor, load TranscriptInitialContent into it, install the returned initial snapshot, subscribe to subagent progress, then start exactly three tasks: processor.run(client.events), snapshot installation, and filtered control handling.
- [ ] Snapshot installation runs on MainActor, checks processorID against the current actor and requires revision greater than installedSnapshotRevision, then assigns items and runtimeState once. Emit a fixed-name TranscriptSnapshotInstalled points-of-interest signpost containing revision only, with no transcript payload. No RpcFrame reduction or complete-array assignment remains in the raw event loop.
- [ ] Handle metadata controls with the existing applyEventMetadata. Handle extensionUIRequest with ExtensionUIRouter, but call processor methods for confirm/select/openURL rows and notification notices. Before a reconciliation boundary is handled, await processor.currentSnapshot() and pass it through the revision-aware installer; this guarantees the final visible state is installed even if the snapshot consumer task has not run yet. Then schedule SessionTimelineLoader work and send history/warning changes back through processor.reconcile.
- [ ] Route sendPrompt, refreshState, extension removal, reconciliation warning, and failure/runtime transitions through processor actor methods. Keep immediate controller state changes required for recovery and composer availability, while the matching processor snapshot remains authoritative for transcript items.
- [ ] restart and unexpected exit call stopEventPipeline before opening/recovery state. Any already-buffered snapshot from the old ID fails the guard. Preserve draft, recovery sheet, stderr log, title/model/thinking/context metadata, and extension timeout behavior.
- [ ] Run the new SessionController and processor tests, then the complete app suite, which covers existing extension and transcript behavior:

      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-transcript-controller-tests test '-only-testing:TenXAppTests/controllerRejectsSnapshotFromReplacedProcessor()' '-only-testing:TenXAppTests/initialHistorySnapshotPreservesCurrentState()' '-only-testing:TenXAppTests/finalSnapshotPrecedesReconciliation()' '-only-testing:TenXAppTests/restartStopsThePreviousProcessor()' '-only-testing:TenXAppTests/extensionRequestsRemainLosslessDuringBurst()' '-only-testing:TenXAppTests/unexpectedExitRejectsLaterSnapshots()'
      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-transcript-controller-tests test '-only-testing:TenXAppTests/burstUpdatesCoalesceIntoOneManualFlush()' '-only-testing:TenXAppTests/coalescedPublicationNeverExceedsTwentyPerSecond()' '-only-testing:TenXAppTests/immediateBoundaryFlushesBeforeControlForwarding()' '-only-testing:TenXAppTests/extensionAndReconciliationControlsRemainOrdered()' '-only-testing:TenXAppTests/malformedAndUnknownFramesProduceNoSnapshot()' '-only-testing:TenXAppTests/stoppingProcessorFinishesStreams()' '-only-testing:TenXAppTests/latestSnapshotBufferDropsOnlySupersededSnapshots()'
      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-transcript-controller-tests test

- [ ] Commit: refactor(transcript): move event reduction off main

## Task 5: Skip unchanged assistant presentation work

**Files:**
- Create: App/Sessions/AssistantMessageContentView.swift
- Modify: App/Sessions/MessageBubbleView.swift
- Modify: Tests/TenXAppTests/MessageBubbleViewTests.swift
- Modify: Tests/TenXAppTests/ViewSnapshotTests.swift

- [ ] Load writing-ui and visual-ui before touching these files. The intended user-facing result is pixel-identical; do not alter text, spacing, colors, references, selection, or accessibility.
- [ ] Add failing tests named assistantContentEqualityIgnoresUnrelatedTranscriptUpdates and assistantContentEqualityTracksIdentityTextAndFinality. Assert equality depends only on message id, visibleText, and isFinal; a changed id, visible text, or finality must compare unequal.
- [ ] Run the focused tests and confirm AssistantMessageContentView is missing:

      ruby scripts/generate_xcodeproj.rb
      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-assistant-content-tests test '-only-testing:TenXAppTests/assistantContentEqualityIgnoresUnrelatedTranscriptUpdates()' '-only-testing:TenXAppTests/assistantContentEqualityTracksIdentityTextAndFinality()'

- [ ] Move only the assistant ResponseMetadataView, MessageContentParser, MessageBlockView, TranscriptReference extraction, FlowLayout, and TranscriptReferenceView subtree into AssistantMessageContentView: View, Equatable. Implement static equality with id, visibleText, and isFinal and apply .equatable() at the call site in MessageBubbleView.
- [ ] Leave user and other-role rendering in MessageBubbleView. Do not memoize mutable view state or cache parsed content globally.
- [ ] Run the equality tests, every transcript snapshot test at both sizes, and all snapshots with recording disabled. Assert the reference-image directory is byte-for-byte unchanged:

      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-assistant-content-tests test '-only-testing:TenXAppTests/assistantContentEqualityIgnoresUnrelatedTranscriptUpdates()' '-only-testing:TenXAppTests/assistantContentEqualityTracksIdentityTextAndFinality()' '-only-testing:TenXAppTests/richAssistantMessageSnapshot()' '-only-testing:TenXAppTests/longWrappingMessageSnapshot()' '-only-testing:TenXAppTests/fullTranscriptCompactWindowSnapshot()' '-only-testing:TenXAppTests/fullTranscriptWideWindowSnapshot()'
      git diff --exit-code -- Tests/TenXAppTests/ReferenceImages

- [ ] Commit: perf(transcript): skip unchanged assistant rendering

## Task 6: Repeat the burst, verify the product, and publish evidence

**Files:**
- Modify: docs/performance/2026-08-25-transcript-streaming.md
- Modify only if a requirement-backed defect is found in the files above.

- [ ] Regenerate the project and confirm no unintended project churn:

      ruby scripts/generate_xcodeproj.rb
      git diff --check

- [ ] Run the complete app and OmpKit suites. Record any repeatable pre-existing OmpKit process-lifecycle failure separately; do not change that subsystem:

      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-transcript-final-tests test
      swift test --package-path OmpKit

- [ ] Build the fixed Release app into a new task-specific path:

      xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-transcript-fixed-release build

- [ ] Load launching-local-builds. Launch the exact fixed executable with the same CFFIXED_USER_HOME, PATH, project directory, input, 2 ms cadence, and 1,000 complete snapshots used for baseline. Confirm the bundle and exact PID are visible.
- [ ] Through the real UI click Send once while recording Time Profiler, points of interest, and one-second process samples under /private/tmp/tenx-performance-recordings/fixed-transcript. Verify the composer remains interactive, the viewport follows only while near the bottom, and the final text becomes visible. Capture a screenshot from the real fixed build after completion.
- [ ] Count TranscriptSnapshotInstalled signposts during each wall-clock second. Accept at most 20 non-boundary installations per second, exactly one final message, ordered/lossless control boundaries, zero unknown rows after the 10,000-frame test, and idle at or below 1% CPU after settling.
- [ ] Compare fixed peak CPU, RSS, physical footprint, main-thread CPU time, parser/Markdown stacks, responsiveness, and post-burst idle with the baseline. Confirm historical assistant parsing is absent during unrelated tool/control snapshot changes.
- [ ] Complete the Fixed column and threshold verdicts in docs/performance/2026-08-25-transcript-streaming.md. Include exact commands and local trace names; do not commit binary Instruments output.
- [ ] Stop only the exact Release PID and confirm its fake OMP child is gone. Load verifying-work and rerun any stale evidence it identifies.
- [ ] Inspect the final diff against both approved specs. Report unrelated observations without absorbing them into this branch.
- [ ] Commit: perf(transcript): record bounded streaming results

## Done When

- [ ] The controlled baseline and fixed Release runs use the same 1,000-update workload and real app interaction.
- [ ] Unsupported frames produce no rows, no snapshot, and no payload logging.
- [ ] Lossless controls and terminal state remain ordered while replaceable UI snapshots stay at or below 20 Hz.
- [ ] Old processors cannot update a restarted or stopped controller.
- [ ] Existing transcript visuals, extension UI, history reconciliation, recovery, app tests, and OmpKit behavior remain intact.
- [ ] Post-burst idle returns to at most 1% CPU and before/after CPU/memory evidence is reproducible from the report.

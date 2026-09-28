# OMP Event Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep 10x usable and readable when OMP emits guidance, unknown or oversized tool data, or an unsupported interactive request.

**Architecture:** Keep `OmpKit` as the transport boundary. Normalize complete frames in the existing App transcript and control paths into bounded product items before SwiftUI sees them. Use the same guidance classifier for live events and restored session entries; retain explicit tool-name routing and typed extension controls.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, macOS, local `OmpKit` and the bundled `OmpExtension`.

**Spec:** [OMP event boundary design](../specs/2026-09-28-omp-event-boundary-design.md)

## Execution Routing

- **Implementation:** Cursor, **Composer 2.5 high fast**.
- **Verification and auditing:** **Grok 4.7 xhigh fast**.
- **Visual verification and steering:** the main Codex session with Tanner.
- These are the user-selected models. If unavailable in the destination harness, report the limitation; do not silently substitute a different model.
- [Approved interactive UI reference](../designs/2026-09-28-omp-tool-gallery.html) is a design mockup, not evidence of implemented behavior.

## Global Constraints

- Work only in an isolated 10x worktree; leave the main checkout and port 3000 alone. Do not depend on unreleased OMP changes.
- The sole new preference is **Show agent guidance**, off by default. It does not alter model input or OMP configuration.
- Keep required input and approvals visible regardless of the preference. Keep the provider-account machine channel ahead of generic extension UI fallback.
- Bound every value before it reaches a transcript view. Do not stringify an entire `JSONValue` to discover a preview.
- Reuse `CornerCard`, `FileTypeIcon`, file-reference actions, and the existing source/console/diff surfaces. Do not hand-edit `10x.xcodeproj`; run `ruby scripts/generate_xcodeproj.rb` after adding Swift files.
- Do not add a database/schema change, dependency, generic event bus, three-mode passthrough selector, or per-event model summarization.
- Run targeted Swift Testing selectors by function name and confirm the “Test run with … tests” summary. Verify user flows in a built app, not a dev server.
- Load `writing-ui` and `visual-ui` before UI tasks, `launching-local-builds` before launching a build, and `verifying-work` before claiming a checkpoint works.

## Review Focus

1. Repeated `message_start`/`message_end` and history reconciliation must update one guidance ID, not duplicate it. Task 2 tests this.
2. A user file mention stays visible as a reference with its injected body absent, even when guidance is hidden. Tasks 1–3 test this.
3. A large nested result, long scalar, or inline media block cannot escape through an expansion, accessibility label, or copy preview. Task 5 tests this.
4. A worker with the wrong or missing `parentToolCallID` must not appear under another delegation or vanish. Task 7 tests this.
5. Unsupported extension UI must produce at most one response for the original process and ID, even across a restart. Task 9 tests this.

## File Map and Working Checkpoints

| Checkpoint | Owned files and responsibility | Working proof |
| --- | --- | --- |
| 1. Guidance | New `App/Sessions/GuidancePresentation.swift` and `GuidanceCardView.swift`; `TranscriptReducer`, `TranscriptHistoryMapper`, `TranscriptItem`, `TranscriptView`; existing preference store, setting row, `SessionController` and `AppModel` | A real advisor and hidden developer message are absent by default and appear as compact items when switched on, live and after reopen. |
| 2. Passive events and tools | New `App/Sessions/EventDiagnostic.swift` and `App/Tools/ToolPayloadBudget.swift`; existing tool reducers, extractor, surface/scaffold, diff, subagent, and row projection | Unknown events and malformed tool fields remain bounded; Read/Write/Edit/Run/Search/Delegate cards match the approved hierarchy. |
| 3. Interactive recovery | `OmpKit` frame validation, `ExtensionUIRouter`, `SessionController`, and their tests | Known dialogs still work; unsupported dialogs are cancelled once or show a restart path. |

Do not begin checkpoint 2 until checkpoint 1 works in a built app. Each checkpoint can be reviewed without taking on the next.

---

### Task 1: Classify and bound guidance

**Files:**
- Create: `App/Sessions/GuidancePresentation.swift`
- Test: `Tests/TenXAppTests/GuidancePresentationTests.swift`

**Interfaces:**
- Produce `GuidancePresentation: Identifiable, Equatable, Sendable` with `id`, `kind` (`advisor`, `agentGuidance`, `referencedFile`), `visibility` (`always` or `whenEnabled`), `byteCount`, and `preview`.
- Produce `GuidanceClassifier.classify(id: String, message: JSONValue) -> GuidancePresentation?` and `BoundaryText.preview(_ text: String, byteLimit: Int, lineLimit: Int) -> String`.
- The classifier reads advisor `details.notes` first; fallback removes advisory envelope markers. It recognizes `fileMention` or an explicitly user-attributed developer item with file metadata; it never guesses from body text or includes the injected file body.

- [ ] **Step 1: Add `guidanceClassifierBoundsAndLabels()` and companion failing tests** for advisor notes, developer/hidden custom messages, `fileMention` and user-attributed developer file content, empty content, and a multibyte string. Regenerate the project so the new test file is included. Assert:

~~~swift
#expect(advisor?.kind == .advisor)
#expect(advisor?.preview == "Check the probe window.")
#expect(fileMention?.kind == .referencedFile)
#expect(fileMention?.visibility == .always)
#expect(!fileMentionPreview.contains("injected file body"))
#expect(Data(largePreview.utf8).count <= 512)
~~~

- [ ] **Step 2: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/guidanceClassifierBoundsAndLabels()"` and confirm a nonzero test count with failure.
- [ ] **Step 3: Implement** the classifier and a UTF-8-safe preview capped at **512 bytes and 6 lines**. Sanitize titles to **80 bytes**. Do not build a `ContentDocument` from the full instruction body before truncating.
- [ ] **Step 4: Regenerate the project** to include `GuidancePresentation.swift`.
- [ ] **Step 5: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/guidanceClassifierBoundsAndLabels()"` and the companion classifier selectors; expect nonzero executed tests and PASS.
- [ ] **Step 6: Commit** `feat: classify bounded OMP guidance`.

### Task 2: Feed one guidance index from live and restored paths

**Files:**
- Modify: `App/Sessions/TranscriptItem.swift`, `App/Sessions/TranscriptReducer.swift`, `App/Sessions/TranscriptHistoryMapper.swift`, `App/Sessions/TranscriptMessageNormalizer.swift`, `App/Sessions/TranscriptEventProcessor.swift`, `App/Sessions/TranscriptTurnProjection.swift`, `App/Sessions/TranscriptView.swift`
- Test: `Tests/TenXAppTests/TranscriptReducerTests.swift`, `Tests/TenXAppTests/TranscriptHistoryMapperTests.swift`, `Tests/TenXAppTests/TranscriptEventProcessorTests.swift`

**Interfaces:**
- Add `TranscriptItem.guidance(GuidancePresentation)`. Both `TranscriptReducer.consume(_:,at:)` and `TranscriptHistoryMapper.map(header:path:)` call Task 1's classifier.
- Use the message ID in both paths where present; use the session-entry ID for a restored message without one. A live ID-less item gets a session-local ID and is replaced during reconciliation.
- Keep the **latest 128 guidance items** per session, each with Task 1's bounded preview; represent evicted items with one count-only “Earlier guidance omitted” item.

- [ ] **Step 1: Add `liveAndRestoredGuidanceHaveStableIdentity()` and companion failing replay tests**: repeated start/end of the same advisor, a developer message, a displayed custom message, a hidden custom message, file mention, history reload, and a 129th guidance item. Assert one stable item per message, same kind/preview after restore, visible conversation unchanged, and omission count instead of raw text.
- [ ] **Step 2: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/liveAndRestoredGuidanceHaveStableIdentity()"`; confirm it fails with one executed test.
- [ ] **Step 3: Route guidance before normal message display filtering** and update by ID rather than append on terminal updates. Make `TranscriptHistory` carry normalized items directly; retire its `dropped` descriptor handoff only after these tests prove parity. Update exhaustive `TranscriptItem` switches and turn projection without treating guidance as response evidence; `TranscriptView` can hide the new case until Task 3 renders it.
- [ ] **Step 4: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/liveAndRestoredGuidanceHaveStableIdentity()"` and companion reducer/history/processor selectors; expect nonzero executed tests and PASS.
- [ ] **Step 5: Commit** `feat: normalize live and restored guidance`.

### Task 3: Ship the single visibility switch and compact row

**Files:**
- Create: `App/Sessions/GuidanceCardView.swift`
- Modify: `App/Settings/HarnessNoticePreferenceStore.swift`, `App/Settings/HarnessNoticeSettingRowView.swift`, `App/Settings/SettingsView.swift`, `App/Sessions/TranscriptView.swift`, `App/Sessions/SessionController.swift`, `App/Application/AppModel.swift`
- Remove after parity proof: `App/Sessions/HarnessNoticeSummarizer.swift`, `App/Sessions/HarnessMessageDescriptor.swift`, `Tests/TenXAppTests/HarnessNoticeSummarizerTests.swift`
- Test: `Tests/TenXAppTests/HarnessNoticePreferenceStoreTests.swift`, `Tests/TenXAppTests/HarnessNoticeSettingRowTests.swift`, `Tests/TenXAppTests/SessionControllerTests.swift`, `Tests/TenXAppTests/ViewSnapshotTests.swift`

**Interfaces:**
- Reuse `HarnessNoticePreferenceStore.isEnabled` and its persisted key as the migration source. Expose `SessionController.showsAgentGuidance: Bool` for the transcript to observe.
- `GuidanceCardView` uses `CornerCard` and displays title, bounded preview, size, and omission count where applicable. The transcript filters `whenEnabled` items at projection time, not by deleting them.

- [ ] **Step 1: Add `agentGuidanceToggleUpdatesVisibleRows()` and companion failing preference/view tests**: old enabled value maps to the new switch; default is off; the setting reads “Show agent guidance” with the approved supporting text; threshold/model menus are absent; toggling twice preserves row IDs and scroll target order; file mention remains visible in both states.
- [ ] **Step 2: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/agentGuidanceToggleUpdatesVisibleRows()"` and confirm it fails with one executed test.
- [ ] **Step 3: Implement the row and filter**, remove the old model-summary callback and descriptor/summarizer code after the normalized path works, and leave old stored threshold/model values and cache file untouched for compatibility. Update setting search terms and accessibility labels.
- [ ] **Step 4: Regenerate the project** to include `GuidanceCardView.swift` and remove obsolete Swift files.
- [ ] **Step 5: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/agentGuidanceToggleUpdatesVisibleRows()"` and companion settings/transcript/controller selectors; expect nonzero executed tests and PASS.
- [ ] **Step 6: Build** `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS'`; expect `BUILD SUCCEEDED`.
- [ ] **Step 7: Drive a real OMP session** with advisor and hidden guidance in the built app; toggle during the run and after reopen. Confirm conversation, controls, and scroll position hold.
- [ ] **Step 8: Commit** `feat: show bounded agent guidance on demand` with evidence.

### Task 4: Record unknown passive events without a raw payload path

**Files:**
- Create: `App/Sessions/EventDiagnostic.swift`
- Modify: `App/Sessions/TranscriptItem.swift`, `App/Sessions/TranscriptReducer.swift`, `App/Sessions/TranscriptHistoryMapper.swift`, `App/Sessions/TranscriptView.swift`, `App/Sessions/TranscriptTurnProjection.swift`
- Test: `Tests/TenXAppTests/EventDiagnosticTests.swift`, `Tests/TenXAppTests/TranscriptReducerTests.swift`, `Tests/TenXAppTests/TranscriptHistoryMapperTests.swift`

**Interfaces:**
- Produce `EventDiagnostic: Identifiable, Equatable, Sendable` with source ID, sanitized type (80 UTF-8 bytes), byte count, and optional safe preview.
- Produce `EventDiagnostic.make(id: String, type: String, payload: JSONValue) -> EventDiagnostic`; size counting stops after **256 nodes** and marks the count as a lower bound.
- Add `TranscriptItem.diagnostic(EventDiagnostic)` and update exhaustive item switches.
- Unknown passive events and unknown saved entries create countable diagnostics; default transcript hides them. With the guidance switch on, a compact “Additional activity” row may show type and size. Never preview arbitrary nested content, tool arguments, file contents, or instruction bodies.

- [ ] **Step 1: Add `unknownPassiveEventStaysBounded()` and companion failing tests** for an unknown event with a secret-looking payload, an unknown saved entry, a malformed noninteractive known event, a terminal tool/subagent update missing display fields, repeated updates, and 129 diagnostics. Regenerate the project. Assert normal conversation continues, no secret appears in items or accessibility text, a terminal card closes with a display error, and the index caps at **128** entries plus one omitted count.
- [ ] **Step 2: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/unknownPassiveEventStaysBounded()"`; confirm nonzero failing count.
- [ ] **Step 3: Implement** diagnostics in the existing reducer/mapper paths, preserving required status/control event handling and stable IDs. Count size with a capped traversal instead of encoding the whole payload; show “at least” when the count saturates. Expose a subdued row only through the existing switch.
- [ ] **Step 4: Regenerate the project** to include `EventDiagnostic.swift`.
- [ ] **Step 5: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/unknownPassiveEventStaysBounded()"` and companion diagnostic selectors; expect nonzero executed tests and PASS.
- [ ] **Step 6: Commit** `feat: contain unknown passive events`.

### Task 5: Bound tool extraction and fallback

**Files:**
- Create: `App/Tools/ToolPayloadBudget.swift`
- Modify: `App/Tools/ToolPresentation.swift`, `App/Tools/ToolContentExtractor.swift`, `App/Tools/ToolEventReducer.swift`, `App/Tools/ToolSurfaceView.swift`
- Test: `Tests/TenXAppTests/ToolPayloadBudgetTests.swift`, `Tests/TenXAppTests/ToolContentExtractorTests.swift`, `Tests/TenXAppTests/ToolEventReducerTests.swift`

**Interfaces:**
- Produce `ToolPayloadBudget.limit(_ value: JSONValue) -> JSONValue` and apply it before storing arguments/results or extracting `ToolCardContent`.
- Limits: **8 KiB per text scalar**, **32 array children**, **4 object/array levels**, **256 total nodes**, and **256 KiB of inline media data**. Over-limit media becomes a labeled placeholder with MIME/size; copy says “Copy preview” unless full persisted content can be fetched deliberately.
- Preserve enough known keys for `ToolCardRegistry` summaries; mark truncation explicitly. `ToolBody.data` receives only bounded JSON. Expansion enforces the same limits; it never converts an entire original JSON tree to a string.
- When a session file exists, a separate “Open session file” action can reach the persisted full result; keep the tool call ID copyable for locating it. This uses the existing file-opening service and avoids a second raw-result cache.

- [ ] **Step 1: Add `toolBudgetBoundsNestedAndMediaPayloads()` and companion failing tests** for a 1 MB source string, 10,000-child array, deep object, oversized base64 image, unknown tool, missing path/result, interrupted stream, and an error with partial output. Regenerate the project. Assert bounded stored values, bounded rendered/accessibility text, stable call ID/phase, and a visible fallback.
- [ ] **Step 2: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/toolBudgetBoundsNestedAndMediaPayloads()"`; confirm nonzero failing count.
- [ ] **Step 3: Apply the budget at `ToolPresentation` ingestion** and adjust the extractor/surfaces to use bounded values. Keep the current explicit per-tool registry and aliases. A malformed known tool uses the generic bounded card instead of losing its call.
- [ ] **Step 4: Regenerate the project** to include `ToolPayloadBudget.swift`.
- [ ] **Step 5: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/toolBudgetBoundsNestedAndMediaPayloads()"` and companion budget/extractor/reducer selectors; expect nonzero executed tests and PASS.
- [ ] **Step 6: Commit** `feat: bound tool content before presentation`.

### Task 6: Refine file, work, and external-tool surfaces

**Files:**
- Modify: `App/Tools/ToolCardScaffold.swift`, `App/Tools/ToolSurfaceView.swift`, `App/Tools/ToolContentExtractor.swift`, `App/Tools/DiffView.swift`
- Test: `Tests/TenXAppTests/ToolContentExtractorTests.swift`, `Tests/TenXAppTests/ViewSnapshotTests.swift`

**Interfaces:** Read/Write share one source surface; Edit selects one diff per file. The header uses the existing file reference and type icon; an attached neutral strip holds the folder path and actions. Run/Search/external tools retain dedicated semantic surfaces. Missing files cannot open, and bounded copying says “Copy preview.”

- [ ] **Step 1: Add `fileToolCardsUseAttachedPathSurface()` and companion failing tests/snapshots** for Read, Write, multi-file Edit, Run failure, grouped Search, Browser, and Computer. Assert filename and file icon appear in the header, the folder path belongs to its source/diff, the second edited file selects its own diff, and the full-result action appears only when a session file is available.
- [ ] **Step 2: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/fileToolCardsUseAttachedPathSurface()"`; confirm nonzero failing count.
- [ ] **Step 3: Reuse the existing surfaces and file-reference actions** to implement the approved hierarchy, including the persisted-session inspection action specified in Task 5. Preserve disclosure and streaming IDs from `ToolCardScaffold`. Keep control labels and empty/error states inside their owning surface.
- [ ] **Step 4: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/fileToolCardsUseAttachedPathSurface()"` and companion extractor/snapshot selectors; expect nonzero executed tests and PASS.
- [ ] **Step 5: Build** `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS'`; expect `BUILD SUCCEEDED`.
- [ ] **Step 6: Inspect changed snapshots** against the approved visual hierarchy.
- [ ] **Step 7: Drive Read/Write/Edit/Run/Search** in the built app through running, success, and failure.
- [ ] **Step 8: Commit** `feat: refine semantic tool surfaces` with evidence.

### Task 7: Nest Delegate worker rows

**Files:**
- Create: `App/Sessions/DelegateCardView.swift` for parent and child rows; keep `SubagentCardView` for orphan workers
- Modify: `App/Sessions/TranscriptPresentationRow.swift`, `App/Sessions/TranscriptView.swift`, `App/Sessions/SubagentCardView.swift`
- Test: `Tests/TenXAppTests/TranscriptPresentationRowTests.swift`, `Tests/TenXAppTests/ViewSnapshotTests.swift`

**Interfaces:** Add `TranscriptPresentationRow.delegation(id: String, tool: ToolPresentation, workers: [SubagentPresentation])`. Extend `rows(from:)` to attach workers only by exact `parentToolCallID`, retaining orphan workers as standalone rows. Delegate shows the assignment and count in the parent header; each worker row shows identity, current activity/final result, and Open session when available.

- [ ] **Step 1: Add `delegateRowsPreserveParentOwnership()` and companion failing projection/snapshot tests** for two workers under one delegation, a worker under another parent, an orphan, result-before-lifecycle ordering, and updates that must not duplicate rows.
- [ ] **Step 2: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/delegateRowsPreserveParentOwnership()"`; confirm nonzero failing count.
- [ ] **Step 3: Implement parent/child projection and the quiet worker row**. Do not infer ownership from names or timing. Keep activity history and model/usage metadata in the worker session or explicit detail.
- [ ] **Step 4: Regenerate the project** to include `DelegateCardView.swift`.
- [ ] **Step 5: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/delegateRowsPreserveParentOwnership()"` and companion projection/snapshot selectors; expect nonzero executed tests and PASS.
- [ ] **Step 6: Build** `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS'`; expect `BUILD SUCCEEDED`.
- [ ] **Step 7: Inspect the Delegate snapshot** against the approved compact worker hierarchy.
- [ ] **Step 8: Drive a real delegation** in the built app.
- [ ] **Step 9: Commit** `feat: group delegate worker activity` with evidence.

### Task 8: Reject structurally invalid interactive IDs

**Files:**
- Modify: `OmpKit/Sources/OmpKit/Wire/RpcFrame.swift`
- Test: `OmpKit/Tests/OmpKitTests/FrameDecodingTests.swift`

**Interfaces:** `RpcFrame.decode(line:)` rejects a missing, empty, or whitespace-only `extension_ui_request.id` as `RpcFrameError.malformedFrame`. This is a child-session transport failure, not a guessed response target.

- [ ] **Step 1: Add `extensionRequestRequiresUsableID()` and companion failing frame tests** asserting all three invalid IDs fail while a valid request with an unknown method still decodes to `.extensionUIRequest`.
- [ ] **Step 2: Run** `swift test --package-path OmpKit --filter extensionRequestRequiresUsableID`; confirm the filter executes and fails.
- [ ] **Step 3: Add the ID guard** without changing unrelated frame types; keep existing process-failure handling scoped to the child session.
- [ ] **Step 4: Run** `swift test --package-path OmpKit --filter extensionRequestRequiresUsableID` and companion decoding tests; expect nonzero executed tests and PASS.
- [ ] **Step 5: Commit** `fix: reject extension requests without usable IDs`.

### Task 9: Cancel unsupported extension UI once and show recovery

**Files:**
- Modify: `App/ExtensionUI/ExtensionUIRouter.swift`, `App/Sessions/SessionController.swift`, `App/Sessions/TranscriptItem.swift`, `App/Sessions/TranscriptView.swift`
- Test: `Tests/TenXAppTests/ExtensionUIRouterTests.swift`, `Tests/TenXAppTests/SessionControllerTests.swift`

**Interfaces:**
- Add `ExtensionUIParseResult: Equatable` with cases `known(ExtensionUIState)`, `reservedChannel`, and `unsupported(reason: String)`. Produce it from `ExtensionUIRouter.classify(_ request: ExtensionUIRequest) -> ExtensionUIParseResult`; keep the provider-account marker ahead of fallback.
- For unsupported/malformed requests with a valid ID, `SessionController` sends `RpcCommand.extensionUIResponse(id: request.id, body: ["cancelled": .bool(true)])` through the captured pipeline handle exactly once and appends a bounded visible notice. If that send fails, surface existing session recovery. If the child remains blocked after cancellation, offer the existing Restart session action from a visible recovery notice; correlate timer/action with pipeline generation so a restarted process receives nothing stale.

- [ ] **Step 1: Add `unsupportedExtensionRequestCancelsOnce()` and companion failing router/controller tests** for confirm/select/input/editor/open URL, unknown method, malformed known method, reserved provider channel, duplicate request ID, send failure, and restart while cancellation is pending. Assert known requests keep their native UI; unsupported requests send one cancellation on the correct client; no provider-account request becomes a user prompt.
- [ ] **Step 2: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/unsupportedExtensionRequestCancelsOnce()"`; confirm nonzero failing count.
- [ ] **Step 3: Implement parse outcomes and controller fallback** using the existing `PipelineContext` and `extensionResponsesInFlight` fence. Show a concise notice without raw payload. If the turn has not reached `agent_end` or `prompt_result` after **10 seconds**, offer Restart session; cancel this check on process change or turn completion.
- [ ] **Step 4: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/unsupportedExtensionRequestCancelsOnce()"` and companion router/controller selectors; expect nonzero executed tests and PASS.
- [ ] **Step 5: Build** `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS'`; expect `BUILD SUCCEEDED`.
- [ ] **Step 6: Drive one real known dialog and synthetic unsupported/malformed requests** through the built app; confirm no indefinitely pending input.
- [ ] **Step 7: Commit** `feat: recover unsupported extension requests` with evidence.

### Task 10: Check the full user flow and close the plan

**Files:** No product code unless a checkpoint verification finds a scoped defect; store evidence under `docs/superpowers/evidence/`.

- [ ] **Step 1: Run** `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'`; expect a nonzero Swift Testing count and PASS.
- [ ] **Step 2: Run** `swift test --package-path OmpKit`; expect a nonzero count and PASS.
- [ ] **Step 3: Build** `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS'`; expect `BUILD SUCCEEDED`. Resolve failures caused by this branch only.
- [ ] **Step 4: Launch the Release build** using the `launching-local-builds` skill and confirm it is visible.
- [ ] **Step 5: Drive an actual OMP session** through the guidance switch, Read/Write/Edit/Run/Search/Delegate, one required approval/input, unknown passive event, oversized tool result, and unsupported request recovery.
- [ ] **Step 6: Capture screenshots/logs** that prove each checkpoint and record skipped scenarios with reasons.
- [ ] **Step 7: Commit the evidence** as `docs: verify OMP event boundary flows`.
- [ ] **Step 8: Flip the implementation PR ready** with the verification evidence.
- [ ] **Step 9: Use `reviewing-code`** for the planned review and fix only findings within this plan's scope. Merge only when checks are green and Tanner approves.

## Execution Handoff

The first checkpoint is the first independently reviewable working slice. After each checkpoint, report Verified / Not verified / For Tanner to test with build and interaction evidence, then continue only within the approved execution scope. A follow-up implementation branch may supersede this plan with measured constraints, but it must update this document before broadening scope.

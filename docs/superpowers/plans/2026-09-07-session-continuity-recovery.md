# Session Continuity and Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recover a failed existing-session open without losing its target or staged input, and preserve extension arguments on fresh persistent processes.

**Architecture:** Keep the requested existing path on the current controller before opening. Reuse the existing managed-session registry, restart operation, and recovery card. Append session-directory arguments to the process configuration instead of replacing extension arguments.

**Tech Stack:** Swift 6.1, SwiftUI, macOS 15+, OmpKit, Swift Testing, Xcode.

**Spec:** `docs/superpowers/specs/2026-09-07-session-continuity-recovery-design.md`

## Global Constraints

- macOS 15 or later; Swift 6.1; SwiftUI and the existing OmpKit package.
- No dependency changes, schema work, app deployment, or merge.
- Work only in this task's linked worktree. Do not touch other instances or port 3000.
- Never hand-edit `10x.xcodeproj`; if source files are added, regenerate with `ruby scripts/generate_xcodeproj.rb` using xcodeproj 1.27.0.
- Reuse the existing recovery card, typography, colors, and button style. No new user-facing diagnostic prefixes or em dashes.
- Preserve draft text and attachments; never automatically resend uncertain input.
- Broader audit areas remain tracked in the implementation roadmap and get separate changes.

---

### Task 1: Preserve extensions in fresh persistent processes

**Files:**
- Modify: `OmpKit/Sources/OmpKit/SessionProcessManager.swift`, `openNew` and `warm`.
- Test: `OmpKit/Tests/OmpKitTests/ProcessManagerTests.swift`.

**Interfaces:**
- Consumes: `SessionProcessManager.init(extraArguments:supportsUserInteraction:clientFactory:)`, `warm(projectDirectory:)`, and `openNew(projectDirectory:provider:model:thinking:)`.
- Produces: unchanged API; fresh configurations contain configured extension arguments followed by `--session-dir` and the canonical project bucket.

- [ ] **Step 1: Add a regression for the arguments delivered to both fresh-process paths.** The break is dropping a configured extension when a session directory is added. Reuse `ConfigurationCapture`, `fixtureURL`, and the existing fake process; capture the real manager's outgoing configuration before substituting the executable.

```swift
@Test(arguments: [false, true])
func freshProcessesKeepConfiguredExtensions(isWarm: Bool) async throws {
    let capture = ConfigurationCapture()
    let manager = SessionProcessManager(
        extraArguments: ["-e", "/fake/ext/index.ts"],
        supportsUserInteraction: true,
        clientFactory: { configuration in
            capture.append(configuration)
            var fake = configuration
            fake.executable = "/usr/bin/env"
            fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, "basic"]
            fake.rawArgv = true
            fake.cwd = nil
            return RpcClient(configuration: fake)
        })
    if isWarm { _ = try await manager.warm(projectDirectory: "/tmp/project") }
    _ = try await manager.openNew(projectDirectory: "/tmp/project")
    let configuration = try #require(capture.snapshot().first)
    #expect(configuration.extraArguments == [
        "-e", "/fake/ext/index.ts", "--session-dir",
        expectedFreshSessionDirectory(for: "/tmp/project"),
    ])
    #expect(configuration.noSession == false)
    #expect(configuration.supportsUserInteraction)
    await manager.closeAll()
}
```

Ensure the child is also closed if an assertion setup throws, using the package's existing cleanup pattern.

- [ ] **Step 2: Run the focused regression and record the expected missing-extension failure.**

```bash
swift test --package-path OmpKit --filter freshProcessesKeepConfiguredExtensions
```

Expected: both warm and cold cases fail because `extraArguments` begins with `--session-dir` instead of the extension.

- [ ] **Step 3: Append the session-directory arguments in both paths.** Keep the existing assignment of configured `extraArguments`, replacing only the later overwrite:

```swift
configuration.extraArguments += ["--session-dir", sessionDirectory]
```

- [ ] **Step 4: Run the focused test and then the OmpKit suite once.**

```bash
swift test --package-path OmpKit --filter freshProcessesKeepConfiguredExtensions
swift test --package-path OmpKit
```

Expected: new cases and the existing persistence, checkout, process-exit, and argument tests pass. Record the actual Swift Testing count.

- [ ] **Step 5: Commit only the implementation and its test.**

```bash
git add OmpKit/Sources/OmpKit/SessionProcessManager.swift OmpKit/Tests/OmpKitTests/ProcessManagerTests.swift
git commit -m "fix(runtime): preserve extensions on fresh session processes"
```

### Task 2: Recover the same existing session after an early open failure

**Files:**
- Modify: `App/Sessions/SessionController.swift`, existing open/new/recovery state.
- Modify: `App/Sessions/ActiveSessionView.swift`, existing failed-state recovery card.
- Modify: `App/Sessions/RuntimeRecoveryView.swift`, defaulted action label.
- Test: `Tests/TenXAppTests/AppModelNavigationTests.swift` and `Tests/TenXAppTests/SessionControllerTests.swift`.
- Test: `Tests/TenXAppTests/ViewSnapshotTests.swift` only if a focused recovery rendering check is needed; do not re-record unrelated snapshots.

**Interfaces:**
- Consumes: `SessionMetadata.path`/`.cwd`, `SessionController.openExisting(_:)`, `openNew(projectURL:selection:)`, `restart()`, and the existing `AppModel` path registry.
- Produces: `SessionController.canRetryOpening: Bool`; `RuntimeRecoveryView.restartLabel: String = "Restart session"`. No new retry registry, callback chain, or public process-manager API.

- [ ] **Step 1: Replace the obsolete nil-path failure expectation with a failing user-flow regression.** Start from `failedOpenExistingWithoutSessionPathIsNotReusedOnRetry`, using its disposable directory, `makeNavigationExecutable`, `navigationDependencies`, and `navigationMetadata`. Create the project directory so a missing CWD does not obscure the intended fixture crash. Keep the original target `/tmp/fake.jsonl`, which matches the existing fake's state. The behavioral core is:

```swift
model.openSession(metadata)
let failed = try #require(model.activeSession)
await waitUntil("the session to report its failure") { isFailed(failed.runtimeState) }
failed.draft = "Continue after reopening"
let attachment = ComposerAttachment(name: "context.png", data: Data([1, 2, 3]),
    mimeType: "image/png", pixelWidth: 1, pixelHeight: 1)
failed.attachments = [attachment]
#expect(failed.sessionPath == metadata.path)
#expect(model.managedController(for: metadata.path) === failed)
#expect(failed.canRetryOpening)
_ = try makeNavigationExecutable(in: container, mode: "basic")
await failed.restart()
#expect(failed.isComposerAvailable)
#expect(!failed.isRecoveryPresented)
#expect(!failed.canRetryOpening)
#expect(failed.sessionPath == metadata.path)
#expect(failed.projectURL?.path == metadata.cwd)
#expect(failed.draft == "Continue after reopening")
#expect(failed.attachments == [attachment])
await failed.sendPrompt()
#expect(failed.draft.isEmpty)
#expect(failed.attachments.isEmpty)
model.openNewSession()
model.openSession(metadata)
#expect(model.activeSession === failed)
await manager.closeAll()
```

Also cover a controller that previously opened an existing session and then fails to open a new one: it must have no previous `sessionPath`, preserve the new prompt, and remain eligible for the existing Review prompt flow. Use the existing factory and failure fixtures in `SessionControllerTests.swift`; capture actual new-session state rather than asserting source text. Add no production-only test seam.

- [ ] **Step 2: Run the focused app regression and record the expected pre-handle retry failure.** Before the computed property exists, temporarily omit only its two assertions so RED measures the existing behavior (missing path, missing ownership, disabled composer after restart), then restore them with the implementation.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /tmp/10x-session-recovery-tests \
  -only-testing:'TenXAppTests/failedExistingSessionCanReopenAndKeepItsDraft()'
```

Confirm a nonzero Swift Testing count; file-shaped selectors are invalid here. Do not wait on `canRetryOpening` in the failing test because that would turn the missing behavior into a timeout.

- [ ] **Step 3: Retain the target and reuse recovery.** Assign `self.sessionPath = metadata.path` after detaching the previous session and before beginning the existing-session open; clear `self.sessionPath` when a new-session opening intent replaces it. Keep generation guards and process cleanup in their current order. Derive the recovery action from the runtime and handle:

```swift
var canRetryOpening: Bool {
    guard case .failed = runtimeState else { return false }
    return sessionPath != nil && handle == nil
}
```

The existing `restart()` now has a requested path even if the first open never returned a handle. It must reconnect without sending the draft. `AppModel` retains this controller through its existing non-nil path branch. Verify no stale opening task closes a replacement process.

Extend `RuntimeRecoveryView` with a defaulted `restartLabel` and use `Button(restartLabel, action: onRestart)`. In the existing failed card, pass `"Retry opening"` when `canRetryOpening` is true, otherwise retain `"Restart session"`. For that failed-open state use `"The session could not open. Retry opening it or check the log."`; keep existing failed-new and connected-command explanations. Do not add a new card or change the process-exit card.

- [ ] **Step 4: Run relevant lifecycle cases and then the app suite once.** Include the new recovery tests, existing restart tests, prompt failure preservation, new-session failure review, process exit, and retained-session navigation. Use function selectors and confirm each selected test actually ran. Then:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /tmp/10x-session-recovery-tests
```

Record actual failures and counts. Do not silently update snapshot references or absorb unrelated failures.

- [ ] **Step 5: Commit the recovery change and focused regressions.**

```bash
git add App/Sessions/SessionController.swift App/Sessions/ActiveSessionView.swift \
  App/Sessions/RuntimeRecoveryView.swift Tests/TenXAppTests/AppModelNavigationTests.swift \
  Tests/TenXAppTests/SessionControllerTests.swift
git commit -m "fix(sessions): retain failed opening targets for recovery"
```

### Task 3: Verify the first roadmap slice in an isolated Release build

**Files:**
- Create: `docs/superpowers/evidence/2026-09-07-session-continuity-recovery/README.md` and actual screenshots/log summaries.
- Update: this plan's checkboxes and the audit implementation roadmap.

**Interfaces:**
- Consumes: completed Tasks 1 and 2 and the installed OMP runtime.
- Produces: reproducible evidence tied to branch/SHA, with explicit verified, unverified, and user-test items.

- [ ] **Step 1: Build Release from the current committed branch.** Follow `launching-local-builds` and `verifying-work`. Use a unique derived-data directory, app bundle ID `com.nextstep.tenx.sessionrecovery`, and disposable defaults/project/session data. Never replace or terminate the user's installed app or earlier audit instance.

```bash
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release \
  -derivedDataPath /tmp/10x-session-recovery-release \
  CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=com.nextstep.tenx.sessionrecovery
```

- [ ] **Step 2: Confirm the window is visible and drive real controls.** Test: first-action new session using a warm project, first-action existing-session open, cold controls, completed content after closing/relaunching, missing/unavailable session open followed by a successful retry, failed new-session Review prompt, rejected submission, and child exit/restart. Use disposable session files and a controlled executable fixture only for failure injection. Label fixture-based checks separately from actual-OMP persistence checks.
- [ ] **Step 3: Save evidence and record limits.** Include each trigger, expected/result, actual runtime version, artifact SHA, screenshots, test counts, and any blocked case. Do not call a direct RPC probe proof of a UI interaction.
- [ ] **Step 4: Update PR #32 with actual outcomes, verify base compatibility, and perform review.** Keep it draft if a required check is red or blocked. No merge. Continue to the next audit slice once this reviewable working slice is recorded.

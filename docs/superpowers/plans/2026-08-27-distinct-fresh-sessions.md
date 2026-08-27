# Distinct Fresh Sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every 10x new-session launch create and retain a distinct persisted OMP session, independent of OMP's `autoResume` setting.

**Architecture:** Keep `SessionProcessManager` as the owner of runtime identity. Every fresh launch supplies OMP's canonical project bucket through `--session-dir`, which bypasses `autoResume` and creates a persisted session at startup. Warm checkout uses `new_session` within that persistent manager. Registration requires a real `sessionFile` and rejects an already-owned path before mutating the handle index.

**Tech Stack:** Swift 6.1, Swift Concurrency actors, Swift Testing, OmpKit RPC, Python fake RPC fixture

---

## File Structure

- Modify `OmpKit/Sources/OmpKit/SessionProcessManager.swift`: define the duplicate-path error, make cold creation explicit, and enforce unique handle ownership.
- Modify `OmpKit/Tests/OmpKitTests/ProcessManagerTests.swift`: cover cold launch arguments, RPC ordering, two same-project sessions, and duplicate-path cleanup.
- Modify `OmpKit/Tests/OmpKitTests/ProcessManagerTestFixtures.swift`: allow mode-specific fake-server arguments.
- Modify `OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py`: provide process-unique session identities.

### Task 1: Explicit Cold Fresh-Session Lifecycle

> **Live-validation correction:** The original `--no-session` plan below was
> disproved against the installed OMP binary. `--no-session` is permanently
> in-memory even after `new_session`. The implemented contract uses
> `--session-dir <canonical-project-bucket>`, omits `new_session` for cold
> startup, and rejects a missing `sessionFile`. The original red/green steps are
> retained as historical planning context; final verification follows the
> corrected contract.

**Files:**
- Modify: `OmpKit/Tests/OmpKitTests/ProcessManagerTests.swift:58-89`
- Modify: `OmpKit/Tests/OmpKitTests/ProcessManagerTestFixtures.swift:51-70`
- Modify: `OmpKit/Sources/OmpKit/SessionProcessManager.swift:257-275`

- [ ] **Step 1: Add the failing cold-lifecycle test**

```swift
@Test func coldOpenNewStartsDetachedAndExplicitlyCreatesASession() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ColdOpenNew-\(UUID().uuidString)", isDirectory: true)
    let commandLog = directory.appendingPathComponent("commands.log")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: commandLog.path, contents: nil)

    let capture = ConfigurationCapture()
    let manager = capturingManager(
        capture,
        mode: "command-log",
        modeArguments: [commandLog.path])
    _ = try await manager.openNew(projectDirectory: directory.path)

    let configuration = try #require(capture.snapshot().first)
    #expect(configuration.noSession)
    #expect(configuration.resolvedArguments == [
        "--mode", "rpc", "--no-title", "--no-session",
    ])
    let commands = try String(contentsOf: commandLog, encoding: .utf8)
        .split(separator: "\n")
        .map(String.init)
    #expect(commands == ["negotiate_protocol", "new_session", "get_state"])
    await manager.closeAll()
}
```

Extend `capturingManager` with `modeArguments: [String] = []` and append those arguments after `mode`.

- [ ] **Step 2: Run the test to prove the root cause**

Run: `swift test --package-path OmpKit --filter coldOpenNewStartsDetachedAndExplicitlyCreatesASession`

Expected: FAIL because `configuration.noSession` is false and the command log omits `new_session`.

- [ ] **Step 3: Implement the minimum explicit lifecycle**

```swift
configuration.noSession = true
let client = clientFactory(configuration)
managed = ManagedClient(id: UUID(), client: client)
isWarmCheckout = false
beginTransition(managed: managed, openingID: openingID, sessionPath: fallbackPath)
task = Task { () throws -> ManagedHandle in
    try await client.start()
    _ = try await client.send(.newSession(parentSession: nil))
    let state = try await client.send(.getState())
    let path = state.data?["sessionFile"]?.stringValue ?? fallbackPath
    return ManagedHandle(
        managed: managed,
        handle: Handle(sessionPath: path, client: client))
}
```

Keep provider, model, and thinking launch flags unchanged. Update `openNewForwardsProviderModelThinkingFlags` so its expected resolved arguments end with `"--no-session"`.

- [ ] **Step 4: Run focused lifecycle tests**

Run: `swift test --package-path OmpKit --filter 'coldOpenNew|openNewForwardsProviderModelThinkingFlags'`

Expected: both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add OmpKit/Sources/OmpKit/SessionProcessManager.swift OmpKit/Tests/OmpKitTests/ProcessManagerTests.swift OmpKit/Tests/OmpKitTests/ProcessManagerTestFixtures.swift
git commit -m "fix(ompkit): explicitly create cold sessions"
```

### Task 2: Distinct Same-Project Session Regression

**Files:**
- Modify: `OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py:152-157`
- Modify: `OmpKit/Tests/OmpKitTests/ProcessManagerTests.swift:79-90`

- [ ] **Step 1: Add process-unique fake identities**

```python
if mode == "unique-session-file":
    identifier = str(os.getpid())
    STATE = {
        "model": {"id": "fake", "provider": "test"},
        "isStreaming": False,
        "sessionId": f"fake-{identifier}",
        "sessionFile": f"/tmp/fake-{identifier}.jsonl",
    }
```

- [ ] **Step 2: Add the same-project regression test**

```swift
@Test func twoColdSessionsInOneProjectKeepDistinctRuntimeOwners() async throws {
    let capture = ConfigurationCapture()
    let manager = capturingManager(capture, mode: "unique-session-file")

    let first = try await manager.openNew(projectDirectory: "/tmp/project")
    let second = try await manager.openNew(projectDirectory: "/tmp/project")

    #expect(first.sessionPath != second.sessionPath)
    #expect(first.client !== second.client)
    #expect(await manager.handle(for: first.sessionPath)?.client === first.client)
    #expect(await manager.handle(for: second.sessionPath)?.client === second.client)
    #expect(capture.snapshot().allSatisfy(\.noSession))
    await manager.closeAll()
}
```

- [ ] **Step 3: Run the regression**

Run: `swift test --package-path OmpKit --filter twoColdSessionsInOneProjectKeepDistinctRuntimeOwners`

Expected: PASS with two distinct persisted paths and clients.

- [ ] **Step 4: Commit**

```bash
git add OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py OmpKit/Tests/OmpKitTests/ProcessManagerTests.swift
git commit -m "test(ompkit): cover same-project fresh sessions"
```

### Task 3: Reject Duplicate Runtime Ownership

**Files:**
- Modify: `OmpKit/Tests/OmpKitTests/ProcessManagerTests.swift`
- Modify: `OmpKit/Sources/OmpKit/SessionProcessManager.swift:1-8,459-468`

- [ ] **Step 1: Add the failing duplicate-path test**

```swift
@Test func duplicateNewSessionPathPreservesTheExistingOwner() async throws {
    let clients = ClientCapture()
    let manager = SessionProcessManager(clientFactory: { configuration in
        var fake = configuration
        fake.executable = "/usr/bin/env"
        fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, "basic"]
        fake.rawArgv = true
        fake.cwd = nil
        let client = RpcClient(configuration: fake)
        clients.append(client)
        return client
    })
    let first = try await manager.openNew(projectDirectory: "/tmp/project")

    do {
        _ = try await manager.openNew(projectDirectory: "/tmp/project")
        Issue.record("expected duplicate session path to fail")
    } catch let error as SessionProcessManagerError {
        #expect(error == .duplicateSessionPath("/tmp/fake.jsonl"))
    }

    let spawned = clients.snapshot()
    #expect(spawned.count == 2)
    #expect(await manager.handle(for: first.sessionPath)?.client === first.client)
    #expect(await spawned[0].exitCode == nil)
    #expect(await spawned[1].exitCode != nil)
    await manager.closeAll()
}
```

- [ ] **Step 2: Run the test and confirm failure**

Run: `swift test --package-path OmpKit --filter duplicateNewSessionPathPreservesTheExistingOwner`

Expected: FAIL because the second transition overwrites `handles[sessionPath]`.

- [ ] **Step 3: Add the typed error and guarded registration**

```swift
public enum SessionProcessManagerError: Error, Sendable, Equatable {
    case duplicateSessionPath(String)
}
```

```swift
private func activateTransition(
    managed: ManagedClient,
    openingID: UUID,
    sessionPath: String
) throws -> Handle? {
    guard transitions[managed.id]?.openingID == openingID else { return nil }
    guard handles[sessionPath] == nil else {
        throw SessionProcessManagerError.duplicateSessionPath(sessionPath)
    }
    transitions.removeValue(forKey: managed.id)
    let handle = Handle(sessionPath: sessionPath, client: managed.client)
    handles[sessionPath] = ManagedHandle(managed: managed, handle: handle)
    return handle
}
```

Update both call sites to use `try activateTransition(...)`. Existing catch paths retain the old owner and discard the rejected transition.

- [ ] **Step 4: Run ownership and transition coverage**

Run: `swift test --package-path OmpKit --filter 'duplicateNewSessionPath|coldOpenNew|warmTransition|openNewChecksOutWarmClient'`

Expected: all selected tests PASS.

- [ ] **Step 5: Commit**

```bash
git add OmpKit/Sources/OmpKit/SessionProcessManager.swift OmpKit/Tests/OmpKitTests/ProcessManagerTests.swift
git commit -m "fix(ompkit): reject duplicate session ownership"
```

### Task 4: Full Verification and Handoff

**Files:**
- Modify: PR body only when outbound push is available

- [ ] **Step 1: Run all OmpKit tests**

Run: `swift test --package-path OmpKit`

Expected: zero failures, including the corrected persistent-session contract.

- [ ] **Step 1a: Run the real OMP persistence regression**

Run: `OMPKIT_INTEGRATION=1 OMPKIT_EXECUTABLE="$HOME/.bun/bin/omp" swift test --package-path OmpKit --filter realManagerCreatesDistinctPersistentSessionsInOneProject`

Expected: two distinct `.jsonl` paths in one canonical project bucket and zero failures.

- [ ] **Step 2: Run all app tests**

Run: `xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-fresh-session-tests test`

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Run a production build**

Run: `xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-fresh-session-release build`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Confirm a clean, scoped diff**

```bash
git diff --check origin/main...HEAD
git status --short
git diff --stat origin/main...HEAD
```

Expected: no whitespace errors, no uncommitted files, and changes limited to the design, plan, process manager, process-manager tests, and fake fixture.

- [ ] **Step 5: Push and update the draft PR when policy permits**

Run: `git push origin codex/fix-fresh-session-auto-resume`

Expected: branch is published and the draft PR body contains exact test counts and build evidence. Do not mark ready or merge without explicit authorization.

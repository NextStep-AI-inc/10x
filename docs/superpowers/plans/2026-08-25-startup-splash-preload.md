# Startup Splash and Warm Project Preload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Present a compact startup window on cold launch while 10x prepares workspace data and negotiates reusable OMP clients for the two most recent valid projects.

**Architecture:** A unique SwiftUI startup scene renders a pure `SplashView` from `StartupState`, while the existing `AppModel` coordinates one idempotent bootstrap attempt. `RecentProjectStore` ranks local project paths, and the existing `SessionProcessManager` remains the sole owner of warm and active OMP children so checkout, eviction, cancellation, and quit teardown share one lifecycle.

**Tech Stack:** Swift 6.0 with complete concurrency checking, SwiftUI and Observation, AppKit lifecycle bridging, Swift Testing, OmpKit RPC v2, macOS 15+

**Spec:** `docs/superpowers/specs/2026-08-25-startup-splash-preload-design.md`

## Global Constraints

- Target macOS 15 and later; use scene-native SwiftUI `Window`, `WindowGroup`, `defaultLaunchBehavior`, `restorationBehavior`, `defaultPosition`, `windowBackgroundDragBehavior`, and `windowResizability` APIs.
- The splash is a separate, unique, normal-level, nonrestored, nonresizable 640 × 400 point window. It never transforms into the workspace.
- Disable workspace scene restoration as well: SwiftUI's suppressed launch behavior applies only when no prior workspace scene is restored, while this flow must always gate a cold process behind the splash.
- Show the splash only once per app process. Workspace reopen and additional workspace windows bypass it.
- Use the exact visible copy from the spec. The upper label is `BUILD 0.1.0` for the current bundle and must not contain `10x Desktop`.
- Keep project names, paths, session names, provider names, model names, prompts, and account data out of the splash and its display logs.
- Reuse `TenXPalette`, `TenXTypography`, `BrandWordmark`, `GhostActionStyle`, and `AccessibilityAnnouncer`; do not add a design dependency or duplicate an existing primitive.
- The signal is one continuous path: flat rule followed by one centered sine wavelength over roughly 160 points, with a 16 point nominal amplitude and baseline-pinned endpoints.
- The cyan segment and amplitude breathing are indeterminate motion. Reduce Motion and recovery both freeze them; the ledger remains the complete status source.
- The success gate includes every applicable stage and up to two real no-session OMP clients. Use a 350 ms minimum visibility floor, a 10 second watchdog, selective retry, and no fixed branding delay.
- Missing OMP routes to the existing full-size `SetupView` after the 350 ms floor without waiting for the watchdog.
- Provider usage refresh remains nonblocking. Provider discovery still determines whether the first workspace route is provider setup or new session.
- The highest-ranked warm client remains primary. Only the second unclaimed client gets a five-minute post-handoff expiry; memory pressure may evict any unclaimed client earlier.
- `SessionProcessManager` is the only owner of OMP children. Timeout, cancellation, failed negotiation, checkout failure, eviction, OMP replacement, and app quit must reap every affected child.
- Preserve existing per-session idempotence and unexpected-exit recovery. A second concurrent session in the same project may not share a checked-out client.
- Use strict typed Swift and complete concurrency checking. Do not add unchecked type weakening, dependencies, schema changes, or unrelated refactors.
- Every new app source or app-test file must be followed by `ruby scripts/generate_xcodeproj.rb` before `xcodebuild`.
- Follow TDD for each task: focused red test, minimal implementation, focused green test, relevant full suite, atomic conventional commit.
- This checkout had no configured Git remote on 2026-08-25, so a draft PR could not be opened during planning. Before implementation, recheck `git remote -v`; if a remote exists, open the draft first and link this plan and spec. Never merge without Tanner's explicit instruction.
- Final verification uses the Release build and the real window. Load `launching-local-builds`, `visual-ui`, `writing-ui`, and `verifying-work` before the final launch and handoff.
- Baseline on 2026-08-25: `swift test --package-path OmpKit` passed with only its two opt-in integration skips; the macOS scheme passed 237 tests.

## File Map

### Startup domain and persistence

- Create `App/Startup/RecentProjectStore.swift`: persist explicit project selections and rank the top two valid canonical directories.
- Create `App/Startup/StartupState.swift`: typed stage/status/phase values, exact copy, attempt identity, recovery, retry selection, handoff generation, and timing dependency.
- Create `App/Startup/StartupSceneView.swift`: bridge model actions to `openWindow` and `dismissWindow`; no preload logic or styling.

### Splash UI

- Create `App/Startup/SplashView.swift`: fixed 640 × 400 composition, footer, recovery actions, focus, and announcements.
- Create `App/Startup/StartupLedgerView.swift`: four stable semantic rows and their accessible status labels.
- Create `App/Startup/StartupSignalView.swift`: shared black/cyan path geometry and TimelineView motion.

### Application integration

- Create `App/Application/OmpCommandRunner.swift`: cancellation-aware one-shot OMP subprocess execution shared by lookup, settings, and usage.
- Modify `App/Application/AppDependencies.swift`: inject recent-project persistence, process/settings factories, and startup timing.
- Modify `App/Application/AppModel.swift`: idempotent bootstrap, stage orchestration, session watcher, selective retry, Continue fallback, warm-exit handling, memory-pressure handling, and shutdown.
- Modify `App/Setup/OmpExecutableLocator.swift`: inspect candidates through the cancellation-aware command runner.
- Modify `App/Settings/OmpConfigRunning.swift`: replace the detached blocking process with the shared command runner.
- Modify `App/Settings/SettingsViewModel.swift`: return whether preload produced a usable settings catalog/path while retaining its existing visible error state.
- Modify `App/Providers/OmpUsageRunning.swift`: make the nonblocking usage refresh reap its child when canceled or on quit.
- Modify `App/Providers/ProviderManagementViewModel.swift`: cancel and await provider/usage refresh operations during shutdown.
- Modify `App/TenXApp.swift`: declare startup and launch-suppressed workspace scenes.
- Create `App/Application/AppTerminationDelegate.swift`: defer app termination until `AppModel.shutdown()` has reaped children.

### OmpKit lifecycle

- Modify `OmpKit/Sources/OmpKit/SessionProcessManager.swift`: unified managed-client identity, warm pool, atomic checkout, secondary expiry, memory eviction, and complete teardown.
- Modify `OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py`: optional command logging for checkout assertions.
- Create `OmpKit/Tests/OmpKitTests/ProcessManagerTestFixtures.swift`: shared fake manager, configuration capture, and completion flag used by both process-manager test files.
- Modify `OmpKit/Tests/OmpKitTests/ProcessManagerTests.swift`: existing active-session regression coverage.
- Create `OmpKit/Tests/OmpKitTests/WarmProcessManagerTests.swift`: warm, checkout, eviction, crash, and teardown behavior.

### App tests and generated project

- Create `Tests/TenXAppTests/RecentProjectStoreTests.swift`.
- Create `Tests/TenXAppTests/OmpCommandRunnerTests.swift`.
- Create `Tests/TenXAppTests/StartupStateTests.swift`.
- Create `Tests/TenXAppTests/StartupTestFixtures.swift`.
- Create `Tests/TenXAppTests/AppModelStartupTests.swift`.
- Create `Tests/TenXAppTests/StartupSignalTests.swift`.
- Create `Tests/TenXAppTests/StartupSplashSnapshotTests.swift`.
- Create `Tests/TenXAppTests/ReferenceImages/startup-splash-loading.png`.
- Create `Tests/TenXAppTests/ReferenceImages/startup-splash-recovery.png`.
- Modify `Tests/TenXAppTests/OmpConfigServiceTests.swift`.
- Modify `Tests/TenXAppTests/AppModelNavigationTests.swift` only where dependency construction must supply the new factories.
- Regenerate `10x.xcodeproj/project.pbxproj` as new app and test files are added.

---

### Task 1: Persist and Rank Recent Projects

**Files:**
- Create: `App/Startup/RecentProjectStore.swift`
- Create: `Tests/TenXAppTests/RecentProjectStoreTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` via `ruby scripts/generate_xcodeproj.rb`

**Interfaces:**
- Consumes: `UserDefaults`, `URL` resource values, and `[SessionMetadata]` from OmpKit.
- Produces: `RecentProjectStore.init(defaults:key:)`, `recordSelection(_:)`, and `rankedProjects(sessions:) -> [URL]`.

- [ ] **Step 1: Write the failing ranking and persistence tests**

Create tests that use an isolated defaults suite and real temporary directories:

```swift
import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor
@Test func explicitProjectsRankBeforeSessionHistoryAndDeduplicate() throws {
    let fixture = try RecentProjectFixture()
    defer { fixture.cleanup() }
    let first = try fixture.directory("Explicit")
    let second = try fixture.directory("Session")
    let store = fixture.store()
    store.recordSelection(first)

    let projects = store.rankedProjects(sessions: [
        fixture.session(cwd: second.path, modified: Date(timeIntervalSince1970: 20)),
        fixture.session(cwd: first.path, modified: Date(timeIntervalSince1970: 30)),
    ])

    #expect(projects == [first.resolvingSymlinksInPath(), second.resolvingSymlinksInPath()])
}

@MainActor
@Test func recordSelectionMovesAProjectToTheFrontAcrossStoreInstances() throws {
    let fixture = try RecentProjectFixture()
    defer { fixture.cleanup() }
    let first = try fixture.directory("First")
    let second = try fixture.directory("Second")
    fixture.store().recordSelection(first)
    fixture.store().recordSelection(second)
    fixture.store().recordSelection(first)

    #expect(fixture.store().rankedProjects(sessions: []) == [
        first.resolvingSymlinksInPath(),
        second.resolvingSymlinksInPath(),
    ])
}

@MainActor
@Test func rankingFiltersMissingFilesAndStopsAtTwoProjects() throws {
    let fixture = try RecentProjectFixture()
    defer { fixture.cleanup() }
    let first = try fixture.directory("One")
    let second = try fixture.directory("Two")
    let third = try fixture.directory("Three")
    let missing = fixture.root.appending(path: "Deleted", directoryHint: .isDirectory)

    let projects = fixture.store().rankedProjects(sessions: [
        fixture.session(cwd: missing.path, modified: Date(timeIntervalSince1970: 40)),
        fixture.session(cwd: first.path, modified: Date(timeIntervalSince1970: 30)),
        fixture.session(cwd: second.path, modified: Date(timeIntervalSince1970: 20)),
        fixture.session(cwd: third.path, modified: Date(timeIntervalSince1970: 10)),
    ])

    #expect(projects == [first.resolvingSymlinksInPath(), second.resolvingSymlinksInPath()])
}
```

The fixture creates `UserDefaults(suiteName:)`, removes that persistent domain in `cleanup()`, writes directories below a UUID-named temporary root, and creates `SessionMetadata` with unique paths and the supplied `cwd`/`modified` values.

- [ ] **Step 2: Generate the project and prove the tests are red**

Run:

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:TenXAppTests/RecentProjectStoreTests test
```

Expected: compile failure because `RecentProjectStore` does not exist.

- [ ] **Step 3: Implement the minimal deterministic store**

Create the production type with a two-entry explicit history and one canonical validation path:

```swift
import Foundation
import OmpKit

@MainActor
struct RecentProjectStore: Sendable {
    static let defaultKey = "recent-project-paths"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = Self.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func recordSelection(_ url: URL) {
        guard let project = canonicalDirectory(url) else { return }
        let prior = defaults.stringArray(forKey: key) ?? []
        let paths = [project.path] + prior.filter { path in
            URL(filePath: path).resolvingSymlinksInPath().standardizedFileURL.path
                != project.path
        }
        defaults.set(Array(paths.prefix(2)), forKey: key)
    }

    func rankedProjects(sessions: [SessionMetadata]) -> [URL] {
        let explicitPaths = defaults.stringArray(forKey: key) ?? []
        let sessionPaths = sessions
            .sorted { $0.modified > $1.modified }
            .map(\.cwd)
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        var projects: [URL] = []

        for path in explicitPaths + sessionPaths {
            guard projects.count < 2,
                  let project = canonicalDirectory(URL(filePath: path, directoryHint: .isDirectory)),
                  seen.insert(project.path).inserted
            else { continue }
            projects.append(project)
        }
        return projects
    }

    private func canonicalDirectory(_ url: URL) -> URL? {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isReadableKey]
        guard let values = try? canonical.resourceValues(forKeys: keys),
              values.isDirectory == true,
              values.isReadable == true
        else { return nil }
        return canonical
    }
}
```

- [ ] **Step 4: Run focused and existing navigation tests**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:TenXAppTests/RecentProjectStoreTests \
  -only-testing:TenXAppTests/AppModelNavigationTests test
```

Expected: both selections PASS; the store returns only valid, distinct, ranked directories.

- [ ] **Step 5: Commit the ranking unit**

```bash
git add App/Startup/RecentProjectStore.swift \
  Tests/TenXAppTests/RecentProjectStoreTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat: track recent projects"
```

---

### Task 2: Add Warm No-session Client Ownership

**Files:**
- Modify: `OmpKit/Sources/OmpKit/SessionProcessManager.swift`
- Create: `OmpKit/Tests/OmpKitTests/ProcessManagerTestFixtures.swift`
- Modify: `OmpKit/Tests/OmpKitTests/ProcessManagerTests.swift`
- Create: `OmpKit/Tests/OmpKitTests/WarmProcessManagerTests.swift`

**Interfaces:**
- Consumes: existing `RpcClientConfiguration.noSession`, `RpcClient.start()`, and `RpcClient.termination`.
- Produces: `SessionProcessManager.WarmHandle`, `WarmExit`, `unexpectedWarmExits`, `warm(projectDirectory:)`, `isWarm(projectDirectory:)`, and `cancelWarmings() async -> [String]`.

- [ ] **Step 1: Extract shared process-manager test fixtures**

Move `ConfigurationCapture`, `CompletionFlag`, `capturingManager`, and `fakeManager` unchanged from `ProcessManagerTests.swift` into `ProcessManagerTestFixtures.swift`. Remove only their `private` access modifiers so both test files can use them. Add a locked `ClientCapture` with `append(_:)` and `snapshot()` for cancellation assertions. Run the existing process-manager selection before adding warm tests:

```bash
swift test --package-path OmpKit --filter ProcessManagerTests
```

Expected: existing tests PASS with no behavioral change.

- [ ] **Step 2: Write failing warm-pool tests**

Use the existing fake server and configuration capture:

```swift
import Foundation
import Testing
@testable import OmpKit

@Test func warmStartsOneNoSessionClientPerCanonicalProject() async throws {
    let capture = ConfigurationCapture()
    let manager = capturingManager(capture)
    let firstProject = URL(filePath: "/tmp/project-a").resolvingSymlinksInPath().path
    let secondProject = URL(filePath: "/tmp/project-b").resolvingSymlinksInPath().path

    async let first = manager.warm(projectDirectory: firstProject)
    async let second = manager.warm(projectDirectory: secondProject)
    let handles = try await [first, second]
    let configurations = capture.snapshot()

    #expect(handles.count == 2)
    #expect(configurations.count == 2)
    #expect(configurations.allSatisfy(\.noSession))
    #expect(Set(configurations.compactMap { $0.cwd?.path }) == [
        firstProject, secondProject,
    ])
    await manager.closeAll()
}

@Test func concurrentWarmForOneProjectSharesOneChild() async throws {
    let capture = ConfigurationCapture()
    let manager = capturingManager(capture)
    async let first = manager.warm(projectDirectory: "/tmp/shared")
    async let second = manager.warm(projectDirectory: "/tmp/shared")
    let handles = try await [first, second]

    #expect(handles[0].client === handles[1].client)
    #expect(capture.snapshot().count == 1)
    await manager.closeAll()
}

@Test func warmExitIsReportedAndRemovedBeforeCheckout() async throws {
    let manager = fakeManager(mode: "crash-after-negotiation")
    let project = URL(filePath: "/tmp/dies").resolvingSymlinksInPath().path
    _ = try await manager.warm(projectDirectory: project)
    let event = await withTimeout(.seconds(5)) {
        for await exit in manager.unexpectedWarmExits { return exit }
        return nil
    } ?? nil

    #expect(event?.projectDirectory == project)
    #expect(event?.code == 7)
    #expect(await !manager.isWarm(projectDirectory: project))
    await manager.closeAll()
}

@Test func closeAllReapsWarmAndActiveClients() async throws {
    let manager = fakeManager()
    let warm = try await manager.warm(projectDirectory: "/tmp/warm")
    let active = try await manager.open(sessionPath: "/tmp/active.jsonl", cwd: "/tmp")

    await manager.closeAll()

    #expect(await warm.client.exitCode != nil)
    #expect(await active.client.exitCode != nil)
}

@Test func cancelWarmingsReapsAnInflightChildWithoutEvictingReadyWarmClients() async throws {
    let configurations = ConfigurationCapture()
    let clients = ClientCapture()
    let readyProject = URL(filePath: "/tmp/ready").resolvingSymlinksInPath().path
    let blockedProject = URL(filePath: "/tmp/blocked").resolvingSymlinksInPath().path
    let manager = SessionProcessManager(clientFactory: { configuration in
        configurations.append(configuration)
        var fake = configuration
        fake.executable = "/usr/bin/env"
        let mode = configuration.cwd?.path == readyProject ? "basic" : "never-ready"
        fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, mode]
        fake.rawArgv = true
        fake.cwd = nil
        fake.startupTimeout = .seconds(30)
        let client = RpcClient(configuration: fake)
        clients.append(client)
        return client
    })
    _ = try await manager.warm(projectDirectory: readyProject)
    let blocked = Task {
        try? await manager.warm(projectDirectory: blockedProject)
    }
    while configurations.snapshot().count < 2 { await Task.yield() }

    let canceled = await manager.cancelWarmings()
    _ = await blocked.value

    #expect(canceled == [blockedProject])
    #expect(await manager.isWarm(projectDirectory: readyProject))
    #expect(await !manager.isWarm(projectDirectory: blockedProject))
    #expect(await clients.snapshot()[1].exitCode != nil)
    await manager.closeAll()
}
```

- [ ] **Step 3: Run the OmpKit tests and confirm the warm API is absent**

Run:

```bash
swift test --package-path OmpKit --filter WarmProcessManagerTests
```

Expected: compile failure for `WarmHandle`, `warm`, `unexpectedWarmExits`, and `isWarm`.

- [ ] **Step 4: Refactor process ownership around one managed identity**

Replace separate watcher ownership with private managed wrappers so one termination watcher follows a client when it moves from warm to active:

```swift
private struct ManagedClient: Sendable {
    let id: UUID
    let client: RpcClient
}

private struct ManagedHandle: Sendable {
    let managed: ManagedClient
    let handle: Handle
}

private struct ManagedWarmHandle: Sendable {
    let managed: ManagedClient
    let handle: WarmHandle
}

private var handles: [String: ManagedHandle] = [:]
private var warmHandles: [String: ManagedWarmHandle] = [:]
private var terminationWatchers: [UUID: Task<Void, Never>] = [:]

private struct WarmOpening {
    let id: UUID
    let task: Task<ManagedWarmHandle, any Error>
}

private var warming: [String: WarmOpening] = [:]
```

Keep public active handles source-compatible by unwrapping `ManagedHandle.handle` in `open`, `handle(for:)`, and tests. Replace `watchForExit(_:)` with one watcher per managed ID:

```swift
private func watchForExit(_ managed: ManagedClient) {
    terminationWatchers[managed.id] = Task { [weak self] in
        for await _ in managed.client.termination {}
        guard let self, !Task.isCancelled else { return }
        await self.reportExit(managed)
    }
}
```

`reportExit(_:)` first removes a matching warm entry and yields `WarmExit`; otherwise it removes a matching active entry and yields the existing `UnexpectedExit`. Do not cancel and recreate the watcher during checkout in Task 3.

- [ ] **Step 5: Implement idempotent warm startup**

Add the public values and a warm opening table mirroring the existing active opening table:

```swift
public struct WarmHandle: Sendable {
    public let projectDirectory: String
    public let client: RpcClient
}

public struct WarmExit: Sendable {
    public let projectDirectory: String
    public let code: Int32?
    public let stderrTail: String
}

@discardableResult
public func warm(projectDirectory: String) async throws -> WarmHandle {
    let project = canonicalProjectDirectory(projectDirectory)
    if let existing = warmHandles[project] { return existing.handle }
    if let inFlight = warming[project] { return try await inFlight.task.value.handle }

    let openingID = UUID()
    let factory = clientFactory
    let executable = executable
    let task = Task { () throws -> ManagedWarmHandle in
        var configuration = RpcClientConfiguration()
        configuration.executable = executable
        configuration.cwd = URL(filePath: project, directoryHint: .isDirectory)
        configuration.noSession = true
        let client = factory(configuration)
        try await client.start()
        let managed = ManagedClient(id: UUID(), client: client)
        return ManagedWarmHandle(
            managed: managed,
            handle: WarmHandle(projectDirectory: project, client: client))
    }
    warming[project] = WarmOpening(id: openingID, task: task)

    do {
        let opened = try await task.value
        guard warming[project]?.id == openingID else {
            await opened.managed.client.shutdown()
            throw CancellationError()
        }
        warming.removeValue(forKey: project)
        warmHandles[project] = opened
        watchForExit(opened.managed)
        return opened.handle
    } catch {
        if warming[project]?.id == openingID { warming.removeValue(forKey: project) }
        throw error
    }
}
```

`canonicalProjectDirectory(_:)` uses `resolvingSymlinksInPath().standardizedFileURL.path`. `closeAll()` cancels active openings and warm openings, shuts down registered active and warm clients, awaits any opening that escaped cancellation, cancels every watcher, and finishes neither public exit stream until manager deinitialization.

Add the selective in-flight cancellation used by watchdog, Continue, warm loss, and memory pressure:

```swift
@discardableResult
public func cancelWarmings() async -> [String] {
    let projects = warming.keys.sorted()
    let openings = Array(warming.values)
    warming.removeAll()
    for opening in openings { opening.task.cancel() }
    for opening in openings {
        if let opened = try? await opening.task.value {
            await opened.managed.client.shutdown()
        }
    }
    return projects
}
```

Because `warm(projectDirectory:)` checks the opening ID after awaiting its shared task, removing the opening makes every canceled waiter reject any late result and shut it down. Registered successful warm handles remain untouched. `closeAll()` calls `cancelWarmings()` before closing registered warm and active handles.

- [ ] **Step 6: Run focused and full OmpKit suites**

Run:

```bash
swift test --package-path OmpKit --filter WarmProcessManagerTests
swift test --package-path OmpKit
```

Expected: warm tests PASS; all existing process-manager tests remain green; only the two opt-in real-environment tests may skip.

- [ ] **Step 7: Commit unified warm ownership**

```bash
git add OmpKit/Sources/OmpKit/SessionProcessManager.swift \
  OmpKit/Tests/OmpKitTests/ProcessManagerTestFixtures.swift \
  OmpKit/Tests/OmpKitTests/ProcessManagerTests.swift \
  OmpKit/Tests/OmpKitTests/WarmProcessManagerTests.swift
git commit -m "feat(ompkit): warm project clients"
```

---

### Task 3: Check Out, Retain, and Evict Warm Clients

**Files:**
- Modify: `OmpKit/Sources/OmpKit/SessionProcessManager.swift`
- Modify: `OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py`
- Modify: `OmpKit/Tests/OmpKitTests/WarmProcessManagerTests.swift`

**Interfaces:**
- Consumes: Task 2's canonical warm pool and managed-client watcher.
- Produces: warm-first behavior in `open(sessionPath:cwd:)` and `openNew(projectDirectory:)`, plus `beginWarmRetention(primaryProjectDirectory:)` and `evictWarmClients() async -> [String]`.

- [ ] **Step 1: Add command logging to the fake RPC server**

Allow one test mode to append every received command type to a path supplied as the second argument:

```python
import os

command_log = sys.argv[2] if mode == "command-log" and len(sys.argv) > 2 else None

def log_command(command_type):
    if command_log is None:
        return
    with open(command_log, "a", encoding="utf-8") as handle:
        handle.write((command_type or "parse") + "\n")
```

Call `log_command(ctype)` immediately after decoding each command. Keep every existing fake-server mode unchanged.

Add two scoped lifecycle modes in the command dispatch:

```python
if mode == "reject-new-session" and ctype == "new_session":
    emit({"id": cid, "type": "response", "command": ctype,
          "success": False, "error": "new session rejected"})
    continue
if mode == "crash-after-switch" and ctype == "switch_session":
    emit({"id": cid, "type": "response", "command": ctype, "success": True})
    time.sleep(0.2)
    sys.stderr.write("crash-after-switch\n")
    sys.stderr.flush()
    raise SystemExit(8)
```

Within the existing `negotiate_protocol` branch, after emitting the successful negotiation response and before its `continue`, add the deterministic post-handoff crash mode:

```python
if mode == "crash-after-trigger":
    while not os.path.exists(sys.argv[2]):
        time.sleep(0.01)
    sys.stderr.write("crash-after-trigger\n")
    sys.stderr.flush()
    raise SystemExit(9)
```

- [ ] **Step 2: Write failing checkout tests**

Use a temporary command-log file and a captured client factory:

```swift
@Test func openNewChecksOutWarmClientAndCreatesARealSessionPath() async throws {
    let fixture = try WarmManagerFixture(mode: "command-log")
    defer { fixture.cleanup() }
    let manager = fixture.manager
    let warm = try await manager.warm(projectDirectory: fixture.project.path)

    let active = try await manager.openNew(projectDirectory: fixture.project.path)

    #expect(active.client === warm.client)
    #expect(active.sessionPath == "/tmp/fake.jsonl")
    #expect(fixture.configurationCount == 1)
    #expect(try fixture.commands() == [
        "negotiate_protocol", "new_session", "get_state",
    ])
    await manager.closeAll()
}

@Test func openExistingChecksOutWarmClientWithSwitchSession() async throws {
    let fixture = try WarmManagerFixture(mode: "command-log")
    defer { fixture.cleanup() }
    let manager = fixture.manager
    let warm = try await manager.warm(projectDirectory: fixture.project.path)

    let active = try await manager.open(
        sessionPath: "/tmp/existing.jsonl",
        cwd: fixture.project.path)

    #expect(active.client === warm.client)
    #expect(active.sessionPath == "/tmp/existing.jsonl")
    #expect(fixture.configurationCount == 1)
    #expect(try fixture.commands() == [
        "negotiate_protocol", "switch_session",
    ])
    await manager.closeAll()
}

@Test func secondConcurrentSessionInOneProjectSpawnsAColdChild() async throws {
    let fixture = try WarmManagerFixture(mode: "basic")
    defer { fixture.cleanup() }
    let manager = fixture.manager
    _ = try await manager.warm(projectDirectory: fixture.project.path)

    async let first = manager.open(
        sessionPath: "/tmp/one.jsonl", cwd: fixture.project.path)
    async let second = manager.open(
        sessionPath: "/tmp/two.jsonl", cwd: fixture.project.path)
    let handles = try await [first, second]

    #expect(handles[0].client !== handles[1].client)
    #expect(fixture.configurationCount == 2)
    await manager.closeAll()
}
```

- [ ] **Step 3: Write failing retention and memory-eviction tests**

Inject a sleep gate through the manager initializer rather than waiting five real minutes:

```swift
@Test func gracePeriodEvictsOnlyTheUnclaimedSecondaryClient() async throws {
    let gate = WarmSleepGate()
    let fixture = try WarmManagerFixture(
        mode: "basic",
        warmGracePeriod: .seconds(300),
        sleep: { duration in try await gate.sleep(for: duration) })
    defer { fixture.cleanup() }
    let primary = try fixture.directory("Primary")
    let secondary = try fixture.directory("Secondary")
    let primaryHandle = try await fixture.manager.warm(projectDirectory: primary.path)
    let secondaryHandle = try await fixture.manager.warm(projectDirectory: secondary.path)

    await fixture.manager.beginWarmRetention(primaryProjectDirectory: primary.path)
    await gate.waitUntilSleeping(for: .seconds(300))
    await gate.release(.seconds(300))
    await fixture.waitUntil { await secondaryHandle.client.exitCode != nil }

    #expect(await fixture.manager.isWarm(projectDirectory: primary.path))
    #expect(await !fixture.manager.isWarm(projectDirectory: secondary.path))
    #expect(await primaryHandle.client.exitCode == nil)
    await fixture.manager.closeAll()
}

@Test func memoryPressureEvictsWarmClientsButNotCheckedOutClients() async throws {
    let fixture = try WarmManagerFixture(mode: "basic")
    defer { fixture.cleanup() }
    let warmOnly = try fixture.directory("WarmOnly")
    let activeProject = try fixture.directory("Active")
    _ = try await fixture.manager.warm(projectDirectory: warmOnly.path)
    _ = try await fixture.manager.warm(projectDirectory: activeProject.path)
    let active = try await fixture.manager.openNew(projectDirectory: activeProject.path)

    let evicted = await fixture.manager.evictWarmClients()

    #expect(evicted == [warmOnly.resolvingSymlinksInPath().path])
    #expect(await active.client.exitCode == nil)
    #expect(await fixture.manager.handle(for: active.sessionPath) != nil)
    await fixture.manager.closeAll()
}
```

Add the remaining lifecycle assertions explicitly:

```swift
@Test func failedNewSessionCheckoutReapsTheWarmChild() async throws {
    let fixture = try WarmManagerFixture(mode: "reject-new-session")
    defer { fixture.cleanup() }
    let warm = try await fixture.manager.warm(projectDirectory: fixture.project.path)

    await #expect(throws: RpcClientError.self) {
        _ = try await fixture.manager.openNew(projectDirectory: fixture.project.path)
    }

    #expect(await warm.client.exitCode != nil)
    #expect(await !fixture.manager.isWarm(projectDirectory: fixture.project.path))
    await fixture.manager.closeAll()
}

@Test func checkedOutSecondarySurvivesItsFormerGraceTimer() async throws {
    let gate = WarmSleepGate()
    let fixture = try WarmManagerFixture(
        mode: "basic",
        sleep: { duration in try await gate.sleep(for: duration) })
    defer { fixture.cleanup() }
    let primary = try fixture.directory("Primary")
    let secondary = try fixture.directory("Secondary")
    _ = try await fixture.manager.warm(projectDirectory: primary.path)
    _ = try await fixture.manager.warm(projectDirectory: secondary.path)
    await fixture.manager.beginWarmRetention(primaryProjectDirectory: primary.path)
    await gate.waitUntilSleeping(for: .seconds(300))
    let active = try await fixture.manager.openNew(projectDirectory: secondary.path)

    await gate.release(.seconds(300))
    #expect(await active.client.exitCode == nil)
    #expect(await fixture.manager.handle(for: active.sessionPath) != nil)
    await fixture.manager.closeAll()
}

@Test func checkedOutWarmCrashUsesTheActiveExitStream() async throws {
    let fixture = try WarmManagerFixture(mode: "crash-after-switch")
    defer { fixture.cleanup() }
    _ = try await fixture.manager.warm(projectDirectory: fixture.project.path)
    _ = try await fixture.manager.open(
        sessionPath: "/tmp/crashes.jsonl",
        cwd: fixture.project.path)

    let activeExit = await withTimeout(.seconds(5)) {
        for await exit in fixture.manager.unexpectedExits { return exit }
        return nil
    } ?? nil

    #expect(activeExit?.sessionPath == "/tmp/crashes.jsonl")
    #expect(activeExit?.code == 8)
    await fixture.manager.closeAll()
}
```

Implement `WarmSleepGate` as an actor keyed by `Duration`. `sleep(for:)` stores a throwing continuation under a UUID inside `withTaskCancellationHandler`; cancellation removes and resumes that continuation with `CancellationError`. `waitUntilSleeping(for:)` waits until the keyed waiter collection is nonempty, and `release(_:)` resumes and removes every waiter for that duration. `WarmManagerFixture` owns a UUID-scoped temporary root, project directory, command-log URL, thread-safe configuration capture, and manager. Its factory forwards the original configuration into the capture, sets `executable = "/usr/bin/env"`, sets `extraArguments = ["python3", fixtureURL("fake_server.py").path, mode] + (mode == "command-log" ? [commandLog.path] : [])`, and sets `rawArgv = true` and `cwd = nil`. `cleanup()` calls no process APIs; every test must await `manager.closeAll()` before removing the fixture root.

- [ ] **Step 4: Prove checkout and retention are red**

Run:

```bash
swift test --package-path OmpKit --filter WarmProcessManagerTests
```

Expected: checkout spawns an additional client or omits the required commands, and retention APIs do not compile.

- [ ] **Step 5: Implement atomic warm checkout**

Add one actor-isolated removal helper that cancels expiry without touching the unified termination watcher:

```swift
private func takeWarmClient(projectDirectory: String) -> ManagedWarmHandle? {
    let project = canonicalProjectDirectory(projectDirectory)
    warmExpiryTasks.removeValue(forKey: project)?.cancel()
    return warmHandles.removeValue(forKey: project)
}
```

At the start of a new active open, atomically remove the warm client before awaiting RPC:

```swift
private func checkOutForNewSession(projectDirectory: String) async throws -> ManagedHandle? {
    guard let warm = takeWarmClient(projectDirectory: projectDirectory) else { return nil }
    do {
        _ = try await warm.managed.client.send(.newSession(parentSession: nil))
        let state = try await warm.managed.client.send(.getState())
        let path = state.data?["sessionFile"]?.stringValue
            ?? "new:\(warm.handle.projectDirectory):\(UUID().uuidString)"
        let handle = Handle(sessionPath: path, client: warm.managed.client)
        let managed = ManagedHandle(managed: warm.managed, handle: handle)
        handles[path] = managed
        return managed
    } catch {
        terminationWatchers.removeValue(forKey: warm.managed.id)?.cancel()
        await warm.managed.client.shutdown()
        throw error
    }
}

private func checkOut(
    sessionPath: String,
    projectDirectory: String
) async throws -> ManagedHandle? {
    guard let warm = takeWarmClient(projectDirectory: projectDirectory) else { return nil }
    do {
        _ = try await warm.managed.client.send(.switchSession(path: sessionPath))
        let handle = Handle(sessionPath: sessionPath, client: warm.managed.client)
        let managed = ManagedHandle(managed: warm.managed, handle: handle)
        handles[sessionPath] = managed
        return managed
    } catch {
        terminationWatchers.removeValue(forKey: warm.managed.id)?.cancel()
        await warm.managed.client.shutdown()
        throw error
    }
}
```

Call these helpers before cold spawning. Preserve the existing same-session `handles` and `opening` checks so duplicate opens for one session still share one active child. A different session in the same cwd finds the warm entry already removed and follows the cold path.

- [ ] **Step 6: Implement secondary expiry and memory eviction**

Inject one sleep function and the production five-minute value:

```swift
public typealias Sleep = @Sendable (Duration) async throws -> Void

private let warmGracePeriod: Duration
private let sleep: Sleep
private var warmExpiryTasks: [String: Task<Void, Never>] = [:]

public init(
    executable: String = "omp",
    warmGracePeriod: Duration = .seconds(300),
    sleep: @escaping Sleep = { duration in
        try await ContinuousClock().sleep(for: duration)
    },
    clientFactory: @escaping ClientFactory = { RpcClient(configuration: $0) }
) {
    self.executable = executable
    self.warmGracePeriod = warmGracePeriod
    self.sleep = sleep
    self.clientFactory = clientFactory
    (exitStream, exitContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    (warmExitStream, warmExitContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
}
```

Schedule only nonprimary warm entries and guard each expiry with the managed ID so a replacement cannot be closed by an old timer:

```swift
public func beginWarmRetention(primaryProjectDirectory: String?) {
    let primary = primaryProjectDirectory.map(canonicalProjectDirectory)
    for (project, warm) in warmHandles where project != primary {
        let managedID = warm.managed.id
        warmExpiryTasks[project]?.cancel()
        warmExpiryTasks[project] = Task { [weak self, sleep, warmGracePeriod] in
            do { try await sleep(warmGracePeriod) } catch { return }
            await self?.expireWarmClient(project: project, managedID: managedID)
        }
    }
}

@discardableResult
public func evictWarmClients() async -> [String] {
    let projects = warmHandles.keys.sorted()
    for project in projects { await closeWarm(projectDirectory: project) }
    return projects
}
```

`closeWarm(projectDirectory:)` cancels that entry's timer and watcher, removes it, and awaits `client.shutdown()`. `closeAll()` also cancels every expiry task.

- [ ] **Step 7: Run all lifecycle tests**

Run:

```bash
swift test --package-path OmpKit --filter WarmProcessManagerTests
swift test --package-path OmpKit --filter ProcessManagerTests
swift test --package-path OmpKit
```

Expected: focused checkout/retention tests PASS; existing idempotence, cancellation, crash, and teardown tests remain green.

- [ ] **Step 8: Commit reusable checkout and retention**

```bash
git add OmpKit/Sources/OmpKit/SessionProcessManager.swift \
  OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py \
  OmpKit/Tests/OmpKitTests/WarmProcessManagerTests.swift
git commit -m "feat(ompkit): reuse and evict warm clients"
```

---

### Task 4: Make One-shot OMP Commands Cancellable

**Files:**
- Create: `App/Application/OmpCommandRunner.swift`
- Modify: `App/Setup/OmpExecutableLocator.swift`
- Modify: `App/Settings/OmpConfigRunning.swift`
- Modify: `App/Providers/OmpUsageRunning.swift`
- Modify: `App/Providers/ProviderManagementViewModel.swift`
- Create: `Tests/TenXAppTests/OmpCommandRunnerTests.swift`
- Modify: `Tests/TenXAppTests/OmpExecutableLocatorTests.swift`
- Modify: `Tests/TenXAppTests/OmpConfigServiceTests.swift`
- Modify: `Tests/TenXAppTests/OmpUsageServiceTests.swift`
- Modify: `Tests/TenXAppTests/ProviderManagementViewModelTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` via generator

**Interfaces:**
- Consumes: Foundation `Process`, the existing OMP command arguments, and POSIX process-group signaling.
- Produces: `OmpCommandRunner.run(executableURL:arguments:) async throws -> Data`; lookup, settings, and usage commands that finish process cleanup before cancellation returns.

- [ ] **Step 1: Write failing success and cancellation/reaping tests**

Create two real temporary executables. The first prints a small payload. The second records its PID, ignores `SIGTERM`, and loops so the runner must escalate to `SIGKILL`:

```swift
import Darwin
import Foundation
import Testing
@testable import TenXApp

@Test func ompCommandRunnerReturnsStdoutWithoutExposingStderr() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let executable = try fixture.executable(
        name: "success",
        body: "printf 'ready\\n'; printf 'token=secret\\n' >&2")

    let data = try await OmpCommandRunner().run(
        executableURL: executable,
        arguments: [])

    #expect(String(decoding: data, as: UTF8.self) == "ready\n")
    #expect(!String(decoding: data, as: UTF8.self).contains("secret"))
}

@Test func cancellingOmpCommandRunnerReapsAnIgnoringProcessGroup() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let pidFile = fixture.root.appending(path: "blocked.pid")
    let executable = try fixture.executable(
        name: "blocked",
        body: "trap '' TERM; /bin/sh -c 'trap \"\" TERM; while :; do sleep 1; done' & child=$!; printf '%s %s' $$ $child > \"$1\"; wait $child")
    let operation = Task {
        try await OmpCommandRunner().run(
            executableURL: executable,
            arguments: [pidFile.path])
    }
    let pids = try await fixture.waitForPIDs(in: pidFile, count: 2)

    operation.cancel()
    await #expect(throws: CancellationError.self) {
        _ = try await operation.value
    }
    for pid in pids { try await fixture.waitUntilProcessIsGone(pid) }

    for pid in pids {
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }
}
```

`OmpCommandFixture` creates one UUID-scoped temporary root, writes `"#!/bin/sh\n" + body + "\n"` with mode `0o755`, polls the PID file at 10 ms for at most two seconds until it contains the requested number of valid `pid_t` values, and polls `kill(pid, 0)` for at most three seconds. Both polling helpers throw a fixture timeout error rather than hanging.

- [ ] **Step 2: Generate the project and prove the command-runner tests are red**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:TenXAppTests/OmpCommandRunnerTests test
```

Expected: compile failure because `OmpCommandRunner` does not exist.

- [ ] **Step 3: Implement cancellation-safe one-shot execution**

Create a small process state that closes the race between task cancellation and `Process.run()`:

```swift
import Darwin
import Foundation
import Synchronization

enum OmpCommandRunnerError: Error, Sendable {
    case nonzeroExit(Int32)
}

struct OmpCommandRunner: Sendable {
    func run(executableURL: URL, arguments: [String]) async throws -> Data {
        let state = OmpCommandProcessState(
            executableURL: executableURL,
            arguments: arguments)
        let worker = Task.detached { try await state.run() }

        return try await withTaskCancellationHandler {
            let data = try await worker.value
            try Task.checkCancellation()
            return data
        } onCancel: {
            worker.cancel()
            state.cancel()
        }
    }
}

private struct OmpCommandProcessStorage {
    let process: Process
    let output: Pipe
    let error: Pipe
    var isCancellationRequested = false
    var processGroupID: pid_t?
}

private struct OmpCommandProcessTarget {
    let group: pid_t?
    let pid: pid_t
}

private final class OmpCommandProcessState: Sendable {
    private let storage: Mutex<OmpCommandProcessStorage>

    init(executableURL: URL, arguments: [String]) {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        storage = Mutex(OmpCommandProcessStorage(
            process: process,
            output: output,
            error: error))
    }

    func run() async throws -> Data {
        try Task.checkCancellation()
        let started = try storage.withLock { storage in
            try storage.process.run()
            let pid = storage.process.processIdentifier
            storage.processGroupID = setpgid(pid, pid) == 0 || getpgid(pid) == pid
                ? pid
                : nil
            return (
                storage.process,
                storage.output.fileHandleForReading,
                storage.error.fileHandleForReading,
                storage.isCancellationRequested)
        }
        if started.3 { cancel() }

        async let outputData = started.1.readToEnd() ?? Data()
        async let errorData = started.2.readToEnd() ?? Data()
        started.0.waitUntilExit()
        let data = try await outputData
        _ = try await errorData
        try Task.checkCancellation()
        guard started.0.terminationStatus == 0 else {
            throw OmpCommandRunnerError.nonzeroExit(started.0.terminationStatus)
        }
        return data
    }

    func cancel() {
        let target = storage.withLock { storage -> OmpCommandProcessTarget? in
            storage.isCancellationRequested = true
            guard storage.process.isRunning else { return nil }
            return OmpCommandProcessTarget(
                group: storage.processGroupID,
                pid: storage.process.processIdentifier)
        }
        guard let target else { return }
        signal(
            group: target.group,
            pid: target.pid,
            descendants: target.group == nil ? Self.descendantPIDs(of: target.pid) : [],
            signal: SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
            self.forceKillIfNeeded()
        }
    }

    private func forceKillIfNeeded() {
        let target = storage.withLock { storage -> OmpCommandProcessTarget? in
            guard storage.process.isRunning else { return nil }
            return OmpCommandProcessTarget(
                group: storage.processGroupID,
                pid: storage.process.processIdentifier)
        }
        guard let target else { return }
        signal(
            group: target.group,
            pid: target.pid,
            descendants: target.group == nil ? Self.descendantPIDs(of: target.pid) : [],
            signal: SIGKILL)
    }

    private func signal(
        group: pid_t?,
        pid: pid_t,
        descendants: [pid_t],
        signal: Int32
    ) {
        if let group {
            killpg(group, signal)
        } else if pid > 0 {
            for descendant in descendants.reversed() { kill(descendant, signal) }
            kill(pid, signal)
        }
    }

    private static func descendantPIDs(of parent: pid_t) -> [pid_t] {
        let query = Process()
        let output = Pipe()
        query.executableURL = URL(filePath: "/usr/bin/pgrep")
        query.arguments = ["-P", String(parent)]
        query.standardOutput = output
        query.standardError = FileHandle.nullDevice
        guard (try? query.run()) != nil else { return [] }
        query.waitUntilExit()
        let direct = String(
            decoding: (try? output.fileHandleForReading.readToEnd()) ?? Data(),
            as: UTF8.self)
            .split(whereSeparator: \Character.isWhitespace)
            .compactMap { pid_t($0) }
        return direct + direct.flatMap { descendantPIDs(of: $0) }
    }
}
```

The locked cancellation bit is authoritative: cancellation before spawn makes `Task.checkCancellation()` fail; cancellation in the check/run race is observed by `registerStartedProcess()`; cancellation after spawn signals the new process group. The worker cannot return until `waitUntilExit()` and both pipe drains complete, so callers never observe cancellation before reaping.

- [ ] **Step 4: Route every one-shot OMP command through the runner**

- `OmpExecutableLocator.inspect(_:)` becomes async, calls the runner with `--version`, and parses the first line exactly as today. `locate(preferredURL:)` checks `Task.isCancelled` before each candidate and after each inspection so canceled lookup can never be mistaken for a missing installation.
- `OmpConfigProcessRunner.run(arguments:)` returns `try await OmpCommandRunner().run(executableURL:arguments:)`; delete its detached `Process` block and private duplicate error enum.
- `OmpUsageProcessRunner.run(arguments:)` makes the same replacement; provider usage remains nonblocking at the AppModel layer.
- Replace `ProviderManagementViewModel.shutdown()` with the owned teardown below. Clear stored operations before awaiting so stale refresh work cannot be joined by later calls:

```swift
func shutdown() async {
    let events = eventTask
    eventTask = nil
    events?.cancel()
    let providers = providerRefreshOperation
    providerRefreshOperation = nil
    providers?.task.cancel()
    let usage = usageRefreshOperation
    usageRefreshOperation = nil
    usage?.task.cancel()

    await providerService.shutdown()
    await events?.value
    await providers?.task.value
    await usage?.task.value
}
```

Add the ownership regression to `ProviderManagementViewModelTests.swift`:

```swift
@MainActor
@Test func providerShutdownCancelsAndAwaitsAnInflightUsageCommand() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let pidFile = fixture.root.appending(path: "usage.pid")
    let executable = try fixture.executable(
        name: "blocked-usage",
        body: "printf '%s' $$ > '\(pidFile.path)'; trap '' TERM; while :; do sleep 1; done")
    let model = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: []),
        usageService: OmpUsageService(
            runner: OmpUsageProcessRunner(executableURL: executable)),
        openURL: { _ in })
    let load = Task { await model.loadUsage() }
    let pids = try await fixture.waitForPIDs(in: pidFile, count: 1)
    let pid = try #require(pids.first)

    await model.shutdown()
    await load.value
    try await fixture.waitUntilProcessIsGone(pid)

    #expect(kill(pid, 0) == -1)
    #expect(errno == ESRCH)
}
```

Extend the existing locator, config, and usage selections with a canceled blocking executable assertion. Each assertion records the PID, cancels the public operation, awaits it, and uses the shared fixture to prove the PID is gone. Do not expose stderr in any user-facing error.

- [ ] **Step 5: Run focused and full app regressions**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:TenXAppTests/OmpCommandRunnerTests \
  -only-testing:TenXAppTests/OmpExecutableLocatorTests \
  -only-testing:TenXAppTests/OmpConfigServiceTests \
  -only-testing:TenXAppTests/OmpUsageServiceTests \
  -only-testing:TenXAppTests/ProviderManagementViewModelTests test
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' test
```

Expected: cancellation tests PASS with recorded PIDs absent; all app tests remain green.

- [ ] **Step 6: Commit cancellation-safe command execution**

```bash
git add App/Application/OmpCommandRunner.swift App/Setup/OmpExecutableLocator.swift \
  App/Settings/OmpConfigRunning.swift App/Providers/OmpUsageRunning.swift \
  App/Providers/ProviderManagementViewModel.swift \
  Tests/TenXAppTests/OmpCommandRunnerTests.swift \
  Tests/TenXAppTests/OmpExecutableLocatorTests.swift \
  Tests/TenXAppTests/OmpConfigServiceTests.swift \
  Tests/TenXAppTests/OmpUsageServiceTests.swift \
  Tests/TenXAppTests/ProviderManagementViewModelTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "fix: reap canceled omp commands"
```

---

### Task 5: Model Startup Stages, Recovery, and Timing

**Files:**
- Create: `App/Startup/StartupState.swift`
- Create: `Tests/TenXAppTests/StartupStateTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` via generator

**Interfaces:**
- Consumes: exact stage/copy/timing decisions from the design spec.
- Produces: `StartupStageID`, `StartupStageStatus`, `StartupStageRow`, `StartupPhase`, `StartupTiming`, and observable `StartupState`.

- [ ] **Step 1: Write failing state-transition and copy tests**

```swift
import Testing
@testable import TenXApp

@MainActor
@Test func startupRowsUseTheApprovedOrderAndExactCopy() {
    let state = StartupState()

    #expect(state.rows.map(\.id) == [
        .runtime, .sessions, .settings, .recentProjects,
    ])
    #expect(state.rows.map(\.title) == [
        "Preparing runtime",
        "Loading sessions",
        "Loading settings",
        "Preparing recent projects",
    ])
    #expect(StartupState.buildLabel(version: "0.1.0") == "BUILD 0.1.0")
    #expect(!StartupState.buildLabel(version: "0.1.0").contains("10x"))
}

@MainActor
@Test func recoveryPreservesReadyRowsAndStopsOnlyUnfinishedRows() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markLoading(.runtime, attemptID: attempt)
    state.markReady(.runtime, attemptID: attempt)
    state.markLoading(.sessions, attemptID: attempt)

    state.enterRecovery(attemptID: attempt)

    #expect(state.phase == .recovery)
    #expect(state.status(of: .runtime) == .ready)
    #expect(state.status(of: .sessions) == .stopped)
    #expect(state.status(of: .settings) == .stopped)
    #expect(state.footerTitle == "Startup needs attention")
    #expect(state.footerDetail == "Retry the stopped work or continue with what is ready.")
    #expect(!state.isSignalAnimating)
}

@MainActor
@Test func retryReturnsOnlyStoppedStagesAndIgnoresLateAttempts() {
    let state = StartupState()
    let first = UUID()
    state.beginAttempt(id: first)
    state.markReady(.runtime, attemptID: first)
    state.enterRecovery(attemptID: first)
    let retry = UUID()

    let stages = state.beginRetry(id: retry)
    state.markReady(.sessions, attemptID: first)

    #expect(stages == [.sessions, .settings, .recentProjects])
    #expect(state.status(of: .runtime) == .ready)
    #expect(state.status(of: .sessions) == .queued)
}

@MainActor
@Test func handoffGenerationAdvancesOnlyOncePerAttempt() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.requestHandoff(attemptID: attempt)
    state.requestHandoff(attemptID: attempt)

    #expect(state.phase == .handoff)
    #expect(state.handoffGeneration == 1)
}

@MainActor
@Test func footerUsesTheFirstLoadingStageInLedgerOrder() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markLoading(.settings, attemptID: attempt)
    state.markLoading(.sessions, attemptID: attempt)

    #expect(state.footerTitle == "Loading sessions")
    #expect(state.footerDetail == "Indexing active and archived sessions")
}

@MainActor
@Test func invalidatedReadyStageBecomesRetryable() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    for stage in StartupStageID.allCases {
        state.markReady(stage, attemptID: attempt)
    }

    state.markStopped(.recentProjects, attemptID: attempt)
    state.enterRecovery(attemptID: attempt)

    #expect(state.status(of: .recentProjects) == .stopped)
    #expect(state.beginRetry(id: UUID()) == [.recentProjects])
}
```

- [ ] **Step 2: Generate the project and prove the state tests are red**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:TenXAppTests/StartupStateTests test
```

Expected: compile failure because the startup state types do not exist.

- [ ] **Step 3: Implement typed stages and exact copy**

Use enums rather than stringly keyed dictionaries:

```swift
import Foundation
import Observation

enum StartupStageID: String, CaseIterable, Identifiable, Hashable, Sendable {
    case runtime
    case sessions
    case settings
    case recentProjects

    var id: Self { self }

    var title: String {
        switch self {
        case .runtime: "Preparing runtime"
        case .sessions: "Loading sessions"
        case .settings: "Loading settings"
        case .recentProjects: "Preparing recent projects"
        }
    }

    var detail: String {
        switch self {
        case .runtime: "Checking OMP and provider access"
        case .sessions: "Indexing active and archived sessions"
        case .settings: "Preparing your configuration"
        case .recentProjects: "Starting recent workspaces"
        }
    }
}

enum StartupStageStatus: String, Equatable, Sendable {
    case queued = "Queued"
    case loading = "Loading"
    case ready = "Ready"
    case stopped = "Stopped"
}

struct StartupStageRow: Identifiable, Equatable, Sendable {
    let id: StartupStageID
    let status: StartupStageStatus
    var title: String { id.title }
    var accessibilityLabel: String { "\(title), \(status.rawValue)" }
}

enum StartupPhase: Equatable, Sendable {
    case preparing
    case recovery
    case handoff
}
```

Add `StartupTiming` with production values and an injectable sleep boundary:

```swift
struct StartupTiming: Sendable {
    let minimumVisibility: Duration
    let timeout: Duration
    let sleep: @Sendable (Duration) async throws -> Void

    static let live = StartupTiming(
        minimumVisibility: .milliseconds(350),
        timeout: .seconds(10),
        sleep: { duration in try await ContinuousClock().sleep(for: duration) })
}
```

- [ ] **Step 4: Implement stale-safe state transitions**

`StartupState` owns only presentation state, never tasks or process handles:

```swift
@MainActor
@Observable
final class StartupState {
    private(set) var phase: StartupPhase = .preparing
    private(set) var handoffGeneration = 0
    private(set) var attemptID: UUID?
    private var statuses: [StartupStageID: StartupStageStatus] = Dictionary(
        uniqueKeysWithValues: StartupStageID.allCases.map { ($0, .queued) })

    var rows: [StartupStageRow] {
        StartupStageID.allCases.map {
            StartupStageRow(id: $0, status: statuses[$0] ?? .queued)
        }
    }

    var footerTitle: String {
        phase == .recovery ? "Startup needs attention" : currentStage.title
    }

    var footerDetail: String {
        phase == .recovery
            ? "Retry the stopped work or continue with what is ready."
            : currentStage.detail
    }

    var isSignalAnimating: Bool { phase == .preparing }

    static func buildLabel(version: String) -> String { "BUILD \(version)" }

    func status(of stage: StartupStageID) -> StartupStageStatus {
        statuses[stage] ?? .queued
    }

    func beginAttempt(id: UUID) {
        guard phase != .handoff else { return }
        attemptID = id
        phase = .preparing
        statuses = Dictionary(
            uniqueKeysWithValues: StartupStageID.allCases.map { ($0, .queued) })
    }

    func beginRetry(id: UUID) -> Set<StartupStageID> {
        let stages = Set(StartupStageID.allCases.filter { status(of: $0) != .ready })
        attemptID = id
        phase = .preparing
        for stage in stages { statuses[stage] = .queued }
        return stages
    }

    func markLoading(_ stage: StartupStageID, attemptID: UUID) {
        guard self.attemptID == attemptID, phase == .preparing else { return }
        statuses[stage] = .loading
    }

    func markReady(_ stage: StartupStageID, attemptID: UUID) {
        guard self.attemptID == attemptID, phase == .preparing else { return }
        statuses[stage] = .ready
    }

    func markStopped(_ stage: StartupStageID, attemptID: UUID) {
        guard self.attemptID == attemptID, phase == .preparing else { return }
        statuses[stage] = .stopped
    }

    func enterRecovery(attemptID: UUID) {
        guard self.attemptID == attemptID, phase != .handoff else { return }
        for stage in StartupStageID.allCases where status(of: stage) != .ready {
            statuses[stage] = .stopped
        }
        phase = .recovery
    }

    func requestHandoff(attemptID: UUID) {
        guard self.attemptID == attemptID, phase != .handoff else { return }
        phase = .handoff
        handoffGeneration += 1
    }

    private var currentStage: StartupStageID {
        StartupStageID.allCases.first { status(of: $0) == .loading }
            ?? StartupStageID.allCases.last(where: { status(of: $0) == .ready })
            ?? .runtime
    }
}
```

- [ ] **Step 5: Run state, copy, and navigation tests**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:TenXAppTests/StartupStateTests \
  -only-testing:TenXAppTests/AppModelNavigationTests test
```

Expected: all selected tests PASS; exact copy contains no project data, no `10x Desktop`, and no em dash.

- [ ] **Step 6: Commit the startup presentation model**

```bash
git add App/Startup/StartupState.swift Tests/TenXAppTests/StartupStateTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "feat: model startup progress"
```

---

### Task 6: Coordinate One Idempotent Startup Attempt in AppModel

**Files:**
- Modify: `App/Application/AppDependencies.swift`
- Modify: `App/Application/AppModel.swift`
- Modify: `App/Settings/SettingsViewModel.swift`
- Modify: `Tests/TenXAppTests/OmpConfigServiceTests.swift`
- Modify: `Tests/TenXAppTests/AppModelNavigationTests.swift`
- Create: `Tests/TenXAppTests/StartupTestFixtures.swift`
- Create: `Tests/TenXAppTests/AppModelStartupTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` via generator

**Interfaces:**
- Consumes: Task 1's `RecentProjectStore`, Task 3's warm lifecycle, Task 4's cancellation-safe commands, Task 5's `StartupState`/`StartupTiming`, and the current session/provider/settings models.
- Produces: `AppModel.startupState`, idempotent `bootstrap()`, `retryStartup()`, `continueToWorkspace()`, `workspaceDidOpen()`, `handleMemoryPressure()`, and `shutdown()`.

- [ ] **Step 1: Make settings preload report truthful readiness**

Change `SettingsViewModel.load()` to return success without changing its existing visible error behavior:

```swift
@discardableResult
func load() async -> Bool {
    guard !isLoading else { return loadError == nil && !configPath.isEmpty }
    isLoading = true
    loadError = nil
    defer { isLoading = false }
    do {
        async let values = service.list()
        async let path = service.path()
        catalog = SettingsCatalog.build(from: .object(try await values))
        configPath = try await path
        return true
    } catch {
        loadError = "[Settings:SettingsViewModel] Unable to load settings — \(error.localizedDescription)"
        return false
    }
}
```

Extend `OmpConfigServiceTests.swift`:

```swift
@MainActor
@Test func settingsLoadReportsWhetherCatalogAndPathAreReady() async {
    let ready = SettingsViewModel(service: OmpConfigService(runner: FakeConfigRunner()))
    let failed = SettingsViewModel(service: OmpConfigService(runner: FailingConfigRunner()))

    #expect(await ready.load())
    #expect(ready.settingCount > 0)
    #expect(!ready.configPath.isEmpty)
    #expect(await !failed.load())
    #expect(failed.loadError != nil)
}
```

Run the focused test before and after the change. The red run must fail because `load()` currently returns `Void`.

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:TenXAppTests/settingsLoadReportsWhetherCatalogAndPathAreReady test
```

- [ ] **Step 2: Extend AppDependencies with concrete factories**

Keep lifecycle ownership in `AppModel` while allowing tests to supply fake children and clocks:

```swift
struct AppDependencies: Sendable {
    let ompLocator: any OmpLocating
    let sessionLibrary: SessionLibrary
    let recentProjectStore: RecentProjectStore
    let startupTiming: StartupTiming
    let makeProcessManager: @Sendable (String) -> SessionProcessManager
    let makeSettingsModel: @MainActor @Sendable (URL) -> SettingsViewModel
    let makeProviderModel: @MainActor @Sendable (URL) -> ProviderManagementViewModel

    @MainActor static let live = AppDependencies(
        ompLocator: OmpExecutableLocator(),
        sessionLibrary: SessionLibrary(),
        recentProjectStore: RecentProjectStore(),
        startupTiming: .live,
        makeProcessManager: { executable in
            SessionProcessManager(executable: executable)
        },
        makeSettingsModel: { executableURL in
            SettingsViewModel(service: OmpConfigService(
                runner: OmpConfigProcessRunner(executableURL: executableURL)))
        },
        makeProviderModel: { executableURL in
            ProviderManagementViewModel(
                providerService: ProviderManagementService(executableURL: executableURL),
                usageService: OmpUsageService(
                    runner: OmpUsageProcessRunner(executableURL: executableURL)),
                openURL: { url in NSWorkspace.shared.open(url) })
        })
}
```

Update every test dependency builder to inject a temporary `RecentProjectStore`, a nonspawning `SessionProcessManager` factory, a passing fake settings runner, and the existing provider fixture. Mark builders that construct the main-actor store `@MainActor`; do not add unchecked sendability to `UserDefaults`.

- [ ] **Step 3: Add deterministic startup fixtures**

`StartupTestFixtures.swift` should provide:

```swift
import Foundation
import OmpKit
import Testing
@testable import TenXApp

actor CountingOmpLocator: OmpLocating {
    private let installation: OmpInstallation?
    private(set) var count = 0

    init(installation: OmpInstallation?) {
        self.installation = installation
    }

    func locate(preferredURL: URL?) async -> OmpInstallation? {
        count += 1
        return installation
    }
}

actor StartupConfigRunner: OmpConfigRunning {
    private let startedGate: LoadGate?
    private let isFailing: Bool
    private var isBlocked: Bool

    init(
        startedGate: LoadGate? = nil,
        isFailing: Bool = false,
        isBlocked: Bool = false
    ) {
        self.startedGate = startedGate
        self.isFailing = isFailing
        self.isBlocked = isBlocked
    }

    func run(arguments: [String]) async throws -> Data {
        await startedGate?.started()
        if isBlocked {
            try await ContinuousClock().sleep(for: .seconds(60))
        }
        if isFailing { throw StartupFixtureError.config }
        if arguments == ["config", "path"] {
            return Data("/tmp/omp/config.json\n".utf8)
        }
        return Data(#"{"autoResume":{"value":false,"type":"boolean","description":"Automatically resume"}}"#.utf8)
    }

    func setBlocked(_ value: Bool) {
        isBlocked = value
    }
}

enum StartupFixtureError: Error, Sendable {
    case config
}

extension StartupTiming {
    static func controlledTimeout(_ gate: LoadGate) -> StartupTiming {
        StartupTiming(
            minimumVisibility: .zero,
            timeout: .seconds(10),
            sleep: { duration in
                guard duration == .seconds(10) else { return }
                await gate.started()
                await gate.waitForRelease()
            })
    }
}

@MainActor
func waitForModelState(
    _ predicate: @escaping @MainActor () async -> Bool
) async {
    for _ in 0..<200 {
        if await predicate() { return }
        try? await ContinuousClock().sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for startup fixture state")
}
```

Reuse the existing module-wide `LoadGate` from `ProviderTestFixtures.swift`; do not declare a duplicate. Also provide a UUID-scoped temporary root/defaults suite, helpers that write valid session JSONL metadata for a supplied cwd/modified date, and `makeStartupDependencies(...)`. Use `OmpInstallation(executableURL: URL(filePath: "/usr/bin/true"), version: "test")` for locator results; the injected process-manager factory supplies `RpcClient` instances backed by `fake_server.py`, so no wrapper or developer OMP state is needed. The dependency helper accepts a locator, library, defaults, timing, settings runner, provider model, and process-manager factory.

- [ ] **Step 4: Write failing idempotence, floor, and route tests**

```swift
@MainActor
@Test func concurrentBootstrapCallsShareOneAttemptAndRespectTheFloor() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let locator = CountingOmpLocator(installation: fixture.installation)
    let minimumGate = LoadGate()
    let timing = StartupTiming(
        minimumVisibility: .milliseconds(350),
        timeout: .seconds(10),
        sleep: { duration in
            if duration == .milliseconds(350) {
                await minimumGate.started()
                await minimumGate.waitForRelease()
            } else {
                try await ContinuousClock().sleep(for: .seconds(60))
            }
        })
    let model = fixture.model(locator: locator, timing: timing)

    async let first: Void = model.bootstrap()
    async let second: Void = model.bootstrap()
    await minimumGate.waitForStart()

    #expect(await locator.count == 1)
    #expect(model.startupState.handoffGeneration == 0)
    await minimumGate.release()
    await first
    await second
    #expect(model.startupState.handoffGeneration == 1)
    await model.shutdown()
}

@MainActor
@Test func missingOmpHandsOffToSetupWithoutWaitingForTheWatchdog() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let timeoutGate = LoadGate()
    let timing = StartupTiming(
        minimumVisibility: .zero,
        timeout: .seconds(10),
        sleep: { duration in
            if duration == .seconds(10) {
                await timeoutGate.started()
                try await ContinuousClock().sleep(for: .seconds(60))
            }
        })
    let model = fixture.model(
        locator: CountingOmpLocator(installation: nil),
        timing: timing)

    await model.bootstrap()

    #expect(model.route == .setup)
    #expect(model.startupState.handoffGeneration == 1)
    #expect(model.startupState.phase == .handoff)
    await model.shutdown()
}
```

- [ ] **Step 5: Write failing preload, watchdog, retry, Continue, and watcher tests**

```swift
@MainActor
@Test func bootstrapWarmsTwoRecentProjectsBeforeHandoff() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let older = try fixture.project("Older")
    let newer = try fixture.project("Newer")
    try fixture.writeSession(cwd: older, modified: Date(timeIntervalSince1970: 10))
    try fixture.writeSession(cwd: newer, modified: Date(timeIntervalSince1970: 20))
    let manager = fixture.processManager()
    let model = fixture.model(processManager: manager)

    await model.bootstrap()

    #expect(model.startupState.phase == .handoff)
    #expect(await manager.isWarm(projectDirectory: newer.path))
    #expect(await manager.isWarm(projectDirectory: older.path))
    #expect(model.selectedProjectURL == newer.resolvingSymlinksInPath())
    #expect(model.sessions.count == 2)
    await model.shutdown()
}

@MainActor
@Test func watchdogStopsUnfinishedRowsAndRetryKeepsReadyRows() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let settingsGate = LoadGate()
    let timeoutGate = LoadGate()
    let settingsRunner = StartupConfigRunner(
        startedGate: settingsGate,
        isBlocked: true)
    let model = fixture.model(
        timing: .controlledTimeout(timeoutGate),
        settingsRunner: settingsRunner)
    let bootstrap = Task { await model.bootstrap() }
    await settingsGate.waitForStart()
    await waitForModelState {
        model.startupState.status(of: .runtime) == .ready
    }
    await timeoutGate.release()
    await bootstrap.value

    #expect(model.startupState.phase == .recovery)
    #expect(model.startupState.status(of: .runtime) == .ready)
    #expect(model.startupState.status(of: .settings) == .stopped)
    await settingsRunner.setBlocked(false)
    await model.bootstrap()
    #expect(model.startupState.phase == .recovery)
    await model.retryStartup()
    #expect(model.startupState.phase == .handoff)
    #expect(model.startupState.status(of: .runtime) == .ready)
    await model.shutdown()
}

@MainActor
@Test func continueKeepsSuccessfulWarmClientAndStartsWorkspaceFallbackLoads() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let first = try fixture.project("First")
    let second = try fixture.project("Second")
    let manager = fixture.mixedWarmManager(
        readyProject: first,
        stalledProject: second)
    let timeoutGate = LoadGate()
    let model = fixture.model(
        processManager: manager,
        timing: .controlledTimeout(timeoutGate))
    model.chooseProject(first)
    try fixture.writeSession(cwd: second, modified: .now)

    let bootstrap = Task { await model.bootstrap() }
    await waitForModelState { await manager.isWarm(projectDirectory: first.path) }
    await waitForModelState { fixture.mixedWarmConfigurationCount == 2 }
    let stalledClient = try #require(fixture.mixedWarmClient(for: second))
    await timeoutGate.release()
    await bootstrap.value
    #expect(model.startupState.phase == .recovery)
    await model.continueToWorkspace()

    #expect(model.startupState.phase == .handoff)
    #expect(await manager.isWarm(projectDirectory: first.path))
    #expect(await !manager.isWarm(projectDirectory: second.path))
    #expect(await stalledClient.exitCode != nil)
    await model.shutdown()
}

@MainActor
@Test func memoryPressureBeforeHandoffEvictsWarmClientsAndMakesTheStageRetryable() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let project = try fixture.project("Pressure")
    let minimumGate = LoadGate()
    let timing = StartupTiming(
        minimumVisibility: .milliseconds(350),
        timeout: .seconds(10),
        sleep: { duration in
            if duration == .milliseconds(350) { await minimumGate.started() }
            try await ContinuousClock().sleep(for: .seconds(60))
        })
    let manager = fixture.processManager()
    let model = fixture.model(processManager: manager, timing: timing)
    model.chooseProject(project)
    let bootstrap = Task { await model.bootstrap() }
    await waitForModelState { await manager.isWarm(projectDirectory: project.path) }

    await model.handleMemoryPressure()
    await bootstrap.value

    #expect(model.startupState.phase == .recovery)
    #expect(model.startupState.status(of: .recentProjects) == .stopped)
    #expect(await !manager.isWarm(projectDirectory: project.path))
    await model.shutdown()
}

@MainActor
@Test func warmCrashBeforeHandoffPreservesAnotherReadyWarmClient() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let stable = try fixture.project("Stable")
    let crashing = try fixture.project("Crashing")
    let manager = fixture.processManager(
        modesByProject: [crashing.path: "crash-after-negotiation"])
    _ = try await manager.warm(projectDirectory: stable.path)
    let model = fixture.model(processManager: manager)
    model.chooseProject(stable)
    try fixture.writeSession(cwd: crashing, modified: .now)

    await model.bootstrap()

    #expect(model.startupState.phase == .recovery)
    #expect(model.startupState.status(of: .recentProjects) == .stopped)
    #expect(await manager.isWarm(projectDirectory: stable.path))
    await model.shutdown()
}

@MainActor
@Test func warmExitAfterHandoffDoesNotReplayStartupRecovery() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let project = try fixture.project("PostHandoff")
    let trigger = fixture.file("post-handoff-crash.trigger")
    let manager = fixture.triggeredCrashManager(
        project: project,
        trigger: trigger)
    let model = fixture.model(processManager: manager)
    model.chooseProject(project)
    await model.bootstrap()
    #expect(model.startupState.phase == .handoff)

    try Data().write(to: trigger)
    await waitForModelState { await !manager.isWarm(projectDirectory: project.path) }
    for _ in 0..<20 { await Task.yield() }

    #expect(model.startupState.phase == .handoff)
    #expect(model.startupState.handoffGeneration == 1)
    await model.shutdown()
}

@MainActor
@Test func sessionWatcherRefreshesMetadataAfterHandoff() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let model = fixture.model()
    await model.bootstrap()
    #expect(model.sessions.isEmpty)

    try fixture.writeSession(cwd: try fixture.project("Watched"), modified: .now)
    await waitForModelState { model.sessions.count == 1 }

    #expect(model.sessions.first?.cwd.hasSuffix("Watched") == true)
    await model.shutdown()
}
```

`StartupTiming.controlledTimeout(_:)` is a test-only fixture value: its minimum-visibility sleep returns immediately, while its timeout sleep marks the supplied `LoadGate` as started and waits for that gate to be released. `mixedWarmManager` selects fake-server mode by canonical `configuration.cwd`, exposes its locked capture count as `mixedWarmConfigurationCount`, stores clients by canonical cwd for `mixedWarmClient(for:)`, and uses a cancellable never-ready child for the stalled project. The general `processManager(modesByProject:)` overload uses `basic` for every canonical project absent from the map. `triggeredCrashManager(project:trigger:)` passes the trigger path after `crash-after-trigger` only for its canonical target project. `waitForModelState` accepts an async predicate, polls at 10 ms for at most two seconds, then records a Swift Testing issue.

- [ ] **Step 6: Prove the AppModel tests are red**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:TenXAppTests/AppModelStartupTests \
  -only-testing:TenXAppTests/settingsLoadReportsWhetherCatalogAndPathAreReady test
```

Expected: compile failures for the new dependency fields, startup state property, lifecycle methods, and settings Boolean result.

- [ ] **Step 7: Add idempotent operation ownership to AppModel**

Add focused private state rather than a second coordinator:

```swift
private struct StartupOperation {
    let id: UUID
    let task: Task<Void, Never>
}

private(set) var startupState = StartupState()
@ObservationIgnored private var startupOperation: StartupOperation?
@ObservationIgnored private var sessionChangeTask: Task<Void, Never>?
@ObservationIgnored private var warmExitTask: Task<Void, Never>?
@ObservationIgnored private var providerUsageTask: Task<Void, Never>?
@ObservationIgnored private var fallbackTasks: [Task<Void, Never>] = []
@ObservationIgnored private var memoryPressureSource: DispatchSourceMemoryPressure?
@ObservationIgnored private var hasStartedWarmRetention = false
```

`bootstrap()` joins one operation and never reruns after handoff:

```swift
func bootstrap() async {
    if let operation = startupOperation {
        await operation.task.value
        return
    }
    guard startupState.attemptID == nil else { return }
    let id = UUID()
    startupState.beginAttempt(id: id)
    let task = Task { [weak self] in
        guard let self else { return }
        await self.runStartupAttempt(id: id, stages: Set(StartupStageID.allCases))
    }
    startupOperation = StartupOperation(id: id, task: task)
    await task.value
    if startupOperation?.id == id { startupOperation = nil }
}

func retryStartup() async {
    guard startupState.phase == .recovery else { return }
    if let operation = startupOperation {
        await operation.task.value
        return
    }
    let id = UUID()
    let stages = startupState.beginRetry(id: id)
    let task = Task { [weak self] in
        guard let self else { return }
        await self.runStartupAttempt(id: id, stages: stages)
    }
    startupOperation = StartupOperation(id: id, task: task)
    await task.value
    if startupOperation?.id == id { startupOperation = nil }
}
```

`chooseProject(_:)` calls `dependencies.recentProjectStore.recordSelection(_:)` after accepting the standardized URL.

- [ ] **Step 8: Implement the watchdog and staged preparation**

Use a generic race whose timeout child throws after the injected sleep:

```swift
private enum StartupAttemptError: Error {
    case timeout
    case settingsUnavailable
}

private func withWatchdog<Value: Sendable>(
    attemptID: UUID,
    _ operation: @escaping @MainActor @Sendable () async throws -> Value
) async throws -> Value {
    let timing = dependencies.startupTiming
    return try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await timing.sleep(timing.timeout)
            throw StartupAttemptError.timeout
        }
        do {
            guard let first = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return first
        } catch {
            group.cancelAll()
            await cancelUnfinishedStartupWork(attemptID: attemptID)
            throw error
        }
    }
}

private func cancelUnfinishedStartupWork(attemptID: UUID) async {
    _ = await processManager?.cancelWarmings()
    guard startupState.attemptID == attemptID,
          startupState.status(of: .runtime) != .ready
    else { return }
    let provider = providerModel
    providerModel = nil
    let usage = providerUsageTask
    providerUsageTask = nil
    usage?.cancel()
    await provider?.shutdown()
    await usage?.value
}
```

`runStartupAttempt(id:stages:)` starts a minimum-visibility task and races the complete preparation, including OMP lookup, against the watchdog. It performs these exact operations:

1. If `.runtime` is selected, mark it loading and locate OMP. Cancel and await any prior `providerUsageTask`. When the executable matches the current installation, retain the existing process manager, settings model, and successful warm handles but create a fresh provider model if the prior discovery was canceled. When the executable changes, await the old provider shutdown and process-manager `closeAll()` before constructing all three replacements. Start warm-exit watching, launch provider usage in an owned nonblocking task, and await provider discovery. Mark runtime ready even when discovery reports its existing visible failure, because provider setup is then the determined route.
2. If OMP is missing, set `.setup`, cancel irrelevant work, await only the 350 ms floor, request handoff, and return.
3. Mark selected sessions/settings rows loading. Load active and archived sessions concurrently, assign both arrays, start exactly one `SessionLibrary.changes` consumer, and mark sessions ready. Await `SettingsViewModel.load()` and throw `settingsUnavailable` when it returns false.
4. After current active sessions are available, rank projects, set `selectedProjectURL` to the first result only when it is nil, mark recent projects loading, and use a throwing task group to await `processManager.warm(projectDirectory:)` for every result. Zero results mark the row ready immediately.
5. After all selected units are ready, await the minimum floor and request one handoff. Do not start the secondary grace timer until the scene has actually requested the workspace window.
6. On terminal failure or timeout, cancel and await child work, keep ready rows and registered warm clients, then call `enterRecovery(attemptID:)`.
7. On cancellation caused by Continue, replacement, or shutdown, do not mutate the state from that stale attempt.

Every state mutation passes the attempt ID. After every suspension and before marking a row ready, changing route, or requesting handoff, call `try Task.checkCancellation()`. The attempt catch checks `Task.isCancelled` before translating any error into recovery. Structured child tasks must finish cancellation cleanup before recovery or handoff returns.

- [ ] **Step 9: Implement Retry, Continue, warm-exit, pressure, and shutdown paths**

Use these public behaviors:

```swift
func continueToWorkspace() async {
    guard startupState.phase == .recovery, let attemptID = startupState.attemptID else { return }
    let operation = startupOperation
    startupOperation = nil
    operation?.task.cancel()
    await cancelUnfinishedStartupWork(attemptID: attemptID)
    await operation?.task.value
    startupState.requestHandoff(attemptID: attemptID)
    startFallbackLoadsForStoppedStages()
}

func workspaceDidOpen() async {
    guard !hasStartedWarmRetention else { return }
    hasStartedWarmRetention = true
    await processManager?.beginWarmRetention(
        primaryProjectDirectory: selectedProjectURL?.path)
}

func handleMemoryPressure() async {
    guard let processManager else { return }
    let evicted = await processManager.evictWarmClients()
    let canceled = await processManager.cancelWarmings()
    guard !evicted.isEmpty || !canceled.isEmpty,
          startupState.phase == .preparing,
          let attemptID = startupState.attemptID
    else { return }
    let operation = startupOperation
    startupOperation = nil
    operation?.task.cancel()
    await operation?.task.value
    startupState.markStopped(.recentProjects, attemptID: attemptID)
    startupState.enterRecovery(attemptID: attemptID)
}

func shutdown() async {
    memoryPressureSource?.cancel()
    memoryPressureSource = nil
    let startup = startupOperation
    startupOperation = nil
    startup?.task.cancel()
    let sessionChanges = sessionChangeTask
    sessionChangeTask = nil
    sessionChanges?.cancel()
    let warmExits = warmExitTask
    warmExitTask = nil
    warmExits?.cancel()
    let usage = providerUsageTask
    providerUsageTask = nil
    usage?.cancel()
    let fallbacks = fallbackTasks
    fallbackTasks.removeAll()
    fallbacks.forEach { $0.cancel() }
    await providerModel?.shutdown()
    await processManager?.closeAll()
    await startup?.task.value
    await sessionChanges?.value
    await warmExits?.value
    await usage?.value
    for fallback in fallbacks { await fallback.value }
}
```

`startFallbackLoadsForStoppedStages()` stores at most three nonblocking tasks in `fallbackTasks` for missing session, settings, and provider data after Continue; it does not recreate failed warm clients. Store provider usage refresh in `providerUsageTask`. `workspaceDidOpen()` is idempotent and starts retention only after `openWindow` has been requested. The warm-exit consumer cancels the startup operation, calls `cancelWarmings()` to reap other unfinished clients, awaits the operation, calls `markStopped(.recentProjects, attemptID:)`, then enters recovery; it ignores post-handoff pool loss. A main-queue `DispatchSource.makeMemoryPressureSource(eventMask:[.warning,.critical])` calls `handleMemoryPressure()`; tests invoke the public method directly.

When `useOmp(at:)` replaces an installation after setup, cancel and await `providerUsageTask`, then await old provider shutdown and old `processManager.closeAll()` before assigning new owners. It does not replay the splash.

- [ ] **Step 10: Run focused startup and regression suites**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:TenXAppTests/AppModelStartupTests \
  -only-testing:TenXAppTests/AppModelNavigationTests \
  -only-testing:TenXAppTests/OmpConfigServiceTests test
swift test --package-path OmpKit
```

Expected: startup timing/retry/Continue/watcher tests PASS; current navigation/provider/settings behavior remains green; OmpKit remains green.

- [ ] **Step 11: Commit startup orchestration**

```bash
git add App/Application/AppDependencies.swift App/Application/AppModel.swift \
  App/Settings/SettingsViewModel.swift \
  Tests/TenXAppTests/OmpConfigServiceTests.swift \
  Tests/TenXAppTests/AppModelNavigationTests.swift \
  Tests/TenXAppTests/StartupTestFixtures.swift \
  Tests/TenXAppTests/AppModelStartupTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat: coordinate startup preload"
```

---

### Task 7: Build the Compact Splash, Ledger, and Animated Signal

**Files:**
- Create: `App/Startup/StartupSignalView.swift`
- Create: `App/Startup/StartupLedgerView.swift`
- Create: `App/Startup/SplashView.swift`
- Create: `Tests/TenXAppTests/StartupSignalTests.swift`
- Create: `Tests/TenXAppTests/StartupSplashSnapshotTests.swift`
- Create: `Tests/TenXAppTests/ReferenceImages/startup-splash-loading.png`
- Create: `Tests/TenXAppTests/ReferenceImages/startup-splash-recovery.png`
- Modify: `10x.xcodeproj/project.pbxproj` via generator

**Interfaces:**
- Consumes: Task 5's `StartupState.rows`, phase, footer copy, signal state, and handoff-neutral actions.
- Produces: `SplashView(state:buildVersion:onRetry:onContinue:)`, `StartupLedgerView(rows:)`, and `StartupSignalView(isAnimating:)`.

- [ ] **Step 1: Write failing analytic geometry tests**

Protect the approved sine shape from regressing into a cosine join, flat line, or mountain profile:

```swift
import CoreGraphics
import Testing
@testable import TenXApp

@Test func startupSignalUsesOneCenteredSineWaveWithPinnedEndpoints() {
    let geometry = StartupSignalGeometry(width: 640, midY: 24, amplitude: 16)

    #expect(geometry.waveStart.x == 480)
    #expect(geometry.wavePoint(progress: 0).y == 24)
    #expect(abs(geometry.wavePoint(progress: 0.25).y - 40) < 0.001)
    #expect(abs(geometry.wavePoint(progress: 0.5).y - 24) < 0.001)
    #expect(abs(geometry.wavePoint(progress: 0.75).y - 8) < 0.001)
    #expect(abs(geometry.wavePoint(progress: 1).y - 24) < 0.001)
}

@Test func signalMotionBreathesAroundSixteenPointsAndFreezesForReducedMotion() {
    #expect(StartupSignalMotion.amplitude(elapsed: 0, reduceMotion: false) == 16)
    #expect(StartupSignalMotion.amplitude(elapsed: 0.7, reduceMotion: false) <= 18)
    #expect(StartupSignalMotion.amplitude(elapsed: 0.7, reduceMotion: false) >= 14)
    #expect(StartupSignalMotion.amplitude(elapsed: 100, reduceMotion: true) == 16)
    #expect(StartupSignalMotion.progress(elapsed: 100, reduceMotion: true) == 0)
}
```

- [ ] **Step 2: Write failing loading and recovery snapshots**

Build deterministic states and force Reduce Motion so reference images never depend on wall-clock phase:

```swift
import SwiftUI
import Testing
@testable import TenXApp

@MainActor
@Test func startupSplashLoadingSnapshot() throws {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markLoading(.runtime, attemptID: attempt)
    state.markReady(.runtime, attemptID: attempt)
    state.markLoading(.sessions, attemptID: attempt)

    try assertSnapshot(
        SplashView(
            state: state,
            buildVersion: "0.1.0",
            onRetry: {},
            onContinue: {})
            .environment(\.accessibilityReduceMotion, true),
        name: "startup-splash-loading",
        size: CGSize(width: 640, height: 400))
}

@MainActor
@Test func startupSplashRecoverySnapshot() throws {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markReady(.runtime, attemptID: attempt)
    state.markReady(.sessions, attemptID: attempt)
    state.markLoading(.recentProjects, attemptID: attempt)
    state.enterRecovery(attemptID: attempt)

    try assertSnapshot(
        SplashView(
            state: state,
            buildVersion: "0.1.0",
            onRetry: {},
            onContinue: {})
            .environment(\.accessibilityReduceMotion, true),
        name: "startup-splash-recovery",
        size: CGSize(width: 640, height: 400))
}
```

- [ ] **Step 3: Generate the project and prove geometry/UI are red**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:TenXAppTests/StartupSignalTests \
  -only-testing:TenXAppTests/StartupSplashSnapshotTests test
```

Expected: compile failure because the signal and splash views do not exist.

- [ ] **Step 4: Implement one shared signal geometry**

Keep the black base and cyan overlay on the exact same `Shape`:

```swift
struct StartupSignalGeometry {
    static let waveWidth: CGFloat = 160
    let width: CGFloat
    let midY: CGFloat
    let amplitude: CGFloat

    var waveStart: CGPoint {
        CGPoint(x: max(0, width - Self.waveWidth), y: midY)
    }

    func wavePoint(progress: CGFloat) -> CGPoint {
        CGPoint(
            x: waveStart.x + Self.waveWidth * progress,
            y: midY + CGFloat(sin(Double(progress) * 2 * .pi)) * amplitude)
    }
}

enum StartupSignalMotion {
    static func amplitude(elapsed: TimeInterval, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 16 }
        return CGFloat(16 + 2 * sin(elapsed * 2 * .pi / 2.8))
    }

    static func progress(elapsed: TimeInterval, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return CGFloat((elapsed / 1.8).truncatingRemainder(dividingBy: 1))
    }
}

private struct StartupSignalShape: Shape {
    let amplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        let geometry = StartupSignalGeometry(
            width: rect.width,
            midY: rect.midY,
            amplitude: amplitude)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: geometry.waveStart)
        for index in 1...64 {
            path.addLine(to: geometry.wavePoint(progress: CGFloat(index) / 64))
        }
        return path
    }
}
```

`StartupSignalView` uses `TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isAnimating || reduceMotion))`. Keep `startDate` and `frozenElapsed` as local `@State`: update `frozenElapsed` from each live timeline tick, reuse it while recovery pauses, and reset it to zero when Reduce Motion is enabled. Stroke the complete shape in near-black, then overlay a cyan 0.14-length trimmed segment. When the segment wraps past 0 or 1, render two complementary trims so it never disappears at the seam. Use round line caps and joins.

- [ ] **Step 5: Implement the stable ledger**

`StartupLedgerView` is a fixed-width four-row stack. Each row always occupies its position and exposes one combined accessibility label:

```swift
struct StartupLedgerView: View {
    let rows: [StartupStageRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: 16) {
                    Text(row.title)
                    Spacer(minLength: 12)
                    Text(row.status.rawValue)
                        .foregroundStyle(statusColor(row.status))
                }
                .font(TenXTypography.mono(size: 10))
                .frame(height: 25)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(TenXPalette.color(TenXPalette.separatorHex))
                        .frame(height: 1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
            }
        }
        .frame(width: 286)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Startup preparation")
    }
}
```

Queued and Ready use muted/near-black text, Loading uses cyan, and Stopped uses signal red. Do not display internal errors.

- [ ] **Step 6: Implement the exact 640 × 400 composition**

`SplashView` has no startup tasks, timers, filesystem access, route decisions, or process handles. Use this fixed region structure:

```swift
struct SplashView: View {
    let state: StartupState
    let buildVersion: String
    let onRetry: () -> Void
    let onContinue: () -> Void

    @Environment(\.accessibilityAnnouncer) private var announcer
    @FocusState private var isRetryFocused: Bool
    @AccessibilityFocusState private var isRetryAccessibilityFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(StartupState.buildLabel(version: buildVersion))
                        .font(TenXTypography.mono(size: 10, weight: .medium))
                        .tracking(1.3)
                    Text("Preparing your workspace")
                        .font(TenXTypography.title(size: 27))
                    Spacer()
                }
                StartupLedgerView(rows: state.rows)
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 10)
            .frame(height: 248)

            StartupSignalView(isAnimating: state.isSignalAnimating)
                .frame(height: 48)

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
                .frame(height: 104)
        }
        .frame(width: 640, height: 400)
        .background(TenXPalette.color(TenXPalette.canvasHex))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TenXPalette.color(TenXPalette.separatorHex), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preparing your workspace")
    }
}
```

The footer uses a leading status stack and a trailing `BrandWordmark`. Use cyan for the active footer title and signal red for `Startup needs attention`; keep the detail muted. In recovery, place `Retry` and `Continue to workspace` below the two status lines without moving the wordmark. Style Retry as the primary bordered action and Continue with `GhostActionStyle`. On entry to recovery, yield once, focus Retry for keyboard and VoiceOver, and announce `Startup needs attention. Retry the stopped work or continue with what is ready.` On ordinary row changes, announce the changed row's combined accessibility label without moving focus.

- [ ] **Step 7: Record and inspect the two reference images**

```bash
RECORD_SNAPSHOTS=1 xcodebuild -project 10x.xcodeproj -scheme 10x \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:TenXAppTests/StartupSplashSnapshotTests test
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:TenXAppTests/StartupSignalTests \
  -only-testing:TenXAppTests/StartupSplashSnapshotTests test
```

Inspect both PNGs directly. Confirm exact 640 × 400 bounds, no `10x Desktop` label, one baseline-pinned sine cycle, equal excursion above/below the rule, all four rows, cyan loading state, red stopped state, complete recovery copy, unclipped buttons, and lower-right wordmark. Rerecord only after correcting a visible mismatch; never approve a reference image by code inspection alone.

- [ ] **Step 8: Run accessibility/copy regressions**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:TenXAppTests/StartupStateTests \
  -only-testing:TenXAppTests/StartupSignalTests \
  -only-testing:TenXAppTests/StartupSplashSnapshotTests \
  -only-testing:TenXAppTests/AccessibilityAnnouncerTests test
```

Expected: all selected tests PASS. Search production startup files for banned visible copy:

```bash
rg -n '10x Desktop|Runtime [12]|Continue without preloading|—|AI-powered|Thinking|Analyzing' App/Startup
```

Expected: no matches.

- [ ] **Step 9: Commit the splash UI and references**

```bash
git add App/Startup/StartupSignalView.swift App/Startup/StartupLedgerView.swift \
  App/Startup/SplashView.swift Tests/TenXAppTests/StartupSignalTests.swift \
  Tests/TenXAppTests/StartupSplashSnapshotTests.swift \
  Tests/TenXAppTests/ReferenceImages/startup-splash-loading.png \
  Tests/TenXAppTests/ReferenceImages/startup-splash-recovery.png \
  10x.xcodeproj/project.pbxproj
git commit -m "feat: add startup splash"
```

---

### Task 8: Gate Workspace Launch and Reap Processes on Quit

**Files:**
- Create: `App/Startup/StartupSceneView.swift`
- Create: `App/Application/AppTerminationDelegate.swift`
- Modify: `App/TenXApp.swift`
- Modify: `Tests/TenXAppTests/AppModelStartupTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` via generator

**Interfaces:**
- Consumes: Task 6's one-shot handoff generation and shutdown method; Task 7's pure splash.
- Produces: startup window ID `startup`, workspace window ID `workspace`, programmatic open-then-dismiss handoff, launch suppression, and async termination deferral.

- [ ] **Step 1: Add a failing shutdown ownership test**

```swift
@Test func startupAndWorkspaceUseDistinctStableSceneIDs() {
    #expect(AppWindowID.startup == "startup")
    #expect(AppWindowID.workspace == "workspace")
    #expect(AppWindowID.startup != AppWindowID.workspace)
}

@MainActor
@Test func shutdownCancelsBootstrapAndReapsWarmAndActiveChildren() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let manager = fixture.processManager()
    let model = fixture.model(processManager: manager)
    await model.bootstrap()
    let warm = try await manager.warm(projectDirectory: try fixture.project("Warm").path)
    let active = try await manager.open(
        sessionPath: "/tmp/active.jsonl",
        cwd: try fixture.project("Active").path)

    await model.shutdown()

    #expect(await warm.client.exitCode != nil)
    #expect(await active.client.exitCode != nil)
    #expect(await manager.handle(for: active.sessionPath) == nil)
}
```

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:TenXAppTests/shutdownCancelsBootstrapAndReapsWarmAndActiveChildren test
```

Expected: compile failure because `AppWindowID` does not exist yet; after adding the scene bridge, the lifecycle assertion must also prove every owned child exits.

- [ ] **Step 2: Implement the pure scene-action bridge**

```swift
import SwiftUI

enum AppWindowID {
    static let startup = "startup"
    static let workspace = "workspace"
}

struct StartupSceneView: View {
    let model: AppModel

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var handledHandoffGeneration = 0

    var body: some View {
        SplashView(
            state: model.startupState,
            buildVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            onRetry: { Task { await model.retryStartup() } },
            onContinue: { Task { await model.continueToWorkspace() } })
        .task { await model.bootstrap() }
        .onChange(of: model.startupState.handoffGeneration, initial: true) {
            _, generation in
            guard generation > handledHandoffGeneration else { return }
            handledHandoffGeneration = generation
            Task { @MainActor in
                openWindow(id: AppWindowID.workspace)
                await model.workspaceDidOpen()
                dismissWindow(id: AppWindowID.startup)
            }
        }
    }
}
```

The `Bundle` conditional cast stays at the Foundation boundary implied by `object(forInfoDictionaryKey:)`. The UI never substitutes a hard-coded marketing version, so the rendered build label always derives from the packaged app metadata.

- [ ] **Step 3: Add an async termination bridge**

```swift
import AppKit

@MainActor
final class AppTerminationDelegate: NSObject, NSApplicationDelegate {
    var shutdown: (@MainActor @Sendable () async -> Void)?
    private var isFinishingTermination = false
    private var isShutdownComplete = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isShutdownComplete else { return .terminateNow }
        guard !isFinishingTermination else { return .terminateLater }
        isFinishingTermination = true
        Task {
            await shutdown?()
            isShutdownComplete = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
```

The delegate owns no model state and performs no process operation itself. It only lets `AppModel.shutdown()` finish before AppKit exits.

- [ ] **Step 4: Declare the two scene-native windows**

Replace the single launch-visible `WindowGroup` with:

```swift
@main
struct TenXApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(AppTerminationDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Preparing your workspace", id: AppWindowID.startup) {
            StartupSceneView(model: model)
                .onAppear {
                    appDelegate.shutdown = { await model.shutdown() }
                }
        }
        .defaultSize(width: 640, height: 400)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        .windowStyle(.plain)
        .windowBackgroundDragBehavior(.enabled)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(
            model.startupState.phase == .handoff ? .suppressed : .presented)

        WindowGroup("10x", id: AppWindowID.workspace) {
            AppShellView(model: model)
                .frame(minWidth: 760, minHeight: 560)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await model.refreshProvidersIfNeeded() }
                }
        }
        .defaultLaunchBehavior(
            model.startupState.phase == .handoff ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}
```

Do not attach `bootstrap()` to the workspace scene. Open the workspace before dismissing startup, as `StartupSceneView` does. The complementary dynamic launch behaviors make the startup scene presented only before first handoff and make the workspace the direct Dock-reopen target afterward, so the splash cannot replay within the process.

- [ ] **Step 5: Generate, compile, and run lifecycle regressions**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:TenXAppTests/AppModelStartupTests \
  -only-testing:TenXAppTests/AppModelNavigationTests \
  -only-testing:TenXAppTests/StartupSplashSnapshotTests test
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' build
```

Expected: selected tests PASS and the Release build succeeds with macOS 15 availability checks satisfied.

- [ ] **Step 6: Commit scene and lifecycle integration**

```bash
git add App/Startup/StartupSceneView.swift \
  App/Application/AppTerminationDelegate.swift App/TenXApp.swift \
  Tests/TenXAppTests/AppModelStartupTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat: gate workspace launch on startup"
```

---

### Task 9: Verify the Complete Release Experience

**Files:**
- Verify all branch changes against the design spec.
- Do not add production code in this task unless a failed acceptance check identifies a scoped defect.

**Interfaces:**
- Consumes: the completed startup flow from Tasks 1–8.
- Produces: test output, Release build, real-window screenshots, process evidence, and a clean branch ready for review.

- [ ] **Step 1: Regenerate and prove the generated project is current**

```bash
ruby scripts/generate_xcodeproj.rb
git diff --check
git status --short
```

Expected: generator creates no uncommitted project change; `git diff --check` exits 0. If the generator changes the project because a prior task forgot it, commit only that generated correction with the owning task's files before continuing.

- [ ] **Step 2: Run both complete test suites**

```bash
swift test --package-path OmpKit
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' test
```

Expected: OmpKit PASS with only its two opt-in integration skips; all macOS tests PASS, including both exact startup snapshots.

- [ ] **Step 3: Build a fresh Release product**

```bash
startup_derived_data=$(mktemp -d /tmp/tenx-startup-release.XXXXXX)
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$startup_derived_data" build
startup_app="$startup_derived_data/Build/Products/Release/10x.app"
test -d "$startup_app"
```

Expected: `** BUILD SUCCEEDED **` and the packaged app exists at the asserted path.

- [ ] **Step 4: Exercise loading and recovery in the real Release window**

Load `launching-local-builds` before launching. Set `startup_blocked_home=$(mktemp -d /tmp/tenx-startup-blocked.XXXXXX)`, then create two temporary project/session directories and a temporary executable `$startup_blocked_home/.bun/bin/omp` wrapper inside it with mode `0o755` and this exact content:

```bash
#!/bin/zsh
if [[ "$1" == "--version" ]]; then
  print -r -- "omp/18.0.4"
  exit 0
fi
exec /usr/bin/env python3 "$TENX_FAKE_SERVER" never-ready
```

Launch the packaged executable directly with `TENX_FAKE_SERVER="$PWD/OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py"`, `CFFIXED_USER_HOME="$startup_blocked_home"`, and a sanitized `PATH`; save its PID as `startup_blocked_pid`.

Within the first 10 seconds, confirm and capture:

- only one centered 640 × 400 startup window is visible,
- the workspace is absent,
- the cyan segment travels over the flat rule and sine section,
- the sine is centered, smooth, medium amplitude, and pinned to the rule at both joins,
- the ledger contains only the four approved generic stages,
- the label is `BUILD 0.1.0`, and
- the wordmark remains lower right.

After 10 seconds, capture the same window showing retained ready rows, red Stopped rows, frozen motion, `Retry`, and `Continue to workspace`. Click `Retry`; confirm only stopped rows return to Queued/Loading, ready rows remain ready, and no second window appears. After the second recovery, click `Continue to workspace`; confirm the workspace opens, the splash closes, and every unfinished wrapper child exits. Save both screenshots to an absolute path outside the repository and record their paths in the completion report.

- [ ] **Step 5: Exercise successful real-OMP reuse**

Set `startup_real_home=$(mktemp -d /tmp/tenx-startup-real.XXXXXX)`. Put a symlink to `/Users/tannerpham/.bun/bin/omp` at `$startup_real_home/.bun/bin/omp`, create two valid project directories, and write one minimal session JSONL file per cwd beneath `$startup_real_home/.omp/agent/sessions/manual-a/` and `manual-b/`. Launch the Release executable with that isolated `CFFIXED_USER_HOME`, save its PID as `startup_real_pid`, and record child PIDs, RSS, and cwd values with `ps` and `lsof` before choosing either project.

Verify:

1. two project-bound no-session clients finish negotiation before workspace handoff,
2. the workspace opens once and the splash disappears with no blank gap,
3. starting a new session in the primary project keeps that warm process PID,
4. opening the other recent project within five minutes keeps its second warm PID,
5. a second concurrent session in one project creates a different PID,
6. reopening a workspace window in the same app process does not replay the splash, and
7. quitting with a workspace open and cold-relaunching still presents only the splash until handoff, and
8. provider usage may still load after handoff without affecting readiness.

Record the measured handoff time, child count, and RSS. Compare the result to the design measurement of approximately 710 ms and 305.9 MB per local no-session OMP client without treating those development numbers as a pass/fail threshold.

- [ ] **Step 6: Verify missing OMP, Reduce Motion, eviction, and quit**

- Set `startup_missing_home=$(mktemp -d /tmp/tenx-startup-missing.XXXXXX)`, launch with no OMP and a sanitized `PATH`, and save the PID as `startup_missing_pid`; confirm the existing full-size `SetupView` replaces the splash after the 350 ms floor and never shows compact Locate OMP controls.
- Set `startup_motion_home=$(mktemp -d /tmp/tenx-startup-motion.XXXXXX)`, enable Reduce Motion only in that isolated preferences home, relaunch the blocked wrapper, and save the PID as `startup_motion_pid`; confirm the cyan segment and wave are static while ledger text continues to change.
- Use the automated `handleMemoryPressure()` test as the pressure simulation evidence; do not issue a system-wide memory-pressure command.
- Leave the secondary real warm client unused for five minutes and confirm only that PID exits; the primary remains.
- Quit during a fresh blocked warm attempt, then run `ps` for the recorded child PIDs and confirm none remains.

- [ ] **Step 7: Inspect the complete branch and report precisely**

```bash
git diff --check main...HEAD
git status --short
git log --oneline main..HEAD
git diff --stat main...HEAD
```

Expected: clean worktree, no whitespace errors, and only planned files. Review every visible string against `writing-ui`, every rendered state against `visual-ui`, and process/cancellation code against the orphan-prevention requirements. Do not merge.

- [ ] **Step 8: Clean up only the recorded verification processes and roots, then report**

Terminate any still-running app PID recorded by Steps 4–6 and wait for it. Confirm every recorded OMP child PID is absent with `ps -p`. Remove only the isolated roots created by this task after matching their exact prefixes:

```bash
for startup_pid in \
  "${startup_blocked_pid:-}" "${startup_real_pid:-}" \
  "${startup_missing_pid:-}" "${startup_motion_pid:-}"
do
  if [[ "$startup_pid" =~ ^[0-9]+$ ]] && kill -0 "$startup_pid" 2>/dev/null; then
    kill "$startup_pid"
    wait "$startup_pid" 2>/dev/null || true
  fi
done

for startup_temp in \
  "${startup_derived_data:-}" "${startup_blocked_home:-}" \
  "${startup_real_home:-}" "${startup_missing_home:-}" \
  "${startup_motion_home:-}"
do
  case "$startup_temp" in
    /tmp/tenx-startup-release.*|/tmp/tenx-startup-blocked.*|/tmp/tenx-startup-real.*|/tmp/tenx-startup-missing.*|/tmp/tenx-startup-motion.*)
      rm -rf -- "$startup_temp"
      ;;
    "") ;;
    *) echo "Refusing unexpected cleanup path: $startup_temp" >&2; exit 1 ;;
  esac
done

git status --short
```

Expected: recorded child PIDs remain absent, every task-owned temporary root is removed, and the branch is clean. Report in the required `Verified`, `Not verified`, and `For you to test` sections, including absolute screenshot paths. Do not merge.

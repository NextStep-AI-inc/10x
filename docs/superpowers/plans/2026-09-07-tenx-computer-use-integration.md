# 10x Computer Use Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the isolated Agent Desktop model in the 10x app with the shared-window ComputerKit daemon: per-session computer-use chrome (header item, rail badge, preview popover, on-screen overlay), a supervision-driven menu bar panel, a ⇧⌘C invocation command, and a rewritten settings section.

**Architecture:** The app imports the `ComputerKit` SwiftPM package (built by Plan 1, `docs/superpowers/plans/2026-09-07-computerkit.md`) and subscribes to the `tenx-computer` daemon's supervision socket. Per-session state comes from the session's own transcript stream (MCP tool calls carry `window_id`), correlated with daemon events by window id — no process-lineage tricks. The Agent Desktop provider stack, lease, and single-owner registry are deleted: the daemon is the cross-process arbiter. Spec: `docs/superpowers/specs/2026-09-07-computer-use-refinement-design.md`.

**Tech Stack:** SwiftUI, SwiftPM local packages (OmpKit + ComputerKit), generated xcodeproj (never hand-edit — change `scripts/generate_xcodeproj.rb` and re-run), XCTest.

**Working directory for all commands:** `/Users/tannerpham/CS Projects/.worktrees/10x-computer-use-design`

**Prerequisite:** Plan 1 executed — `ComputerKit/` exists with `swift test` green and `ComputerKit/.build/release/tenx-computer` built.

**Test command (used throughout):**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' 2>&1 | tail -30
```

If the scheme is missing, run `xcodebuild -list -project 10x.xcodeproj` and use the listed scheme. To run one test class, add `-only-testing:TenXAppTests/<ClassName>`.

**Naming collision warning:** both OmpKit and ComputerKit define `JSONValue`. In app files that import both, qualify: `ComputerKit.JSONValue`, `ComputerKit.SupervisionEvent`.

**Wire freeze (post-Plan-1 audit, commit 2968eb4):** the supervision protocol is final — camelCase keys; `sessionStarted{session,harness,label,pid}`; `stopped{reason,session}` (`session: null` = global); `permissions{screenRecording,accessibility}`; `screenshotTaken{...,width,height,scale}`; `action` x/y are `null` for type/key, window center for scroll. Absent optionals encode as explicit `null`, never omitted keys. `windowReleased.reason` ∈ `disconnect|stopped|shutoff|released|window_gone`. Do not change these from Plan 2 code — change ComputerKit instead and re-freeze.

---

### Task 1: Wire ComputerKit into the app target

**Files:**
- Modify: `scripts/generate_xcodeproj.rb:53-64` (the OmpKit package block)
- Modify: `10x.xcodeproj/project.pbxproj` (generated — never hand-edit)
- Test: `Tests/TenXAppTests/ComputerKitWiringTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import ComputerKit
import XCTest

final class ComputerKitWiringTests: XCTestCase {
    func test_computerKitIsLinked() {
        // SupervisionEvent is the type the app's supervision client decodes.
        let event = SupervisionEvent.stopped(reason: "wiring check", session: nil)
        XCTAssertEqual(event, .stopped(reason: "wiring check", session: nil))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/ComputerKitWiringTests 2>&1 | tail -5`
Expected: FAIL — `No such module 'ComputerKit'`.

- [ ] **Step 3: Add the package to the generator**

In `scripts/generate_xcodeproj.rb`, immediately after the OmpKit block (lines 53-64), add:

```ruby
computer_package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
computer_package.relative_path = "ComputerKit"
project.root_object.package_references << computer_package

computer_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
computer_product.package = computer_package
computer_product.product_name = "ComputerKit"
app.package_product_dependencies << computer_product

computer_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
computer_build_file.product_ref = computer_product
app.frameworks_build_phase.files << computer_build_file
```

- [ ] **Step 4: Regenerate the project and run the test**

Run: `ruby scripts/generate_xcodeproj.rb && xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/ComputerKitWiringTests 2>&1 | tail -5`
Expected: PASS. `git diff --stat 10x.xcodeproj/project.pbxproj` shows a small generated diff.

- [ ] **Step 5: Commit**

```bash
git add scripts/generate_xcodeproj.rb 10x.xcodeproj/project.pbxproj Tests/TenXAppTests/ComputerKitWiringTests.swift
git commit -m "feat(computer-use): link ComputerKit into the app target"
```

---

### Task 2: SupervisionClient — the app's daemon subscription

**Files:**
- Create: `App/ComputerUse/SupervisionClient.swift`
- Test: `Tests/TenXAppTests/SupervisionClientTests.swift`

One app-wide client owns the supervision socket and reduces events into observable snapshot state. All UI (menu bar, overlay, popover, badges) reads this snapshot.

- [ ] **Step 1: Write the failing test**

```swift
import ComputerKit
import XCTest
@testable import TenXApp

final class SupervisionClientTests: XCTestCase {
    func makeClient() -> SupervisionClient {
        SupervisionClient(socketPath: NSTemporaryDirectory() + "unused-\(UUID().uuidString).sock")
    }

    func test_sessionStarted_addsSessionGroupedByHarness() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.sessionStarted(session: 2, harness: "Cursor", label: nil, pid: nil))
        XCTAssertEqual(client.sessions[1]?.harness, "omp")
        XCTAssertEqual(client.sessions[2]?.harness, "Cursor")
    }

    func test_windowClaimed_attachesWindowToSession() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
        XCTAssertEqual(client.sessions[1]?.windows.first?.windowID, 10)
        XCTAssertEqual(client.sessions[1]?.windows.first?.app, "Safari")
    }

    func test_windowReleased_removesWindow() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
        client.apply(.windowReleased(session: 1, windowID: 10, reason: "released"))
        XCTAssertEqual(client.sessions[1]?.windows.count, 0)
    }

    func test_screenshotTaken_storesLatestFramePerWindow() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
        client.apply(.screenshotTaken(session: 1, windowID: 10, pngBase64: Data([1, 2]).base64EncodedString(), width: 100, height: 100, scale: 2))
        client.apply(.screenshotTaken(session: 1, windowID: 10, pngBase64: Data([3, 4]).base64EncodedString(), width: 100, height: 100, scale: 2))
        XCTAssertEqual(client.frames[10], Data([3, 4]))
    }

    func test_action_updatesLastAction() {
        let client = makeClient()
        client.apply(.action(session: 1, windowID: 10, kind: "click", x: 50, y: 60))
        XCTAssertEqual(client.lastAction?.windowID, 10)
        XCTAssertEqual(client.lastAction?.kind, "click")
    }

    func test_statusChanged_updatesSessionStatus() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.statusChanged(session: 1, status: "Running tests…"))
        XCTAssertEqual(client.sessions[1]?.status, "Running tests…")
    }

    func test_stopped_clearsEverything() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
        client.apply(.stopped(reason: "global shut-off", session: nil))
        XCTAssertTrue(client.sessions.isEmpty)
        XCTAssertTrue(client.frames.isEmpty)
    }

    func test_stoppedWithSession_removesOnlyThatSession() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.sessionStarted(session: 2, harness: "Cursor", label: nil, pid: nil))
        client.apply(.stopped(reason: "session 1 stopped", session: 1))
        XCTAssertNil(client.sessions[1])
        XCTAssertNotNil(client.sessions[2])
    }

    func test_permissions_storesLatest() {
        let client = makeClient()
        XCTAssertNil(client.permissions)
        client.apply(.permissions(screenRecording: true, accessibility: false))
        XCTAssertEqual(client.permissions?.screenRecording, true)
        XCTAssertEqual(client.permissions?.accessibility, false)
    }

    func test_sessionEnded_removesOnlyThatSession() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.sessionStarted(session: 2, harness: "Cursor", label: nil, pid: nil))
        client.apply(.sessionEnded(session: 1, harness: "omp"))
        XCTAssertNil(client.sessions[1])
        XCTAssertNotNil(client.sessions[2])
    }

    func test_hasAnyActivity_drivesMenuBarInsertion() {
        let client = makeClient()
        XCTAssertFalse(client.hasAnyActivity)
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
        XCTAssertTrue(client.hasAnyActivity)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/SupervisionClientTests 2>&1 | tail -5`
Expected: FAIL — `SupervisionClient` does not exist.

- [ ] **Step 3: Write minimal implementation**

`App/ComputerUse/SupervisionClient.swift`:

```swift
import ComputerKit
import Foundation

public struct ClaimedWindowState: Equatable, Identifiable, Sendable {
    public let windowID: Int
    public var app: String
    public var title: String
    public var bounds: String
    public var id: Int { windowID }
}

public struct ComputerSessionState: Equatable, Identifiable, Sendable {
    public let id: Int
    public var harness: String
    public var label: String?
    public var status: String?
    public var windows: [ClaimedWindowState] = []
}

/// App-wide view of the tenx-computer daemon. Owns the supervision socket;
/// UI reads the snapshot. Reconnects with a slow poll while the daemon is
/// absent — it starts on first MCP use, so absence is the normal idle state.
@Observable
public final class SupervisionClient {
    public private(set) var sessions: [Int: ComputerSessionState] = [:]
    public private(set) var frames: [Int: Data] = [:] // windowID -> latest PNG
    public private(set) var lastAction: (windowID: Int, kind: String, x: Double?, y: Double?, at: Date)?
    public private(set) var isConnected = false
    public private(set) var permissions: (screenRecording: Bool, accessibility: Bool)?

    /// True when any harness has a claimed window — drives MenuBarExtra insertion.
    public var hasAnyActivity: Bool {
        sessions.values.contains { !$0.windows.isEmpty }
    }

    private let socketPath: String
    private var listenTask: Task<Void, Never>?

    /// Side-channel for per-session forwarding — AppModel sets this to route
    /// events to the active session's ComputerUseController.
    public var onEvent: ((SupervisionEvent) -> Void)?

    public init(socketPath: String = DaemonServer.defaultSocketPath) {
        self.socketPath = socketPath
    }

    public func start() {
        guard listenTask == nil else { return }
        listenTask = Task.detached { [weak self] in await self?.listenLoop() }
    }

    public func stop() {
        listenTask?.cancel()
        listenTask = nil
    }

    public func stopSession(_ sessionID: Int) {
        send(.object(["command": .string("stop_session"), "session": .number(Double(sessionID))]))
    }

    public func stopAll() {
        send(.object(["command": .string("stop_all")]))
    }

    private func send(_ command: ComputerKit.JSONValue) {
        Task.detached { [socketPath] in
            guard let client = try? DaemonClient(socketPath: socketPath) else { return }
            try? client.send(.object(["role": .string("supervision")]))
            _ = try? client.receive() // handshake ack
            try? client.send(command)
        }
    }

    private func listenLoop() async {
        while !Task.isCancelled {
            do {
                let client = try DaemonClient(socketPath: socketPath)
                try client.send(.object(["role": .string("supervision")]))
                _ = try client.receive() // handshake ack
                await MainActor.run { self.isConnected = true }
                while !Task.isCancelled {
                    let line = try client.receive()
                    let event = try SupervisionEvent(jsonLine: String(decoding: try JSONEncoder().encode(line), as: UTF8.self))
                    await MainActor.run { self.apply(event) }
                }
            } catch {
                await MainActor.run { self.isConnected = false }
                // ponytail: fixed 2s retry — the daemon appears on first MCP use
                // and events are state-rebuildable, so no backoff sophistication.
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Pure reducer — the tested surface.
    public func apply(_ event: SupervisionEvent) {
        switch event {
        case .sessionStarted(let session, let harness, let label, _):
            sessions[session] = ComputerSessionState(id: session, harness: harness, label: label)
        case .sessionEnded(let session, _):
            if let ended = sessions.removeValue(forKey: session) {
                for window in ended.windows { frames.removeValue(forKey: window.windowID) }
            }
        case .windowClaimed(let session, _, let windowID, let app, let title, let bounds):
            sessions[session]?.windows.append(ClaimedWindowState(windowID: windowID, app: app, title: title, bounds: bounds))
        case .windowReleased(let session, let windowID, _):
            sessions[session]?.windows.removeAll { $0.windowID == windowID }
            frames.removeValue(forKey: windowID)
        case .action(_, let windowID, let kind, let x, let y):
            lastAction = (windowID, kind, x, y, Date())
        case .screenshotTaken(_, let windowID, let pngBase64, _, _, _):
            if let data = Data(base64Encoded: pngBase64) { frames[windowID] = data }
        case .statusChanged(let session, let status):
            sessions[session]?.status = status
        case .permissions(let screenRecording, let accessibility):
            permissions = (screenRecording, accessibility)
        case .stopped(_, let session):
            if let session {
                // Per-session stop: drop just that session.
                if let ended = sessions.removeValue(forKey: session) {
                    for window in ended.windows { frames.removeValue(forKey: window.windowID) }
                }
            } else {
                sessions.removeAll()
                frames.removeAll()
                lastAction = nil
            }
        }
        onEvent?(event)
    }
}
```

Note: `SupervisionEvent` and `DaemonClient` are ComputerKit's; `SupervisionEvent(jsonLine:)` round-trips through JSONValue because `DaemonClient.receive()` returns `ComputerKit.JSONValue`. If that double-encode offends, add a `DaemonClient.receiveLine() throws -> String` to ComputerKit — do NOT fork the event decoder.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/SupervisionClientTests 2>&1 | tail -5`
Expected: PASS — 9 tests.

- [ ] **Step 5: Commit**

```bash
git add App/ComputerUse/SupervisionClient.swift Tests/TenXAppTests/SupervisionClientTests.swift
git commit -m "feat(computer-use): supervision client with snapshot reducer"
```

---

### Task 3: MenuBarPresentation — grouping reducer

**Files:**
- Create: `App/ComputerUse/MenuBarPresentation.swift`
- Test: `Tests/TenXAppTests/MenuBarPresentationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import TenXApp

final class MenuBarPresentationTests: XCTestCase {
    func session(_ id: Int, _ harness: String, windows: [ClaimedWindowState] = []) -> ComputerSessionState {
        ComputerSessionState(id: id, harness: harness, status: nil, windows: windows)
    }

    func window(_ id: Int, _ app: String) -> ClaimedWindowState {
        ClaimedWindowState(windowID: id, app: app, title: "", bounds: "0,0 800x600")
    }

    func test_groupsByHarness_sortedByName() {
        let groups = MenuBarPresentation.groups(sessions: [
            1: session(1, "omp"), 2: session(2, "Cursor"), 3: session(3, "omp"),
        ])
        XCTAssertEqual(groups.map(\.harness), ["Cursor", "omp"])
        XCTAssertEqual(groups[1].sessions.map(\.id), [1, 3])
    }

    func test_sessionsWithoutWindows_areExcluded() {
        let groups = MenuBarPresentation.groups(sessions: [
            1: session(1, "omp", windows: [window(10, "Safari")]),
            2: session(2, "Cursor"), // connected but idle
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].harness, "omp")
    }

    func test_tenXSessions_sortFirst() {
        let groups = MenuBarPresentation.groups(sessions: [
            1: session(1, "Cursor", windows: [window(10, "Safari")]),
            2: session(2, "10x", windows: [window(11, "Terminal")]),
        ])
        XCTAssertEqual(groups.map(\.harness), ["10x", "Cursor"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/MenuBarPresentationTests 2>&1 | tail -5`
Expected: FAIL — `MenuBarPresentation` does not exist.

- [ ] **Step 3: Write minimal implementation**

`App/ComputerUse/MenuBarPresentation.swift`:

```swift
import Foundation

struct HarnessSessionGroup: Equatable {
    let harness: String
    let sessions: [ComputerSessionState]
}

enum MenuBarPresentation {
    /// Groups sessions with at least one claimed window by harness.
    /// "10x" sorts first (own sessions are the ones you can open in-app);
    /// the rest sort alphabetically.
    static func groups(sessions: [Int: ComputerSessionState]) -> [HarnessSessionGroup] {
        let active = sessions.values.filter { !$0.windows.isEmpty }
        let grouped = Dictionary(grouping: active, by: \.harness)
        return grouped
            .map { HarnessSessionGroup(harness: $0.key, sessions: $0.value.sorted { $0.id < $1.id }) }
            .sorted { lhs, rhs in
                if lhs.harness == "10x" { return true }
                if rhs.harness == "10x" { return false }
                return lhs.harness.localizedCaseInsensitiveCompare(rhs.harness) == .orderedAscending
            }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/MenuBarPresentationTests 2>&1 | tail -5`
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add App/ComputerUse/MenuBarPresentation.swift Tests/TenXAppTests/MenuBarPresentationTests.swift
git commit -m "feat(computer-use): menu bar grouping reducer"
```

---

### Task 4: Transcript activity tracking + MCP tool cards

**Files:**
- Create: `App/ComputerUse/ComputerActivityTracker.swift`
- Modify: `App/Tools/ToolCardRegistry.swift:17`
- Modify: `App/Tools/ComputerToolPresentation.swift:43`
- Test: `Tests/TenXAppTests/ComputerActivityTrackerTests.swift`

The per-session source of truth is the session's own transcript: MCP tool calls are named `mcp__tenx-computer_computer_claim` etc. and carry `window_id` in their input. This tracker turns that stream into per-session activity — no daemon correlation needed for chrome.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import TenXApp

final class ComputerActivityTrackerTests: XCTestCase {
    func test_ignoresNonComputerTools() {
        var tracker = ComputerActivityTracker()
        XCTAssertFalse(tracker.toolStarted(name: "bash", input: nil))
        XCTAssertFalse(tracker.isActive)
    }

    func test_claim_marksActiveWithWindow() {
        var tracker = ComputerActivityTracker()
        XCTAssertTrue(tracker.toolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10]))
        XCTAssertTrue(tracker.isActive)
        XCTAssertEqual(tracker.claimedWindowIDs, [10])
    }

    func test_launch_claimsResultWindow() {
        var tracker = ComputerActivityTracker()
        _ = tracker.toolStarted(name: "mcp__tenx-computer_computer_launch", input: ["app": "Safari"])
        tracker.toolCompleted(name: "mcp__tenx-computer_computer_launch", claimedWindowID: 11)
        XCTAssertEqual(tracker.claimedWindowIDs, [11])
    }

    func test_release_removesWindow() {
        var tracker = ComputerActivityTracker()
        _ = tracker.toolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        _ = tracker.toolStarted(name: "mcp__tenx-computer_computer_release", input: ["window_id": 10])
        XCTAssertFalse(tracker.isActive)
    }

    func test_act_marksControlling() {
        var tracker = ComputerActivityTracker()
        _ = tracker.toolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        _ = tracker.toolStarted(name: "mcp__tenx-computer_computer_act", input: ["window_id": 10, "action": "click"])
        XCTAssertEqual(tracker.phase, .controlling)
    }

    func test_readOnlyTools_keepReadyPhase() {
        var tracker = ComputerActivityTracker()
        _ = tracker.toolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        _ = tracker.toolStarted(name: "mcp__tenx-computer_computer_screenshot", input: ["window_id": 10])
        XCTAssertEqual(tracker.phase, .ready)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/ComputerActivityTrackerTests 2>&1 | tail -5`
Expected: FAIL — `ComputerActivityTracker` does not exist.

- [ ] **Step 3: Write minimal implementation**

`App/ComputerUse/ComputerActivityTracker.swift`:

```swift
import Foundation

enum ComputerActivityPhase: Equatable {
    case off
    case ready        // holds claims, no input action yet / lately
    case controlling  // an act call is in flight or just completed
}

/// Reduces one session's MCP tool stream into computer-use activity.
/// Tool names arrive as mcp__tenx-computer_<tool>; inputs carry window_id.
struct ComputerActivityTracker {
    static let toolPrefix = "mcp__tenx-computer_computer_"

    private(set) var claimedWindowIDs: Set<Int> = []
    private(set) var phase: ComputerActivityPhase = .off
    private var pendingActCount = 0

    var isActive: Bool { !claimedWindowIDs.isEmpty }

    /// Returns true when the tool is one of ours.
    @discardableResult
    mutating func toolStarted(name: String, input: [String: Any]?) -> Bool {
        guard name.hasPrefix(Self.toolPrefix) else { return false }
        let tool = String(name.dropFirst(Self.toolPrefix.count))
        switch tool {
        case "claim":
            if let id = input?["window_id"] as? Int { claimedWindowIDs.insert(id) }
        case "release":
            if let id = input?["window_id"] as? Int { claimedWindowIDs.remove(id) }
        case "act":
            pendingActCount += 1
        default:
            break // windows/screenshot/status/launch: no state change at start
        }
        recompute()
        return true
    }

    /// `claimedWindowID` is parsed from the tool result text for computer_launch
    /// ("launched X; claimed window N …") by the caller.
    mutating func toolCompleted(name: String, claimedWindowID: Int? = nil) {
        guard name.hasPrefix(Self.toolPrefix) else { return }
        let tool = String(name.dropFirst(Self.toolPrefix.count))
        switch tool {
        case "act": pendingActCount = max(0, pendingActCount - 1)
        case "launch": if let claimedWindowID { claimedWindowIDs.insert(claimedWindowID) }
        default: break
        }
        recompute()
    }

    private mutating func recompute() {
        if claimedWindowIDs.isEmpty { phase = .off }
        else if pendingActCount > 0 { phase = .controlling }
        else { phase = .ready }
    }
}
```

In `App/Tools/ToolCardRegistry.swift`, replace the `"computer"` case so both the legacy built-in and the MCP tools map to the computer card:

```swift
        switch name.lowercased() {
        case "computer": .computer
        case let n where n.hasPrefix("mcp__tenx-computer_computer_"): .computer
```

In `App/Tools/ComputerToolPresentation.swift:43`, widen the failable init's name check the same way:

```swift
        guard presentation.name.lowercased() == "computer"
            || presentation.name.lowercased().hasPrefix("mcp__tenx-computer_computer_") else { return nil }
```

Update `Tests/TenXAppTests/ComputerToolPresentationTests.swift`: add one test that `ComputerToolPresentation` accepts `mcp__tenx-computer_computer_act` with a screenshot payload shaped like the MCP image content (base64 PNG in the result).

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/ComputerActivityTrackerTests -only-testing:TenXAppTests/ComputerToolPresentationTests 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/ComputerUse/ComputerActivityTracker.swift App/Tools/ToolCardRegistry.swift App/Tools/ComputerToolPresentation.swift Tests/TenXAppTests
git commit -m "feat(computer-use): track per-session activity from mcp tool stream"
```

---

### Task 5: Delete the Agent Desktop stack; new ComputerUseController

**Files:**
- Delete: `App/ComputerUse/AgentDesktopProvider.swift`, `AeroSpaceProvider.swift`, `HammerspoonProvider.swift`, `BackgroundProvider.swift`, `AgentDesktopCoordinator.swift`, `AgentDesktopHostTool.swift`, `AgentDesktopManifest.swift`, `DedicatedWindowLauncher.swift`, `AgentDesktopCommandRunner.swift`, `AgentDesktopProbeWindow.swift`, `ComputerUseLease.swift`, `ComputerUseRegistry.swift`, `ComputerUseState.swift`
- Delete: `App/ExtensionUI/ComputerHandoffCardView.swift`
- Delete tests: `AgentDesktop*Tests.swift`, `DedicatedWindowLauncherTests.swift`, `ComputerUseLeaseTests.swift`, `ComputerUseRegistryTests.swift`, `ComputerUseStateTests.swift`, `ComputerUseControllerTests.swift`, `ComputerUseSetupModelTests.swift`
- Replace: `App/ComputerUse/ComputerUseController.swift` (741 lines → ~120)
- Modify: `App/Application/AppDependencies.swift:18-32`, `App/Sessions/SessionController.swift:26-27,53-55,75-77,270-285,339-342,434-448,472-473`, `App/Application/AppModel.swift:19,42-58,112-115,136-139,182-184,265-301`, `App/TenXApp.swift:13-14`, `App/Sessions/SessionHeaderView.swift` (compile fixes only — real redesign is Task 7), `App/Sessions/TranscriptView.swift:182-191` (remove handoff card), `App/Settings/ComputerUseSetupModel.swift` + `ComputerUseSettingsSection.swift` (stub — real rewrite is Task 12)

Rationale: the daemon is now the cross-process arbiter (exclusive claims), so the lease and single-owner registry are redundant. Multi-session control is a feature: N sessions, N claimed windows, one daemon. The `setComputerUse`/`agent_desktop`/handoff RPC contract is replaced by the MCP mount (Task 12).

- [ ] **Step 1: Write the failing test for the new controller**

`Tests/TenXAppTests/ComputerUseControllerTests.swift` (new, replacing the deleted one):

```swift
import XCTest
@testable import TenXApp

final class ComputerUseControllerTests: XCTestCase {
    func makeController() -> ComputerUseController {
        ComputerUseController(supervision: SupervisionClient(socketPath: NSTemporaryDirectory() + "unused-\(UUID().uuidString).sock"))
    }

    func test_toolStream_drivesActivity() {
        let controller = makeController()
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(controller.claimedWindowIDs, [10])
    }

    func test_statusEvent_surfacesAgentStatus() {
        let controller = makeController()
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        // Correlate first: the claim event for our window identifies our daemon session.
        controller.applySupervision(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: ""))
        controller.applySupervision(.statusChanged(session: 1, status: "Running tests…"))
        XCTAssertEqual(controller.status, "Running tests…")
    }

    func test_statusEvent_fromOtherSession_isIgnored() {
        let controller = makeController()
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        controller.applySupervision(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: ""))
        controller.applySupervision(.statusChanged(session: 99, status: "not ours"))
        XCTAssertNil(controller.status)
    }

    func test_stop_withoutDaemonSession_isNoop() async {
        let controller = makeController()
        await controller.stopComputerUse() // must not crash or hang
        XCTAssertEqual(controller.phase, .off)
    }

    func test_daemonSession_correlatesByClaimedWindow() {
        let controller = makeController()
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        // A claim event for OUR window identifies which daemon session is us.
        controller.applySupervision(.windowClaimed(session: 7, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: ""))
        XCTAssertEqual(controller.daemonSessionID, 7)
    }

    func test_stoppedEvent_clearsActivity() {
        let controller = makeController()
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        controller.applySupervision(.stopped(reason: "global shut-off", session: nil))
        XCTAssertEqual(controller.phase, .off)
        XCTAssertEqual(controller.claimedWindowIDs, [])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/ComputerUseControllerTests 2>&1 | tail -5`
Expected: FAIL to compile (old controller signature mismatch is fine — it gets replaced next step).

- [ ] **Step 3: Delete the old stack and write the new controller**

Delete the files listed above (`git rm`). Replace `App/ComputerUse/ComputerUseController.swift` with:

```swift
import ComputerKit
import Foundation

/// Per-session computer-use state, derived from the session's own MCP tool
/// stream plus the shared daemon supervision feed. The daemon owns claims and
/// exclusivity; this controller is chrome + the stop button.
@Observable
final class ComputerUseController {
    private(set) var phase: ComputerActivityPhase = .off
    private(set) var claimedWindowIDs: Set<Int> = []
    private(set) var status: String?
    private(set) var daemonSessionID: Int?

    private var tracker = ComputerActivityTracker()
    private let supervision: SupervisionClient

    init(supervision: SupervisionClient) {
        self.supervision = supervision
    }

    var isEnabled: Bool { phase != .off }

    /// Latest preview frame for this session's most recently claimed window.
    var latestFrame: Data? {
        claimedWindowIDs.sorted().last.flatMap { supervision.frames[$0] }
    }

    // MARK: - Transcript stream (called by SessionController)

    func handleToolStarted(name: String, input: [String: Any]?) {
        tracker.toolStarted(name: name, input: input)
        sync()
    }

    func handleToolCompleted(name: String, claimedWindowID: Int? = nil) {
        tracker.toolCompleted(name: name, claimedWindowID: claimedWindowID)
        sync()
    }

    // MARK: - Supervision feed (forwarded from AppModel's subscription)

    func applySupervision(_ event: SupervisionEvent) {
        switch event {
        case .windowClaimed(let session, _, let windowID, _, _, _):
            if claimedWindowIDs.contains(windowID) { daemonSessionID = session }
        case .statusChanged(let session, let status) where session == daemonSessionID:
            self.status = status
        case .windowReleased(_, let windowID, _):
            claimedWindowIDs.remove(windowID)
        case .stopped(_, let session) where session == nil || session == daemonSessionID:
            claimedWindowIDs.removeAll()
            status = nil
            daemonSessionID = nil
        default:
            break
        }
        sync()
    }

    // MARK: - Stop

    func stopComputerUse() async {
        if let daemonSessionID { supervision.stopSession(daemonSessionID) }
        tracker = ComputerActivityTracker()
        status = nil
        self.daemonSessionID = nil
        sync()
    }

    private func sync() {
        phase = tracker.phase
        claimedWindowIDs = tracker.claimedWindowIDs
    }
}
```

Then fix every reference so the build is green:

- `AppDependencies.swift`: replace `computerUseRegistry` with `supervisionClient = SupervisionClient()`; `makeSessionController` passes it through.
- `SessionController.swift`: replace the `ComputerUseController(registry:preference:)` init with `ComputerUseController(supervision:)`; delete `attachAndReconcile`, host-tool routing, and handoff handling; in the tool-event handlers, call `computerUse.handleToolStarted(name:input:)` / `handleToolCompleted(name:claimedWindowID:)` for every tool (the tracker ignores non-computer tools); subscribe to `supervision` events by forwarding to `computerUse.applySupervision(_:daemonSession:)` — simplest wiring: `SessionController` polls nothing; `AppModel` forwards events from its own subscription to the active session's controller. Parse the launch result's claimed id from result text with a regex on `claimed window (\d+)`.
- `AppModel.swift`: expose `let supervision: SupervisionClient` (from dependencies, started in `bootstrap()`); delete `computerUsePhaseDidChange`'s lease/helper bookkeeping; keep `emergencyShortcut` but repoint it (next bullet); delete `helperProcessID`/provider lifecycle observers at :265-301 (sleep/willTerminate observers stay, now calling `supervision.stopAll()`); `activeComputerUse` computed property stays (same shape). Forward every supervision event to `activeSession?.computerUse.applySupervision(_:)` — simplest wiring: `SupervisionClient.apply` is called on MainActor, so add a `var onEvent: ((SupervisionEvent) -> Void)?` hook to SupervisionClient that AppModel sets.
- `AppModelNavigationTests.swift`: delete `appModelPassesCurrentDesktopPreferenceToEverySessionFactory` (:36-67, preference store is gone); update every `AppDependencies(...)` construction to the new `supervisionClient:` label.
- `ViewSnapshotTests.swift`: delete `computerHandoffSnapshot` (:42-52) and its reference image; `computerUseSettingsSnapshot` (:79) will change against the stub section — re-record it.
- `GlobalEmergencyShortcut`: change `update(phase:onStop:)` to `update(isActive:onStop:)` — register when `supervision.hasAnyActivity`, and the handler calls `supervision.stopAll()` (panic = global shut-off). Update `GlobalEmergencyShortcutTests` accordingly (rename cases: registers when active, clears when idle).
- `TenXApp.swift`: the `.onChange(of: model.activeComputerUse?.phase)` block becomes `.onChange(of: model.supervision.hasAnyActivity)` updating the emergency shortcut; the MenuBarExtra binding reads `model.supervision.hasAnyActivity` (panel content is Task 10 — keep the old view compiling with a temporary trivial body).
- `SessionHeaderView.swift`: delete `computerControls`, the confirmation dialog, phase/safetyMode computeds; the header shows only title + metadata for now (Task 7 adds the real item). Remove `phaseOverride`/`safetyModeOverride`/`isCompleteContractOverride` init params and fix snapshot-test call sites.
- `TranscriptView.swift`: remove the `.computerHandoff` card branch (:182-191) and its ExtensionUI case.
- `ComputerUseSetupModel.swift` / `ComputerUseSettingsSection.swift`: reduce to a stub section reading "Computer use settings arrive with the daemon install step" so `SettingsView` compiles (Task 12 rewrites both).
- `ComputerUsePreferenceStore`: delete with the setup model's preference half.

- [ ] **Step 4: Build and run the full suite**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' 2>&1 | tail -15`
Expected: build succeeds; all remaining tests pass (new controller tests included).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(computer-use)!: replace agent desktop stack with daemon-backed controller

BREAKING: removes the AeroSpace/Hammerspoon isolation providers, the
agent_desktop host tool, the cross-process lease, and the single-owner
registry. Window claims and exclusivity now live in the tenx-computer
daemon; sessions may control separate windows concurrently."
```

---

### Task 6: Per-session stop from the header (correlation proof)

**Files:**
- Modify: `App/ComputerUse/ComputerUseController.swift`
- Test: `Tests/TenXAppTests/ComputerUseControllerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
    func test_stop_sendsStopSessionForCorrelatedDaemonSession() async {
        let socketPath = NSTemporaryDirectory() + "tenx-test-\(UUID().uuidString).sock"
        let engine = FakeEngine() // from ComputerKit tests? NO — see note below
        ...
    }
```

ComputerKit's `FakeEngine` lives in its test target and is not visible to the app. Instead, verify against a real `DaemonServer` with a minimal app-side fake. Add to the test file:

```swift
import ComputerKit

private final class NoopEngine: DesktopEngine {
    var isCancelled: @Sendable () -> Bool = { false }
    func preflightPermissions() -> PermissionStatus { .init(screenRecording: true, accessibility: true) }
    func listWindows(onScreenOnly: Bool) throws -> [WindowInfo] { [] }
    func screenshot(windowID: CGWindowID) throws -> Screenshot {
        Screenshot(pngData: Data(), pixelSize: .zero, scale: 1)
    }
    func launch(app: String) throws -> WindowInfo { throw ComputerError("nope") }
    func act(_ action: ComputerAction, window: WindowInfo) throws {}
}

final class ComputerUseStopIntegrationTests: XCTestCase {
    func test_stop_revokesSessionAtDaemon() async throws {
        let socketPath = NSTemporaryDirectory() + "tenx-test-\(UUID().uuidString).sock"
        let daemon = DaemonServer(engine: NoopEngine(), socketPath: socketPath)
        try daemon.start()
        defer { daemon.stop() }

        // Simulate an agent session at the daemon.
        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp")]))
        try mcp.send(.object([
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ]))
        _ = try mcp.receive()

        let supervision = SupervisionClient(socketPath: socketPath)
        let controller = ComputerUseController(supervision: supervision)
        // Correlate: our transcript claimed window 10; daemon says session 1 claimed it.
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        controller.applySupervision(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: ""))

        await controller.stopComputerUse()

        // The daemon should stop session 1 — its tools error. Poll: the stop
        // command travels a separate connection, so ordering isn't instant.
        var isError = false
        for _ in 0..<20 where !isError {
            try mcp.send(.object([
                "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
                "params": .object(["name": .string("computer_windows"), "arguments": .object([:])]),
            ]))
            let response = try mcp.receive()
            isError = response["result"]?["isError"] == .bool(true)
            if !isError { try await Task.sleep(for: .milliseconds(100)) }
        }
        XCTAssertTrue(isError)
    }
}
```

Note: `SupervisionClient.stopSession` currently opens a throwaway connection per command — fine for tests and real use (commands are rare).

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/ComputerUseStopIntegrationTests 2>&1 | tail -5`
Expected: FAIL if Task 5's `stopComputerUse` doesn't actually send (it does — so this may pass immediately; if so, treat Step 1-2 as characterization and move on).

- [ ] **Step 3: Run full suite**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Tests/TenXAppTests/ComputerUseControllerTests.swift App/ComputerUse/ComputerUseController.swift
git commit -m "test(computer-use): prove per-session stop reaches the daemon"
```

---

### Task 7: Header metadata item + "Currently viewing" popover

**Files:**
- Modify: `App/Sessions/SessionHeaderView.swift`
- Create: `App/ComputerUse/CurrentlyViewingPopover.swift`
- Test: `Tests/TenXAppTests/ViewSnapshotTests.swift` (extend the existing pattern)

Design (approved mockups): a subtle item in the existing metadata row — `display` icon + app name of the controlled window, mono 10, muted — that turns cyan while controlling and opens the preview popover on click. The popover is a `CornerCard` showing the near-live frame, window title, agent status line, and a Stop button (`GhostActionStyle`, signal red).

- [ ] **Step 1: Write the failing test**

Add to `ViewSnapshotTests.swift` (the file uses Swift Testing + a custom `assertSnapshot(view, name:size:)` helper):

```swift
@MainActor
@Test func sessionHeaderComputerItemSnapshot() throws {
    let controller = SessionController(
        processManager: SessionProcessManager(),
        supervision: SupervisionClient(socketPath: NSTemporaryDirectory() + "unused-\(UUID().uuidString).sock"))
    controller.computerUse.handleToolStarted(
        name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
    try assertSnapshot(
        SessionHeaderView(controller: controller),
        name: "session-header-computer",
        size: CGSize(width: 760, height: 54))
}

@MainActor
@Test func currentlyViewingPopoverSnapshot() throws {
    try assertSnapshot(
        CurrentlyViewingPopover(
            framePNG: nil,
            windowTitle: "Safari — Apple",
            status: "Running tests…",
            onStop: {}),
        name: "currently-viewing-popover",
        size: CGSize(width: 400, height: 260))
}
```

(The `SessionController` init shown is the post-Task-5 signature — adjust argument labels to whatever Task 5 landed on.)

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/ViewSnapshotTests 2>&1 | tail -5`
Expected: FAIL (missing reference images / type missing).

- [ ] **Step 3: Implement**

`App/ComputerUse/CurrentlyViewingPopover.swift`:

```swift
import SwiftUI

/// "Currently viewing" — near-live frame of the window this session controls.
struct CurrentlyViewingPopover: View {
    let framePNG: Data?
    let windowTitle: String
    let status: String?
    let onStop: () -> Void

    var body: some View {
        CornerCard {
            VStack(alignment: .leading, spacing: 8) {
                if let framePNG, let image = NSImage(data: framePNG) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 360, maxHeight: 240)
                } else {
                    Text("Waiting for first frame…")
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .frame(width: 360, height: 120)
                }
                Text(windowTitle)
                    .font(TenXTypography.body(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let status, !status.isEmpty {
                    Text(status)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .lineLimit(2)
                }
                HStack {
                    Spacer()
                    Button("Stop Computer", action: onStop)
                        .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.signalRedHex)))
                        .accessibilityLabel("Stop computer control for this session")
                }
            }
            .padding(10)
        }
        .frame(width: 380)
    }
}
```

In `SessionHeaderView.swift`, inside the metadata `HStack(spacing: 14)` after the `ForEach`, add the computer item (this is the whole header treatment — no separate button row):

```swift
                if let computer = computerItem {
                    Button { isComputerPopoverPresented.toggle() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "display")
                                .font(.system(size: 9, weight: .medium))
                            Text(computer.label)
                        }
                        .foregroundStyle(computer.isControlling
                            ? TenXPalette.color(TenXPalette.cyanHex)
                            : TenXPalette.color(TenXPalette.mutedTextHex))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Computer use")
                    .accessibilityValue(computer.label)
                    .popover(isPresented: $isComputerPopoverPresented) {
                        CurrentlyViewingPopover(
                            framePNG: controller.computerUse.latestFrame,
                            windowTitle: computer.label,
                            status: controller.computerUse.status,
                            onStop: {
                                isComputerPopoverPresented = false
                                Task { await controller.computerUse.stopComputerUse() }
                            })
                    }
                }
```

with supporting code on the view:

```swift
    @State private var isComputerPopoverPresented = false

    private var computerItem: (label: String, isControlling: Bool)? {
        guard controller.computerUse.isEnabled else { return nil }
        let names = controller.computerUse.windowAppNames // add: map claimed ids through supervision snapshot
        let label = names.first ?? "Computer"
        return (label, controller.computerUse.phase == .controlling)
    }
```

Add `windowAppNames` to `ComputerUseController`: map `claimedWindowIDs` through `supervision.sessions` windows (app names), sorted.

- [ ] **Step 4: Record snapshots and run**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/ViewSnapshotTests 2>&1 | tail -5`
Expected: PASS after recording reference images per the file's existing convention.

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/SessionHeaderView.swift App/ComputerUse/CurrentlyViewingPopover.swift App/ComputerUse/ComputerUseController.swift Tests/TenXAppTests
git commit -m "feat(computer-use): header metadata item with currently-viewing popover"
```

---

### Task 8: Rail badge

**Files:**
- Modify: `App/Shell/FloatingRailView.swift:141-175` (session row)
- Modify: `App/Application/AppModel.swift` (expose which session paths have active computer use)
- Test: `Tests/TenXAppTests/RailPresentationTests.swift` (extend)

A small cyan dot on the session's `RailTreeMarker` when that session holds computer claims. V1 ceiling: only sessions with a live `SessionController` report activity — today that is the active session plus any retiring ones. Note this in code.

- [ ] **Step 1: Write the failing test**

```swift
    func test_sessionItem_showsComputerBadgeWhenActive() {
        // RailPresentation.items gains hasComputerUse on session items
    }
```

Extend `RailPresentationItem`'s session content with `hasComputerUse: Bool`, sourced from a new `AppModel.computerUseActiveSessionPaths: Set<String>`.

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/RailPresentationTests 2>&1 | tail -5`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `AppModel`:

```swift
    /// ponytail: only sessions with a live controller report activity (active +
    /// retiring). Ceiling: a background session that keeps controlling while
    /// closed loses its badge until reopened. Upgrade path: persist claims per
    /// session path in the daemon and query by path.
    var computerUseActiveSessionPaths: Set<String> {
        var paths = Set<String>()
        if let activeSession, activeSession.computerUse.isEnabled,
           let path = activeSession.sessionPath { paths.insert(path) }
        return paths
    }
```

(`SessionController.sessionPath` exists per the subsystem map — it is passed to `attachAndReconcile`; expose it if private.)

Thread `hasComputerUse` through `RailPresentation.items(groups:selectedSessionPath:)` (add a `computerUseActivePaths: Set<String>` parameter) and render in `FloatingRailView`'s session row:

```swift
                    RailTreeMarker(
                        label: item.markerLabel,
                        position: item.treePosition,
                        isSelected: item.isSelected)
                        .frame(width: 34, height: 28)
                        .overlay(alignment: .topTrailing) {
                            if item.hasComputerUse {
                                Circle()
                                    .fill(TenXPalette.color(TenXPalette.cyanHex))
                                    .frame(width: 6, height: 6)
                                    .offset(x: -2, y: 1)
                            }
                        }
```

Update `RailAccessibility.sessionLabel` to append "Computer use active" when badged.

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/RailPresentationTests -only-testing:TenXAppTests/AccessibilityLabelTests 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/Shell App/Application Tests/TenXAppTests
git commit -m "feat(computer-use): rail badge for sessions holding computer claims"
```

---

### Task 9: On-screen overlay — cursor, two-corner frame, tag

**Files:**
- Create: `App/ComputerUse/OverlayModel.swift`
- Create: `App/ComputerUse/ComputerUseOverlayView.swift`
- Create: `App/ComputerUse/OverlayWindowController.swift`
- Test: `Tests/TenXAppTests/OverlayModelTests.swift`

Design (approved mockups): a borderless, click-through `NSPanel` per claimed window — two-corner stroke around the window, a tag at the top-left corner (session identity + agent status), and a cursor dot that jumps/pulses on `action` events. Bounds track the real window via `CGWindowList` polling.

- [ ] **Step 1: Write the failing test**

```swift
import ComputerKit
import XCTest
@testable import TenXApp

final class OverlayModelTests: XCTestCase {
    func test_claim_addsOverlay() {
        let model = OverlayModel()
        model.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "100,100 800x600"))
        XCTAssertEqual(model.overlays[10]?.app, "Safari")
        XCTAssertEqual(model.overlays[10]?.frame, CGRect(x: 100, y: 100, width: 800, height: 600))
    }

    func test_action_movesCursorInWindowRelativePoints() {
        let model = OverlayModel()
        model.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: "100,100 800x600"))
        model.apply(.action(session: 1, windowID: 10, kind: "click", x: 50, y: 60))
        XCTAssertEqual(model.overlays[10]?.cursor, CGPoint(x: 50, y: 60))
        XCTAssertEqual(model.overlays[10]?.cursorKind, "click")
    }

    func test_status_updatesTag() {
        let model = OverlayModel()
        model.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: "100,100 800x600"))
        model.apply(.statusChanged(session: 1, status: "Running tests…"))
        XCTAssertEqual(model.overlays[10]?.status, "Running tests…")
    }

    func test_release_removesOverlay() {
        let model = OverlayModel()
        model.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: "100,100 800x600"))
        model.apply(.windowReleased(session: 1, windowID: 10, reason: "released"))
        XCTAssertTrue(model.overlays.isEmpty)
    }

    func test_boundsParsing_toleratesJunk() {
        XCTAssertNil(OverlayModel.parseBounds("garbage"))
        XCTAssertEqual(OverlayModel.parseBounds("100,100 800x600"), CGRect(x: 100, y: 100, width: 800, height: 600))
    }

    func test_stopped_clearsAll() {
        let model = OverlayModel()
        model.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: "100,100 800x600"))
        model.apply(.stopped(reason: "global shut-off", session: nil))
        XCTAssertTrue(model.overlays.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/OverlayModelTests 2>&1 | tail -5`
Expected: FAIL — `OverlayModel` does not exist.

- [ ] **Step 3: Implement**

`App/ComputerUse/OverlayModel.swift`:

```swift
import ComputerKit
import CoreGraphics
import Foundation

struct OverlayState: Equatable {
    var app: String
    var frame: CGRect
    var status: String?
    var cursor: CGPoint?
    var cursorKind: String?
    var cursorAt: Date?
}

/// Pure reducer behind the on-screen overlay. One state per claimed window.
@Observable
final class OverlayModel {
    private(set) var overlays: [Int: OverlayState] = [:] // windowID -> state
    private var sessionStatus: [Int: String] = [:]
    private var windowSession: [Int: Int] = [:]

    func apply(_ event: SupervisionEvent) {
        switch event {
        case .windowClaimed(let session, _, let windowID, let app, _, let bounds):
            windowSession[windowID] = session
            overlays[windowID] = OverlayState(
                app: app,
                frame: Self.parseBounds(bounds) ?? .zero,
                status: sessionStatus[session],
                cursor: nil, cursorKind: nil, cursorAt: nil)
        case .windowReleased(_, let windowID, _):
            overlays.removeValue(forKey: windowID)
            windowSession.removeValue(forKey: windowID)
        case .action(_, let windowID, let kind, let x, let y):
            // type/key carry null coordinates — the cursor stays put.
            guard overlays[windowID] != nil, let x, let y else { return }
            overlays[windowID]?.cursor = CGPoint(x: x, y: y)
            overlays[windowID]?.cursorKind = kind
            overlays[windowID]?.cursorAt = Date()
        case .statusChanged(let session, let status):
            sessionStatus[session] = status
            for (windowID, owner) in windowSession where owner == session {
                overlays[windowID]?.status = status
            }
        case .sessionEnded(let session, _):
            for (windowID, owner) in windowSession where owner == session {
                overlays.removeValue(forKey: windowID)
                windowSession.removeValue(forKey: windowID)
            }
            sessionStatus.removeValue(forKey: session)
        case .stopped:
            overlays.removeAll()
            windowSession.removeAll()
            sessionStatus.removeAll()
        default:
            break
        }
    }

    /// Reposition overlays as windows move (called on a 0.5s timer).
    func pollBounds(_ boundsProvider: (Int) -> CGRect?) {
        for windowID in overlays.keys {
            if let bounds = boundsProvider(windowID) {
                overlays[windowID]?.frame = bounds
            } else {
                overlays.removeValue(forKey: windowID) // window closed
                windowSession.removeValue(forKey: windowID)
            }
        }
    }

    static func parseBounds(_ string: String) -> CGRect? {
        // "x,y WxH"
        let parts = string.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let origin = parts[0].split(separator: ",").compactMap { Double($0) }
        let size = parts[1].split(separator: "x").compactMap { Double($0) }
        guard origin.count == 2, size.count == 2 else { return nil }
        return CGRect(x: origin[0], y: origin[1], width: size[0], height: size[1])
    }
}
```

`App/ComputerUse/ComputerUseOverlayView.swift`:

```swift
import SwiftUI

/// Drawn inside a click-through panel exactly over the claimed window.
struct ComputerUseOverlayView: View {
    let state: OverlayState

    var body: some View {
        ZStack(alignment: .topLeading) {
            TwoCornerFrame()
                .stroke(TenXPalette.color(TenXPalette.cyanHex), lineWidth: 1.5)

            tag
                .offset(x: -1, y: -22)

            if let cursor = state.cursor {
                CursorDot(kind: state.cursorKind)
                    .position(cursor)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: state.cursor)
    }

    private var tag: some View {
        HStack(spacing: 6) {
            Text(state.app)
                .font(TenXTypography.mono(size: 9, weight: .semibold))
            if let status = state.status, !status.isEmpty {
                Text(status)
                    .font(TenXTypography.mono(size: 9))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(TenXPalette.color(TenXPalette.canvasHex))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(TenXPalette.color(TenXPalette.nearBlackHex))
    }
}

/// Two opposite corners of a rectangle — the 10x frame language.
struct TwoCornerFrame: Shape {
    var cornerLength: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))
        // bottom-right
        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
        return path
    }
}

struct CursorDot: View {
    let kind: String?

    var body: some View {
        Circle()
            .fill(TenXPalette.color(TenXPalette.cyanHex))
            .frame(width: 10, height: 10)
            .overlay {
                Circle().stroke(TenXPalette.color(TenXPalette.nearBlackHex), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 2)
            .accessibilityLabel("Agent cursor\(kind.map { ": \($0)" } ?? "")")
    }
}
```

`App/ComputerUse/OverlayWindowController.swift`:

```swift
import AppKit
import SwiftUI

/// Owns one click-through NSPanel per claimed window, driven by OverlayModel.
/// ponytail: panels reposition on a 0.5s CGWindowList poll. Ceiling: overlays
/// lag fast window drags. Upgrade path: CGS window-move notifications.
@MainActor
final class OverlayWindowController {
    private let model = OverlayModel()
    private var panels: [Int: NSPanel] = [:]
    private var pollTimer: Timer?

    func start() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        for panel in panels.values { panel.close() }
        panels.removeAll()
    }

    func apply(_ event: SupervisionEvent) {
        model.apply(event)
        syncPanels()
    }

    private func poll() {
        model.pollBounds { windowID in
            guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowID)) as? [[String: Any]],
                  let entry = list.first,
                  let dict = entry[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
            return rect
        }
        syncPanels()
    }

    private func syncPanels() {
        for (windowID, state) in model.overlays {
            let panel = panels[windowID] ?? makePanel(windowID: windowID)
            // macOS window coords are bottom-left origin; panels use the same.
            panel.setFrame(state.frame.insetBy(dx: -6, dy: -6), display: true)
            (panel.contentView as? NSHostingView<ComputerUseOverlayView>)?.rootView = ComputerUseOverlayView(state: state)
            panel.orderFrontRegardless()
        }
        let gone = panels.keys.filter { model.overlays[$0] == nil }
        for windowID in gone {
            panels[windowID]?.close()
            panels.removeValue(forKey: windowID)
        }
    }

    private func makePanel(windowID: Int) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ComputerUseOverlayView(state: model.overlays[windowID]!))
        panels[windowID] = panel
        return panel
    }
}
```

Wire it in `AppModel`: own an `OverlayWindowController`, forward every supervision event to it (same place events are forwarded to the active session's controller), `start()` in `bootstrap()`, `stop()` on terminate.

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/OverlayModelTests 2>&1 | tail -5`
Expected: PASS — 6 tests.

- [ ] **Step 5: Manual verification (real overlay)**

Build and run the app, run `tenx-computer selfcheck` in a terminal (it claims nothing, but confirms daemon health), then from any MCP client claim a window and act on it. Expected: cyan two-corner frame + tag around the window; cursor dot pulses where actions land; frame follows window moves within ~0.5s; everything vanishes on stop-all.

- [ ] **Step 6: Commit**

```bash
git add App/ComputerUse App/Application Tests/TenXAppTests/OverlayModelTests.swift
git commit -m "feat(computer-use): on-screen overlay with cursor, frame, and tag"
```

---

### Task 10: Menu bar panel

**Files:**
- Replace: `App/ComputerUse/ComputerUseMenuBarView.swift`
- Modify: `App/TenXApp.swift:21-37`
- Test: `Tests/TenXAppTests/ViewSnapshotTests.swift` (extend)

Design (approved mockups): grouped by harness (10x first), one row per session — status text, claimed window list; per-session Stop; 10x sessions get Open; footer with global "Stop All Computer Use".

- [ ] **Step 1: Write the failing snapshot tests**

```swift
@MainActor
@Test func computerMenuBarGroupedSnapshot() throws {
    let client = SupervisionClient(socketPath: NSTemporaryDirectory() + "unused-\(UUID().uuidString).sock")
    client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
    client.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
    client.apply(.sessionStarted(session: 2, harness: "Cursor", label: nil, pid: nil))
    client.apply(.windowClaimed(session: 2, harness: "Cursor", windowID: 11, app: "Terminal", title: "zsh", bounds: "0,0 800x600"))
    try assertSnapshot(
        ComputerUseMenuBarView(client: client, onOpenSession: { _ in }, openableSessionIDs: [1]),
        name: "computer-menu-bar",
        size: CGSize(width: 320, height: 220))
}

@MainActor
@Test func computerMenuBarEmptySnapshot() throws {
    let client = SupervisionClient(socketPath: NSTemporaryDirectory() + "unused-\(UUID().uuidString).sock")
    try assertSnapshot(
        ComputerUseMenuBarView(client: client, onOpenSession: { _ in }, openableSessionIDs: []),
        name: "computer-menu-bar-empty",
        size: CGSize(width: 320, height: 80))
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/ViewSnapshotTests 2>&1 | tail -5`
Expected: FAIL.

- [ ] **Step 3: Implement**

Replace `ComputerUseMenuBarView.swift`:

```swift
import SwiftUI

struct ComputerUseMenuBarView: View {
    let client: SupervisionClient
    var onOpenSession: (Int) -> Void // only called for rows where canOpen is true
    var openableSessionIDs: Set<Int>  // daemon sessions known to be 10x's own

    var body: some View {
        let groups = MenuBarPresentation.groups(sessions: client.sessions)
        if groups.isEmpty {
            Text("No windows in use")
                .font(TenXTypography.body(size: 12))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .padding(10)
        } else {
            ForEach(groups, id: \.harness) { group in
                Section(group.harness) {
                    ForEach(group.sessions) { session in
                        sessionRow(session)
                    }
                }
            }
            Divider()
            Button("Stop All Computer Use") { client.stopAll() }
                .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                .accessibilityLabel("Stop all computer use, all apps")
        }
        if !client.isConnected {
            Divider()
            Text("Daemon not running — starts on first use")
                .font(TenXTypography.mono(size: 9))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: ComputerSessionState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(session.label ?? "Session \(session.id)")
                    .font(TenXTypography.body(size: 12, weight: .semibold))
                if let status = session.status, !status.isEmpty {
                    Text(status)
                        .font(TenXTypography.mono(size: 9))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .lineLimit(1)
                }
                Spacer()
                if openableSessionIDs.contains(session.id) {
                    Button("Open") { onOpenSession(session.id) }
                }
                Button("Stop") { client.stopSession(session.id) }
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            }
            ForEach(session.windows) { window in
                Text("  \(window.app) — \(window.title)")
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .lineLimit(1)
            }
        }
    }
}
```

In `TenXApp.swift`, replace the MenuBarExtra content and binding:

```swift
        MenuBarExtra(isInserted: computerMenuBinding) {
            ComputerUseMenuBarView(
                client: model.supervision,
                onOpenSession: { daemonSession in model.openSession(forDaemonSession: daemonSession) },
                openableSessionIDs: model.openableDaemonSessionIDs)
        } label: {
            Label("10x Computer", systemImage: "display")
        }
```

```swift
    private var computerMenuBinding: Binding<Bool> {
        Binding(
            get: { model.supervision.hasAnyActivity || model.supervision.isConnected },
            set: { _ in }) // insertion is state-driven; nothing to do on removal
    }
```

In `AppModel`: `openableDaemonSessionIDs` = the active session's `computerUse.daemonSessionID` (when correlated); `openSession(forDaemonSession:)` is a no-op when the id isn't ours (foreign harness rows simply don't get Open — the view handles that via the set).

- [ ] **Step 4: Record snapshots, run**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/ViewSnapshotTests 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/ComputerUse/ComputerUseMenuBarView.swift App/TenXApp.swift App/Application/AppModel.swift Tests/TenXAppTests
git commit -m "feat(computer-use): menu bar panel grouped by harness with global stop"
```

---

### Task 11: ⇧⌘C command

**Files:**
- Modify: `App/TenXApp.swift`
- Modify: `App/Application/AppModel.swift`
- Test: `Tests/TenXAppTests/AppModelNavigationTests.swift` (extend)

- [ ] **Step 1: Write the failing test**

A live send needs a running omp, so the unit surface is the guard plus the disabled state:

```swift
@MainActor
@Test func beginComputerUseWithoutActiveSessionIsNoop() async {
    let model = AppModel()
    await model.beginComputerUse() // must not crash; nothing to send to
    #expect(model.activeSession == nil)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/AppModelNavigationTests 2>&1 | tail -5`
Expected: FAIL — `beginComputerUse` does not exist.

- [ ] **Step 3: Implement**

In `AppModel`:

```swift
    /// ⇧⌘C — point the active session at the computer tools. The MCP mount is
    /// user-level (Task 12), so every omp session already has the tools; the
    /// command is the agent's cue to use them.
    func beginComputerUse() async {
        guard let activeSession, activeSession.isComposerAvailable else { return }
        activeSession.draft = "Use the computer: claim a window with computer_claim (or launch one with computer_launch), then work there. Set computer_status so I can follow along."
        await activeSession.sendPrompt()
    }
```

In `TenXApp.swift`, add to the `WindowGroup` scene:

```swift
        .commands {
            CommandGroup(after: .newItem) {
                Button("Use Computer") {
                    Task { await model.beginComputerUse() }
                }
                .keyboardShortcut("c", modifiers: [.shift, .command])
                .disabled(model.activeSession?.isComposerAvailable != true)
            }
        }
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/AppModelNavigationTests 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/TenXApp.swift App/Application/AppModel.swift Tests/TenXAppTests
git commit -m "feat(computer-use): shift-command-c invokes computer use"
```

---

### Task 12: Install, MCP mount, and settings

**Files:**
- Create: `scripts/install_computer.sh`
- Create: `App/ComputerUse/ComputerUseInstaller.swift`
- Replace: `App/Settings/ComputerUseSetupModel.swift`
- Replace: `App/Settings/ComputerUseSettingsSection.swift`
- Test: `Tests/TenXAppTests/ComputerUseInstallerTests.swift`

Distribution (spec): the binary installs to `~/Library/Application Support/10x/tenx-computer`; omp mounts it via the user-level `~/.omp/agent/mcp.json` (research: no per-process mount exists in RPC mode; user config covers every omp session). Other harnesses get printed config snippets to copy.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import TenXApp

final class ComputerUseInstallerTests: XCTestCase {
    func test_mcpMount_mergesIntoExistingConfig() throws {
        let dir = NSTemporaryDirectory() + "tenx-install-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let configPath = dir + "/mcp.json"
        try #"{"mcpServers":{"other":{"command":"/usr/bin/other"}}}"#.write(toFile: configPath, atomically: true, encoding: .utf8)

        let installer = ComputerUseInstaller(binaryPath: "/x/tenx-computer", ompConfigPath: configPath)
        try installer.ensureMounted()

        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let config = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let servers = config["mcpServers"] as! [String: Any]
        XCTAssertNotNil(servers["other"]) // preserved
        let entry = servers["tenx-computer"] as! [String: Any]
        XCTAssertEqual(entry["command"] as? String, "/x/tenx-computer")
        XCTAssertEqual(entry["args"] as? [String], ["mcp"])
    }

    func test_mcpMount_createsConfigWhenMissing() throws {
        let dir = NSTemporaryDirectory() + "tenx-install-\(UUID().uuidString)"
        let configPath = dir + "/mcp.json"
        let installer = ComputerUseInstaller(binaryPath: "/x/tenx-computer", ompConfigPath: configPath)
        try installer.ensureMounted()
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath))
    }

    func test_mcpMount_isIdempotent() throws {
        let dir = NSTemporaryDirectory() + "tenx-install-\(UUID().uuidString)"
        let configPath = dir + "/mcp.json"
        let installer = ComputerUseInstaller(binaryPath: "/x/tenx-computer", ompConfigPath: configPath)
        try installer.ensureMounted()
        let first = try String(contentsOfFile: configPath)
        try installer.ensureMounted()
        XCTAssertEqual(first, try String(contentsOfFile: configPath))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/ComputerUseInstallerTests 2>&1 | tail -5`
Expected: FAIL — `ComputerUseInstaller` does not exist.

- [ ] **Step 3: Implement**

`scripts/install_computer.sh`:

```bash
#!/bin/bash
# Builds tenx-computer and installs it where the app and MCP configs expect it.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="$HOME/Library/Application Support/10x"
mkdir -p "$DEST"
(cd ComputerKit && swift build -c release)
cp "ComputerKit/.build/release/tenx-computer" "$DEST/tenx-computer"
echo "installed: $DEST/tenx-computer"
```

`App/ComputerUse/ComputerUseInstaller.swift`:

```swift
import Foundation

struct ComputerUseInstaller {
    static let installPath = NSHomeDirectory() + "/Library/Application Support/10x/tenx-computer"
    static let defaultOmpConfigPath = NSHomeDirectory() + "/.omp/agent/mcp.json"

    let binaryPath: String
    let ompConfigPath: String

    init(binaryPath: String = ComputerUseInstaller.installPath,
         ompConfigPath: String = ComputerUseInstaller.defaultOmpConfigPath) {
        self.binaryPath = binaryPath
        self.ompConfigPath = ompConfigPath
    }

    var isInstalled: Bool { FileManager.default.fileExists(atPath: binaryPath) }

    /// Merge (never clobber) the tenx-computer entry into omp's user MCP config.
    func ensureMounted() throws {
        let url = URL(fileURLWithPath: ompConfigPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = existing
        }
        var servers = config["mcpServers"] as? [String: Any] ?? [:]
        let entry: [String: Any] = ["command": binaryPath, "args": ["mcp"]]
        if let existing = servers["tenx-computer"] as? [String: Any],
           NSDictionary(dictionary: existing).isEqual(to: entry) { return } // idempotent
        servers["tenx-computer"] = entry
        config["mcpServers"] = servers
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
```

Replace `ComputerUseSetupModel.swift` with a small model: install state, selfcheck runner (`Process` on the installed binary with `selfcheck`, capture stdout/stderr, 30s timeout), and permission deep links (`x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture` / `?Privacy_Accessibility`). Replace `ComputerUseSettingsSection.swift` with rows: Install status (+ "Install / Reinstall" button running `scripts/install_computer.sh` via Process), "Run selfcheck" with output, permission deep links, and a "Stop all computer use" button calling `supervision.stopAll()`. Delete the Agent Desktop picker and helper instructions.

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/ComputerUseInstallerTests 2>&1 | tail -5`
Expected: PASS — 3 tests.

- [ ] **Step 5: Run the installer for real**

Run: `bash scripts/install_computer.sh && "$HOME/Library/Application Support/10x/tenx-computer" selfcheck`
Expected: `installed: …` then `selfcheck: OK` (after granting permissions when prompted).

- [ ] **Step 6: Commit**

```bash
git add scripts/install_computer.sh App/ComputerUse/ComputerUseInstaller.swift App/Settings Tests/TenXAppTests/ComputerUseInstallerTests.swift
git commit -m "feat(computer-use): installer, omp mcp mount, rewritten settings section"
```

---

### Task 13: Acceptance pass

**Files:**
- Modify: `docs/qa/computer-use-release-acceptance.md`

- [ ] **Step 1: Rewrite the acceptance checklist for the new model**

Replace the Agent Desktop steps with:

1. Fresh state: no daemon (`pkill tenx-computer`), no claims. Menu bar icon absent.
2. In a 10x session, press ⇧⌘C. Agent claims or launches a window. Verify: header metadata item appears; rail badge appears; overlay frame + tag on the window; menu bar icon appears listing the session under its harness.
3. While the agent works: type into the controlled window yourself — the agent continues (non-interrupting). Click the header item — popover shows a fresh frame and the agent's status.
4. Watch the cursor dot track actions on the overlay.
5. Stop from the header popover → claims release, overlay vanishes, badge clears.
6. Start computer use from Cursor (config snippet from settings) → the 10x menu bar lists the Cursor session; Stop from 10x kills Cursor's control (its next tool call errors).
7. Global: menu bar "Stop All Computer Use" and ⌃⌥⌘Esc each stop everything, all harnesses.
8. `tenx-computer selfcheck` passes; `stop-all` from a terminal works with no app running.

- [ ] **Step 2: Execute the checklist manually; record results in the doc**

- [ ] **Step 3: Full suite green**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' 2>&1 | tail -10` and `(cd ComputerKit && swift test)`
Expected: everything passes.

- [ ] **Step 4: Commit**

```bash
git add docs/qa/computer-use-release-acceptance.md
git commit -m "docs(computer-use): acceptance checklist for shared-window computer use"
```

---

## Self-review notes (resolved before commit of this plan)

- **Spec coverage:** overlay (T9), header item (T7), rail badge (T8), popover (T7), menu bar + global shut-off (T10), command (T11), settings (T12), MCP mount for omp (T12), other-harness configs (T12 snippets + spec), deletion of the old model (T5), acceptance (T13). Cursor/Codex/Claude Code config snippets live in the spec's resolved-verifications section; settings links to them.
- **Correlation without process lineage:** per-session chrome keys off the transcript's own `window_id`s; daemon session ids attach via matching `windowClaimed` events (T5/T6). Ceiling noted: two 10x sessions claiming the *same* window is impossible (daemon exclusivity), so window-id correlation is unambiguous.
- **Harness label ceiling:** 10x-spawned omp sessions report `clientInfo.name == "omp"`, so the menu bar groups them as "omp", not "10x". Fixing that needs omp to set a custom client name per launch — flagged as a follow-up, not V1.

# 10x Agent Desktop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add opt-in, per-session computer use to 10x with layered Agent Desktop isolation, observable evidence, explicit foreground handoff, and an immediate Stop path.

**Architecture:** 10x remains a host and coordinator: OMP executes every model-authored desktop action, while a `ComputerUseController` owns authorization and lifecycle and an `AgentDesktopCoordinator` owns helper selection, dedicated-window manifests, and conservative cleanup. SwiftUI observes a small state machine, renders OMP's existing computer results including images, and answers the typed foreground-handoff contract implemented by the prerequisite OMP plan.

**Tech Stack:** macOS 15+, Swift 6.1, SwiftUI, Observation, AppKit, OmpKit RPC v2, Swift Testing, AeroSpace CLI, Hammerspoon CLI

**Spec:** `docs/superpowers/specs/2026-08-25-computer-use-agent-desktop-design.md`

## Global Constraints

- Platform is macOS 15+, Swift 6.1, SwiftUI; integration baseline is OMP 18.0.4 and RPC protocol v2.
- Complete focus-isolation requires the OMP `set_computer_use` and `computer_foreground_handoff` contract from `2026-08-25-omp-computer-foreground-handoff.md`.
- Computer use starts Off for every session and is enabled only by an explicit session action.
- Only one computer-enabled 10x session may hold the cross-process lease per Mac.
- Automatic provider order is AeroSpace, Hammerspoon, then Background Only.
- No automatic helper installation, unconfirmed helper configuration edits, SIP changes, private Space APIs, VM, or second automation engine.
- Provider subprocesses use an executable URL plus fixed argument arrays, a bounded timeout, validated JSON, and no shell evaluation.
- Never automatically focus a workspace, raise a window, switch a desktop, move the pointer, or type into the user's active application.
- Prefer new process instances or new windows and claim only window IDs absent from the before snapshot.
- Existing windows are borrowed only when the user's request explicitly requires them; borrowed windows are never moved, closed, or restored.
- Stop is idempotent, denies pending handoff, aborts active control, disables OMP computer use, conservatively releases owned resources, and releases the lease.
- Errors use `[Module:Function] Description — {sanitized context}` and do not expose private window titles, paths, scripts, or screen content.
- App and test files are explicitly generated into `10x.xcodeproj`; run `ruby scripts/generate_xcodeproj.rb` after adding Swift files.
- Verify builds from Release configuration; port 3000 is not used.

---

## Dependency order

```text
OMP foreground-handoff release/local build
                    |
                    v
OmpKit contract -> lifecycle + lease -> provider + manifest
                    |                         |
                    +----------+--------------+
                               v
                    SessionController integration
                         |       |       |
                         v       v       v
                      setup   tool UI  handoff/Stop
                               |
                               v
                      Release acceptance
```

## File map

| File or directory | Responsibility |
|---|---|
| `OmpKit/Sources/OmpKit/Wire/RpcCommand.swift` | Typed computer-use RPC commands and foreground response |
| `OmpKit/Sources/OmpKit/Wire/RpcFrame.swift` | Typed host-tool call/cancel frames for Agent Desktop launch requests |
| `OmpKit/Tests/OmpKitTests/CommandEncodingTests.swift` | Wire encoding contract |
| `docs/contracts/rpc-wire-contract.md` | Version-gated OMP/10x RPC compatibility |
| `App/ComputerUse/ComputerUseState.swift` | UI-facing state, policy, readiness, and sanitized failure types |
| `App/ComputerUse/ComputerUseLease.swift` | Cross-process advisory file lock |
| `App/ComputerUse/ComputerUseController.swift` | Per-session lifecycle and idempotent Stop |
| `App/ComputerUse/ComputerUseRegistry.swift` | Same-process one-enabled-session invariant |
| `App/ComputerUse/AgentDesktopProvider.swift` | Provider protocol and capability value types |
| `App/ComputerUse/AgentDesktopCoordinator.swift` | Selection, probing, manifest lifecycle, and cleanup |
| `App/ComputerUse/AgentDesktopCommandRunner.swift` | Bounded fixed-argv process execution |
| `App/ComputerUse/AgentDesktopProbeWindow.swift` | Non-key, disposable owned window for per-session capture/input verification |
| `App/ComputerUse/AeroSpaceProvider.swift` | AeroSpace discovery, window snapshots, and non-focusing moves |
| `App/ComputerUse/HammerspoonProvider.swift` | Versioned user-installed 10x integration bridge |
| `App/Resources/Hammerspoon/tenx.lua` | Auditable version-1 integration template installed only by explicit user action |
| `App/ComputerUse/BackgroundProvider.swift` | No-workspace safe fallback |
| `App/ComputerUse/AgentDesktopManifest.swift` | Ephemeral owned/borrowed window and process records |
| `App/ComputerUse/DedicatedWindowLauncher.swift` | Before/launch/after window diff and claims |
| `App/ComputerUse/AgentDesktopHostTool.swift` | OMP host-tool definition, call routing, cancellation, and result frames |
| `App/Settings/ComputerUseSetupModel.swift` | Setup probe orchestration and persisted preference |
| `App/Settings/ComputerUseSettingsSection.swift` | Specialized setup UI above generated rows |
| `App/Tools/ComputerToolPresentation.swift` | Parse OMP output, image blocks, screenshots, and capabilities |
| `App/Tools/ComputerToolCardView.swift` | Dedicated card and screenshot gallery |
| `App/ExtensionUI/ComputerHandoffCardView.swift` | Blocking approve/cancel UI |
| `App/ComputerUse/ComputerUseMenuBarView.swift` | Active target and emergency Stop |
| `App/ComputerUse/GlobalEmergencyShortcut.swift` | Carbon global hot-key registration that invokes the same Stop path |
| `App/Sessions/SessionController.swift` | Connect RPC events to computer lifecycle |
| `App/Sessions/SessionHeaderView.swift` | Computer state, Enable, handoff status, and Stop |
| `App/TenXApp.swift` | Temporary menu bar scene and lifecycle fail-closed hooks |

### Task 1: OmpKit Computer RPC Contract and Version Gate

**Files:**
- Modify: `OmpKit/Sources/OmpKit/Wire/RpcCommand.swift`
- Modify: `OmpKit/Sources/OmpKit/Wire/RpcFrame.swift`
- Modify: `OmpKit/Tests/OmpKitTests/CommandEncodingTests.swift`
- Modify: `OmpKit/Tests/OmpKitTests/FrameDecodingTests.swift`
- Modify: `OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py`
- Modify: `docs/contracts/rpc-wire-contract.md`

**Interfaces:**
- Consumes: prerequisite OMP commands `set_computer_use`, `get_computer_use`, `probe_computer_use`, state field `computerUse`, and extension UI method `computer_foreground_handoff`.
- Produces: `ComputerForegroundPolicy`, `ComputerUseRPCState`, `ComputerCapabilities`, typed host-tool definitions/call frames, `RpcCommand.setComputerUse`, `RpcCommand.getComputerUse`, `RpcCommand.probeComputerUse`, `RpcCommand.setHostTools`, `RpcCommand.hostToolResult`, and `RpcCommand.computerForegroundHandoffResponse`.

- [ ] **Step 1: Write failing command-encoding tests**

```swift
@Test func computerUseCommandsEncodeTheForegroundPolicy() throws {
    let line = try RpcCommand.setComputerUse(
        enabled: true,
        foregroundPolicy: .requireHandoff
    ).encodedLine(id: "computer-1")
    let value = try JSONValue.decode(from: line)
    #expect(value["type"]?.stringValue == "set_computer_use")
    #expect(value["enabled"]?.boolValue == true)
    #expect(value["foregroundPolicy"]?.stringValue == "require-handoff")
    #expect(RpcCommand.getComputerUse().type == "get_computer_use")
    #expect(RpcCommand.probeComputerUse().type == "probe_computer_use")
}

@Test func agentDesktopHostToolFramesRemainCorrelated() throws {
    let frame = try RpcFrame.decode(line: Data(#"{"type":"host_tool_call","id":"host-1","toolCallId":"tool-1","name":"agent_desktop","arguments":{"action":"launch","application":"TextEdit"}}"#.utf8))
    guard case .hostToolCall(let call) = frame else {
        Issue.record("Expected host tool call")
        return
    }
    #expect(call.id == "host-1")
    #expect(call.name == "agent_desktop")
}
```

- [ ] **Step 2: Run OmpKit tests and confirm the command API is missing**

Run: `swift test --package-path OmpKit --filter computerUseCommandsEncodeTheForegroundPolicy`

Expected: FAIL at compile time because the new command factories do not exist.

- [ ] **Step 3: Add typed command and state values**

```swift
public enum ComputerForegroundPolicy: String, Sendable, Codable, Equatable {
    case allow
    case requireHandoff = "require-handoff"
}

public struct ComputerUseRPCState: Sendable, Equatable {
    public let enabled: Bool
    public let foregroundPolicy: ComputerForegroundPolicy

    public init(enabled: Bool, foregroundPolicy: ComputerForegroundPolicy) {
        self.enabled = enabled
        self.foregroundPolicy = foregroundPolicy
    }

    public init?(json: JSONValue?) {
        guard let enabled = json?["enabled"]?.boolValue,
              let rawPolicy = json?["foregroundPolicy"]?.stringValue,
              let policy = ComputerForegroundPolicy(rawValue: rawPolicy)
        else { return nil }
        self.enabled = enabled
        foregroundPolicy = policy
    }
}

public enum ComputerPermissionState: String, Sendable, Equatable {
    case granted
    case denied
    case unavailable
    case unknown
}

public struct ComputerCapabilities: Sendable, Equatable {
    public let backend: String
    public let capture: ComputerPermissionState
    public let input: ComputerPermissionState
    public let accessibility: ComputerPermissionState

    public init(
        backend: String,
        capture: ComputerPermissionState,
        input: ComputerPermissionState,
        accessibility: ComputerPermissionState
    ) {
        self.backend = backend
        self.capture = capture
        self.input = input
        self.accessibility = accessibility
    }

    public init?(json: JSONValue?) {
        guard let backend = json?["backend"]?.stringValue else { return nil }
        self.backend = backend
        capture = ComputerPermissionState(rawValue: json?["capturePermission"]?.stringValue ?? "") ?? .unknown
        input = ComputerPermissionState(rawValue: json?["inputPermission"]?.stringValue ?? "") ?? .unknown
        accessibility = ComputerPermissionState(rawValue: json?["axPermission"]?.stringValue ?? "") ?? .unknown
    }

    public var isReady: Bool {
        capture == .granted && input == .granted && accessibility == .granted
    }

    public static let unknown = ComputerCapabilities(
        backend: "unknown",
        capture: .unknown,
        input: .unknown,
        accessibility: .unknown)
}

public struct ComputerProbeResult: Sendable, Equatable {
    public let capabilities: ComputerCapabilities
    public let captureSucceeded: Bool
    public let backgroundInputSucceeded: Bool?

    public init?(json: JSONValue?) {
        guard let capabilities = ComputerCapabilities(json: json?["capabilities"]),
              let captureSucceeded = json?["captureSucceeded"]?.boolValue
        else { return nil }
        self.capabilities = capabilities
        self.captureSucceeded = captureSucceeded
        backgroundInputSucceeded = json?["backgroundInputSucceeded"]?.boolValue
    }
}
```

```swift
public static func setComputerUse(
    enabled: Bool,
    foregroundPolicy: ComputerForegroundPolicy
) -> RpcCommand {
    RpcCommand(type: "set_computer_use", fields: [
        "enabled": .bool(enabled),
        "foregroundPolicy": .string(foregroundPolicy.rawValue),
    ])
}

public static func getComputerUse() -> RpcCommand {
    RpcCommand(type: "get_computer_use")
}

public static func probeComputerUse(
    target: String? = nil,
    verificationText: String? = nil
) -> RpcCommand {
    var fields: [String: JSONValue] = [:]
    if let target { fields["target"] = .string(target) }
    if let verificationText { fields["verificationText"] = .string(verificationText) }
    return RpcCommand(type: "probe_computer_use", fields: fields)
}

public static func computerForegroundHandoffResponse(
    id: String,
    approved: Bool
) -> RpcCommand {
    extensionUIResponse(id: id, body: ["approved": .bool(approved)])
}
```

Add the existing OMP host-tool wire shapes to OmpKit instead of parsing generic events in views:

```swift
public struct HostToolDefinition: Sendable, Equatable {
    public let name: String
    public let description: String
    public let parameters: JSONValue

    public init(name: String, description: String, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct HostToolCall: Sendable, Equatable {
    public let id: String
    public let toolCallID: String
    public let name: String
    public let arguments: JSONValue
}

public enum RpcFrame {
    case hostToolCall(HostToolCall)
    case hostToolCancel(id: String, targetID: String)
}
```

Implement `setHostTools(_:)`, `hostToolUpdate(id:partialResult:)`, and `hostToolResult(id:result:isError:)` using OMP's documented correlation ID and content-array result shape. These are required for the model to request a dedicated window before calling `computer`.

- [ ] **Step 4: Add fixture coverage for supported and older OMP**

Teach `fake_server.py` to return `computerUse` and a fixed `ComputerProbeResult` (`captureSucceeded: true`, `backgroundInputSucceeded: true`) for `probe_computer_use` when launched with `--computer-contract`, and to return an unknown-command failure otherwise. Add integration assertions:

```swift
let response = try await client.send(.setComputerUse(
    enabled: true,
    foregroundPolicy: .requireHandoff))
#expect(ComputerUseRPCState(json: response.data) == ComputerUseRPCState(
    enabled: true,
    foregroundPolicy: .requireHandoff))
let probe = try await client.send(.probeComputerUse())
#expect(probe.data?["capabilities"]?["capturePermission"]?.stringValue == "granted")
let tools = try await client.send(.setHostTools([HostToolDefinition(
    name: "agent_desktop",
    description: "Launch a dedicated app window",
    parameters: .object(["type": .string("object")]))]))
#expect(tools.data?["toolNames"]?.arrayValue?.compactMap(\.stringValue) == ["agent_desktop"])
```

Provide the explicit public initializer used above.

- [ ] **Step 5: Document feature detection**

Add this rule to `rpc-wire-contract.md`:

```text
Complete Agent Desktop contract: get_state.data.computerUse parses and
set_computer_use(enabled, foregroundPolicy: require-handoff) succeeds.
Best-effort background mode: either signal is absent or the command returns an
unknown-command error. Best-effort mode must not display the non-interruption guarantee.
```

- [ ] **Step 6: Run OmpKit tests**

Run: `swift test --package-path OmpKit`

Expected: PASS.

- [ ] **Step 7: Commit the wire contract**

```bash
git add OmpKit/Sources/OmpKit/Wire/RpcCommand.swift OmpKit/Sources/OmpKit/Wire/RpcFrame.swift OmpKit/Tests/OmpKitTests/CommandEncodingTests.swift OmpKit/Tests/OmpKitTests/FrameDecodingTests.swift OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py docs/contracts/rpc-wire-contract.md
git commit -m "feat(ompkit): add computer use RPC contract"
```

### Task 2: Computer State Machine, Lease, and Same-Process Registry

**Files:**
- Create: `App/ComputerUse/ComputerUseState.swift`
- Create: `App/ComputerUse/ComputerUseLease.swift`
- Create: `App/ComputerUse/ComputerUseRegistry.swift`
- Create: `Tests/TenXAppTests/ComputerUseStateTests.swift`
- Create: `Tests/TenXAppTests/ComputerUseLeaseTests.swift`
- Create: `Tests/TenXAppTests/ComputerUseRegistryTests.swift`
- Modify: `scripts/generate_xcodeproj.rb` only if a new non-Swift resource is introduced; Swift files are globbed automatically.
- Regenerate: `10x.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: no earlier app task.
- Produces: `ComputerUsePhase`, `ComputerUseState`, `ComputerUseLease.acquire(sessionID:)`, and `ComputerUseRegistry.activate(_:stopPrevious:)`.

- [ ] **Step 1: Write failing state-transition tests**

```swift
@Test func computerUseTransitionsFailClosed() throws {
    var machine = ComputerUseStateMachine()
    try machine.transition(to: .preparing)
    try machine.transition(to: .ready)
    try machine.transition(to: .controlling(target: "TextEdit"))
    try machine.transition(to: .needsHandoff(target: "TextEdit", reason: "Background input unavailable"))
    try machine.transition(to: .ready)
    try machine.transition(to: .stopping)
    try machine.transition(to: .off)
    #expect(machine.phase == .off)
    #expect(throws: ComputerUseTransitionError.self) {
        try ComputerUseStateMachine().transition(to: .controlling(target: "Safari"))
    }
}
```

- [ ] **Step 2: Run the app tests and confirm the types are missing**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task2`

Expected: FAIL at compile time.

- [ ] **Step 3: Implement the explicit phase model**

```swift
enum ComputerUsePhase: Equatable, Sendable {
    case off
    case preparing
    case ready
    case controlling(target: String)
    case needsHandoff(target: String, reason: String)
    case unavailable(message: String, isBestEffortAvailable: Bool)
    case stopping
}

enum ComputerUseSafetyMode: Equatable, Sendable {
    case focusIsolated
    case legacyBestEffort
}

struct ComputerUseStateMachine: Sendable {
    private(set) var phase: ComputerUsePhase = .off

    mutating func transition(to next: ComputerUsePhase) throws {
        guard Self.isAllowed(from: phase, to: next) else {
            throw ComputerUseTransitionError.invalid(from: phase, to: next)
        }
        phase = next
    }

    private static func isAllowed(from: ComputerUsePhase, to: ComputerUsePhase) -> Bool {
        if case .stopping = to {
            if case .off = from { return false }
            return true
        }
        switch (from, to) {
        case (.off, .preparing),
             (.preparing, .ready),
             (.ready, .controlling(_)),
             (.controlling(_), .ready),
             (.controlling(_), .needsHandoff(_, _)),
             (.needsHandoff(_, _), .controlling(_)),
             (.needsHandoff(_, _), .ready),
             (.preparing, .needsHandoff(_, _)),
             (.preparing, .unavailable(_, _)),
             (.ready, .unavailable(_, _)),
             (.controlling(_), .unavailable(_, _)),
             (.stopping, .off):
            return true
        default:
            return false
        }
    }
}

enum ComputerUseTransitionError: Error {
    case invalid(from: ComputerUsePhase, to: ComputerUsePhase)
}
```

Allow only the diagrammed forward transitions plus any enabled state to `.stopping`, `.stopping` to `.off`, and `.preparing`/`.ready`/`.controlling` to `.unavailable`.

- [ ] **Step 4: Write failing lease contention and crash-release tests**

```swift
@Test func onlyOneLeaseOwnerCanHoldTheComputer() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let first = ComputerUseLease(directory: directory)
    let second = ComputerUseLease(directory: directory)
    try await first.acquire(sessionID: "session-a")
    await #expect(throws: ComputerUseLeaseError.self) {
        try await second.acquire(sessionID: "session-b")
    }
    await first.release()
    try await second.acquire(sessionID: "session-b")
}
```

- [ ] **Step 5: Implement the advisory lock**

Open `Application Support/10x/computer-use.lock` with `O_CREAT | O_RDWR`, call `flock(fd, LOCK_EX | LOCK_NB)`, and write only sanitized diagnostics:

```swift
struct ComputerUseLeaseOwner: Codable, Sendable {
    let processID: Int32
    let sessionID: String
}

actor ComputerUseLease {
    private var descriptor: Int32 = -1

    func acquire(sessionID: String) throws {
        guard descriptor == -1 else { return }
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ComputerUseLeaseError.openFailed }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw ComputerUseLeaseError.inUse
        }
        descriptor = fd
        try writeOwner(ComputerUseLeaseOwner(processID: getpid(), sessionID: sessionID))
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
}

enum ComputerUseLeaseError: Error {
    case openFailed
    case inUse
    case metadataWriteFailed
}
```

Do not treat file contents as ownership authority; only the live OS lock decides.

- [ ] **Step 6: Implement the same-process registry**

```swift
@MainActor
final class ComputerUseRegistry {
    private weak var active: ComputerUseStopping?

    func activate(
        _ candidate: ComputerUseStopping,
        stopPrevious: @MainActor (ComputerUseStopping) async -> Void
    ) async {
        if let active, active !== candidate { await stopPrevious(active) }
        active = candidate
    }

    func release(_ candidate: ComputerUseStopping) {
        if active === candidate { active = nil }
    }
}
```

Define `ComputerUseStopping: AnyObject` with `func stopComputerUse() async`.

- [ ] **Step 7: Regenerate the project and run tests**

Run:

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task2
```

Expected: PASS.

- [ ] **Step 8: Commit the lifecycle primitives**

```bash
git add App/ComputerUse Tests/TenXAppTests/ComputerUseStateTests.swift Tests/TenXAppTests/ComputerUseLeaseTests.swift Tests/TenXAppTests/ComputerUseRegistryTests.swift 10x.xcodeproj/project.pbxproj 10x.xcodeproj/xcshareddata/xcschemes/10x.xcscheme
git commit -m "feat(computer): add lifecycle and exclusive lease"
```

### Task 3: Provider Selection and Safe Helper Runner

**Files:**
- Create: `App/ComputerUse/AgentDesktopProvider.swift`
- Create: `App/ComputerUse/AgentDesktopCommandRunner.swift`
- Create: `App/ComputerUse/AeroSpaceProvider.swift`
- Create: `App/ComputerUse/HammerspoonProvider.swift`
- Create: `App/ComputerUse/BackgroundProvider.swift`
- Create: `App/ComputerUse/AgentDesktopCoordinator.swift`
- Create: `App/ComputerUse/AgentDesktopProbeWindow.swift`
- Create: `App/Resources/Hammerspoon/tenx.lua`
- Modify: `scripts/generate_xcodeproj.rb`
- Create: `Tests/TenXAppTests/AgentDesktopCommandRunnerTests.swift`
- Create: `Tests/TenXAppTests/AgentDesktopCoordinatorTests.swift`
- Create: `Tests/TenXAppTests/AgentDesktopProviderTests.swift`
- Create: `Tests/TenXAppTests/AgentDesktopProbeWindowTests.swift`
- Regenerate: `10x.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: no Task 2 implementation details.
- Produces: `AgentDesktopPreference`, `AgentDesktopProvider`, `AgentDesktopCoordinator.prepare(sessionToken:)`, and `AgentDesktopCommandRunning.run(executable:arguments:timeout:)`.

- [ ] **Step 1: Write failing provider-selection tests**

```swift
@Test func automaticSelectsTheFirstHealthyProvider() async throws {
    let aero = FakeProvider(kind: .aeroSpace, probe: .healthy)
    let hammer = FakeProvider(kind: .hammerspoon, probe: .healthy)
    let background = FakeProvider(kind: .background, probe: .healthy)
    let coordinator = AgentDesktopCoordinator(providers: [aero, hammer, background])

    let prepared = try await coordinator.prepare(
        preference: .automatic,
        sessionToken: "abc123")
    #expect(prepared.provider == .aeroSpace)
    #expect(aero.prepareCalls == ["abc123"])
    #expect(hammer.prepareCalls.isEmpty)
}

@Test func explicitUnhealthyProviderDoesNotSilentlyChangePreference() async throws {
    let coordinator = AgentDesktopCoordinator(providers: [
        FakeProvider(kind: .aeroSpace, probe: .missing),
        FakeProvider(kind: .background, probe: .healthy),
    ])
    let result = await coordinator.readiness(preference: .aeroSpace)
    #expect(result.preferredFailure != nil)
    #expect(result.backgroundFallbackAvailable)
}
```

- [ ] **Step 2: Write failing runner injection/timeout tests**

```swift
@Test func commandRunnerNeverInvokesAShell() async throws {
    let executable = fixtureExecutable("argv-printer")
    let output = try await AgentDesktopCommandRunner().run(
        executable: executable,
        arguments: ["window;touch /tmp/should-not-exist", "$(whoami)"],
        timeout: .seconds(1))
    #expect(output.json == .array([
        .string("window;touch /tmp/should-not-exist"),
        .string("$(whoami)"),
    ]))
    #expect(!FileManager.default.fileExists(atPath: "/tmp/should-not-exist"))
}

@MainActor @Test func probeWindowOrdersBehindWithoutTakingFocus() throws {
    let previouslyKey = NSApp.keyWindow
    let probe = AgentDesktopProbeWindow()
    let target = try probe.open()
    #expect(target.windowID.isEmpty == false)
    #expect(probe.window.isKeyWindow == false)
    #expect(NSApp.keyWindow === previouslyKey)
    probe.close()
}
```

- [ ] **Step 3: Run the tests and verify the provider layer is absent**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task3`

Expected: FAIL at compile time.

- [ ] **Step 4: Define the provider contract**

```swift
enum AgentDesktopProviderKind: String, Codable, Sendable, CaseIterable {
    case aeroSpace
    case hammerspoon
    case background
}

enum AgentDesktopPreference: String, Codable, Sendable, CaseIterable {
    case automatic
    case aeroSpace
    case hammerspoon
    case backgroundOnly
}

struct ProviderCapabilities: Sendable, Equatable {
    let canIsolate: Bool
    let canMoveWithoutFocus: Bool
    let canCaptureOffscreen: Bool
    let canInputInBackground: Bool
}

enum ProviderAvailability: Sendable, Equatable {
    case healthy
    case missing
    case incompatible
    case failed
}

struct ProviderProbe: Sendable, Equatable {
    let availability: ProviderAvailability
    let integrationVersion: String?
    let capabilities: ProviderCapabilities
}

protocol AgentDesktopProvider: Sendable {
    var kind: AgentDesktopProviderKind { get }
    func probe() async -> ProviderProbe
    func prepare(sessionToken: String) async throws -> PreparedAgentDesktop
    func listWindows() async throws -> [AgentWindow]
    func watchWindows() async throws -> AsyncStream<AgentWindowEvent>
    func move(windowID: String, to workspaceID: String) async throws
    func restore(windowID: String, to workspaceID: String) async throws
    func openVisibly(workspaceID: String) async throws
    func release(workspaceID: String) async
}

struct PreparedAgentDesktop: Sendable, Equatable {
    let provider: AgentDesktopProviderKind
    let workspaceID: String?
    let capabilities: ProviderCapabilities
}

struct AgentWindow: Sendable, Equatable {
    let id: String
    let processID: Int32
    let app: String
    let workspaceID: String?
}

enum AgentWindowEvent: Sendable, Equatable {
    case appeared(AgentWindow)
    case disappeared(id: String)
}
```

`ProviderProbe` carries `availability`, fixed integration version, and capabilities `canIsolate`, `canMoveWithoutFocus`, `canCaptureOffscreen`, and `canInputInBackground`.

- [ ] **Step 5: Implement a bounded fixed-argv runner**

Use `Process.executableURL` and `Process.arguments`; collect stdout/stderr with a 64 KiB cap; race termination against `Task.sleep(for:)`; terminate on timeout; decode a single JSON object or array; and return sanitized errors that include provider and exit status but not raw stdout/stderr.

```swift
protocol AgentDesktopCommandRunning: Sendable {
    func run(
        executable: URL,
        arguments: [String],
        timeout: Duration
    ) async throws -> AgentDesktopCommandOutput
}

struct AgentDesktopCommandOutput: Sendable, Equatable {
    let json: JSONValue
    let exitStatus: Int32
}
```

`AgentDesktopCoordinator` exposes these exact operations:

```swift
func prepare(
    preference: AgentDesktopPreference,
    sessionToken: String
) async throws -> PreparedAgentDesktop

@MainActor
func probePreparedWorkspace(
    _ prepared: PreparedAgentDesktop,
    probe: @escaping @Sendable (String, String) async throws -> ComputerProbeResult
) async throws -> ComputerProbeResult

func cleanup(manifest: AgentDesktopManifest) async -> CleanupReport
```

`probePreparedWorkspace` creates a borderless `NSPanel` containing one `NSTextField`, calls `orderBack(nil)` so it never becomes key, observes its window ID, moves it through the selected provider when a workspace exists, and passes the ID plus a random `10x-probe-<token>` string to the OMP closure. It verifies capture and background AX value delivery, closes the panel in `defer`, never focuses the workspace, and records a failed result for the handoff path.

```swift
@MainActor
final class AgentDesktopProbeWindow {
    struct Target: Sendable {
        let windowID: String
        let verificationText: String
    }

    private(set) var window: NSPanel

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 96),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        let field = NSTextField(string: "10x Agent Desktop probe")
        field.frame = NSRect(x: 20, y: 30, width: 280, height: 24)
        panel.contentView?.addSubview(field)
        window = panel
    }

    func open() throws -> Target {
        window.level = .normal
        window.collectionBehavior = [.transient]
        window.orderBack(nil)
        return Target(
            windowID: String(window.windowNumber),
            verificationText: "10x-probe-\(UUID().uuidString.lowercased())")
    }

    func close() { window.close() }
}
```

- [ ] **Step 6: Implement the three providers**

Use only these command families:

```swift
// AeroSpace
["list-windows", "--all", "--json"]
["move-node-to-workspace", "--window-id", windowID, workspaceID]

// Hammerspoon: fixed integration entry points, with values JSON-encoded first
["-c", "return hs.json.encode(tenx.probe())"]
["-c", "return hs.json.encode(tenx.listWindows())"]
["-c", fixedMoveInvocation(windowID: windowID, workspaceID: workspaceID)]
```

The AeroSpace workspace identifier is `10x-` plus a lowercase 12-character token validated by `^[a-z0-9-]+$`. Preparation never issues `workspace`, `focus`, or `move-workspace-to-monitor`; only `openVisibly` may issue `workspace <validated-id>`, and only after the user approves a foreground handoff. Its temporary watcher is an in-process diff of validated `list-windows` snapshots and never edits AeroSpace configuration. The Hammerspoon provider accepts only integration major version `1` and uses the bundled, auditable `tenx.lua` template's temporary `hs.window.filter` watcher; setup, not runtime, lets the user install that template and designate the native Space. The app never writes `~/.hammerspoon/init.lua`. `BackgroundProvider` observes window IDs through read-only Core Graphics window metadata, while `move`, `restore`, and `openVisibly` are no-ops and it reports `canIsolate = false`. Every watcher ends when its `AsyncStream` is cancelled.

`tenx.lua` exports only `probe`, `listWindows`, `startWatcher`, `moveWindow`, `restoreWindow`, `openSpace`, and `stopWatcher`, validates string IDs before calling Hammerspoon APIs, and sets `tenx.integrationVersion = "1.0.0"`. `openSpace` is the only entry point that calls `hs.spaces.gotoSpace`, and the provider invokes it only after user-approved handoff. Update `generate_xcodeproj.rb` to copy the `App/Resources/Hammerspoon` folder into the app bundle; runtime setup reads the template but never installs it automatically.

```ruby
hammerspoon = app_group.new_file("App/Resources/Hammerspoon")
hammerspoon.last_known_file_type = "folder"
app.resources_build_phase.add_file_reference(hammerspoon)
```

- [ ] **Step 7: Implement deterministic selection**

```swift
func candidates(for preference: AgentDesktopPreference) -> [AgentDesktopProviderKind] {
    switch preference {
    case .automatic: [.aeroSpace, .hammerspoon, .background]
    case .aeroSpace: [.aeroSpace]
    case .hammerspoon: [.hammerspoon]
    case .backgroundOnly: [.background]
    }
}
```

For explicit unhealthy providers, return readiness with an offered background fallback but do not invoke it until the user chooses the fallback action.

- [ ] **Step 8: Regenerate, test, and commit**

Run:

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task3
```

Expected: PASS.

```bash
git add App/ComputerUse App/Resources/Hammerspoon/tenx.lua scripts/generate_xcodeproj.rb Tests/TenXAppTests/AgentDesktopCommandRunnerTests.swift Tests/TenXAppTests/AgentDesktopCoordinatorTests.swift Tests/TenXAppTests/AgentDesktopProviderTests.swift Tests/TenXAppTests/AgentDesktopProbeWindowTests.swift 10x.xcodeproj/project.pbxproj 10x.xcodeproj/xcshareddata/xcschemes/10x.xcscheme
git commit -m "feat(computer): add layered desktop providers"
```

### Task 4: Dedicated Window Claims and Conservative Manifest Cleanup

**Files:**
- Create: `App/ComputerUse/AgentDesktopManifest.swift`
- Create: `App/ComputerUse/DedicatedWindowLauncher.swift`
- Create: `App/ComputerUse/AgentDesktopHostTool.swift`
- Modify: `App/ComputerUse/AgentDesktopCoordinator.swift`
- Create: `Tests/TenXAppTests/AgentDesktopManifestTests.swift`
- Create: `Tests/TenXAppTests/DedicatedWindowLauncherTests.swift`
- Create: `Tests/TenXAppTests/AgentDesktopHostToolTests.swift`
- Regenerate: `10x.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `AgentDesktopProvider.listWindows`, `move`, `restore`, and `PreparedAgentDesktop` from Task 3.
- Produces: `AgentDesktopManifest`, `DedicatedWindowLauncher.launch(_:in:)`, model-facing `AgentDesktopHostTool`, `borrow(windowID:)`, and conservative `cleanup()`.

- [ ] **Step 1: Write failing ownership-diff tests**

```swift
@Test func claimsOnlyWindowIDsCreatedAfterLaunch() async throws {
    let windows = WindowSnapshotSequence([
        [AgentWindow(id: "existing", processID: 7, app: "TextEdit")],
        [
            AgentWindow(id: "existing", processID: 7, app: "TextEdit"),
            AgentWindow(id: "new", processID: 9, app: "TextEdit"),
        ],
    ])
    let result = try await launcher(windows: windows).launch(
        AgentApplication(bundleIdentifier: "com.apple.TextEdit", strategy: .newInstance),
        in: preparedDesktop)
    #expect(result.ownedWindows.map(\.id) == ["new"])
    #expect(result.ownedWindows.allSatisfy { $0.id != "existing" })
}
```

- [ ] **Step 2: Write failing cleanup safety tests**

```swift
@Test func cleanupNeverMovesOrClosesBorrowedOrAmbiguousWindows() async {
    var manifest = AgentDesktopManifest(provider: .aeroSpace, workspaceID: "10x-abc")
    manifest.borrow(windowID: "auth-window")
    manifest.recordAmbiguous(application: "TextEdit")
    await coordinator.cleanup(manifest: manifest)
    #expect(provider.restoreCalls.isEmpty)
    #expect(launcher.closeCalls.isEmpty)
}
```

- [ ] **Step 3: Run tests and confirm the manifest API is missing**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task4`

Expected: FAIL at compile time.

- [ ] **Step 4: Implement ephemeral ownership records**

```swift
struct AgentOwnedWindow: Sendable, Equatable {
    let id: String
    let processID: Int32
    let originalWorkspaceID: String?

    init(_ window: AgentWindow) {
        id = window.id
        processID = window.processID
        originalWorkspaceID = window.workspaceID
    }
}

struct AgentDesktopManifest: Sendable, Equatable {
    let provider: AgentDesktopProviderKind
    let workspaceID: String?
    private(set) var ownedProcessIDs: Set<Int32> = []
    private(set) var ownedWindows: [AgentOwnedWindow] = []
    private(set) var borrowedWindowIDs: Set<String> = []
    private(set) var ambiguousApplications: Set<String> = []

    init(provider: AgentDesktopProviderKind, workspaceID: String?) {
        self.provider = provider
        self.workspaceID = workspaceID
    }

    init(prepared: PreparedAgentDesktop) {
        provider = prepared.provider
        workspaceID = prepared.workspaceID
    }

    mutating func borrow(windowID: String) {
        borrowedWindowIDs.insert(windowID)
    }

    mutating func recordAmbiguous(application: String) {
        ambiguousApplications.insert(application)
    }
}

enum AgentApplicationLaunchStrategy: Sendable {
    case newInstance
    case newWindow
}

struct AgentApplication: Sendable {
    let bundleIdentifier: String
    let strategy: AgentApplicationLaunchStrategy
}

struct WindowLaunchResult: Sendable {
    let processID: Int32
    let ownedWindows: [AgentOwnedWindow]
}

struct CleanupReport: Sendable, Equatable {
    let preservedApplicationNames: [String]
    let restoredWindowCount: Int
}
```

Keep the manifest in memory on `ComputerUseController`; do not add database or settings persistence.

- [ ] **Step 5: Implement before/launch/after claims**

```swift
let before = Set(try await provider.listWindows().map(\.id))
let events = try await provider.watchWindows()
let process = try await applicationLauncher.launch(application)
let after = try await waitForStableWindows(events: events, provider: provider, timeout: .seconds(5))
let created = after.filter { !before.contains($0.id) }
guard !created.isEmpty else { throw DedicatedWindowLaunchError.noNewWindow }
if let workspaceID = desktop.workspaceID {
    for window in created { try await provider.move(windowID: window.id, to: workspaceID) }
}
return WindowLaunchResult(
    processID: process.processIdentifier,
    ownedWindows: created.map(AgentOwnedWindow.init))
```

Use `NSWorkspace.openApplication(at:configuration:)` with `.createsNewApplicationInstance` for `.newInstance`. For `.newWindow`, send only the application's documented new-window action, then use the same ID diff. If more than one uncorrelated app window appears, mark the claim ambiguous and move none.

- [ ] **Step 6: Expose a narrow OMP host tool for model launch requests**

Register this exact tool contract only while computer use is enabled:

```swift
enum AgentDesktopHostTool {
    static let definition = HostToolDefinition(
        name: "agent_desktop",
        description: "Launch a dedicated app window before using computer. Prefer launch. Borrow an existing window only when the user's request explicitly requires its current authenticated or stateful contents.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object(["enum": .array([.string("launch"), .string("borrow")])]),
                "application": .object(["type": .string("string")]),
                "windowId": .object(["type": .string("string")]),
            ]),
            "required": .array([.string("action")]),
            "additionalProperties": .bool(false),
        ]))
}
```

`launch` resolves an installed application by bundle identifier or localized name, runs the before/watcher/launch/after flow, and returns only claimed window IDs plus sanitized app name. `borrow` requires a currently enumerated window ID, records it without moving it, and returns that ID. A host-tool cancel cancels the launch task; exactly one error result is sent and late completion is ignored.

Keep the provider watcher attached to the active manifest. A disappeared owned window removes only that ID; a disappeared borrowed window removes only its borrow marker. It never infers that another window from the same application is a replacement.

- [ ] **Step 7: Implement conservative cleanup**

Restore only owned windows whose IDs still exist and whose original workspace is known. V1 never closes an external window or terminates an app process because 10x does not have a trustworthy, cross-application dirty-document signal under the OMP permission identity. Leave all launched windows open, release ownership, and return a `CleanupReport` listing sanitized application names and restoration count. Borrowed and ambiguous windows receive no action.

```swift
for window in manifest.ownedWindows where liveWindowIDs.contains(window.id) {
    guard let originalWorkspaceID = window.originalWorkspaceID else { continue }
    try? await provider.restore(windowID: window.id, to: originalWorkspaceID)
}
return CleanupReport(
    preservedApplicationNames: sanitizedApplicationNames(for: manifest.ownedWindows),
    restoredWindowCount: manifest.ownedWindows.filter { $0.originalWorkspaceID != nil }.count)
```

- [ ] **Step 8: Regenerate, test, and commit**

Run:

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task4
```

Expected: PASS.

```bash
git add App/ComputerUse Tests/TenXAppTests/AgentDesktopManifestTests.swift Tests/TenXAppTests/DedicatedWindowLauncherTests.swift Tests/TenXAppTests/AgentDesktopHostToolTests.swift 10x.xcodeproj/project.pbxproj 10x.xcodeproj/xcshareddata/xcschemes/10x.xcscheme
git commit -m "feat(computer): claim dedicated agent windows"
```

### Task 5: Per-Session Controller and OMP Lifecycle Integration

**Files:**
- Create: `App/ComputerUse/ComputerUseController.swift`
- Modify: `App/Application/AppDependencies.swift`
- Modify: `App/Application/AppModel.swift`
- Modify: `App/Sessions/SessionController.swift`
- Modify: `OmpKit/Sources/OmpKit/SessionProcessManager.swift`
- Create: `Tests/TenXAppTests/ComputerUseControllerTests.swift`
- Modify: `Tests/TenXAppTests/SessionControllerTests.swift`
- Modify: `OmpKit/Tests/OmpKitTests/ProcessManagerTests.swift`
- Regenerate: `10x.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: RPC contract from Task 1, lease/registry from Task 2, coordinator/manifest from Tasks 3-4.
- Produces: `ComputerUseController.enable()`, `stopComputerUse()`, host-tool registration/routing, `handleToolStarted`, `handleToolEnded`, and observable `phase`.

- [ ] **Step 1: Write failing lifecycle tests with protocol fakes**

```swift
@MainActor @Test func enableAcquiresPreparesThenEnablesOMP() async throws {
    let log = CallLog()
    let controller = makeComputerController(log: log)
    await controller.enable()
    #expect(log.values == [
        "registry", "lease.acquire", "desktop.prepare", "omp.enable",
        "omp.host-tools", "omp.probe", "desktop.probe",
    ])
    #expect(controller.phase == .ready)
}

@MainActor @Test func failedEnableRollsBackInReverseOrder() async {
    let controller = makeComputerController(ompEnableError: TestError.failed)
    await controller.enable()
    #expect(controller.phase == .unavailable(
        message: "Computer use could not start",
        isBestEffortAvailable: false))
    #expect(controller.cleanupLog == ["desktop.release", "lease.release", "registry.release"])
}
```

- [ ] **Step 2: Write the Stop race test**

```swift
@MainActor @Test func concurrentStopsShareOneCleanup() async {
    let controller = makeEnabledComputerController()
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<3 { group.addTask { await controller.stopComputerUse() } }
    }
    #expect(controller.phase == .off)
    #expect(controller.ompDisableCount == 1)
    #expect(controller.desktopReleaseCount == 1)
    #expect(controller.leaseReleaseCount == 1)
}
```

- [ ] **Step 3: Run tests and confirm the controller is missing**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task5`

Expected: FAIL at compile time.

- [ ] **Step 4: Implement the controller with injected boundaries**

```swift
@MainActor
@Observable
final class ComputerUseController: ComputerUseStopping {
    private(set) var phase: ComputerUsePhase = .off
    private(set) var isolation: AgentDesktopProviderKind?
    private(set) var cleanupReport: CleanupReport?
    private(set) var safetyMode: ComputerUseSafetyMode = .focusIsolated
    private var stopTask: Task<Void, Never>?
    private var manifest: AgentDesktopManifest?

    func enable(safetyMode: ComputerUseSafetyMode = .focusIsolated) async {
        guard phase == .off else { return }
        self.safetyMode = safetyMode
        phase = .preparing
        do {
            var requiresHandoff = false
            await registry.activate(self) { await $0.stopComputerUse() }
            try await lease.acquire(sessionID: sessionID)
            let prepared = try await desktop.prepare(
                preference: safetyMode == .legacyBestEffort ? .backgroundOnly : preference(),
                sessionToken: sessionToken)
            manifest = AgentDesktopManifest(prepared: prepared)
            switch safetyMode {
            case .focusIsolated:
                let state = try await rpc.setComputerUse(enabled: true, policy: .requireHandoff)
                guard state.enabled else { throw ComputerUseError.ompUnavailable }
                let probe = try await desktop.probePreparedWorkspace(prepared) { target, text in
                    try await rpc.probeComputerUse(target: target, verificationText: text)
                }
                guard probe.capabilities.isReady else { throw ComputerUseError.permissionDenied }
                requiresHandoff = !probe.captureSucceeded
                    || probe.backgroundInputSucceeded != true
            case .legacyBestEffort:
                try await rpc.setLegacyComputerUse(enabled: true)
            }
            try await rpc.setHostTools([AgentDesktopHostTool.definition])
            phase = requiresHandoff
                ? .needsHandoff(
                    target: "Agent Desktop",
                    reason: "Background capture or input is unavailable")
                : .ready
        } catch {
            await rollbackEnable(error)
        }
    }

    func stopComputerUse() async {
        if let stopTask { await stopTask.value; return }
        let task = Task { @MainActor [weak self] in await self?.performStop() }
        stopTask = task
        await task.value
        stopTask = nil
    }
}

enum ComputerUseError: Error {
    case ompUnavailable
    case permissionDenied
    case providerUnavailable
}
```

`performStop` sets `.stopping`, denies handoff, sends `.abort()` when a computer call is live, waits for the tool end/turn boundary for at most 2 seconds, sends `set_computer_use(false, require-handoff)`, cleans the manifest, releases lease and registry, then sets `.off` in a `defer`-backed path.

- [ ] **Step 5: Add a narrow RPC client adapter**

Do not expose `RpcClient` to the provider layer:

```swift
protocol ComputerUseRPC: Sendable {
    func state() async throws -> ComputerUseRPCState
    func setComputerUse(
        enabled: Bool,
        policy: ComputerForegroundPolicy
    ) async throws -> ComputerUseRPCState
    func setLegacyComputerUse(enabled: Bool) async throws
    func probeComputerUse(
        target: String?,
        verificationText: String?
    ) async throws -> ComputerProbeResult
    func setHostTools(_ definitions: [HostToolDefinition]) async throws
    func sendHostToolResult(id: String, result: JSONValue, isError: Bool) async throws
    func abort() async throws
}
```

Have `SessionProcessManager.Handle` vend an adapter over its client. `setLegacyComputerUse` sends `/computer on` or `/computer off` through the existing `prompt` RPC and requires `agentInvoked == false`. Older OMP unknown-command failures map to `.legacyBestEffort`; `.focusIsolated` enablement must require `.requireHandoff` support. `.legacyBestEffort` is entered only from an explicit “Use best effort” action, uses `setLegacyComputerUse`, forces `BackgroundProvider`, and sets `safetyMode` so every session surface carries the warning.

- [ ] **Step 6: Integrate one controller per `SessionController`**

Add `private(set) var computerUse: ComputerUseController` and construct it from dependencies shared by `AppModel`. In `finishOpening`, call `computerUse.attach(rpc: handle.computerUseRPC, sessionPath:)` and reconcile `get_state.computerUse`; always leave a newly opened/reopened session `.off` by sending disable if OMP reports enabled.

After OMP enablement, register `AgentDesktopHostTool.definition`, call `probeComputerUse()` through the active RPC process, and require Screen Recording, input, and Accessibility capability results before moving to `.ready`. Ask `AgentDesktopCoordinator` to run its non-focusing prepared-workspace capture probe; record whether off-screen capture and background delivery are supported. A failed off-screen probe does not switch desktops: it records that the first relevant operation must enter `.needsHandoff`. Intercept `.hostToolCall`/`.hostToolCancel` in `SessionController.consumeEvents` and route only the exact `agent_desktop` name to the controller; unknown host tools receive one error result. Then route computer tool events by name:

```swift
if case .event(let type, let payload) = frame,
   payload["toolName"]?.stringValue == "computer" {
    switch type {
    case "tool_execution_start": computerUse.handleToolStarted(payload)
    case "tool_execution_end": computerUse.handleToolEnded(payload)
    default: break
    }
}
```

On Stop, send `set_host_tools([])` before disabling computer use so the model cannot start a new launch during cleanup. Disable with `set_computer_use` in `.focusIsolated` and `setLegacyComputerUse(false)` in `.legacyBestEffort`. On unexpected OMP exit, call `await computerUse.failClosed(reason: .ompExited)` before presenting recovery.

On `model_changed` or `config_update`, re-read computer state. If the active model no longer exposes `computer`, transition to `.unavailable`, unregister the host tool, and run Stop. When a computer tool result reports capture, input, or Accessibility permission loss, use the same fail-closed path and expose the matching System Settings action.

- [ ] **Step 7: Regenerate and run all tests**

Run:

```bash
ruby scripts/generate_xcodeproj.rb
swift test --package-path OmpKit
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task5
```

Expected: PASS.

- [ ] **Step 8: Commit the session lifecycle**

```bash
git add App/ComputerUse/ComputerUseController.swift App/Application/AppDependencies.swift App/Application/AppModel.swift App/Sessions/SessionController.swift OmpKit/Sources/OmpKit/SessionProcessManager.swift Tests/TenXAppTests/ComputerUseControllerTests.swift Tests/TenXAppTests/SessionControllerTests.swift OmpKit/Tests/OmpKitTests/ProcessManagerTests.swift 10x.xcodeproj/project.pbxproj 10x.xcodeproj/xcshareddata/xcschemes/10x.xcscheme
git commit -m "feat(computer): integrate per-session control"
```

### Task 6: Specialized Setup and Readiness UI

**Required skills for this UI task:** `writing-ui`, `visual-ui`

**Files:**
- Create: `App/Settings/ComputerUseSetupModel.swift`
- Create: `App/Settings/ComputerUseSettingsSection.swift`
- Modify: `App/Settings/SettingsView.swift`
- Modify: `App/Settings/SettingsViewModel.swift`
- Modify: `App/Settings/SettingsCatalog.swift`
- Modify: `App/Application/AppModel.swift`
- Create: `Tests/TenXAppTests/ComputerUseSetupModelTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Create: `Tests/TenXAppTests/ReferenceImages/computer-use-settings.png`
- Create: `Tests/TenXAppTests/ReferenceImages/computer-use-settings-degraded.png`
- Regenerate: `10x.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: provider probes from Task 3 and disposable OMP RPC computer state from Task 1.
- Produces: persisted `AgentDesktopPreference`, `ComputerUseReadiness`, harmless setup test, and settings actions.

- [ ] **Step 1: Write failing readiness-model tests**

```swift
@MainActor @Test func setupProbeUsesDisposableOMPAndNeverPersistsEnablement() async {
    let omp = FakeSetupOMP()
    let model = ComputerUseSetupModel(omp: omp, providers: fakeProviders)
    await model.runReadinessCheck()
    #expect(omp.commands == ["get", "enable", "probe", "disable"])
    #expect(model.readiness.ompContract == .complete)
    #expect(omp.didCreateSessionHistory == false)
}
```

- [ ] **Step 2: Run tests and verify the model is absent**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task6`

Expected: FAIL at compile time.

- [ ] **Step 3: Implement setup persistence and disposable probing**

Persist only this key in `UserDefaults`:

```swift
enum ComputerUsePreferenceStore {
    static let isolationKey = "computerUse.isolationPreference"
}

enum OmpComputerContract: Sendable, Equatable {
    case complete
    case legacyBestEffort
    case unavailable
}

struct ComputerUseReadiness: Sendable, Equatable {
    var ompContract: OmpComputerContract
    var capabilities: ComputerCapabilities
    var preferredProvider: ProviderProbe
    var backgroundFallbackAvailable: Bool
}
```

The probe starts the installed OMP with `RpcClientConfiguration.noSession = true`, calls `get_computer_use`, enables `require-handoff`, calls `probe_computer_use`, disables, and shuts down in `defer`. It invokes no prompt and creates no session history. Provider probes run separately.

- [ ] **Step 4: Implement setup actions without silent mutation**

Expose explicit actions:

```swift
enum ComputerUseSetupAction {
    case openScreenRecordingSettings
    case openAccessibilitySettings
    case showAeroSpaceInstructions
    case showHammerspoonInstructions
    case runHarmlessTest
}
```

System Settings actions open Apple's documented Privacy & Security URLs. Helper instruction actions show copyable commands/config text but do not execute installers or write configuration. The harmless test creates `AgentDesktopProbeWindow`, lists and moves it only when the user starts the test, calls `probe_computer_use(target:verificationText:)` through the disposable OMP process, restores it, and reports capture/input/AX/helper results individually.

- [ ] **Step 5: Build the specialized section above generated rows**

Use exact primary copy:

```swift
Text("Computer Use")
Text("Let this session verify work in dedicated app windows without taking over your desktop.")
Picker("Agent Desktop", selection: preferenceBinding) {
    Text("Automatic").tag(AgentDesktopPreference.automatic)
    Text("AeroSpace").tag(AgentDesktopPreference.aeroSpace)
    Text("Hammerspoon").tag(AgentDesktopPreference.hammerspoon)
    Text("Background Only").tag(AgentDesktopPreference.backgroundOnly)
}
Button("Run setup test") { Task { await model.runHarmlessTest() } }
```

Show OMP version/contract, Screen Recording, Accessibility, background input, helper version/health, and best-effort warning as separate rows. For an old OMP contract, explain “Background control may still interrupt your current app”; the explicit best-effort enable action belongs to the session header, not global settings. Filter `computer.enabled` from the editable generated controls and replace it with explanatory text: “10x enables this per session. New sessions always start off.” Leave other `computer.*` settings discoverable below.

Match the existing Settings section hierarchy, `TenXTypography`, `TenXPalette`, dividers, and control widths. Add no new shadow, radius, or button treatment; setup actions use `GhostActionStyle`. Long helper/version text must wrap without pushing controls outside the 760-point minimum window.

- [ ] **Step 6: Add accessibility and snapshot coverage**

Add deterministic snapshot models for complete and degraded readiness. Record and then compare:

```bash
RECORD_SNAPSHOTS=1 xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task6-record
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task6
```

Expected: both runs pass and both PNGs are inspected for readable labels, no clipped status, and a visible best-effort distinction.

- [ ] **Step 7: Regenerate and commit**

Run: `ruby scripts/generate_xcodeproj.rb`

```bash
git add App/Settings App/Application/AppModel.swift Tests/TenXAppTests/ComputerUseSetupModelTests.swift Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/ReferenceImages/computer-use-settings.png Tests/TenXAppTests/ReferenceImages/computer-use-settings-degraded.png 10x.xcodeproj/project.pbxproj 10x.xcodeproj/xcshareddata/xcschemes/10x.xcscheme
git commit -m "feat(settings): add computer use setup"
```

### Task 7: Computer Tool Evidence and Persisted Images

**Required skills for this UI task:** `writing-ui`, `visual-ui`

**Files:**
- Create: `App/Tools/ComputerToolPresentation.swift`
- Create: `App/Tools/ComputerToolCardView.swift`
- Modify: `App/Tools/ToolCardRegistry.swift`
- Modify: `App/Tools/ToolContentExtractor.swift`
- Modify: `App/Sessions/TranscriptView.swift`
- Modify: `App/Sessions/TranscriptHistoryMapper.swift`
- Modify: `App/Sessions/TranscriptReducer.swift`
- Create: `Tests/TenXAppTests/ComputerToolPresentationTests.swift`
- Modify: `Tests/TenXAppTests/ToolContentExtractorTests.swift`
- Modify: `Tests/TenXAppTests/TranscriptHistoryMapperTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Create: `Tests/TenXAppTests/ReferenceImages/computer-tool-card.png`
- Create: `Tests/TenXAppTests/ReferenceImages/computer-tool-gallery.png`
- Regenerate: `10x.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: raw `ToolPresentation.arguments` and `result` already preserved by live and history reducers.
- Produces: `ToolCardKind.computer`, `ComputerToolPresentation.init?(_:)`, and image gallery rendering.

- [ ] **Step 1: Write failing image/content extraction tests**

```swift
@Test func computerPresentationPreservesImagesAndCapabilities() throws {
    let tool = presentation(
        name: "computer",
        arguments: .object([
            "code": .string("await desktop.windows()[0].screenshot()"),
            "read_only": .bool(true),
        ]),
        result: .object([
            "content": .array([
                .object(["type": .string("text"), "text": .string("Captured TextEdit")]),
                .object([
                    "type": .string("image"),
                    "data": .string(onePixelPNGBase64),
                    "mimeType": .string("image/png"),
                ]),
            ]),
            "details": .object([
                "backend": .string("macos"),
                "capturePermission": .string("granted"),
                "inputPermission": .string("granted"),
                "axPermission": .string("granted"),
            ]),
        ]))
    let parsed = try #require(ComputerToolPresentation(tool))
    #expect(parsed.images.count == 1)
    #expect(parsed.isReadOnly)
    #expect(parsed.capabilities.capture == .granted)
}
```

- [ ] **Step 2: Add the persisted-history fixture test**

Append an image-bearing computer tool call/result to the test session fixture and assert:

```swift
let tool = try #require(items.compactMap(\.toolPresentation).first { $0.name == "computer" })
#expect(ComputerToolPresentation(tool)?.images.count == 1)
#expect(ComputerToolPresentation(tool)?.output == "Captured TextEdit")
```

- [ ] **Step 3: Run tests and confirm no dedicated presentation exists**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task7`

Expected: FAIL at compile time.

- [ ] **Step 4: Implement fail-closed parsing**

```swift
struct ComputerImage: Identifiable, Equatable {
    let id: String
    let data: Data
    let mimeType: String
}

struct ComputerToolPresentation: Equatable {
    let target: String?
    let output: String
    let code: String
    let isReadOnly: Bool
    let images: [ComputerImage]
    let capabilities: ComputerCapabilities

    init?(_ presentation: ToolPresentation) {
        guard presentation.name.lowercased() == "computer" else { return nil }
        code = presentation.arguments["code"]?.stringValue ?? ""
        isReadOnly = presentation.arguments["read_only"]?.boolValue == true
        output = ToolContentExtractor.outputText(presentation.result) ?? ""
        images = Self.decodeImages(presentation.result?["content"])
        capabilities = ComputerCapabilities(json: presentation.result?["details"])
            ?? .unknown
        target = presentation.result?["details"]?["screenshots"]?.arrayValue?.last?["target"]?.stringValue
    }
}
```

Accept only base64 image blocks with MIME `image/png` or `image/jpeg`, cap each decoded image at 20 MiB, and skip malformed blocks without dropping text output.

- [ ] **Step 5: Register and render the card**

Add `.computer` before generic matching, map only exact normalized name `computer`, and render `ComputerToolCardView`. The card shows state, target, mode, latest image, thumbnail gallery, output/return value, capability failures, and a collapsed `DisclosureGroup("Computer code")` plus raw details.

```swift
enum ToolCardKind: Equatable {
    case computer
    case read
    case bash
    case edit
    case write
    case search
    case task
    case todo
    case web
    case generic
}

if presentation.name.lowercased() == "computer" { return .computer }
```

```swift
case .computer:
    ComputerToolCardView(presentation: presentation)
```

Build the card on the existing `ToolCardScaffold` and disclosure behavior. Reuse `TenXPalette`, `TenXTypography`, and current tool-card spacing; add no separate card chrome. Give images a bounded maximum height and preserve the card's width at compact and wide transcript sizes.

Use `NSImage(data:)` and preserve aspect ratio. Do not write decoded images to a second archive.

- [ ] **Step 6: Record and inspect snapshots**

```bash
ruby scripts/generate_xcodeproj.rb
RECORD_SNAPSHOTS=1 xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task7-record
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task7
```

Expected: PASS; inspect the PNGs for correct image aspect ratio, keyboard-reachable gallery, readable capability failures, and collapsed code by default.

- [ ] **Step 7: Commit evidence rendering**

```bash
git add App/Tools App/Sessions/TranscriptView.swift App/Sessions/TranscriptHistoryMapper.swift App/Sessions/TranscriptReducer.swift Tests/TenXAppTests/ComputerToolPresentationTests.swift Tests/TenXAppTests/ToolContentExtractorTests.swift Tests/TenXAppTests/TranscriptHistoryMapperTests.swift Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/ReferenceImages/computer-tool-card.png Tests/TenXAppTests/ReferenceImages/computer-tool-gallery.png 10x.xcodeproj/project.pbxproj 10x.xcodeproj/xcshareddata/xcschemes/10x.xcscheme
git commit -m "feat(computer): render desktop verification evidence"
```

### Task 8: Foreground Handoff, Header Controls, Menu Bar Stop, and Fail-Closed Lifecycle

**Required skills for this UI task:** `writing-ui`, `visual-ui`

**Files:**
- Modify: `App/ExtensionUI/ExtensionUIState.swift`
- Modify: `App/ExtensionUI/ExtensionUIRouter.swift`
- Create: `App/ExtensionUI/ComputerHandoffCardView.swift`
- Modify: `App/Sessions/SessionController.swift`
- Modify: `App/Sessions/SessionHeaderView.swift`
- Modify: `App/Sessions/TranscriptView.swift`
- Create: `App/ComputerUse/ComputerUseMenuBarView.swift`
- Create: `App/ComputerUse/GlobalEmergencyShortcut.swift`
- Modify: `App/Application/AppModel.swift`
- Modify: `App/TenXApp.swift`
- Modify: `Tests/TenXAppTests/ExtensionUIRouterTests.swift`
- Modify: `Tests/TenXAppTests/SessionControllerTests.swift`
- Create: `Tests/TenXAppTests/GlobalEmergencyShortcutTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Create: `Tests/TenXAppTests/ReferenceImages/computer-handoff.png`
- Create: `Tests/TenXAppTests/ReferenceImages/computer-session-ready.png`
- Create: `Tests/TenXAppTests/ReferenceImages/computer-session-controlling.png`
- Regenerate: `10x.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: OMP extension UI method `computer_foreground_handoff` and `ComputerUseController` from Task 5.
- Produces: typed handoff state, single-operation approve/cancel, header enable/Stop, menu-bar Stop, emergency shortcut, and lock/sleep/helper failure shutdown.

- [ ] **Step 1: Write failing handoff parsing tests**

```swift
@Test func parsesComputerForegroundHandoff() throws {
    let request = ExtensionUIRequest(
        id: "handoff-1",
        method: "computer_foreground_handoff",
        payload: .object([
            "target": .string("TextEdit"),
            "action": .string("foreground-input"),
            "reason": .string("Background keyboard delivery is unavailable"),
        ]))
    #expect(ExtensionUIRouter.parse(request) == .computerHandoff(
        id: "handoff-1",
        target: "TextEdit",
        action: .foregroundInput,
        reason: "Background keyboard delivery is unavailable"))
}
```

- [ ] **Step 2: Write failing Stop-denies-handoff test**

```swift
@MainActor @Test func stopDeniesPendingHandoffBeforeAbort() async {
    let controller = makeSessionControllerWithPendingHandoff()
    await controller.computerUse.stopComputerUse()
    #expect(controller.sentCommands.prefix(2) == [
        .computerForegroundHandoffResponse(id: "handoff-1", approved: false),
        .abort(),
    ])
}
```

- [ ] **Step 3: Run tests and confirm handoff is unrecognized**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task8`

Expected: FAIL.

- [ ] **Step 4: Add typed handoff routing and one-shot response**

```swift
enum ComputerForegroundAction: String, Equatable {
    case foregroundInput = "foreground-input"
    case pointerMove = "pointer-move"
    case windowRaise = "window-raise"
    case accessibilityFocus = "accessibility-focus"
}

// ExtensionUIState
case computerHandoff(
    id: String,
    target: String,
    action: ComputerForegroundAction,
    reason: String)
```

Route it inline, set the computer phase to `.needsHandoff`, and respond with `computerForegroundHandoffResponse`. Approval first calls `desktop.openAgentDesktopVisibly()` from the selected provider, then sends `approved: true`; cancellation sends false. Remove the card after one response. Never auto-switch back.

```swift
func respondToComputerHandoff(_ state: ExtensionUIState, approved: Bool) async {
    guard case .computerHandoff(let id, _, _, _) = state else { return }
    if approved { await computerUse.openAgentDesktopVisibly() }
    try? await handle?.client.sendRaw(.computerForegroundHandoffResponse(
        id: id,
        approved: approved))
    computerUse.resolveHandoff(approved: approved)
    removeExtensionRequest(id: id)
}
```

- [ ] **Step 5: Build the handoff card and header controls**

Use exact actions and copy:

```swift
Button("Open Agent Desktop and Continue") { onApprove() }
Button("Cancel") { onCancel() }
```

The card states `“TextEdit needs foreground access because background keyboard delivery is unavailable.”` with the sanitized target/reason.

In `TranscriptView`, render `.computerHandoff` with `ComputerHandoffCardView`; keep all other extension UI states on `ApprovalCardView`.

Construct `ComputerHandoffCardView` with the existing `CornerCard` and `GhostActionStyle` used by `ApprovalCardView`. Reuse its keyboard-focus order and default/cancel shortcuts; do not add a modal, shadow, or new warning color token.

In `SessionHeaderView`, render the phase labels `Off`, `Preparing`, `Ready`, `Controlling`, `Needs handoff`, and `Unavailable`. Off with the complete contract shows `Enable Computer`; an older contract shows `Enable Best Effort` and invokes `enable(safetyMode: .legacyBestEffort)` only after its warning confirmation. Every enabled phase shows `Stop Computer`; best-effort Ready/Controlling also retains a visible `Best effort` badge. `Stop Computer` is not the response abort button and has accessibility label “Stop computer control for this session”.

- [ ] **Step 6: Add menu-bar and emergency Stop**

Expose `AppModel.activeComputerUse` and add a `MenuBarExtra` whose content exists only when phase is enabled:

```swift
MenuBarExtra(isInserted: computerMenuBinding) {
    ComputerUseMenuBarView(
        phase: model.activeComputerUse?.phase ?? .off,
        onStop: { Task { await model.activeComputerUse?.stopComputerUse() } })
} label: {
    Label("10x Computer", systemImage: "display")
}
```

Register Control-Option-Command-Escape with Carbon `RegisterEventHotKey`, not a SwiftUI app-only keyboard shortcut, so it works while another app is active. Wrap registration behind this interface and test registration/unregistration with a fake:

```swift
struct GlobalHotKeyToken: Sendable, Equatable {
    let id: UInt32
}

protocol GlobalHotKeyRegistering {
    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        handler: @escaping @Sendable () -> Void
    ) throws -> GlobalHotKeyToken
    func unregister(_ token: GlobalHotKeyToken)
}
```

Install it only while computer use is enabled, unregister it on every Stop/fail-closed path, and have the handler invoke `model.activeComputerUse?.stopComputerUse()` on `MainActor`. Neither the menu item nor hot key activates another app or desktop.

- [ ] **Step 7: Fail closed on lifecycle events**

Subscribe to `NSWorkspace.sessionDidResignActiveNotification`, `NSWorkspace.willSleepNotification`, `NSWorkspace.didTerminateApplicationNotification` for the selected helper PID, and `NSApplication.willTerminateNotification`. Each calls `failClosed`/Stop. App termination starts best-effort denial/child shutdown; the kernel closes the process's advisory-lock descriptor even if async cleanup cannot finish, so another 10x process is never left permanently blocked.

```swift
for name in [
    NSWorkspace.sessionDidResignActiveNotification,
    NSWorkspace.willSleepNotification,
] {
    lifecycleTokens.append(workspace.notificationCenter.addObserver(
        forName: name,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        Task { @MainActor in await self?.activeComputerUse?.failClosed(reason: .systemSuspended) }
    })
}
```

Do not add permission entitlements or unrelated usage-description keys. Screen Recording and Accessibility authorization remain explicit macOS System Settings grants to the actual OMP executable identity.

- [ ] **Step 8: Record and inspect UI states**

```bash
ruby scripts/generate_xcodeproj.rb
RECORD_SNAPSHOTS=1 xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task8-record
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task8
```

Expected: PASS; inspect header Ready/Controlling, handoff action hierarchy, keyboard focus, and Stop visibility.

- [ ] **Step 9: Commit safety controls**

```bash
git add App/ExtensionUI App/Sessions/SessionController.swift App/Sessions/SessionHeaderView.swift App/Sessions/TranscriptView.swift App/ComputerUse/ComputerUseMenuBarView.swift App/ComputerUse/GlobalEmergencyShortcut.swift App/Application/AppModel.swift App/TenXApp.swift Tests/TenXAppTests/ExtensionUIRouterTests.swift Tests/TenXAppTests/SessionControllerTests.swift Tests/TenXAppTests/GlobalEmergencyShortcutTests.swift Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/ReferenceImages/computer-handoff.png Tests/TenXAppTests/ReferenceImages/computer-session-ready.png Tests/TenXAppTests/ReferenceImages/computer-session-controlling.png 10x.xcodeproj/project.pbxproj 10x.xcodeproj/xcshareddata/xcschemes/10x.xcscheme
git commit -m "feat(computer): add handoff and emergency stop"
```

### Task 9: Release-Build End-to-End Acceptance

**Required skill for launching:** `launching-local-builds`

**Files:**
- Create: `docs/qa/computer-use-release-acceptance.md`
- Modify: implementation files only for defects that directly block this approved flow; add a failing regression test before each correction.

**Interfaces:**
- Consumes: complete OMP contract and Tasks 1-8.
- Produces: Release evidence and a pass/fail record for the non-interruption guarantee.

- [ ] **Step 1: Run static and automated verification from a clean branch**

```bash
git diff --check
swift test --package-path OmpKit
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-final-tests
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-release
```

Expected: all commands exit 0.

- [ ] **Step 2: Confirm the Release app is visible before testing**

Launch `/tmp/tenx-agent-desktop-release/Build/Products/Release/10x.app` using the `launching-local-builds` skill. Confirm the process is alive, the main window is visible, and the displayed build is the Release product from this branch.

- [ ] **Step 3: Test AeroSpace isolation while continuously typing elsewhere**

With AeroSpace selected, keep focus in an unrelated TextEdit document and type a unique repeating sentence while the agent:

```text
Launch a dedicated TextEdit window, write “10x Agent Desktop verification”,
capture the result, and report the screenshot without using my current window.
```

Pass only if the unrelated document receives every typed character, the pointer does not move, the current desktop never switches, no existing window moves, a new window ID is claimed, and the transcript contains the expected screenshot.

- [ ] **Step 4: Repeat with browser and Hammerspoon**

Select Hammerspoon, explicitly use the configured Agent Desktop, and run:

```text
Open a dedicated browser window to example.com, capture the page title and
screenshot, and leave my current browser window untouched.
```

Pass only with the same focus/pointer/window criteria. Record helper version, claimed window ID count, and screenshot evidence in the QA document without recording private titles or screen content.

- [ ] **Step 5: Test background fallback and old OMP gating**

With neither helper available, choose Background Only and repeat the TextEdit flow. Then point 10x at OMP 18.0.4 without the prerequisite contract. Pass only if the former is labeled Background Only and the latter clearly says Best effort and never displays the complete non-interruption guarantee.

- [ ] **Step 6: Exercise every fail-closed path**

Run and record these checks:

```text
1. Stop during active computer code: active call cancels, owned resources release once.
2. Deny handoff: no focus change and the tool call fails cleanly.
3. Approve handoff: Agent Desktop opens visibly, one operation runs, no auto-return.
4. Stop helper during control: active call aborts and re-enable is required.
5. Revoke Screen Recording or Accessibility: state becomes Unavailable and links to Settings.
6. Sleep/lock then resume: computer use is Off and requires explicit enablement.
7. Close an owned window: manifest drops only that ID.
8. Leave an owned document unsaved then Stop: window remains open and the report says so.
9. Reopen the session: computer use is Off, prior screenshots still render.
10. Use menu-bar and emergency shortcut Stop: both invoke the same cleanup path without focus change.
```

- [ ] **Step 7: Capture major UI evidence**

Capture Release screenshots for setup complete, setup degraded, Ready, Controlling, Needs handoff, computer evidence gallery, Unavailable, and cleanup report. Store sanitized images in the PR evidence location, not in the application transcript or a new runtime archive.

- [ ] **Step 8: Write the acceptance record**

Use this exact table in `docs/qa/computer-use-release-acceptance.md`:

```markdown
| Configuration | Build | Focus unchanged | Pointer unchanged | Existing windows unchanged | Evidence rendered | Result |
|---|---|---:|---:|---:|---:|---|
| AeroSpace | Release | Yes/No | Yes/No | Yes/No | Yes/No | PASS/FAIL |
| Hammerspoon | Release | Yes/No | Yes/No | Yes/No | Yes/No | PASS/FAIL |
| Background Only | Release | Yes/No | Yes/No | Yes/No | Yes/No | PASS/FAIL |
| Older OMP | Release | N/A | N/A | N/A | Best-effort label Yes/No | PASS/FAIL |
```

Replace each cell with observed evidence; no row may retain slash-separated alternatives.

- [ ] **Step 9: Commit acceptance evidence**

```bash
git add docs/qa/computer-use-release-acceptance.md
git commit -m "test(computer): record release acceptance"
```

## 10x completion gate

- [ ] The prerequisite OMP contract is in the OMP executable used by the Release build.
- [ ] New and reopened sessions start with computer use Off.
- [ ] Cross-process and same-process contention allow one controlling session only.
- [ ] Automatic selection is AeroSpace, Hammerspoon, Background Only; explicit unhealthy preferences require a user fallback choice.
- [ ] Provider commands use fixed argv, timeout, capped output, validated JSON, and no shell.
- [ ] Only new window IDs are claimed; borrowed/ambiguous windows are untouched.
- [ ] Denied handoff produces no focus-changing native call; approval is one-shot.
- [ ] Stop, helper exit, permission loss, lock, sleep, logout, and OMP exit converge on one idempotent fail-closed cleanup.
- [ ] Computer screenshots and details render live and after session reopen.
- [ ] Header, menu bar, and emergency shortcut invoke the same Stop path.
- [ ] AeroSpace, Hammerspoon, Background Only, and older-OMP Release checks are recorded.
- [ ] Any stolen focus, pointer movement, misplaced keystroke, moved existing window, or automatic desktop switch is a release failure.

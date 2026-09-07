# ComputerKit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `tenx-computer` — one dependency-free Swift binary that is both a stdio MCP server (for omp, Cursor, Codex, Claude Code) and a singleton daemon owning window claims, the session registry, and the supervision event stream.

**Architecture:** SwiftPM package `ComputerKit/` in the 10x repo (sibling of `OmpKit`), library target `ComputerKit` + executable target `TenXComputer` (binary name `tenx-computer`). MCP front speaks newline-delimited JSON-RPC over stdio; when a daemon is absent the front spawns it, then proxies stdio to the daemon's Unix socket. The daemon holds the engine (ScreenCaptureKit / CGEvent / AX / CGWindowList / NSWorkspace) behind a protocol so all registry/protocol logic is headless-testable with a fake engine. Spec: `docs/superpowers/specs/2026-09-07-computer-use-refinement-design.md`.

**Tech Stack:** Swift 6, SwiftPM, macOS 15, ScreenCaptureKit (`SCScreenshotManager`), CoreGraphics Event, ApplicationServices AX, Foundation POSIX sockets. No third-party dependencies.

**Working directory for all commands:** `/Users/tannerpham/CS Projects/.worktrees/10x-computer-use-design`

**Conventions:**
- Conventional commits (`feat(computerkit): …`, `test(computerkit): …`).
- `swift test` runs from `ComputerKit/`.
- Engine-touching code is never unit-tested against the real OS — only `selfcheck` (Task 11) touches real capture/input.

---

### Task 1: Package scaffold + JSONValue

**Files:**
- Create: `ComputerKit/Package.swift`
- Create: `ComputerKit/Sources/ComputerKit/Support/JSONValue.swift`
- Test: `ComputerKit/Tests/ComputerKitTests/JSONValueTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ComputerKit

final class JSONValueTests: XCTestCase {
    func test_roundTrip_preservesStructure() throws {
        let value: JSONValue = .object([
            "name": .string("computer_act"),
            "ok": .bool(true),
            "n": .number(42),
            "nothing": .null,
            "list": .array([.number(1), .string("two")]),
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func test_accessors() {
        let value: JSONValue = .object(["x": .number(3)])
        XCTAssertEqual(value["x"]?.doubleValue, 3)
        XCTAssertNil(value["missing"])
        XCTAssertNil(JSONValue.string("s")["x"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ComputerKit && swift test --filter JSONValueTests`
Expected: FAIL — package/targets do not exist yet.

- [ ] **Step 3: Write minimal implementation**

`ComputerKit/Package.swift`:

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ComputerKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ComputerKit", targets: ["ComputerKit"]),
        .executable(name: "tenx-computer", targets: ["TenXComputer"]),
    ],
    targets: [
        .target(name: "ComputerKit"),
        .executableTarget(
            name: "TenXComputer",
            dependencies: ["ComputerKit"],
            path: "Sources/tenx-computer"
        ),
        .testTarget(name: "ComputerKitTests", dependencies: ["ComputerKit"]),
    ]
)
```

Create empty `ComputerKit/Sources/tenx-computer/main.swift` (`print("tenx-computer")`) so the package builds.

`ComputerKit/Sources/ComputerKit/Support/JSONValue.swift`:

```swift
import Foundation

/// Minimal JSON value so MCP framing stays dependency-free and Equatable in tests.
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue {
    public subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var doubleValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    public var intValue: Int? { doubleValue.map(Int.init) }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    public var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ComputerKit && swift test --filter JSONValueTests`
Expected: PASS — `Test Suite 'JSONValueTests' passed`.

- [ ] **Step 5: Commit**

```bash
git add ComputerKit
git commit -m "feat(computerkit): scaffold package with a dependency-free JSON value"
```

---

### Task 2: MCP server dispatch (initialize / tools/list / tools/call routing)

**Files:**
- Create: `ComputerKit/Sources/ComputerKit/MCP/MCPMessages.swift`
- Create: `ComputerKit/Sources/ComputerKit/MCP/MCPServer.swift`
- Test: `ComputerKit/Tests/ComputerKitTests/MCPServerTests.swift`

MCP stdio transport is newline-delimited JSON-RPC 2.0 (no headers). This task covers message handling only; transport comes with the daemon/CLI tasks.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ComputerKit

final class MCPServerTests: XCTestCase {
    final class FakeToolProvider: MCPToolProviding {
        var tools: [MCPTool] = [
            MCPTool(name: "computer_ping", description: "test tool", inputSchema: .object(["type": .string("object")]))
        ]
        func callTool(name: String, arguments: JSONValue) throws -> MCPResult {
            .text("pong:\(name)")
        }
    }

    func makeServer() -> (MCPServer, FakeToolProvider) {
        let provider = FakeToolProvider()
        return (MCPServer(tools: provider), provider)
    }

    func test_initialize_advertisesToolsAndResources() throws {
        let (server, _) = makeServer()
        let response = try server.handle(method: "initialize", params: .object([
            "protocolVersion": .string("2025-06-18"),
            "clientInfo": .object(["name": .string("omp"), "version": .string("18.0.4")]),
        ]))
        XCTAssertEqual(response["serverInfo"]?["name"], .string("tenx-computer"))
        XCTAssertNotNil(response["capabilities"]?["tools"])
        XCTAssertNotNil(response["capabilities"]?["resources"])
        // clientInfo is surfaced so the daemon can label the session by harness
        XCTAssertEqual(server.clientName, "omp")
    }

    func test_toolsList_returnsProviderTools() throws {
        let (server, _) = makeServer()
        let response = try server.handle(method: "tools/list", params: nil)
        let tools = try XCTUnwrap(response["tools"]?.arrayValue)
        XCTAssertEqual(tools.first?["name"], .string("computer_ping"))
    }

    func test_toolsCall_routesToProvider() throws {
        let (server, _) = makeServer()
        let response = try server.handle(method: "tools/call", params: .object([
            "name": .string("computer_ping"), "arguments": .object([:]),
        ]))
        XCTAssertEqual(response["content"]?.arrayValue?.first?["text"], .string("pong:computer_ping"))
        XCTAssertEqual(response["isError"], .bool(false))
    }

    func test_unknownMethod_throwsMethodNotFound() {
        let (server, _) = makeServer()
        XCTAssertThrowsError(try server.handle(method: "nope/nope", params: nil)) { error in
            XCTAssertEqual((error as? MCPError)?.code, -32601)
        }
    }

    func test_notificationInitialized_returnsNil() throws {
        let (server, _) = makeServer()
        XCTAssertNil(try server.handle(method: "notifications/initialized", params: nil))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ComputerKit && swift test --filter MCPServerTests`
Expected: FAIL — `MCPServer` does not exist.

- [ ] **Step 3: Write minimal implementation**

`ComputerKit/Sources/ComputerKit/MCP/MCPMessages.swift`:

```swift
import Foundation

public struct MCPError: Error, Equatable {
    public let code: Int
    public let message: String
    public static func methodNotFound(_ method: String) -> MCPError { MCPError(code: -32601, message: "Method not found: \(method)") }
    public static func invalidParams(_ message: String) -> MCPError { MCPError(code: -32602, message: message) }
    public static func internalError(_ message: String) -> MCPError { MCPError(code: -32603, message: message) }
}

public struct MCPTool: Sendable, Equatable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue
    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public enum MCPResult: Sendable, Equatable {
    case text(String)
    case image(pngBase64: String, text: String)
}

public protocol MCPToolProviding {
    var tools: [MCPTool] { get }
    func callTool(name: String, arguments: JSONValue) throws -> MCPResult
}
```

`ComputerKit/Sources/ComputerKit/MCP/MCPServer.swift`:

```swift
import Foundation

public final class MCPServer {
    public static let protocolVersion = "2025-06-18"
    public private(set) var clientName: String?

    private let tools: MCPToolProviding
    private let resourceProvider: MCPResourceProviding?

    public init(tools: MCPToolProviding, resources: MCPResourceProviding? = nil) {
        self.tools = tools
        self.resourceProvider = resources
    }

    /// Returns the response payload, or nil for notifications.
    @discardableResult
    public func handle(method: String, params: JSONValue?) throws -> JSONValue? {
        switch method {
        case "initialize":
            clientName = params?["clientInfo"]?["name"]?.stringValue
            return .object([
                "protocolVersion": .string(Self.protocolVersion),
                "capabilities": .object([
                    "tools": .object([:]),
                    "resources": .object(["subscribe": .bool(false), "listChanged": .bool(false)]),
                ]),
                "serverInfo": .object(["name": .string("tenx-computer"), "version": .string(ComputerKitInfo.version)]),
            ])
        case "notifications/initialized", "notifications/cancelled":
            return nil
        case "ping":
            return .object([:])
        case "tools/list":
            return .object(["tools": .array(tools.tools.map { tool in
                .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "inputSchema": tool.inputSchema,
                ])
            })])
        case "tools/call":
            guard let name = params?["name"]?.stringValue else { throw MCPError.invalidParams("tools/call requires name") }
            let arguments = params?["arguments"] ?? .object([:])
            do {
                switch try tools.callTool(name: name, arguments: arguments) {
                case .text(let text):
                    return .object([
                        "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
                        "isError": .bool(false),
                    ])
                case .image(let pngBase64, let text):
                    return .object([
                        "content": .array([
                            .object(["type": .string("image"), "data": .string(pngBase64), "mimeType": .string("image/png")]),
                            .object(["type": .string("text"), "text": .string(text)]),
                        ]),
                        "isError": .bool(false),
                    ])
                }
            } catch let error as ComputerError {
                return .object([
                    "content": .array([.object(["type": .string("text"), "text": .string(error.message)])]),
                    "isError": .bool(true),
                ])
            }
        case "resources/list":
            return .object(["resources": .array(resourceProvider?.listResources() ?? [])])
        case "resources/read":
            guard let uri = params?["uri"]?.stringValue else { throw MCPError.invalidParams("resources/read requires uri") }
            guard let resourceProvider, let resource = resourceProvider.readResource(uri: uri) else {
                throw MCPError.invalidParams("Unknown resource: \(uri)")
            }
            return .object(["contents": .array([resource])])
        default:
            throw MCPError.methodNotFound(method)
        }
    }
}

public enum ComputerKitInfo {
    public static let version = "0.1.0"
}
```

`ComputerError` is defined in Task 3; for this task add a temporary definition at the bottom of `MCPMessages.swift` (Task 3 moves it to the engine file — move it then, delete from here):

```swift
public struct ComputerError: Error, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}
```

`MCPResourceProviding` is defined in Task 6; for this task add to `MCPMessages.swift` (Task 6 moves it):

```swift
public protocol MCPResourceProviding {
    func listResources() -> [JSONValue]
    func readResource(uri: String) -> JSONValue?
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ComputerKit && swift test --filter MCPServerTests`
Expected: PASS — 5 tests.

- [ ] **Step 5: Commit**

```bash
git add ComputerKit
git commit -m "feat(computerkit): mcp dispatch for initialize, tools, ping"
```

---

### Task 3: Engine protocol, types, and FakeEngine

**Files:**
- Create: `ComputerKit/Sources/ComputerKit/Engine/DesktopEngine.swift`
- Create: `ComputerKit/Tests/ComputerKitTests/Fakes/FakeEngine.swift`
- Test: `ComputerKit/Tests/ComputerKitTests/DesktopEngineContractTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ComputerKit

/// Pins the DesktopEngine contract against the fake so registry/tool tasks
/// never touch the real OS.
final class DesktopEngineContractTests: XCTestCase {
    func test_fake_listsWindowsAndClaimsNothingByDefault() {
        let engine = FakeEngine()
        engine.windows = [
            WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100),
        ]
        XCTAssertEqual(try engine.listWindows().map(\.appName), ["Safari"])
    }

    func test_fake_recordsActions() throws {
        let engine = FakeEngine()
        engine.windows = [WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)]
        try engine.act(.click(point: .init(x: 10, y: 10), button: .left), windowID: 10)
        XCTAssertEqual(engine.actions.count, 1)
    }

    func test_fake_screenshotReturnsStoredPNG() throws {
        let engine = FakeEngine()
        engine.screenshotPNG = Data([0x89, 0x50, 0x4E, 0x47])
        let shot = try engine.screenshot(windowID: 10)
        XCTAssertEqual(shot.pngData, Data([0x89, 0x50, 0x4E, 0x47]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ComputerKit && swift test --filter DesktopEngineContractTests`
Expected: FAIL — types do not exist.

- [ ] **Step 3: Write minimal implementation**

`ComputerKit/Sources/ComputerKit/Engine/DesktopEngine.swift`:

```swift
import CoreGraphics
import Foundation

public struct WindowInfo: Sendable, Equatable {
    public let id: CGWindowID
    public let appName: String
    public let title: String
    public let bounds: CGRect
    public let pid: pid_t
    public init(id: CGWindowID, appName: String, title: String, bounds: CGRect, pid: pid_t) {
        self.id = id
        self.appName = appName
        self.title = title
        self.bounds = bounds
        self.pid = pid
    }
}

public struct Screenshot: Sendable, Equatable {
    public let pngData: Data
    public let pixelSize: CGSize
    public let scale: Double
    public init(pngData: Data, pixelSize: CGSize, scale: Double) {
        self.pngData = pngData
        self.pixelSize = pixelSize
        self.scale = scale
    }
}

public enum MouseButton: String, Sendable, Equatable {
    case left, right
}

public enum ComputerAction: Sendable, Equatable {
    case click(point: CGPoint, button: MouseButton)
    case doubleClick(point: CGPoint)
    case drag(from: CGPoint, to: CGPoint)
    case scroll(deltaX: Double, deltaY: Double)
    case type(String)
    case key(String) // "cmd+s", "return", "shift+tab", …
}

/// The OS-touching surface. Only MacDesktopEngine implements this for real;
/// everything else in ComputerKit is tested against fakes.
public protocol DesktopEngine {
    func preflightPermissions() -> PermissionStatus
    func listWindows() throws -> [WindowInfo]
    func screenshot(windowID: CGWindowID) throws -> Screenshot
    func launch(app: String) throws -> WindowInfo
    func act(_ action: ComputerAction, window: WindowInfo) throws
}

public struct PermissionStatus: Sendable, Equatable {
    public let screenRecording: Bool
    public let accessibility: Bool
    public var isComplete: Bool { screenRecording && accessibility }
    public init(screenRecording: Bool, accessibility: Bool) {
        self.screenRecording = screenRecording
        self.accessibility = accessibility
    }
}
```

Move `ComputerError` here from `MCPMessages.swift` (delete the temporary copy there).

`ComputerKit/Tests/ComputerKitTests/Fakes/FakeEngine.swift`:

```swift
import Foundation
@testable import ComputerKit

final class FakeEngine: DesktopEngine {
    var windows: [WindowInfo] = []
    var screenshotPNG = Data()
    var actions: [ComputerAction] = []
    var permissionStatus = PermissionStatus(screenRecording: true, accessibility: true)
    var launchedWindow: WindowInfo?

    func preflightPermissions() -> PermissionStatus { permissionStatus }
    func listWindows() throws -> [WindowInfo] { windows }
    func screenshot(windowID: CGWindowID) throws -> Screenshot {
        Screenshot(pngData: screenshotPNG, pixelSize: CGSize(width: 100, height: 100), scale: 2)
    }
    func launch(app: String) throws -> WindowInfo {
        guard let launchedWindow else { throw ComputerError("no such app: \(app)") }
        windows.append(launchedWindow)
        return launchedWindow
    }
    func act(_ action: ComputerAction, window: WindowInfo) throws {
        actions.append(action)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ComputerKit && swift test --filter DesktopEngineContractTests`
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add ComputerKit
git commit -m "feat(computerkit): desktop engine protocol and test fake"
```

---

### Task 4: SessionRegistry — claims, sessions, harness labels

**Files:**
- Create: `ComputerKit/Sources/ComputerKit/Daemon/SessionRegistry.swift`
- Test: `ComputerKit/Tests/ComputerKitTests/SessionRegistryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ComputerKit

final class SessionRegistryTests: XCTestCase {
    let safari = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
    let terminal = WindowInfo(id: 11, appName: "Terminal", title: "zsh", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 200)

    func test_registerSession_labelsHarnessFromClientName() {
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "Cursor")
        XCTAssertEqual(registry.session(session)?.harness, "Cursor")
    }

    func test_claim_assignsWindowToSession() {
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        XCTAssertNoThrow(try registry.claim(safari, for: session))
        XCTAssertEqual(registry.owner(of: safari.id), session)
    }

    func test_claim_rejectsSecondClaimant_andNamesOwner() {
        let registry = SessionRegistry()
        let first = registry.registerSession(clientName: "omp")
        let second = registry.registerSession(clientName: "Cursor")
        try! registry.claim(safari, for: first)
        XCTAssertThrowsError(try registry.claim(safari, for: second)) { error in
            XCTAssertEqual((error as? ComputerError)?.message, "already_claimed: window owned by session 1 (omp)")
        }
    }

    func test_claim_sameSessionTwice_isIdempotent() {
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        try! registry.claim(safari, for: session)
        XCTAssertNoThrow(try registry.claim(safari, for: session))
        XCTAssertEqual(registry.claimedWindows(for: session).count, 1)
    }

    func test_releaseAll_forSession_leavesOtherSessions() {
        let registry = SessionRegistry()
        let first = registry.registerSession(clientName: "omp")
        let second = registry.registerSession(clientName: "Cursor")
        try! registry.claim(safari, for: first)
        try! registry.claim(terminal, for: second)
        registry.releaseAll(for: first)
        XCTAssertNil(registry.owner(of: safari.id))
        XCTAssertEqual(registry.owner(of: terminal.id), second)
    }

    func test_stopSession_revokesToolsAndReleasesClaims() {
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        try! registry.claim(safari, for: session)
        registry.stop(session)
        XCTAssertNil(registry.owner(of: safari.id))
        XCTAssertFalse(registry.isActive(session))
    }

    func test_windowClosed_autoReleasesClaim() {
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        try! registry.claim(safari, for: session)
        registry.windowClosed(safari.id)
        XCTAssertNil(registry.owner(of: safari.id))
    }

    func test_stopAll_releasesEverything() {
        let registry = SessionRegistry()
        let first = registry.registerSession(clientName: "omp")
        let second = registry.registerSession(clientName: "Cursor")
        try! registry.claim(safari, for: first)
        try! registry.claim(terminal, for: second)
        registry.stopAll()
        XCTAssertNil(registry.owner(of: safari.id))
        XCTAssertNil(registry.owner(of: terminal.id))
        XCTAssertFalse(registry.isActive(first))
        XCTAssertFalse(registry.isActive(second))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ComputerKit && swift test --filter SessionRegistryTests`
Expected: FAIL — `SessionRegistry` does not exist.

- [ ] **Step 3: Write minimal implementation**

`ComputerKit/Sources/ComputerKit/Daemon/SessionRegistry.swift`:

```swift
import CoreGraphics
import Foundation

public struct SessionID: Hashable, Sendable, CustomStringConvertible {
    public let raw: Int
    public var description: String { String(raw) }
}

public struct SessionInfo: Sendable, Equatable {
    public let id: SessionID
    public var harness: String
    public var status: String?
    public var isActive: Bool
}

/// Pure claim/session bookkeeping. Thread-safety lives in the daemon (Task 8);
/// this type is deliberately single-threaded value logic.
public final class SessionRegistry {
    public private(set) var sessions: [SessionID: SessionInfo] = [:]
    private var claims: [CGWindowID: SessionID] = [:]
    private var windows: [CGWindowID: WindowInfo] = [:]
    private var nextRawID = 0

    public init() {}

    @discardableResult
    public func registerSession(clientName: String?) -> SessionID {
        nextRawID += 1
        let id = SessionID(raw: nextRawID)
        sessions[id] = SessionInfo(id: id, harness: clientName ?? "unknown", status: nil, isActive: true)
        return id
    }

    public func session(_ id: SessionID) -> SessionInfo? { sessions[id] }

    public func isActive(_ id: SessionID) -> Bool { sessions[id]?.isActive ?? false }

    public func claim(_ window: WindowInfo, for session: SessionID) throws {
        guard isActive(session) else { throw ComputerError("session_stopped") }
        if let owner = claims[window.id] {
            if owner == session { return }
            let ownerInfo = sessions[owner]
            throw ComputerError("already_claimed: window owned by session \(owner) (\(ownerInfo?.harness ?? "unknown"))")
        }
        claims[window.id] = session
        windows[window.id] = window
    }

    public func owner(of windowID: CGWindowID) -> SessionID? { claims[windowID] }

    public func window(_ windowID: CGWindowID) -> WindowInfo? { windows[windowID] }

    public func claimedWindows(for session: SessionID) -> [WindowInfo] {
        claims.filter { $0.value == session }.compactMap { windows[$0.key] }
    }

    public func setStatus(_ status: String?, for session: SessionID) {
        sessions[session]?.status = status
    }

    public func setHarness(_ harness: String, for session: SessionID) {
        sessions[session]?.harness = harness
    }

    @discardableResult
    public func release(_ windowID: CGWindowID) -> Bool {
        claims.removeValue(forKey: windowID) != nil
    }

    public func releaseAll(for session: SessionID) {
        for (windowID, owner) in claims where owner == session {
            claims.removeValue(forKey: windowID)
        }
    }

    public func windowClosed(_ windowID: CGWindowID) {
        claims.removeValue(forKey: windowID)
        windows.removeValue(forKey: windowID)
    }

    public func stop(_ session: SessionID) {
        releaseAll(for: session)
        sessions[session]?.isActive = false
    }

    public func stopAll() {
        claims.removeAll()
        for id in sessions.keys { sessions[id]?.isActive = false }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ComputerKit && swift test --filter SessionRegistryTests`
Expected: PASS — 8 tests.

- [ ] **Step 5: Commit**

```bash
git add ComputerKit
git commit -m "feat(computerkit): session registry with exclusive window claims"
```

---

### Task 5: The seven computer tools

**Files:**
- Create: `ComputerKit/Sources/ComputerKit/Engine/ComputerTools.swift`
- Test: `ComputerKit/Tests/ComputerKitTests/ComputerToolsTests.swift`

Tools: `computer_windows`, `computer_screenshot`, `computer_status` (read-level); `computer_launch`, `computer_claim`, `computer_release`, `computer_act` (exec-level). Approval levels are *descriptions in the schema* — enforcement is the harness's approval mode (spec §MCP surface).

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ComputerKit

final class ComputerToolsTests: XCTestCase {
    let safari = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 100, y: 100, width: 800, height: 600), pid: 100)

    func makeTools() -> (ComputerTools, FakeEngine, SessionRegistry, SessionID) {
        let engine = FakeEngine()
        engine.windows = [safari]
        engine.screenshotPNG = Data([0x89, 0x50])
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        return (ComputerTools(engine: engine, registry: registry, session: session), engine, registry, session)
    }

    func test_windows_listsUnclaimedWithClaimedBy() throws {
        let (tools, _, _, _) = makeTools()
        let result = try tools.callTool(name: "computer_windows", arguments: .object([:]))
        guard case .text(let text) = result else { return XCTFail("expected text") }
        XCTAssertTrue(text.contains("Safari"))
        XCTAssertTrue(text.contains("\"id\":10") || text.contains("\"id\": 10"))
    }

    func test_claim_thenScreenshot_returnsImageContent() throws {
        let (tools, _, _, _) = makeTools()
        _ = try tools.callTool(name: "computer_claim", arguments: .object(["window_id": .number(10)]))
        let result = try tools.callTool(name: "computer_screenshot", arguments: .object(["window_id": .number(10)]))
        guard case .image(let pngBase64, let text) = result else { return XCTFail("expected image") }
        XCTAssertEqual(Data(base64Encoded: pngBase64), Data([0x89, 0x50]))
        XCTAssertTrue(text.contains("800"))
    }

    func test_screenshot_unclaimedWindow_errors() throws {
        let (tools, _, _, _) = makeTools()
        XCTAssertThrowsError(try tools.callTool(name: "computer_screenshot", arguments: .object(["window_id": .number(10)]))) { error in
            XCTAssertEqual((error as? ComputerError)?.message, "window_not_claimed: 10")
        }
    }

    func test_launch_autoClaimsToCaller() throws {
        let (tools, engine, registry, session) = makeTools()
        engine.launchedWindow = WindowInfo(id: 99, appName: "TextEdit", title: "Untitled", bounds: .init(x: 0, y: 0, width: 400, height: 300), pid: 300)
        let result = try tools.callTool(name: "computer_launch", arguments: .object(["app": .string("TextEdit")]))
        guard case .text(let text) = result else { return XCTFail("expected text") }
        XCTAssertTrue(text.contains("99"))
        XCTAssertEqual(registry.owner(of: 99), session)
    }

    func test_act_parsesClickToWindowRelativePoint() throws {
        let (tools, engine, _, _) = makeTools()
        _ = try tools.callTool(name: "computer_claim", arguments: .object(["window_id": .number(10)]))
        _ = try tools.callTool(name: "computer_act", arguments: .object([
            "window_id": .number(10),
            "action": .string("click"),
            "x": .number(50), "y": .number(60),
        ]))
        XCTAssertEqual(engine.actions, [.click(point: CGPoint(x: 50, y: 60), button: .left)])
    }

    func test_act_rejectsUnknownAction() throws {
        let (tools, _, _, _) = makeTools()
        _ = try tools.callTool(name: "computer_claim", arguments: .object(["window_id": .number(10)]))
        XCTAssertThrowsError(try tools.callTool(name: "computer_act", arguments: .object([
            "window_id": .number(10), "action": .string("teleport"),
        ]))) { error in
            XCTAssertEqual((error as? ComputerError)?.message, "invalid_action: teleport")
        }
    }

    func test_status_setsSessionStatus() throws {
        let (tools, _, registry, session) = makeTools()
        _ = try tools.callTool(name: "computer_status", arguments: .object(["status": .string("Running tests…")]))
        XCTAssertEqual(registry.session(session)?.status, "Running tests…")
    }

    func test_stoppedSession_cannotAct() throws {
        let (tools, _, registry, session) = makeTools()
        _ = try tools.callTool(name: "computer_claim", arguments: .object(["window_id": .number(10)]))
        registry.stop(session)
        XCTAssertThrowsError(try tools.callTool(name: "computer_act", arguments: .object([
            "window_id": .number(10), "action": .string("click"), "x": .number(1), "y": .number(1),
        ]))) { error in
            XCTAssertEqual((error as? ComputerError)?.message, "session_stopped")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ComputerKit && swift test --filter ComputerToolsTests`
Expected: FAIL — `ComputerTools` does not exist.

- [ ] **Step 3: Write minimal implementation**

`ComputerKit/Sources/ComputerKit/Engine/ComputerTools.swift`:

```swift
import CoreGraphics
import Foundation

/// Implements the seven-tool MCP surface for one harness session.
public final class ComputerTools: MCPToolProviding {
    private let engine: DesktopEngine
    private let registry: SessionRegistry
    private let session: SessionID

    public init(engine: DesktopEngine, registry: SessionRegistry, session: SessionID) {
        self.engine = engine
        self.registry = registry
        self.session = session
    }

    public var tools: [MCPTool] {
        let windowID: [String: JSONValue] = ["window_id": .object(["type": .string("number"), "description": .string("Window id from computer_windows")])]
        func schema(_ properties: [String: JSONValue], _ required: [String]) -> JSONValue {
            .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array(required.map(JSONValue.string)),
            ])
        }
        return [
            MCPTool(name: "computer_windows", description: "List visible windows: id, app, title, bounds, claimed-by.", inputSchema: schema([:], [])),
            MCPTool(name: "computer_screenshot", description: "Capture a claimed window. Returns an image plus size/scale for coordinate mapping.", inputSchema: schema(windowID, ["window_id"])),
            MCPTool(name: "computer_status", description: "Set the status text shown on your window tag (e.g. \"Running tests…\").", inputSchema: schema(["status": .object(["type": .string("string")])], ["status"])),
            MCPTool(name: "computer_launch", description: "Launch an application by name; its new window is claimed for you.", inputSchema: schema(["app": .object(["type": .string("string")])], ["app"])),
            MCPTool(name: "computer_claim", description: "Claim an existing window by id. Only one session may own a window.", inputSchema: schema(windowID, ["window_id"])),
            MCPTool(name: "computer_release", description: "Release a window you claimed.", inputSchema: schema(windowID, ["window_id"])),
            MCPTool(name: "computer_act", description: "Act on a claimed window at window-relative coordinates. action: click|double_click|right_click|drag|scroll|type|key.", inputSchema: schema([
                "window_id": windowID["window_id"]!,
                "action": .object(["type": .string("string")]),
                "x": .object(["type": .string("number")]),
                "y": .object(["type": .string("number")]),
                "to_x": .object(["type": .string("number")]),
                "to_y": .object(["type": .string("number")]),
                "delta_x": .object(["type": .string("number")]),
                "delta_y": .object(["type": .string("number")]),
                "text": .object(["type": .string("string")]),
                "keys": .object(["type": .string("string"), "description": .string("e.g. \"cmd+s\", \"return\"")]),
                "button": .object(["type": .string("string"), "description": .string("left|right")]),
            ], ["window_id", "action"])),
        ]
    }

    public func callTool(name: String, arguments: JSONValue) throws -> MCPResult {
        guard registry.isActive(session) else { throw ComputerError("session_stopped") }
        switch name {
        case "computer_windows":
            let items = try engine.listWindows().map { window -> JSONValue in
                var object: [String: JSONValue] = [
                    "id": .number(Double(window.id)),
                    "app": .string(window.appName),
                    "title": .string(window.title),
                    "bounds": .string("\(Int(window.bounds.minX)),\(Int(window.bounds.minY)) \(Int(window.bounds.width))x\(Int(window.bounds.height))"),
                ]
                if let owner = registry.owner(of: window.id), let info = registry.session(owner) {
                    object["claimed_by"] = .string("session \(owner) (\(info.harness))")
                }
                return .object(object)
            }
            let data = try JSONEncoder().encode(JSONValue.array(items))
            return .text(String(decoding: data, as: UTF8.self))

        case "computer_claim":
            let window = try windowArgument(arguments, mustBeClaimed: false)
            try registry.claim(window, for: session)
            return .text("claimed window \(window.id) (\(window.appName))")

        case "computer_release":
            let windowID = try windowIDArgument(arguments)
            guard registry.owner(of: windowID) == session else { throw ComputerError("window_not_claimed: \(windowID)") }
            registry.release(windowID)
            return .text("released window \(windowID)")

        case "computer_screenshot":
            let window = try claimedWindow(arguments)
            let shot = try engine.screenshot(windowID: window.id)
            return .image(
                pngBase64: shot.pngData.base64EncodedString(),
                text: "\(window.appName) window \(window.id) — \(Int(shot.pixelSize.width))x\(Int(shot.pixelSize.height))px @\(Int(shot.scale))x; window size \(Int(window.bounds.width))x\(Int(window.bounds.height))pt; coordinates for computer_act are window-relative points"
            )

        case "computer_status":
            guard let status = arguments["status"]?.stringValue else { throw MCPError.invalidParams("computer_status requires status") }
            registry.setStatus(String(status.prefix(80)), for: session)
            return .text("status set")

        case "computer_launch":
            guard let app = arguments["app"]?.stringValue else { throw MCPError.invalidParams("computer_launch requires app") }
            let window = try engine.launch(app: app)
            try registry.claim(window, for: session)
            return .text("launched \(app); claimed window \(window.id) (\(Int(window.bounds.width))x\(Int(window.bounds.height))pt)")

        case "computer_act":
            let window = try claimedWindow(arguments)
            let action = try parseAction(arguments)
            try engine.act(action, window: window)
            return .text("done")

        default:
            throw MCPError.methodNotFound(name)
        }
    }

    private func windowIDArgument(_ arguments: JSONValue) throws -> CGWindowID {
        guard let id = arguments["window_id"]?.intValue else { throw MCPError.invalidParams("requires window_id") }
        return CGWindowID(id)
    }

    private func windowArgument(_ arguments: JSONValue, mustBeClaimed: Bool) throws -> WindowInfo {
        let windowID = try windowIDArgument(arguments)
        guard let window = try engine.listWindows().first(where: { $0.id == windowID }) ?? registry.window(windowID) else {
            throw ComputerError("window_gone: \(windowID)")
        }
        if mustBeClaimed, registry.owner(of: windowID) != session {
            throw ComputerError("window_not_claimed: \(windowID)")
        }
        return window
    }

    private func claimedWindow(_ arguments: JSONValue) throws -> WindowInfo {
        try windowArgument(arguments, mustBeClaimed: true)
    }

    private func parseAction(_ arguments: JSONValue) throws -> ComputerAction {
        guard let action = arguments["action"]?.stringValue else { throw MCPError.invalidParams("computer_act requires action") }
        func point(_ x: String, _ y: String) throws -> CGPoint {
            guard let xValue = arguments[x]?.doubleValue, let yValue = arguments[y]?.doubleValue else {
                throw MCPError.invalidParams("\(action) requires \(x)/\(y)")
            }
            return CGPoint(x: xValue, y: yValue)
        }
        switch action {
        case "click":
            let button = arguments["button"]?.stringValue == "right" ? MouseButton.right : .left
            return .click(point: try point("x", "y"), button: button)
        case "double_click": return .doubleClick(point: try point("x", "y"))
        case "right_click": return .click(point: try point("x", "y"), button: .right)
        case "drag": return .drag(from: try point("x", "y"), to: try point("to_x", "to_y"))
        case "scroll":
            return .scroll(deltaX: arguments["delta_x"]?.doubleValue ?? 0, deltaY: arguments["delta_y"]?.doubleValue ?? 0)
        case "type":
            guard let text = arguments["text"]?.stringValue else { throw MCPError.invalidParams("type requires text") }
            return .type(text)
        case "key":
            guard let keys = arguments["keys"]?.stringValue else { throw MCPError.invalidParams("key requires keys") }
            return .key(keys)
        default:
            throw ComputerError("invalid_action: \(action)")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ComputerKit && swift test --filter ComputerToolsTests`
Expected: PASS — 8 tests.

- [ ] **Step 5: Commit**

```bash
git add ComputerKit
git commit -m "feat(computerkit): seven computer tools over engine and registry"
```

---

### Task 6: Screenshot resources

**Files:**
- Create: `ComputerKit/Sources/ComputerKit/MCP/MCPResources.swift`
- Test: `ComputerKit/Tests/ComputerKitTests/MCPResourcesTests.swift`

Exposes `computer://window/{id}/screenshot` for each claimed window (spec §Materials).

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ComputerKit

final class MCPResourcesTests: XCTestCase {
    func test_listsResourcesForClaimedWindows() {
        let engine = FakeEngine()
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        let window = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        try! registry.claim(window, for: session)
        let resources = ScreenshotResources(engine: engine, registry: registry)
        let list = resources.listResources()
        XCTAssertEqual(list.first?["uri"], .string("computer://window/10/screenshot"))
    }

    func test_readResource_returnsLatestCapture() {
        let engine = FakeEngine()
        engine.screenshotPNG = Data([1, 2, 3])
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        let window = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        try! registry.claim(window, for: session)
        let resources = ScreenshotResources(engine: engine, registry: registry)
        let resource = resources.readResource(uri: "computer://window/10/screenshot")
        XCTAssertEqual(resource?["mimeType"], .string("image/png"))
        XCTAssertEqual(resource?["blob"], .string(Data([1, 2, 3]).base64EncodedString()))
    }

    func test_readResource_unknownURI_returnsNil() {
        let resources = ScreenshotResources(engine: FakeEngine(), registry: SessionRegistry())
        XCTAssertNil(resources.readResource(uri: "computer://window/999/screenshot"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ComputerKit && swift test --filter MCPResourcesTests`
Expected: FAIL — `ScreenshotResources` does not exist.

- [ ] **Step 3: Write minimal implementation**

`ComputerKit/Sources/ComputerKit/MCP/MCPResources.swift`:

```swift
import Foundation

/// Serves computer://window/{id}/screenshot for every claimed window.
public final class ScreenshotResources: MCPResourceProviding {
    private let engine: DesktopEngine
    private let registry: SessionRegistry

    public init(engine: DesktopEngine, registry: SessionRegistry) {
        self.engine = engine
        self.registry = registry
    }

    public func listResources() -> [JSONValue] {
        registry.sessions.keys.flatMap { registry.claimedWindows(for: $0) }.map { window in
            .object([
                "uri": .string("computer://window/\(window.id)/screenshot"),
                "name": .string("\(window.appName) — \(window.title)"),
                "mimeType": .string("image/png"),
            ])
        }
    }

    public func readResource(uri: String) -> JSONValue? {
        guard uri.hasPrefix("computer://window/"), uri.hasSuffix("/screenshot"),
              let id = Int(uri.dropFirst("computer://window/".count).dropLast("/screenshot".count)),
              registry.owner(of: CGWindowID(id)) != nil,
              let shot = try? engine.screenshot(windowID: CGWindowID(id)) else { return nil }
        return .object([
            "uri": .string(uri),
            "mimeType": .string("image/png"),
            "blob": .string(shot.pngData.base64EncodedString()),
        ])
    }
}
```

Move `MCPResourceProviding` here from `MCPMessages.swift` (delete the temporary copy there).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ComputerKit && swift test --filter MCPResourcesTests`
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add ComputerKit
git commit -m "feat(computerkit): screenshot resources per claimed window"
```

---

### Task 7: Supervision event stream

**Files:**
- Create: `ComputerKit/Sources/ComputerKit/Daemon/SupervisionEvent.swift`
- Test: `ComputerKit/Tests/ComputerKitTests/SupervisionEventTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ComputerKit

final class SupervisionEventTests: XCTestCase {
    func test_encodesToSingleLineJSON() throws {
        let event = SupervisionEvent.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600")
        let line = try event.jsonLine()
        XCTAssertFalse(line.contains("\n"))
        let decoded = try SupervisionEvent(jsonLine: line)
        XCTAssertEqual(decoded, event)
    }

    func test_actionEventCarriesPoint() throws {
        let event = SupervisionEvent.action(session: 2, windowID: 10, kind: "click", x: 50, y: 60)
        let decoded = try SupervisionEvent(jsonLine: event.jsonLine())
        XCTAssertEqual(decoded, .action(session: 2, windowID: 10, kind: "click", x: 50, y: 60))
    }

    func test_screenshotTaken_carriesBase64Frame() throws {
        let event = SupervisionEvent.screenshotTaken(session: 1, windowID: 10, pngBase64: "aGk=")
        let decoded = try SupervisionEvent(jsonLine: event.jsonLine())
        XCTAssertEqual(decoded, .screenshotTaken(session: 1, windowID: 10, pngBase64: "aGk="))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ComputerKit && swift test --filter SupervisionEventTests`
Expected: FAIL — `SupervisionEvent` does not exist.

- [ ] **Step 3: Write minimal implementation**

`ComputerKit/Sources/ComputerKit/Daemon/SupervisionEvent.swift`:

```swift
import Foundation

/// Events pushed to supervision subscribers (10x) and commands accepted back.
/// Wire format: one JSON object per line, "type" discriminates.
public enum SupervisionEvent: Equatable, Sendable {
    case sessionStarted(session: Int, harness: String)
    case sessionEnded(session: Int, harness: String)
    case windowClaimed(session: Int, harness: String, windowID: Int, app: String, title: String, bounds: String)
    case windowReleased(session: Int, windowID: Int, reason: String)
    case action(session: Int, windowID: Int, kind: String, x: Double, y: Double)
    case screenshotTaken(session: Int, windowID: Int, pngBase64: String)
    case statusChanged(session: Int, status: String)
    case stopped(reason: String)

    public func jsonLine() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    public init(jsonLine: String) throws {
        self = try JSONDecoder().decode(SupervisionEvent.self, from: Data(jsonLine.utf8))
    }
}

extension SupervisionEvent: Codable {
    private enum Kind: String, Codable {
        case sessionStarted, sessionEnded, windowClaimed, windowReleased, action, screenshotTaken, statusChanged, stopped
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .sessionStarted:
            self = .sessionStarted(session: try container.decode(Int.self, forKey: .session), harness: try container.decode(String.self, forKey: .harness))
        case .sessionEnded:
            self = .sessionEnded(session: try container.decode(Int.self, forKey: .session), harness: try container.decode(String.self, forKey: .harness))
        case .windowClaimed:
            self = .windowClaimed(session: try container.decode(Int.self, forKey: .session), harness: try container.decode(String.self, forKey: .harness), windowID: try container.decode(Int.self, forKey: .windowID), app: try container.decode(String.self, forKey: .app), title: try container.decode(String.self, forKey: .title), bounds: try container.decode(String.self, forKey: .bounds))
        case .windowReleased:
            self = .windowReleased(session: try container.decode(Int.self, forKey: .session), windowID: try container.decode(Int.self, forKey: .windowID), reason: try container.decode(String.self, forKey: .reason))
        case .action:
            self = .action(session: try container.decode(Int.self, forKey: .session), windowID: try container.decode(Int.self, forKey: .windowID), kind: try container.decode(String.self, forKey: .kind), x: try container.decode(Double.self, forKey: .x), y: try container.decode(Double.self, forKey: .y))
        case .screenshotTaken:
            self = .screenshotTaken(session: try container.decode(Int.self, forKey: .session), windowID: try container.decode(Int.self, forKey: .windowID), pngBase64: try container.decode(String.self, forKey: .pngBase64))
        case .statusChanged:
            self = .statusChanged(session: try container.decode(Int.self, forKey: .session), status: try container.decode(String.self, forKey: .status))
        case .stopped:
            self = .stopped(reason: try container.decode(String.self, forKey: .reason))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sessionStarted(let session, let harness):
            try container.encode(Kind.sessionStarted, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(harness, forKey: .harness)
        case .sessionEnded(let session, let harness):
            try container.encode(Kind.sessionEnded, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(harness, forKey: .harness)
        case .windowClaimed(let session, let harness, let windowID, let app, let title, let bounds):
            try container.encode(Kind.windowClaimed, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(harness, forKey: .harness)
            try container.encode(windowID, forKey: .windowID)
            try container.encode(app, forKey: .app)
            try container.encode(title, forKey: .title)
            try container.encode(bounds, forKey: .bounds)
        case .windowReleased(let session, let windowID, let reason):
            try container.encode(Kind.windowReleased, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(windowID, forKey: .windowID)
            try container.encode(reason, forKey: .reason)
        case .action(let session, let windowID, let kind, let x, let y):
            try container.encode(Kind.action, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(windowID, forKey: .windowID)
            try container.encode(kind, forKey: .kind)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        case .screenshotTaken(let session, let windowID, let pngBase64):
            try container.encode(Kind.screenshotTaken, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(windowID, forKey: .windowID)
            try container.encode(pngBase64, forKey: .pngBase64)
        case .statusChanged(let session, let status):
            try container.encode(Kind.statusChanged, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(status, forKey: .status)
        case .stopped(let reason):
            try container.encode(Kind.stopped, forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, session, harness, windowID, app, title, bounds, reason, kind, x, y, pngBase64, status
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ComputerKit && swift test --filter SupervisionEventTests`
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add ComputerKit
git commit -m "feat(computerkit): supervision event wire format"
```

---

### Task 8: Daemon — Unix socket, roles, MCP proxy

**Files:**
- Create: `ComputerKit/Sources/ComputerKit/Daemon/DaemonServer.swift`
- Create: `ComputerKit/Sources/ComputerKit/Daemon/DaemonClient.swift`
- Test: `ComputerKit/Tests/ComputerKitTests/DaemonServerTests.swift`

Design: the daemon listens on a Unix socket. Each client opens with one handshake line: `{"role":"mcp"}` or `{"role":"supervision"}`. MCP clients then exchange NDJSON JSON-RPC (the daemon runs an `MCPServer` per connection, backed by `ComputerTools` for that connection's session). Supervision clients receive the event stream and may send `{"command":"stop_session","session":N}` / `{"command":"stop_all"}`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ComputerKit

final class DaemonServerTests: XCTestCase {
    var socketPath: String!
    var daemon: DaemonServer!

    override func setUp() {
        super.setUp()
        socketPath = NSTemporaryDirectory() + "tenx-computer-test-\(UUID().uuidString).sock"
        daemon = DaemonServer(engine: FakeEngine(), socketPath: socketPath)
        try! daemon.start()
    }

    override func tearDown() {
        daemon.stop()
        try? FileManager.default.removeItem(atPath: socketPath)
        super.tearDown()
    }

    func rpc(_ client: DaemonClient, _ request: [String: JSONValue]) throws -> JSONValue {
        try client.send(.object(request))
        return try client.receive()
    }

    func test_mcpClient_fullFlow() throws {
        let client = try DaemonClient(socketPath: socketPath)
        try client.send(.object(["role": .string("mcp")]))
        let initResponse = try rpc(client, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        XCTAssertEqual(initResponse["result"]?["serverInfo"]?["name"], .string("tenx-computer"))

        let listResponse = try rpc(client, ["jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/list")])
        let names = listResponse["result"]?["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
        XCTAssertEqual(names.count, 7)
    }

    func test_supervisionClient_receivesEvents() throws {
        let supervision = try DaemonClient(socketPath: socketPath)
        try supervision.send(.object(["role": .string("supervision")]))
        _ = try supervision.receive() // handshake ack

        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("Cursor")])]),
        ])

        let event = try supervision.receive()
        XCTAssertEqual(event["type"], .string("sessionStarted"))
        XCTAssertEqual(event["harness"], .string("Cursor"))
    }

    func test_stopAll_revokesSessions() throws {
        let supervision = try DaemonClient(socketPath: socketPath)
        try supervision.send(.object(["role": .string("supervision")]))
        _ = try supervision.receive() // handshake ack

        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        _ = try supervision.receive() // sessionStarted

        try supervision.send(.object(["command": .string("stop_all")]))
        let stopped = try supervision.receive()
        XCTAssertEqual(stopped["type"], .string("stopped"))

        let response = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
            "params": .object(["name": .string("computer_windows"), "arguments": .object([:])]),
        ])
        XCTAssertEqual(response["result"]?["isError"], .bool(true))
    }

    func test_mcpDisconnect_releasesClaims_deadMansSwitch() throws {
        let supervision = try DaemonClient(socketPath: socketPath)
        try supervision.send(.object(["role": .string("supervision")]))
        _ = try supervision.receive() // handshake ack

        var mcp: DaemonClient? = try DaemonClient(socketPath: socketPath)
        try mcp?.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcp!, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        _ = try supervision.receive() // sessionStarted
        mcp = nil // close the connection

        let ended = try supervision.receive()
        XCTAssertEqual(ended["type"], .string("sessionEnded"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ComputerKit && swift test --filter DaemonServerTests`
Expected: FAIL — types do not exist.

- [ ] **Step 3: Write minimal implementation**

`ComputerKit/Sources/ComputerKit/Daemon/DaemonServer.swift`:

```swift
import Foundation

/// Singleton daemon: owns the engine + registry, speaks MCP per client and
/// pushes supervision events.
///
/// Threading: accept runs on a dedicated queue, each client reads on the
/// global queue, and ALL shared state (clients, registry) is guarded by one
/// NSLock. Event volume is tiny, so a single lock is correct and sufficient.
public final class DaemonServer {
    public static let defaultSocketPath = NSHomeDirectory() + "/Library/Application Support/10x/computer.sock"

    private let engine: DesktopEngine
    private let registry = SessionRegistry()
    private let socketPath: String
    private let acceptQueue = DispatchQueue(label: "tenx-computer.accept")
    /// Recursive because broadcast/emitToolEvents re-enter while handleLine holds it.
    private let lock = NSRecursiveLock()
    private var serverFD: Int32 = -1
    private var clients: [Int32: ClientState] = [:]
    private var isRunning = false

    private enum Role { case mcp(SessionID, MCPServer), supervision }
    private final class ClientState {
        var role: Role?
        var buffer = Data()
    }

    public init(engine: DesktopEngine, socketPath: String = DaemonServer.defaultSocketPath) {
        self.engine = engine
        self.socketPath = socketPath
    }

    public func start() throws {
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else { throw ComputerError("socket: \(String(cString: strerror(errno)))") }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            socketPath.withCString { strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), $0, 104) }
        }
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }

        if bound != 0 {
            // ponytail: stale-socket recovery is connect-fail-then-unlink.
            // Ceiling: two daemons started in the same instant can both pass the
            // connect probe. Upgrade path: flock a sibling .lock file.
            let alive = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            guard alive != 0 else { throw ComputerError("daemon_already_running") }
            unlink(socketPath)
            let rebound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            guard rebound == 0 else { throw ComputerError("bind: \(String(cString: strerror(errno)))") }
        }
        guard listen(serverFD, 16) == 0 else { throw ComputerError("listen: \(String(cString: strerror(errno)))") }

        isRunning = true
        acceptQueue.async { [weak self] in self?.acceptLoop() }
    }

    public func stop() {
        lock.lock()
        isRunning = false
        let fds = Array(clients.keys)
        clients.removeAll()
        lock.unlock()
        for fd in fds { close(fd) }
        if serverFD >= 0 { close(serverFD); serverFD = -1 }
        unlink(socketPath)
    }

    private func acceptLoop() {
        while true {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { return }
            lock.lock()
            let running = isRunning
            if running { clients[clientFD] = ClientState() }
            lock.unlock()
            guard running else { close(clientFD); return }
            DispatchQueue.global().async { [weak self] in self?.readLoop(clientFD) }
        }
    }

    private func readLoop(_ fd: Int32) {
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = recv(fd, &chunk, chunk.count, 0)
            guard count > 0 else { break }
            lock.lock()
            clients[fd]?.buffer.append(contentsOf: chunk[0..<count])
            var lines: [Data] = []
            while let newline = clients[fd]?.buffer.firstIndex(of: 0x0A) {
                lines.append(Data(clients[fd]!.buffer.prefix(upTo: newline)))
                clients[fd]!.buffer.removeSubrange(...newline)
            }
            lock.unlock()
            for line in lines { handleLine(fd: fd, line: line) }
        }
        disconnect(fd)
    }

    private func handleLine(fd: Int32, line: Data) {
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: line) else { return }

        lock.lock()
        let client = clients[fd]
        if client?.role == nil {
            if message["role"]?.stringValue == "supervision" {
                client?.role = .supervision
                lock.unlock()
                // Ack so subscribers know events after this point are guaranteed.
                try? write(fd, .object(["role": .string("supervision"), "ok": .bool(true)]))
            } else {
                let session = registry.registerSession(clientName: nil)
                let tools = ComputerTools(engine: engine, registry: registry, session: session)
                let resources = ScreenshotResources(engine: engine, registry: registry)
                client?.role = .mcp(session, MCPServer(tools: tools, resources: resources))
                lock.unlock()
            }
            return
        }
        let role = client?.role
        lock.unlock()

        switch role {
        case .mcp(let session, let server):
            guard let method = message["method"]?.stringValue else { return }
            let id = message["id"]
            // ponytail: MCP work is serialized across clients — computer use is
            // inherently serial per machine (one input stream), so this costs
            // little. Ceiling: a slow screenshot blocks another session's call
            // for its duration. Upgrade path: per-session queues + engine pool.
            lock.lock()
            defer { lock.unlock() }
            let claimsBefore = Set(registry.claimedWindows(for: session).map(\.id))
            do {
                if let result = try server.handle(method: method, params: message["params"]) {
                    if method == "initialize", let name = server.clientName {
                        lock.lock()
                        registry.setHarness(name, for: session)
                        lock.unlock()
                        broadcast(.sessionStarted(session: session.raw, harness: name))
                    }
                    emitToolEvents(session: session, method: method, params: message["params"], claimsBefore: claimsBefore)
                    try write(fd, .object(["jsonrpc": .string("2.0"), "id": id ?? .null, "result": result]))
                }
            } catch let error as MCPError {
                try? write(fd, errorResponse(id: id, code: error.code, message: error.message))
            } catch let error as ComputerError {
                try? write(fd, errorResponse(id: id, code: -32603, message: error.message))
            } catch {
                try? write(fd, errorResponse(id: id, code: -32603, message: "\(error)"))
            }

        case .supervision:
            guard let command = message["command"]?.stringValue else { return }
            switch command {
            case "stop_session":
                if let raw = message["session"]?.intValue {
                    lock.lock()
                    registry.stop(SessionID(raw: raw))
                    lock.unlock()
                    broadcast(.stopped(reason: "session \(raw) stopped"))
                }
            case "stop_all":
                lock.lock()
                registry.stopAll()
                lock.unlock()
                broadcast(.stopped(reason: "global shut-off"))
            default:
                break
            }

        case .none:
            break
        }
    }

    /// Emits supervision events for a completed tools/call. Claims are diffed
    /// around the call so computer_launch (whose window id is only known after
    /// execution) is covered by the same path as computer_claim.
    private func emitToolEvents(session: SessionID, method: String, params: JSONValue?, claimsBefore: Set<CGWindowID>) {
        guard method == "tools/call", let name = params?["name"]?.stringValue else { return }
        lock.lock()
        let newClaims = registry.claimedWindows(for: session).filter { !claimsBefore.contains($0.id) }
        let harness = registry.session(session)?.harness ?? "unknown"
        lock.unlock()
        for window in newClaims {
            broadcast(.windowClaimed(
                session: session.raw, harness: harness, windowID: Int(window.id),
                app: window.appName, title: window.title,
                bounds: "\(Int(window.bounds.minX)),\(Int(window.bounds.minY)) \(Int(window.bounds.width))x\(Int(window.bounds.height))"
            ))
        }
        let args = params?["arguments"]
        switch name {
        case "computer_release":
            if let windowID = args?["window_id"]?.intValue {
                broadcast(.windowReleased(session: session.raw, windowID: windowID, reason: "released"))
            }
        case "computer_act":
            broadcast(.action(
                session: session.raw,
                windowID: args?["window_id"]?.intValue ?? 0,
                kind: args?["action"]?.stringValue ?? "?",
                x: args?["x"]?.doubleValue ?? 0,
                y: args?["y"]?.doubleValue ?? 0
            ))
        case "computer_status":
            broadcast(.statusChanged(session: session.raw, status: args?["status"]?.stringValue ?? ""))
        default:
            break
        }
    }

    private func broadcast(_ event: SupervisionEvent) {
        guard let data = try? event.jsonLine().data(using: .utf8) else { return }
        lock.lock()
        let supervisionFDs = clients.compactMap { fd, client -> Int32? in
            guard case .supervision = client.role else { return nil }
            return fd
        }
        lock.unlock()
        // ponytail: sends happen outside the lock; payloads are tiny and local.
        for fd in supervisionFDs { _ = try? writeRaw(fd, data + Data([0x0A])) }
    }

    private func disconnect(_ fd: Int32) {
        lock.lock()
        let client = clients.removeValue(forKey: fd)
        var ended: (Int, String)?
        if case .mcp(let session, _) = client?.role {
            let harness = registry.session(session)?.harness ?? "unknown"
            registry.stop(session)
            ended = (session.raw, harness)
        }
        lock.unlock()
        if let ended { broadcast(.sessionEnded(session: ended.0, harness: ended.1)) }
        close(fd)
    }

    private func errorResponse(id: JSONValue?, code: Int, message: String) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"), "id": id ?? .null,
            "error": .object(["code": .number(Double(code)), "message": .string(message)]),
        ])
    }

    private func write(_ fd: Int32, _ value: JSONValue) throws {
        try writeRaw(fd, JSONEncoder().encode(value) + Data([0x0A]))
    }

    private func writeRaw(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { pointer in
            guard let base = pointer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let count = send(fd, base + sent, data.count - sent, 0)
                guard count > 0 else { throw ComputerError("send failed") }
                sent += count
            }
        }
    }
}
```

`SessionRegistry.setHarness` was already added in Task 4 — no registry changes needed here.

`ComputerKit/Sources/ComputerKit/Daemon/DaemonClient.swift`:

```swift
import Foundation

/// NDJSON client for the daemon socket — used by the MCP proxy, stop-all,
/// tests, and (in Plan 2) the 10x app's supervision subscription.
public final class DaemonClient {
    private let fd: Int32
    private var buffer = Data()

    public init(socketPath: String = DaemonServer.defaultSocketPath) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ComputerError("socket: \(String(cString: strerror(errno)))") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            socketPath.withCString { strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), $0, 104) }
        }
        guard connect(fd, withUnsafePointer(to: &address, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1, { $0 }) }), socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 else {
            close(fd)
            throw ComputerError("daemon_unreachable: \(socketPath)")
        }
    }

    deinit { close(fd) }

    public func send(_ value: JSONValue) throws {
        let data = try JSONEncoder().encode(value) + Data([0x0A])
        try data.withUnsafeBytes { pointer in
            guard let base = pointer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let count = send(fd, base + sent, data.count - sent, 0)
                guard count > 0 else { throw ComputerError("send failed") }
                sent += count
            }
        }
    }

    public func receive() throws -> JSONValue {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                return try JSONDecoder().decode(JSONValue.self, from: line)
            }
            var chunk = [UInt8](repeating: 0, count: 65536)
            let count = recv(fd, &chunk, chunk.count, 0)
            guard count > 0 else { throw ComputerError("daemon_closed") }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }
}
```

Note: `SessionInfo.harness` is `let` in Task 4 — change it to `var` so `setHarness` works.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ComputerKit && swift test --filter DaemonServerTests`
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```bash
git add ComputerKit
git commit -m "feat(computerkit): daemon socket with mcp and supervision roles"
```

---

### Task 9: Preview frames — near-live "currently viewing"

**Files:**
- Create: `ComputerKit/Sources/ComputerKit/Daemon/PreviewStreamer.swift`
- Modify: `ComputerKit/Sources/ComputerKit/Daemon/DaemonServer.swift` (hook the streamer in)
- Test: `ComputerKit/Tests/ComputerKitTests/PreviewStreamerTests.swift`

Spec: a fresh capture of the actively controlled window on every action, plus a ~1/s heartbeat while controlling.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ComputerKit

final class PreviewStreamerTests: XCTestCase {
    func test_actionTriggersImmediateFrame() {
        let engine = FakeEngine()
        engine.screenshotPNG = Data([9, 9, 9])
        var frames: [SupervisionEvent] = []
        let streamer = PreviewStreamer(engine: engine, interval: 60) { event in frames.append(event) }
        streamer.actionOccurred(session: SessionID(raw: 1), windowID: 10)
        XCTAssertEqual(frames, [.screenshotTaken(session: 1, windowID: 10, pngBase64: Data([9, 9, 9]).base64EncodedString())])
    }

    func test_heartbeatEmitsWhileControlling_thenStops() throws {
        let engine = FakeEngine()
        engine.screenshotPNG = Data([1])
        var frames: [SupervisionEvent] = []
        let streamer = PreviewStreamer(engine: engine, interval: 0.05) { event in frames.append(event) }
        streamer.setActive(session: SessionID(raw: 1), windowID: 10)
        Thread.sleep(forTimeInterval: 0.16)
        streamer.setActive(session: nil, windowID: nil)
        let count = frames.count
        XCTAssertGreaterThanOrEqual(count, 2)
        Thread.sleep(forTimeInterval: 0.12)
        XCTAssertEqual(frames.count, count) // no frames after stop
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ComputerKit && swift test --filter PreviewStreamerTests`
Expected: FAIL — `PreviewStreamer` does not exist.

- [ ] **Step 3: Write minimal implementation**

`ComputerKit/Sources/ComputerKit/Daemon/PreviewStreamer.swift`:

```swift
import CoreGraphics
import Foundation

/// Pushes near-live frames of the actively controlled window to supervision
/// subscribers: immediately on each action, then on a slow heartbeat while
/// control continues. ponytail: one global active window — with N sessions the
/// last actor wins. Ceiling: N>1 sessions controlling simultaneously interleave
/// heartbeats. Upgrade path: per-session timers keyed by window.
public final class PreviewStreamer {
    private let engine: DesktopEngine
    private let interval: TimeInterval
    private let emit: (SupervisionEvent) -> Void
    private var timer: DispatchSourceTimer?
    private var active: (session: SessionID, windowID: CGWindowID)?
    private let queue = DispatchQueue(label: "tenx-computer.preview")

    public init(engine: DesktopEngine, interval: TimeInterval = 1.0, emit: @escaping (SupervisionEvent) -> Void) {
        self.engine = engine
        self.interval = interval
        self.emit = emit
    }

    func actionOccurred(session: SessionID, windowID: CGWindowID) {
        queue.sync {
            setActiveLocked(session: session, windowID: windowID)
            emitFrameLocked()
        }
    }

    func setActive(session: SessionID?, windowID: CGWindowID?) {
        queue.sync {
            if let session, let windowID {
                setActiveLocked(session: session, windowID: windowID)
            } else {
                active = nil
                timer?.cancel()
                timer = nil
            }
        }
    }

    private func setActiveLocked(session: SessionID, windowID: CGWindowID) {
        if active?.windowID == windowID, active?.session == session, timer != nil { return }
        active = (session, windowID)
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.emitFrameLocked() }
        timer.resume()
        self.timer = timer
    }

    private func emitFrameLocked() {
        guard let active, let shot = try? engine.screenshot(windowID: active.windowID) else { return }
        emit(.screenshotTaken(session: active.session.raw, windowID: Int(active.windowID), pngBase64: shot.pngData.base64EncodedString()))
    }
}
```

In `DaemonServer`: add `private lazy var preview = PreviewStreamer(engine: engine) { [weak self] event in self?.broadcast(event) }`, and in `emitToolEvents` add to the `computer_act` case:

```swift
            if let windowID = args?["window_id"]?.intValue {
                preview.actionOccurred(session: session, windowID: CGWindowID(windowID))
            }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ComputerKit && swift test --filter PreviewStreamerTests`
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add ComputerKit
git commit -m "feat(computerkit): near-live preview frames for the active window"
```

---

### Task 10: MacDesktopEngine — real capture, input, windows, launch

**Files:**
- Create: `ComputerKit/Sources/ComputerKit/Engine/MacDesktopEngine.swift`
- Create: `ComputerKit/Sources/ComputerKit/Engine/KeyChord.swift`

No unit tests (hardware/OS-touching) — verified by `selfcheck` in Task 11. Keep every method small and defensive; all failures surface as `ComputerError`.

- [ ] **Step 1: Implement**

`ComputerKit/Sources/ComputerKit/Engine/KeyChord.swift`:

```swift
import CoreGraphics
import Foundation

/// Parses "cmd+s", "ctrl+shift+tab", "return" into flags + virtual key code.
enum KeyChord {
    static func parse(_ chord: String) throws -> (flags: CGEventFlags, keyCode: CGKeyCode) {
        var flags: CGEventFlags = []
        var parts = chord.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.popLast() else { throw ComputerError("invalid_chord: \(chord)") }
        for modifier in parts {
            switch modifier {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: throw ComputerError("invalid_modifier: \(modifier)")
            }
        }
        guard let keyCode = keyCodes[key] else { throw ComputerError("invalid_key: \(key)") }
        return (flags, keyCode)
    }

    // ponytail: letters, digits, and the common named keys only — enough for
    // agent workflows. Ceiling: no F-keys/arrows beyond the listed ones.
    // Upgrade path: full UCKeyTranslate table.
    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "tab": 48, "space": 49, "delete": 51, "escape": 53, "return": 36,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}
```

`ComputerKit/Sources/ComputerKit/Engine/MacDesktopEngine.swift`:

```swift
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// The real engine. Every method converts failures into ComputerError so MCP
/// clients get actionable text instead of crashes.
public final class MacDesktopEngine: DesktopEngine {
    public init() {}

    public func preflightPermissions() -> PermissionStatus {
        PermissionStatus(screenRecording: CGPreflightScreenCaptureAccess(), accessibility: AXIsProcessTrusted())
    }

    public func listWindows() throws -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            throw ComputerError("window_list_unavailable")
        }
        return list.compactMap { entry in
            guard let id = entry[kCGWindowNumber as String] as? Int,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  (entry[kCGWindowLayer as String] as? Int) == 0 else { return nil }
            return WindowInfo(
                id: CGWindowID(id),
                appName: entry[kCGWindowOwnerName as String] as? String ?? "?",
                title: entry[kCGWindowName as String] as? String ?? "",
                bounds: bounds,
                pid: pid_t(pid)
            )
        }
    }

    public func screenshot(windowID: CGWindowID) throws -> Screenshot {
        guard preflightPermissions().screenRecording else { throw ComputerError("permission_missing: screen_recording") }
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Screenshot, Error>!
        Task {
            defer { semaphore.signal() }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                    throw ComputerError("window_gone: \(windowID)")
                }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let configuration = SCStreamConfiguration()
                configuration.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                guard let rep = NSBitmapImageRep(cgImage: image), let png = rep.representation(using: .png, properties: [:]) else {
                    throw ComputerError("screenshot_encode_failed")
                }
                result = .success(Screenshot(
                    pngData: png,
                    pixelSize: CGSize(width: image.width, height: image.height),
                    scale: Double(image.width) / max(1, Double(window.frame.width))
                ))
            } catch let error as ComputerError {
                result = .failure(error)
            } catch {
                result = .failure(ComputerError("screenshot_failed: \(error.localizedDescription)"))
            }
        }
        semaphore.wait()
        return try result.get()
    }

    public func launch(app: String) throws -> WindowInfo {
        guard preflightPermissions().accessibility else { throw ComputerError("permission_missing: accessibility") }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app)
            ?? ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
                .lazy.map({ URL(fileURLWithPath: $0).appendingPathComponent(app + ".app") })
                .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw ComputerError("app_not_found: \(app)")
        }
        let existingPIDs = Set(try listWindows().map(\.pid))
        let semaphore = DispatchSemaphore(value: 0)
        var launched: NSRunningApplication?
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { running, _ in
            launched = running
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        guard let launched else { throw ComputerError("launch_failed: \(app)") }

        // Wait for the app to present a window (up to 5s).
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let window = try listWindows().first(where: { $0.pid == launched.processIdentifier && !existingPIDs.contains($0.pid) })
                ?? try listWindows().first(where: { $0.pid == launched.processIdentifier }) {
                return window
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw ComputerError("launch_no_window: \(app)")
    }

    public func act(_ action: ComputerAction, window: WindowInfo) throws {
        guard preflightPermissions().accessibility else { throw ComputerError("permission_missing: accessibility") }
        let pid = pid_t(window.pid)
        func globalPoint(_ windowRelative: CGPoint) -> CGPoint {
            CGPoint(x: window.bounds.minX + windowRelative.x, y: window.bounds.minY + windowRelative.y)
        }
        switch action {
        case .click(let point, let button):
            let location = globalPoint(point)
            let (downType, upType, cgButton): (CGEventType, CGEventType, CGMouseButton) = button == .right
                ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)
            try post(CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: location, mouseButton: cgButton), to: pid)
            try post(CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: location, mouseButton: cgButton), to: pid)
        case .doubleClick(let point):
            let location = globalPoint(point)
            for state in 1...2 {
                let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left)
                let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left)
                down?.setIntegerValueField(.mouseEventClickState, value: Int64(state))
                up?.setIntegerValueField(.mouseEventClickState, value: Int64(state))
                try post(down, to: pid)
                try post(up, to: pid)
            }
        case .drag(let from, let to):
            let start = globalPoint(from), end = globalPoint(to)
            try post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left), to: pid)
            try post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: end, mouseButton: .left), to: pid)
            try post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left), to: pid)
        case .scroll(let deltaX, let deltaY):
            try post(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(-deltaY), wheel2: Int32(-deltaX), wheel3: 0), to: pid)
        case .type(let text):
            for scalar in text {
                var unichar = Array(String(scalar).utf16)
                try post(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)?.applyingUnicode(&unichar), to: pid)
                try post(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)?.applyingUnicode(&unichar), to: pid)
            }
        case .key(let chord):
            let (flags, keyCode) = try KeyChord.parse(chord)
            let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
            down?.flags = flags
            up?.flags = flags
            try post(down, to: pid)
            try post(up, to: pid)
        }
    }

    private func post(_ event: CGEvent?, to pid: pid_t) throws {
        guard let event else { throw ComputerError("event_create_failed") }
        // ponytail: background delivery only, by design — the agent never steals
        // focus. Ceiling: some apps ignore posted-to-pid events. Upgrade path:
        // CGEventPostToPSN / Skylight private APIs (see pi-natives skylight.rs).
        event.postToPid(pid)
    }
}

private extension CGEvent {
    func applyingUnicode(_ chars: inout [UniChar]) -> CGEvent {
        CGEventKeyboardSetUnicodeString(self, chars.count, &chars)
        return self
    }
}
```

- [ ] **Step 2: Build**

Run: `cd ComputerKit && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Run the full suite (still headless)**

Run: `cd ComputerKit && swift test`
Expected: all suites pass (engine untouched by tests).

- [ ] **Step 4: Commit**

```bash
git add ComputerKit
git commit -m "feat(computerkit): mac engine for capture, input, windows, launch"
```

---

### Task 11: CLI — `mcp`, `daemon`, `stop-all`, `selfcheck`

**Files:**
- Modify: `ComputerKit/Sources/tenx-computer/main.swift`

- [ ] **Step 1: Implement**

`ComputerKit/Sources/tenx-computer/main.swift` (full replacement):

```swift
import ComputerKit
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

func ensureDaemon() throws {
    if let client = try? DaemonClient() { _ = client; return } // already running
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = ["daemon"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    // Wait for the socket to accept connections (up to 3s).
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if let client = try? DaemonClient() { _ = client; return }
        Thread.sleep(forTimeInterval: 0.1)
    }
    throw ComputerError("daemon_start_timeout")
}

func runMCPFront() throws {
    try ensureDaemon()
    let client = try DaemonClient()
    try client.send(.object(["role": .string("mcp")]))

    // stdin -> socket
    DispatchQueue.global().async {
        while let line = readLine(strippingNewline: true) {
            guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else { continue }
            try? client.send(value)
        }
        exit(0)
    }
    // socket -> stdout
    while true {
        let response = try client.receive()
        let data = try JSONEncoder().encode(response)
        FileHandle.standardOutput.write(data + Data([0x0A]))
    }
}

func runDaemon() throws {
    let server = DaemonServer(engine: MacDesktopEngine())
    try server.start()
    FileHandle.standardError.write("tenx-computer daemon listening\n".data(using: .utf8)!)
    dispatchMain()
}

func runStopAll() throws {
    let client = try DaemonClient()
    try client.send(.object(["role": .string("supervision")]))
    try client.send(.object(["command": .string("stop_all")]))
    print("stop_all sent")
}

func runSelfCheck() throws {
    // Real-hardware check: probe window, type, screenshot, assert pixels.
    // Implemented as a tiny in-process app so no external app is touched.
    print("selfcheck: not yet wired — see Task 11 step 2")
}

switch arguments.first {
case "daemon": try runDaemon()
case "stop-all": try runStopAll()
case "selfcheck": try runSelfCheck()
case "mcp", nil: try runMCPFront()
default:
    FileHandle.standardError.write("usage: tenx-computer [mcp|daemon|stop-all|selfcheck]\n".data(using: .utf8)!)
    exit(64)
}
```

- [ ] **Step 2: Implement selfcheck for real**

Replace `runSelfCheck` with a probe-window check. The CLI becomes an accessory app, shows a window with a text field, then drives it through the real engine:

```swift
func runSelfCheck() throws {
    let engine = MacDesktopEngine()
    let permissions = engine.preflightPermissions()
    guard permissions.isComplete else {
        FileHandle.standardError.write("selfcheck: permissions missing — screen_recording=\(permissions.screenRecording) accessibility=\(permissions.accessibility)\nGrant them to this binary in System Settings > Privacy & Security.\n".data(using: .utf8)!)
        exit(1)
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "tenx-computer probe"
    let field = NSTextField(frame: NSRect(x: 20, y: 40, width: 280, height: 30))
    field.stringValue = ""
    window.contentView?.addSubview(field)
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    // Find the probe window through the engine.
    let deadline = Date().addingTimeInterval(5)
    var probe: WindowInfo?
    while Date() < deadline, probe == nil {
        probe = try? engine.listWindows().first(where: { $0.title == "tenx-computer probe" })
        Thread.sleep(forTimeInterval: 0.2)
    }
    guard let probe else { throw ComputerError("selfcheck: probe window not found") }

    // Type into it (background delivery to our own pid).
    try engine.act(.click(point: CGPoint(x: 160, y: 45), button: .left), window: probe)
    try engine.act(.type("hello 10x"), window: probe)

    // Pump the run loop so the events land.
    let settle = Date().addingTimeInterval(1)
    while Date() < settle { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }

    guard field.stringValue == "hello 10x" else {
        FileHandle.standardError.write("selfcheck: input FAILED — field contains \"\(field.stringValue)\"\n".data(using: .utf8)!)
        exit(1)
    }

    let shot = try engine.screenshot(windowID: probe.id)
    guard shot.pngData.count > 10_000 else {
        FileHandle.standardError.write("selfcheck: capture FAILED — suspiciously small PNG (\(shot.pngData.count) bytes)\n".data(using: .utf8)!)
        exit(1)
    }

    print("selfcheck: OK — input typed, capture \(Int(shot.pixelSize.width))x\(Int(shot.pixelSize.height))px @\(Int(shot.scale))x")
    exit(0)
}
```

Add `import AppKit` at the top of `main.swift`.

- [ ] **Step 3: Build and run the suite**

Run: `cd ComputerKit && swift build && swift test`
Expected: `Build complete!`, all tests pass.

- [ ] **Step 4: Run selfcheck on real hardware (manual, needs permissions)**

Run: `cd ComputerKit && swift run tenx-computer selfcheck`
Expected on first run: a permissions error naming Screen Recording / Accessibility — grant them to the built binary (System Settings → Privacy & Security), then re-run.
Expected after grants: `selfcheck: OK — input typed, capture …px @2x`

- [ ] **Step 5: Smoke the MCP front by hand**

Run: `cd ComputerKit && swift run tenx-computer mcp`
Then type one line and press return:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"manual-test"}}}
```

Expected: one JSON line back with `"serverInfo":{"name":"tenx-computer",...}`. Ctrl-C to exit.

- [ ] **Step 6: Commit**

```bash
git add ComputerKit
git commit -m "feat(computerkit): tenx-computer cli with mcp front, daemon, stop-all, selfcheck"
```

---

### Task 12: Full verification pass

- [ ] **Step 1: Whole suite green**

Run: `cd ComputerKit && swift test`
Expected: every suite passes — JSONValue, MCPServer, DesktopEngineContract, SessionRegistry, ComputerTools, MCPResources, SupervisionEvent, DaemonServer, PreviewStreamer.

- [ ] **Step 2: Release build**

Run: `cd ComputerKit && swift build -c release`
Expected: `Build complete!` — binary at `ComputerKit/.build/release/tenx-computer`.

- [ ] **Step 3: selfcheck against the release binary**

Run: `cd ComputerKit && .build/release/tenx-computer selfcheck`
Expected: `selfcheck: OK`.

- [ ] **Step 4: Commit any stragglers**

```bash
git status --short   # expect clean
```

---

## Plan 2 preview (separate document)

10x app integration: supervision client in the app, cursor overlay window, header metadata item, rail marker badge, "Currently viewing" popover, MenuBarExtra panel, ⇧⌘C command, session wiring through omp's MCP mounting (pending the two omp research answers), transcript card adaptation, settings section, acceptance pass.

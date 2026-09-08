import ComputerKit
import XCTest
@testable import ComputerKit
@testable import TenXApp

@MainActor
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
        await controller.stopComputerUse()
        XCTAssertEqual(controller.phase, .off)
    }

    func test_daemonSession_correlatesByClaimedWindow() {
        let controller = makeController()
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
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

    func test_windowReleased_clearsClaim() {
        let controller = makeController()
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        controller.applySupervision(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: ""))
        controller.applySupervision(.windowReleased(session: 1, windowID: 10, reason: "released"))
        XCTAssertEqual(controller.claimedWindowIDs, [])
        XCTAssertEqual(controller.phase, .off)
    }

    func test_focusWindow_frameAndLabelComeFromSameWindow() {
        let supervision = SupervisionClient(socketPath: NSTemporaryDirectory() + "unused-\(UUID().uuidString).sock")
        let controller = ComputerUseController(supervision: supervision)
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 20])
        supervision.apply(.sessionStarted(session: 7, harness: "omp", label: nil, pid: nil))
        supervision.apply(.windowClaimed(session: 7, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
        supervision.apply(.windowClaimed(session: 7, harness: "omp", windowID: 20, app: "Finder", title: "Recents", bounds: "0,0 400x300"))
        controller.applySupervision(.windowClaimed(session: 7, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: ""))
        let png = Data([0x89, 0x50]).base64EncodedString()
        supervision.apply(.screenshotTaken(session: 7, windowID: 20, pngBase64: png, width: 400, height: 300, scale: 2))
        // Most recent claim of the correlated session wins for BOTH surfaces.
        XCTAssertEqual(controller.latestFrame, Data([0x89, 0x50]))
        XCTAssertEqual(controller.focusWindowLabel, "Finder — Recents")
    }
}

private final class NoopEngine: DesktopEngine {
    var windows: [WindowInfo] = []
    var isCancelled: @Sendable () -> Bool = { false }
    func preflightPermissions() -> PermissionStatus { .init(screenRecording: true, accessibility: true) }
    func listWindows(onScreenOnly: Bool) throws -> [WindowInfo] { windows }
    func screenshot(windowID: CGWindowID) throws -> Screenshot {
        Screenshot(pngData: Data(), pixelSize: .zero, scale: 1)
    }
    func launch(app: String) throws -> WindowInfo { throw ComputerError("nope") }
    func act(_ action: ComputerAction, window: WindowInfo) throws {}
}

@MainActor
final class ComputerUseStopIntegrationTests: XCTestCase {
    func test_stop_revokesSessionAtDaemon() async throws {
        let socketPath = "/tmp/tenx-stop-\(UUID().uuidString.prefix(8)).sock"
        defer { try? FileManager.default.removeItem(atPath: socketPath) }
        let daemon = DaemonServer(engine: NoopEngine(), socketPath: socketPath)
        try daemon.start()
        defer { daemon.stop() }

        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp")]))
        try mcp.send(.object([
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ]))
        _ = try mcp.receive()

        let sessionID = daemon.registry.allSessions.keys.map(\.raw).sorted().first!
        let supervision = SupervisionClient(socketPath: socketPath)
        let controller = ComputerUseController(supervision: supervision)
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        controller.applySupervision(.windowClaimed(session: sessionID, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: ""))
        XCTAssertEqual(controller.daemonSessionID, sessionID)

        await controller.stopComputerUse()

        var isError = false
        for _ in 0..<50 where !isError {
            try mcp.send(.object([
                "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
                "params": .object(["name": .string("computer_windows"), "arguments": .object([:])]),
            ]))
            let response = try mcp.receive()
            isError = response["result"]?["isError"] == .bool(true)
            if !isError { try await Task.sleep(for: .milliseconds(50)) }
        }
        XCTAssertTrue(isError)
    }

    /// The header-Stop gap from review: the controller never saw a live
    /// windowClaimed (background session / late attach), so daemonSessionID
    /// is nil. Stop must resolve the daemon session from the supervision
    /// snapshot and still revoke it.
    func test_stop_resolvesDaemonSessionFromSnapshot() async throws {
        let socketPath = "/tmp/tenx-stop-\(UUID().uuidString.prefix(8)).sock"
        defer { try? FileManager.default.removeItem(atPath: socketPath) }
        let engine = NoopEngine()
        engine.windows = [WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: CGRect(x: 0, y: 0, width: 800, height: 600), pid: 0)]
        let daemon = DaemonServer(engine: engine, socketPath: socketPath)
        try daemon.start()
        defer { daemon.stop() }

        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp")]))
        try mcp.send(.object([
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ]))
        _ = try mcp.receive()
        try mcp.send(.object([
            "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
            "params": .object(["name": .string("computer_claim"), "arguments": .object(["window_id": .number(10)])]),
        ]))
        _ = try mcp.receive()

        let sessionID = daemon.registry.allSessions.keys.map(\.raw).sorted().first!
        let supervision = SupervisionClient(socketPath: socketPath)
        // Snapshot arrives as replay/apply only — no applySupervision on the controller.
        supervision.apply(.sessionStarted(session: sessionID, harness: "omp", label: nil, pid: nil))
        supervision.apply(.windowClaimed(session: sessionID, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))

        let controller = ComputerUseController(supervision: supervision)
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        XCTAssertNil(controller.daemonSessionID)

        await controller.stopComputerUse()

        var isError = false
        for _ in 0..<50 where !isError {
            try mcp.send(.object([
                "jsonrpc": .string("2.0"), "id": .number(3), "method": .string("tools/call"),
                "params": .object(["name": .string("computer_windows"), "arguments": .object([:])]),
            ]))
            let response = try mcp.receive()
            isError = response["result"]?["isError"] == .bool(true)
            if !isError { try await Task.sleep(for: .milliseconds(50)) }
        }
        XCTAssertTrue(isError, "stop must reach the daemon even without a correlated daemonSessionID")
    }
}

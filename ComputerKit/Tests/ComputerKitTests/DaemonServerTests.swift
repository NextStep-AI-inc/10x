import XCTest
@testable import ComputerKit

final class DaemonServerTests: XCTestCase {
    private let eventTimeout: TimeInterval = 2

    var socketPath: String!
    var engine: FakeEngine!
    var daemon: DaemonServer!

    override func setUp() {
        super.setUp()
        socketPath = NSTemporaryDirectory() + "tenx-computer-test-\(UUID().uuidString).sock"
        engine = FakeEngine()
        daemon = DaemonServer(engine: engine, socketPath: socketPath)
        try! daemon.start()
    }

    override func tearDown() {
        daemon?.stop()
        try? FileManager.default.removeItem(atPath: socketPath)
        super.tearDown()
    }

    func rpc(_ client: DaemonClient, _ request: [String: JSONValue]) throws -> JSONValue {
        try client.send(.object(request))
        return try client.receive()
    }

    func expectEvent(_ client: DaemonClient, file: StaticString = #filePath, line: UInt = #line) throws -> JSONValue {
        try client.receive(timeout: eventTimeout)
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

        let event = try expectEvent(supervision)
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
        _ = try expectEvent(supervision) // sessionStarted

        try supervision.send(.object(["command": .string("stop_all")]))
        let stopped = try expectEvent(supervision)
        XCTAssertEqual(stopped["type"], .string("stopped"))

        let response = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
            "params": .object(["name": .string("computer_windows"), "arguments": .object([:])]),
        ])
        XCTAssertEqual(response["result"]?["isError"], .bool(true))
    }

    func test_mcpDisconnect_releasesClaims_deadMansSwitch() throws {
        let safari = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        engine.windows = [safari]

        let supervision = try DaemonClient(socketPath: socketPath)
        try supervision.send(.object(["role": .string("supervision")]))
        _ = try supervision.receive() // handshake ack

        var mcp: DaemonClient? = try DaemonClient(socketPath: socketPath)
        try mcp?.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcp!, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        _ = try expectEvent(supervision) // sessionStarted
        _ = try rpc(mcp!, [
            "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
            "params": .object([
                "name": .string("computer_claim"),
                "arguments": .object(["window_id": .number(10)]),
            ]),
        ])
        _ = try expectEvent(supervision) // windowClaimed
        XCTAssertNotNil(daemon.registry.owner(of: 10))

        mcp = nil // close the connection

        let released = try expectEvent(supervision)
        XCTAssertEqual(released["type"], .string("windowReleased"))
        XCTAssertEqual(released["windowID"], .number(10))
        let ended = try expectEvent(supervision)
        XCTAssertEqual(ended["type"], .string("sessionEnded"))
        XCTAssertNil(daemon.registry.owner(of: 10))
    }

    func test_stopSession_revokesSingleSession() throws {
        let supervision = try DaemonClient(socketPath: socketPath)
        try supervision.send(.object(["role": .string("supervision")]))
        _ = try supervision.receive() // handshake ack

        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        _ = try expectEvent(supervision) // sessionStarted

        let sessionID = daemon.registry.sessions.keys.first!.raw
        try supervision.send(.object(["command": .string("stop_session"), "session": .number(Double(sessionID))]))
        let stopped = try expectEvent(supervision)
        XCTAssertEqual(stopped["type"], .string("stopped"))
        XCTAssertEqual(stopped["reason"], .string("session \(sessionID) stopped"))

        let response = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
            "params": .object(["name": .string("computer_windows"), "arguments": .object([:])]),
        ])
        XCTAssertEqual(response["result"]?["isError"], .bool(true))
    }

    func test_secondStart_throwsAlreadyRunning_preservesSocket() throws {
        let second = DaemonServer(engine: FakeEngine(), socketPath: socketPath)
        XCTAssertThrowsError(try second.start()) { error in
            XCTAssertEqual((error as? ComputerError)?.message, "daemon_already_running")
        }

        let client = try DaemonClient(socketPath: socketPath)
        try client.send(.object(["role": .string("mcp")]))
        let response = try rpc(client, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        XCTAssertEqual(response["result"]?["serverInfo"]?["name"], .string("tenx-computer"))
    }

    func test_stop_removesSocketFile() throws {
        _ = try DaemonClient(socketPath: socketPath)
        daemon.stop()
        daemon = nil
        XCTAssertThrowsError(try DaemonClient(socketPath: socketPath)) { error in
            let message = (error as? ComputerError)?.message ?? ""
            XCTAssertTrue(message.hasPrefix("daemon_unreachable:"))
        }
    }

    func test_splitNDJSON_reassemblesLine() throws {
        let client = try DaemonClient(socketPath: socketPath)
        try client.send(.object(["role": .string("mcp")]))

        let request: [String: JSONValue] = [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ]
        var data = try JSONEncoder().encode(JSONValue.object(request))
        data.append(0x0A)
        let split = data.count / 2
        try client.sendBytes(Data(data.prefix(split)))
        try client.sendBytes(Data(data.suffix(from: split)))

        let response = try client.receive()
        XCTAssertEqual(response["result"]?["serverInfo"]?["name"], .string("tenx-computer"))
    }

    func test_windowGone_onToolCall_dropsStaleSnapshot() throws {
        let safari = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        engine.windows = [safari]

        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
            "params": .object([
                "name": .string("computer_claim"),
                "arguments": .object(["window_id": .number(10)]),
            ]),
        ])

        engine.windows = []
        engine.screenshotError = ComputerError("window_gone: 10")
        XCTAssertNotNil(daemon.registry.window(10))

        let shotResponse = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(3), "method": .string("tools/call"),
            "params": .object([
                "name": .string("computer_screenshot"),
                "arguments": .object(["window_id": .number(10)]),
            ]),
        ])
        XCTAssertEqual(shotResponse["result"]?["isError"], .bool(true))
        XCTAssertEqual(shotResponse["result"]?["content"]?.arrayValue?.first?["text"], .string("window_gone: 10"))
        XCTAssertNil(daemon.registry.window(10))
    }

    func test_resourcesRead_captureFailure_returnsCaptureError() throws {
        let safari = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        engine.windows = [safari]
        engine.screenshotShouldFail = true

        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
            "params": .object([
                "name": .string("computer_claim"),
                "arguments": .object(["window_id": .number(10)]),
            ]),
        ])

        let response = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(3), "method": .string("resources/read"),
            "params": .object(["uri": .string("computer://window/10/screenshot")]),
        ])
        XCTAssertNotNil(response["error"])
        let message = response["error"]?["message"]?.stringValue ?? ""
        XCTAssertTrue(message.contains("capture"), "expected capture failure message, got: \(message)")
        XCTAssertFalse(message.contains("Unknown resource"))
    }

    func test_receive_timeout_throwsWhenNoLine() throws {
        let client = try DaemonClient(socketPath: socketPath)
        try client.send(.object(["role": .string("mcp")]))
        XCTAssertThrowsError(try client.receive(timeout: 0.05)) { error in
            XCTAssertEqual((error as? ComputerError)?.message, "receive_timeout")
        }
    }

    func test_stopAll_stopsPreviewHeartbeat() throws {
        daemon.stop()
        daemon = nil
        socketPath = NSTemporaryDirectory() + "tenx-computer-test-\(UUID().uuidString).sock"
        daemon = DaemonServer(engine: engine, socketPath: socketPath, previewInterval: 0.05)
        try daemon.start()

        let safari = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        engine.windows = [safari]
        engine.screenshotPNG = Data([0x89])

        let supervision = try DaemonClient(socketPath: socketPath)
        try supervision.send(.object(["role": .string("supervision")]))
        _ = try supervision.receive()

        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        _ = try expectEvent(supervision)

        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
            "params": .object([
                "name": .string("computer_claim"),
                "arguments": .object(["window_id": .number(10)]),
            ]),
        ])
        _ = try expectEvent(supervision)

        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(3), "method": .string("tools/call"),
            "params": .object([
                "name": .string("computer_act"),
                "arguments": .object([
                    "window_id": .number(10),
                    "action": .string("click"),
                    "x": .number(10),
                    "y": .number(10),
                ]),
            ]),
        ])

        var sawScreenshot = false
        for _ in 0..<5 {
            let event = try expectEvent(supervision)
            if event["type"] == .string("screenshotTaken") {
                sawScreenshot = true
                break
            }
        }
        XCTAssertTrue(sawScreenshot)

        try supervision.send(.object(["command": .string("stop_all")]))
        var gotStopped = false
        for _ in 0..<10 {
            let event = try expectEvent(supervision)
            if event["type"] == .string("stopped") {
                gotStopped = true
                break
            }
        }
        XCTAssertTrue(gotStopped)

        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertThrowsError(try supervision.receive(timeout: 0.1)) { error in
            XCTAssertEqual((error as? ComputerError)?.message, "receive_timeout")
        }
    }

    func test_supervisionClient_unknownEventLine_doesNotTearDownSocket() throws {
        let supervision = try DaemonClient(socketPath: socketPath)
        try supervision.send(.object(["role": .string("supervision")]))
        _ = try supervision.receive() // handshake ack

        try supervision.send(.object(["type": .string("futureEventType"), "foo": .number(1)]))

        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp")]))
        let initResponse = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        XCTAssertEqual(initResponse["result"]?["serverInfo"]?["name"], .string("tenx-computer"))

        let event = try expectEvent(supervision)
        XCTAssertEqual(event["type"], .string("sessionStarted"))
        XCTAssertEqual(event["harness"], .string("omp"))
    }
}

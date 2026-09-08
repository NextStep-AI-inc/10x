import XCTest
@testable import ComputerKit

final class DaemonServerTests: XCTestCase {
    private let eventTimeout: TimeInterval = 2

    var socketPath: String!
    var engine: FakeEngine!
    var daemon: DaemonServer!

    override func setUp() {
        super.setUp()
        socketPath = "/tmp/tx-\(UUID().uuidString.prefix(8)).sock"
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

    func expectEventType(_ client: DaemonClient, _ type: String, file: StaticString = #filePath, line: UInt = #line) throws -> JSONValue {
        for _ in 0..<10 {
            let event = try expectEvent(client, file: file, line: line)
            if event["type"] == .string(type) { return event }
        }
        XCTFail("no \(type) event within 10 reads", file: file, line: line)
        throw ComputerError("missing_event: \(type)")
    }

    func connectSupervision() throws -> DaemonClient {
        let client = try DaemonClient(socketPath: socketPath)
        try client.send(.object(["role": .string("supervision")]))
        _ = try client.receive() // handshake ack
        let permissions = try expectEvent(client)
        XCTAssertEqual(permissions["type"], .string("permissions"))
        return client
    }

    func test_mcpClient_fullFlow() throws {
        let client = try DaemonClient(socketPath: socketPath)
        try client.send(.object(["role": .string("mcp")]))
        let initResponse = try rpc(client, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        XCTAssertEqual(initResponse["result"]?["serverInfo"]?["name"], .string("tenx-computer"))

        let listResponse = try rpc(client, [
            "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/list"),
        ])
        let names = listResponse["result"]?["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
        XCTAssertEqual(names.count, 7)
    }

    func test_supervisionClient_receivesEvents() throws {
        let supervision = try connectSupervision()

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

    func test_sessionStarted_carriesLabelAndPeerPID() throws {
        let supervision = try connectSupervision()

        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp"), "label": .string("Fix login flow")]))
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])

        let event = try expectEvent(supervision)
        XCTAssertEqual(event["type"], .string("sessionStarted"))
        XCTAssertEqual(event["label"], .string("Fix login flow"))
        XCTAssertNotNil(event["pid"])
    }

    func test_stopAll_revokesSessions() throws {
        let supervision = try connectSupervision()

        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        _ = try expectEvent(supervision) // sessionStarted

        try supervision.send(.object(["command": .string("stop_all")]))
        _ = try expectEvent(supervision) // sessionEnded
        let stopped = try expectEvent(supervision)
        XCTAssertEqual(stopped["type"], .string("stopped"))
        XCTAssertEqual(stopped["session"], .null)

        let response = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
            "params": .object(["name": .string("computer_windows"), "arguments": .object([:])]),
        ])
        XCTAssertEqual(response["result"]?["isError"], .bool(true))
    }

    func test_mcpDisconnect_releasesClaims_deadMansSwitch() throws {
        let safari = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        engine.windows = [safari]

        let supervision = try connectSupervision()

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
        XCTAssertNil(daemon.registry.session(SessionID(raw: 1)))
    }

    func test_stopSession_revokesSingleSession() throws {
        let supervision = try connectSupervision()

        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        _ = try expectEvent(supervision) // sessionStarted

        let sessionID = daemon.registry.allSessions.keys.first!.raw
        try supervision.send(.object(["command": .string("stop_session"), "session": .number(Double(sessionID))]))
        let ended = try expectEvent(supervision)
        XCTAssertEqual(ended["type"], .string("sessionEnded"))
        let stopped = try expectEvent(supervision)
        XCTAssertEqual(stopped["type"], .string("stopped"))
        XCTAssertEqual(stopped["reason"], .string("session \(sessionID) stopped"))
        XCTAssertEqual(stopped["session"], .number(Double(sessionID)))

        let response = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
            "params": .object(["name": .string("computer_windows"), "arguments": .object([:])]),
        ])
        XCTAssertEqual(response["result"]?["isError"], .bool(true))
        XCTAssertNotNil(daemon.registry.session(SessionID(raw: sessionID)))
    }

    func test_sessionTombstone_disconnectRemoves_stopSessionKeeps() throws {
        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        let sessionID = daemon.registry.allSessions.keys.first!.raw

        let supervision = try connectSupervision()
        try supervision.send(.object(["command": .string("stop_session"), "session": .number(Double(sessionID))]))
        _ = try expectEvent(supervision) // sessionEnded
        _ = try expectEvent(supervision) // stopped
        XCTAssertNotNil(daemon.registry.session(SessionID(raw: sessionID)))

        let stoppedResponse = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
            "params": .object(["name": .string("computer_windows"), "arguments": .object([:])]),
        ])
        XCTAssertEqual(stoppedResponse["result"]?["isError"], .bool(true))

        var mcp2: DaemonClient? = try DaemonClient(socketPath: socketPath)
        try mcp2?.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcp2!, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("Cursor")])]),
        ])
        let disconnectSession = daemon.registry.allSessions.keys.first { $0.raw != sessionID }!.raw
        mcp2 = nil
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertNil(daemon.registry.session(SessionID(raw: disconnectSession)))
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

    func test_windowGone_onToolCall_dropsStaleSnapshotAndEmitsReleased() throws {
        let safari = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        engine.windows = [safari]

        let supervision = try connectSupervision()

        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        _ = try expectEvent(supervision) // sessionStarted
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
            "params": .object([
                "name": .string("computer_claim"),
                "arguments": .object(["window_id": .number(10)]),
            ]),
        ])
        _ = try expectEvent(supervision) // windowClaimed

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

        let released = try expectEvent(supervision)
        XCTAssertEqual(released["type"], .string("windowReleased"))
        XCTAssertEqual(released["reason"], .string("window_gone"))
        XCTAssertNil(daemon.registry.window(10))
    }

    func test_failedToolCall_emitsNoSupervisionEvents() throws {
        let supervision = try connectSupervision()

        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        _ = try expectEvent(supervision) // sessionStarted

        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
            "params": .object([
                "name": .string("computer_claim"),
                "arguments": .object(["window_id": .number(999)]),
            ]),
        ])

        XCTAssertThrowsError(try supervision.receive(timeout: 0.15)) { error in
            XCTAssertEqual((error as? ComputerError)?.message, "receive_timeout")
        }
    }

    func test_offScreenWindow_claimScreenshotActWork() throws {
        let offScreen = WindowInfo(id: 10, appName: "Safari", title: "Hidden", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        engine.windows = [offScreen]
        engine.offScreenWindowIDs = [10]

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
        let windows = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(3), "method": .string("tools/call"),
            "params": .object(["name": .string("computer_windows"), "arguments": .object([:])]),
        ])
        let listed = windows["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue ?? "[]"
        XCTAssertFalse(listed.contains("\"id\":10"))

        let shot = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(4), "method": .string("tools/call"),
            "params": .object([
                "name": .string("computer_screenshot"),
                "arguments": .object(["window_id": .number(10)]),
            ]),
        ])
        XCTAssertEqual(shot["result"]?["isError"], .bool(false))

        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(5), "method": .string("tools/call"),
            "params": .object([
                "name": .string("computer_act"),
                "arguments": .object([
                    "window_id": .number(10), "action": .string("click"), "x": .number(1), "y": .number(1),
                ]),
            ]),
        ])
        XCTAssertEqual(engine.actions.count, 1)
    }

    func test_actionEventHonestPoints() throws {
        let safari = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        engine.windows = [safari]

        let supervision = try connectSupervision()
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
                    "window_id": .number(10), "action": .string("scroll"), "delta_y": .number(-3),
                ]),
            ]),
        ])
        let scrollAction = try expectEventType(supervision, "action")
        XCTAssertEqual(scrollAction["kind"], .string("scroll"))
        XCTAssertEqual(scrollAction["x"], .number(400))
        XCTAssertEqual(scrollAction["y"], .number(300))

        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(4), "method": .string("tools/call"),
            "params": .object([
                "name": .string("computer_act"),
                "arguments": .object([
                    "window_id": .number(10), "action": .string("type"), "text": .string("hi"),
                ]),
            ]),
        ])
        let typeAction = try expectEventType(supervision, "action")
        XCTAssertEqual(typeAction["type"], .string("action"))
        XCTAssertEqual(typeAction["x"], .null)
        XCTAssertEqual(typeAction["y"], .null)
    }

    func test_statusEventUsesTruncatedValue() throws {
        let supervision = try connectSupervision()
        let mcp = try DaemonClient(socketPath: socketPath)
        try mcp.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        _ = try expectEvent(supervision)

        let longStatus = String(repeating: "x", count: 100)
        _ = try rpc(mcp, [
            "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
            "params": .object([
                "name": .string("computer_status"),
                "arguments": .object(["status": .string(longStatus)]),
            ]),
        ])
        let statusEvent = try expectEvent(supervision)
        XCTAssertEqual(statusEvent["type"], .string("statusChanged"))
        XCTAssertEqual(statusEvent["status"]?.stringValue?.count, 80)
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

    func test_close_unblocksInFlightReceive() throws {
        let client = try DaemonClient(socketPath: socketPath)
        try client.send(.object(["role": .string("mcp")]))
        let threw = expectation(description: "receive throws after close")
        Thread.detachNewThread {
            do {
                _ = try client.receive()
                XCTFail("receive should throw after close")
            } catch {
                XCTAssertEqual((error as? ComputerError)?.message, "daemon_closed")
            }
            threw.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.1) // let receive block first
        client.close()
        wait(for: [threw], timeout: 2)
        client.close() // idempotent
    }

    func test_socketPathTooLong_rejected() {
        let longPath = "/tmp/" + String(repeating: "a", count: 120) + ".sock"
        XCTAssertThrowsError(try DaemonServer(engine: FakeEngine(), socketPath: longPath).start()) { error in
            XCTAssertTrue((error as? ComputerError)?.message.hasPrefix("socket_path_too_long") == true)
        }
        XCTAssertThrowsError(try DaemonClient(socketPath: longPath)) { error in
            XCTAssertTrue((error as? ComputerError)?.message.hasPrefix("socket_path_too_long") == true)
        }
    }

    func test_stopAll_whileBlockingAct_returnsPromptly() throws {
        let safari = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        engine.windows = [safari]
        let actGate = DispatchSemaphore(value: 0)
        engine.actBlock = actGate

        let supervision = try connectSupervision()
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

        let actStarted = expectation(description: "act started")
        DispatchQueue.global().async {
            _ = try? self.rpc(mcp, [
                "jsonrpc": .string("2.0"), "id": .number(3), "method": .string("tools/call"),
                "params": .object([
                    "name": .string("computer_act"),
                    "arguments": .object([
                        "window_id": .number(10), "action": .string("click"), "x": .number(1), "y": .number(1),
                    ]),
                ]),
            ])
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { actStarted.fulfill() }
        wait(for: [actStarted], timeout: 1.0)

        let stopDone = expectation(description: "stop_all returns")
        DispatchQueue.global().async {
            try? supervision.send(.object(["command": .string("stop_all")]))
            stopDone.fulfill()
        }
        wait(for: [stopDone], timeout: 0.5)

        engine.releaseActBlock()
    }

    func test_isCancelled_abortsTypeLoop() throws {
        let engine = FakeEngine()
        engine.windows = [WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)]
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        engine.isCancelled = {
            counter.value += 1
            return counter.value > 2
        }

        let (tools, _, _, _) = makeTools(engine: engine)
        _ = try tools.callTool(name: "computer_claim", arguments: .object(["window_id": .number(10)]))
        XCTAssertThrowsError(try tools.callTool(name: "computer_act", arguments: .object([
            "window_id": .number(10), "action": .string("type"), "text": .string("abcdefghij"),
        ]))) { error in
            XCTAssertEqual((error as? ComputerError)?.message, "aborted: shut-off")
        }
    }

    private func makeTools(engine: FakeEngine) -> (ComputerTools, FakeEngine, SessionRegistry, SessionID) {
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        return (ComputerTools(engine: engine, registry: registry, session: session), engine, registry, session)
    }

    func test_stopAll_stopsPreviewHeartbeat() throws {
        daemon.stop()
        daemon = nil
        socketPath = "/tmp/tx-\(UUID().uuidString.prefix(8)).sock"
        daemon = DaemonServer(engine: engine, socketPath: socketPath, previewInterval: 0.05)
        try daemon.start()

        let safari = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        engine.windows = [safari]
        engine.screenshotPNG = Data([0x89])

        let supervision = try connectSupervision()

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
                XCTAssertEqual(event["width"], .number(100))
                XCTAssertEqual(event["height"], .number(100))
                XCTAssertEqual(event["scale"], .number(2))
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

    func test_heartbeatWindowGone_emitsWindowReleased() throws {
        daemon.stop()
        daemon = nil
        socketPath = "/tmp/tx-\(UUID().uuidString.prefix(8)).sock"
        daemon = DaemonServer(engine: engine, socketPath: socketPath, previewInterval: 0.05)
        try daemon.start()

        let safari = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        engine.windows = [safari]
        engine.screenshotPNG = Data([0x89])

        let supervision = try connectSupervision()
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
                    "window_id": .number(10), "action": .string("click"), "x": .number(1), "y": .number(1),
                ]),
            ]),
        ])

        engine.screenshotError = ComputerError("window_gone: 10")
        let released = expectation(description: "windowReleased from heartbeat")
        DispatchQueue.global().async {
            for _ in 0..<20 {
                guard let event = try? self.expectEvent(supervision) else { continue }
                if event["type"] == .string("windowReleased"), event["reason"] == .string("window_gone") {
                    released.fulfill()
                    return
                }
            }
        }
        wait(for: [released], timeout: 2.0)
        XCTAssertNil(daemon.registry.window(10))
    }

    func test_mcpDisconnect_doesNotStopOtherSessionsPreview() throws {
        daemon.stop()
        daemon = nil
        socketPath = "/tmp/tx-\(UUID().uuidString.prefix(8)).sock"
        daemon = DaemonServer(engine: engine, socketPath: socketPath, previewInterval: 0.05)
        try daemon.start()

        let safari = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        engine.windows = [safari]
        engine.screenshotPNG = Data([0x89])

        let supervision = try connectSupervision()

        let mcpA = try DaemonClient(socketPath: socketPath)
        try mcpA.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcpA, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("omp")])]),
        ])
        _ = try expectEvent(supervision)

        _ = try rpc(mcpA, [
            "jsonrpc": .string("2.0"), "id": .number(2), "method": .string("tools/call"),
            "params": .object([
                "name": .string("computer_claim"),
                "arguments": .object(["window_id": .number(10)]),
            ]),
        ])
        _ = try expectEvent(supervision)

        _ = try rpc(mcpA, [
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

        var mcpB: DaemonClient? = try DaemonClient(socketPath: socketPath)
        try mcpB?.send(.object(["role": .string("mcp")]))
        _ = try rpc(mcpB!, [
            "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("initialize"),
            "params": .object(["clientInfo": .object(["name": .string("Cursor")])]),
        ])
        _ = try expectEvent(supervision)

        mcpB = nil

        _ = try expectEvent(supervision) // sessionEnded from B disconnect

        let screenshotAfterDisconnect = expectation(description: "session A preview continues")
        for _ in 0..<10 {
            let event = try expectEvent(supervision)
            if event["type"] == .string("screenshotTaken"), event["session"] == .number(1) {
                screenshotAfterDisconnect.fulfill()
                break
            }
        }
        wait(for: [screenshotAfterDisconnect], timeout: 1.0)
    }

    func test_supervisionClient_unknownEventLine_doesNotTearDownSocket() throws {
        let supervision = try connectSupervision()

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

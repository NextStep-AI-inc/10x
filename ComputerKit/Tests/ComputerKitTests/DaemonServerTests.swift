import XCTest
@testable import ComputerKit

final class DaemonServerTests: XCTestCase {
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
    }
}

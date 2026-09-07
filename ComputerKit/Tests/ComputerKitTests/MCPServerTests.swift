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

    func test_resourcesSubscribe_isNoOp() throws {
        let (server, _) = makeServer()
        let response = try server.handle(method: "resources/subscribe", params: .object(["uri": .string("computer://window/1/screenshot")]))
        XCTAssertEqual(response, .object([:]))
    }
}

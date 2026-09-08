import XCTest
@testable import ComputerKit

final class MCPServerTests: XCTestCase {
    final class FakeToolProvider: MCPToolProviding {
        enum Behavior {
            case text
            case image
            case error(String)
        }

        var behavior: Behavior = .text
        var tools: [MCPTool] = [
            MCPTool(name: "computer_ping", description: "test tool", inputSchema: .object(["type": .string("object")]))
        ]
        func callTool(name: String, arguments: JSONValue) throws -> MCPResult {
            switch behavior {
            case .text:
                return .text("pong:\(name)")
            case .image:
                return .image(pngBase64: "abc123", text: "screenshot caption")
            case .error(let message):
                throw ComputerError(message)
            }
        }
    }

    func makeServer(behavior: FakeToolProvider.Behavior = .text) -> (MCPServer, FakeToolProvider) {
        let provider = FakeToolProvider()
        provider.behavior = behavior
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

    func test_toolsCall_imageContentEncoding() throws {
        let (server, _) = makeServer(behavior: .image)
        let response = try server.handle(method: "tools/call", params: .object([
            "name": .string("computer_ping"), "arguments": .object([:]),
        ]))
        let content = try XCTUnwrap(response["content"]?.arrayValue)
        XCTAssertEqual(content[0]["type"], .string("image"))
        XCTAssertEqual(content[0]["data"], .string("abc123"))
        XCTAssertEqual(content[0]["mimeType"], .string("image/png"))
        XCTAssertEqual(content[1]["type"], .string("text"))
        XCTAssertEqual(content[1]["text"], .string("screenshot caption"))
        XCTAssertEqual(response["isError"], .bool(false))
    }

    func test_toolsCall_computerError_returnsIsErrorResult() throws {
        let (server, _) = makeServer(behavior: .error("boom"))
        let response = try server.handle(method: "tools/call", params: .object([
            "name": .string("computer_ping"), "arguments": .object([:]),
        ]))
        XCTAssertEqual(response["isError"], .bool(true))
        let text = try XCTUnwrap(response["content"]?.arrayValue?.first?["text"]?.stringValue)
        XCTAssertTrue(text.contains("boom"))
    }

    func test_resourcesList_noProvider_returnsEmptyArray() throws {
        let (server, _) = makeServer()
        let response = try server.handle(method: "resources/list", params: nil)
        XCTAssertEqual(response["resources"]?.arrayValue, [])
    }
}

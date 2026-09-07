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
            // Must answer with an empty array when nothing is claimed — Codex
            // uses resources/list as a health check and flags servers that error.
            return .object(["resources": .array(resourceProvider?.listResources() ?? [])])
        case "resources/subscribe", "resources/unsubscribe":
            // No-op: resources are stateless. Cursor subscribes even when the
            // server declares subscribe:false, and errors here surface in its UI.
            return .object([:])
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

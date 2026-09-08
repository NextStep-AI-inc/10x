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

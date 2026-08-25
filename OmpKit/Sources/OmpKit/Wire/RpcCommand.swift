import Foundation

/// How a prompt sent during an active stream should be queued.
public enum StreamingBehavior: String, Sendable {
    case steer
    case followUp
}

/// How much subagent traffic omp should forward. Defaults to `off` server-side.
public enum SubagentSubscriptionLevel: String, Sendable {
    case off
    case progress
    case events
}

/// One outbound stdin frame.
///
/// Commands carry a generated request id so responses can be correlated;
/// `extension_ui_response` is the exception — its `id` echoes the UI request
/// being answered, and it gets no response of its own.
public struct RpcCommand: Sendable, Equatable {
    public let type: String
    public let fields: [String: JSONValue]

    public init(type: String, fields: [String: JSONValue] = [:]) {
        self.type = type
        self.fields = fields
    }

    /// Serializes to a single newline-terminated JSON line.
    public func encodedLine(id: String) throws -> Data {
        var object = fields
        object["type"] = .string(type)
        // extension_ui_response addresses a pending UI request, so it keeps the
        // id already in `fields` instead of taking a new request id.
        if type != Self.extensionUIResponseType {
            object["id"] = .string(id)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(JSONValue.object(object))
        data.append(UInt8(ascii: "\n"))
        return data
    }

    private static let extensionUIResponseType = "extension_ui_response"

    // MARK: - Protocol

    public static func negotiateProtocol(version: Int) -> RpcCommand {
        RpcCommand(type: "negotiate_protocol", fields: ["protocolVersion": .int(version)])
    }

    // MARK: - Login

    public static func getLoginProviders() -> RpcCommand {
        RpcCommand(type: "get_login_providers")
    }

    public static func login(providerID: String) -> RpcCommand {
        RpcCommand(type: "login", fields: ["providerId": .string(providerID)])
    }

    // MARK: - Prompting

    public static func prompt(message: String, streamingBehavior: StreamingBehavior?) -> RpcCommand {
        var fields: [String: JSONValue] = ["message": .string(message)]
        if let streamingBehavior {
            fields["streamingBehavior"] = .string(streamingBehavior.rawValue)
        }
        return RpcCommand(type: "prompt", fields: fields)
    }

    public static func abort() -> RpcCommand { RpcCommand(type: "abort") }

    public static func newSession(parentSession: String?) -> RpcCommand {
        var fields: [String: JSONValue] = [:]
        if let parentSession { fields["parentSession"] = .string(parentSession) }
        return RpcCommand(type: "new_session", fields: fields)
    }

    // MARK: - State

    public static func getState() -> RpcCommand { RpcCommand(type: "get_state") }

    public static func getAvailableCommands() -> RpcCommand {
        RpcCommand(type: "get_available_commands")
    }

    public static func setSubagentSubscription(level: SubagentSubscriptionLevel) -> RpcCommand {
        RpcCommand(type: "set_subagent_subscription", fields: ["level": .string(level.rawValue)])
    }

    // MARK: - Model and thinking

    public static func setModel(provider: String, modelId: String) -> RpcCommand {
        RpcCommand(type: "set_model", fields: [
            "provider": .string(provider),
            "modelId": .string(modelId),
        ])
    }

    public static func getAvailableModels() -> RpcCommand {
        RpcCommand(type: "get_available_models")
    }

    public static func setThinkingLevel(_ level: String) -> RpcCommand {
        RpcCommand(type: "set_thinking_level", fields: ["level": .string(level)])
    }

    // MARK: - Session

    public static func switchSession(path: String) -> RpcCommand {
        RpcCommand(type: "switch_session", fields: ["sessionPath": .string(path)])
    }

    public static func getSessionStats() -> RpcCommand { RpcCommand(type: "get_session_stats") }

    public static func setSessionName(_ name: String) -> RpcCommand {
        RpcCommand(type: "set_session_name", fields: ["name": .string(name)])
    }

    public static func compact(customInstructions: String?) -> RpcCommand {
        var fields: [String: JSONValue] = [:]
        if let customInstructions {
            fields["customInstructions"] = .string(customInstructions)
        }
        return RpcCommand(type: "compact", fields: fields)
    }

    // MARK: - Messages

    public static func getMessages() -> RpcCommand { RpcCommand(type: "get_messages") }

    public static func getMessagesPage(cursor: String?, limit: Int?) -> RpcCommand {
        var fields: [String: JSONValue] = [:]
        if let cursor { fields["cursor"] = .string(cursor) }
        if let limit { fields["limit"] = .int(limit) }
        return RpcCommand(type: "get_messages_page", fields: fields)
    }

    public static func getSubagentMessages(
        subagentId: String?,
        sessionFile: String?,
        fromByte: Int?
    ) -> RpcCommand {
        var fields: [String: JSONValue] = [:]
        if let subagentId { fields["subagentId"] = .string(subagentId) }
        if let sessionFile { fields["sessionFile"] = .string(sessionFile) }
        if let fromByte { fields["fromByte"] = .int(fromByte) }
        return RpcCommand(type: "get_subagent_messages", fields: fields)
    }

    // MARK: - Extension UI

    /// Answers a pending `extension_ui_request`. `body` carries the method's
    /// reply shape (`value`, `confirmed`, or `cancelled`).
    public static func extensionUIResponse(id: String, body: [String: JSONValue]) -> RpcCommand {
        var fields = body
        fields["id"] = .string(id)
        return RpcCommand(type: extensionUIResponseType, fields: fields)
    }
}

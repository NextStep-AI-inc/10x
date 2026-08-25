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

/// Controls whether computer input may target a background window.
public enum ComputerForegroundPolicy: String, Sendable, Codable, Equatable {
    case allow
    case requireHandoff = "require-handoff"
}

/// The computer-use settings reported by supported omp servers.
public struct ComputerUseRPCState: Sendable, Equatable {
    public let enabled: Bool
    public let foregroundPolicy: ComputerForegroundPolicy

    public init(enabled: Bool, foregroundPolicy: ComputerForegroundPolicy) {
        self.enabled = enabled
        self.foregroundPolicy = foregroundPolicy
    }

    public init?(json: JSONValue?) {
        guard let enabled = json?["enabled"]?.boolValue,
              let rawPolicy = json?["foregroundPolicy"]?.stringValue,
              let foregroundPolicy = ComputerForegroundPolicy(rawValue: rawPolicy)
        else { return nil }
        self.init(enabled: enabled, foregroundPolicy: foregroundPolicy)
    }
}

public enum ComputerPermissionState: String, Sendable, Equatable {
    case granted
    case denied
    case unavailable
    case unknown
}

/// Platform permissions required to execute a computer-use request.
public struct ComputerCapabilities: Sendable, Equatable {
    public let backend: String
    public let capture: ComputerPermissionState
    public let input: ComputerPermissionState
    public let accessibility: ComputerPermissionState

    public init(
        backend: String,
        capture: ComputerPermissionState,
        input: ComputerPermissionState,
        accessibility: ComputerPermissionState
    ) {
        self.backend = backend
        self.capture = capture
        self.input = input
        self.accessibility = accessibility
    }

    public init?(json: JSONValue?) {
        guard let backend = json?["backend"]?.stringValue else { return nil }
        self.init(
            backend: backend,
            capture: ComputerPermissionState(
                rawValue: json?["capturePermission"]?.stringValue ?? ""
            ) ?? .unknown,
            input: ComputerPermissionState(
                rawValue: json?["inputPermission"]?.stringValue ?? ""
            ) ?? .unknown,
            accessibility: ComputerPermissionState(
                rawValue: json?["axPermission"]?.stringValue ?? ""
            ) ?? .unknown
        )
    }

    public var isReady: Bool {
        capture == .granted && input == .granted && accessibility == .granted
    }

    public static let unknown = ComputerCapabilities(
        backend: "unknown", capture: .unknown, input: .unknown, accessibility: .unknown
    )
}

/// The result of a computer-use capability probe.
public struct ComputerProbeResult: Sendable, Equatable {
    public let capabilities: ComputerCapabilities
    public let captureSucceeded: Bool
    public let backgroundInputSucceeded: Bool?

    public init?(json: JSONValue?) {
        guard let capabilities = ComputerCapabilities(json: json?["capabilities"]),
              let captureSucceeded = json?["captureSucceeded"]?.boolValue
        else { return nil }
        self.capabilities = capabilities
        self.captureSucceeded = captureSucceeded
        self.backgroundInputSucceeded = json?["backgroundInputSucceeded"]?.boolValue
    }
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
        // Reply frames address an existing host/UI request, so they keep the
        // correlation id already in `fields` instead of taking a new request id.
        if !Self.replyTypes.contains(type) {
            object["id"] = .string(id)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(JSONValue.object(object))
        data.append(UInt8(ascii: "\n"))
        return data
    }

    private static let extensionUIResponseType = "extension_ui_response"
    private static let replyTypes: Set<String> = [
        extensionUIResponseType,
        "host_tool_update",
        "host_tool_result",
    ]

    // MARK: - Protocol

    public static func negotiateProtocol(version: Int) -> RpcCommand {
        RpcCommand(type: "negotiate_protocol", fields: ["protocolVersion": .int(version)])
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

    public static func setComputerUse(
        enabled: Bool,
        foregroundPolicy: ComputerForegroundPolicy
    ) -> RpcCommand {
        RpcCommand(type: "set_computer_use", fields: [
            "enabled": .bool(enabled),
            "foregroundPolicy": .string(foregroundPolicy.rawValue),
        ])
    }

    public static func getComputerUse() -> RpcCommand {
        RpcCommand(type: "get_computer_use")
    }

    public static func probeComputerUse(
        target: String? = nil,
        verificationText: String? = nil
    ) -> RpcCommand {
        var fields: [String: JSONValue] = [:]
        if let target { fields["target"] = .string(target) }
        if let verificationText { fields["verificationText"] = .string(verificationText) }
        return RpcCommand(type: "probe_computer_use", fields: fields)
    }

    public static func setHostTools(_ tools: [HostToolDefinition]) -> RpcCommand {
        RpcCommand(type: "set_host_tools", fields: [
            "tools": .array(tools.map {
                .object([
                    "name": .string($0.name),
                    "description": .string($0.description),
                    "parameters": $0.parameters,
                ])
            }),
        ])
    }

    public static func hostToolUpdate(id: String, partialResult: JSONValue) -> RpcCommand {
        RpcCommand(type: "host_tool_update", fields: [
            "id": .string(id),
            "partialResult": partialResult,
        ])
    }

    public static func hostToolResult(
        id: String,
        result: JSONValue,
        isError: Bool? = nil
    ) -> RpcCommand {
        var fields: [String: JSONValue] = [
            "id": .string(id),
            "result": result,
        ]
        if let isError { fields["isError"] = .bool(isError) }
        return RpcCommand(type: "host_tool_result", fields: fields)
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

    public static func computerForegroundHandoffResponse(id: String, approved: Bool) -> RpcCommand {
        extensionUIResponse(id: id, body: ["approved": .bool(approved)])
    }
}

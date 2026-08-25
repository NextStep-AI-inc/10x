import Foundation

/// Structural problems with an inbound frame. Unrecognized frame *types* are
/// never errors — they decode to `.event` — so these all signal a malformed line.
public enum RpcFrameError: Error, Sendable, Equatable {
    case notAnObject
    case missingType
    case malformedFrame(type: String, underlying: String)
}

/// The handshake frame omp writes before processing any command.
public struct ReadyFrame: Sendable, Decodable, Equatable {
    public let protocolVersion: Int
    public let supportedProtocolVersions: [Int]?
    public let maxFrameBytes: Int?
    public let maxReassembledFrameBytes: Int?

    public init(
        protocolVersion: Int,
        supportedProtocolVersions: [Int]? = nil,
        maxFrameBytes: Int? = nil,
        maxReassembledFrameBytes: Int? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.supportedProtocolVersions = supportedProtocolVersions
        self.maxFrameBytes = maxFrameBytes
        self.maxReassembledFrameBytes = maxReassembledFrameBytes
    }
}

/// A command result. Correlated to its request by `id`, never by arrival order.
public struct RpcResponse: Sendable, Equatable {
    public let id: String?
    public let command: String
    public let success: Bool
    public let data: JSONValue?
    public let error: String?
    public let code: String?

    public init(
        id: String?, command: String, success: Bool,
        data: JSONValue? = nil, error: String? = nil, code: String? = nil
    ) {
        self.id = id
        self.command = command
        self.success = success
        self.data = data
        self.error = error
        self.code = code
    }

    init(object: [String: JSONValue]) throws {
        guard let command = object["command"]?.stringValue else {
            throw RpcFrameError.malformedFrame(type: "response", underlying: "missing command")
        }
        guard let success = object["success"]?.boolValue else {
            throw RpcFrameError.malformedFrame(type: "response", underlying: "missing success")
        }
        self.init(
            id: object["id"]?.stringValue,
            command: command,
            success: success,
            data: object["data"],
            error: object["error"]?.stringValue,
            code: object["code"]?.stringValue
        )
    }
}

/// One segment of a losslessly-chunked oversized frame (protocol v2).
public struct RpcChunk: Sendable, Equatable {
    public let chunkId: String
    public let index: Int
    public let count: Int
    public let byteLength: Int
    public let data: String

    public init(chunkId: String, index: Int, count: Int, byteLength: Int, data: String) {
        self.chunkId = chunkId
        self.index = index
        self.count = count
        self.byteLength = byteLength
        self.data = data
    }

    init(object: [String: JSONValue]) throws {
        func requiredInt(_ key: String) throws -> Int {
            // `intValue` is nil for JSON booleans, which is the point: the wire
            // contract requires rejecting `true` in a numeric position.
            guard let value = object[key]?.intValue else {
                throw RpcFrameError.malformedFrame(
                    type: "rpc_chunk", underlying: "field \(key) is not an integer")
            }
            return value
        }
        guard let chunkId = object["chunkId"]?.stringValue else {
            throw RpcFrameError.malformedFrame(type: "rpc_chunk", underlying: "missing chunkId")
        }
        guard let data = object["data"]?.stringValue else {
            throw RpcFrameError.malformedFrame(type: "rpc_chunk", underlying: "missing data")
        }
        self.init(
            chunkId: chunkId,
            index: try requiredInt("index"),
            count: try requiredInt("count"),
            byteLength: try requiredInt("byteLength"),
            data: data
        )
    }
}

/// A UI request from an extension running inside the agent. Some methods expect
/// an `extension_ui_response`; the payload is kept whole so callers can decide.
public struct ExtensionUIRequest: Sendable, Equatable {
    public let id: String
    public let method: String
    public let payload: JSONValue

    public init(id: String, method: String, payload: JSONValue) {
        self.id = id
        self.method = method
        self.payload = payload
    }
}

/// One decoded line of omp's stdout stream.
public enum RpcFrame: Sendable, Equatable {
    case ready(ReadyFrame)
    case response(RpcResponse)
    case chunk(RpcChunk)
    case extensionUIRequest(ExtensionUIRequest)
    /// Everything else: session events, notices, command updates, and any frame
    /// type a newer omp introduces.
    case event(type: String, payload: JSONValue)

    public static func decode(line: Data) throws -> RpcFrame {
        let value = try JSONValue.decode(from: line)
        guard case .object(let object) = value else { throw RpcFrameError.notAnObject }
        guard let type = object["type"]?.stringValue else { throw RpcFrameError.missingType }

        switch type {
        case "ready":
            guard let protocolVersion = object["protocolVersion"]?.intValue else {
                throw RpcFrameError.malformedFrame(
                    type: type, underlying: "missing protocolVersion")
            }
            return .ready(ReadyFrame(
                protocolVersion: protocolVersion,
                supportedProtocolVersions: object["supportedProtocolVersions"]?
                    .arrayValue?.compactMap(\.intValue),
                maxFrameBytes: object["maxFrameBytes"]?.intValue,
                maxReassembledFrameBytes: object["maxReassembledFrameBytes"]?.intValue
            ))
        case "response":
            return .response(try RpcResponse(object: object))
        case "rpc_chunk":
            return .chunk(try RpcChunk(object: object))
        case "extension_ui_request":
            guard let id = object["id"]?.stringValue,
                  let method = object["method"]?.stringValue
            else {
                throw RpcFrameError.malformedFrame(type: type, underlying: "missing id or method")
            }
            return .extensionUIRequest(ExtensionUIRequest(id: id, method: method, payload: value))
        default:
            return .event(type: type, payload: value)
        }
    }
}

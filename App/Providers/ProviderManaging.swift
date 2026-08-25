import Foundation
import OmpKit

protocol ProviderRPCClient: Sendable {
    var events: AsyncStream<RpcFrame> { get }

    func start() async throws -> ReadyFrame
    func send(_ command: RpcCommand, timeout: Duration?) async throws -> RpcResponse
    func sendRaw(_ command: RpcCommand) async throws
    func shutdown() async
}

extension RpcClient: ProviderRPCClient {}

protocol ProviderManaging: Sendable {
    var events: AsyncStream<ExtensionUIRequest> { get }

    func providers() async throws -> [ProviderLoginProvider]
    func login(providerID: String) async throws
    func respond(requestID: String, body: [String: JSONValue]) async throws
    func cancelLogin() async
    func shutdown() async
}

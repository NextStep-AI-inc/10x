import Foundation
import OmpKit

struct ProviderLoginEvent: Sendable {
    let request: ExtensionUIRequest
    let generation: Int
}

protocol ProviderRPCClient: Sendable {
    var events: AsyncStream<RpcFrame> { get }

    func start() async throws -> ReadyFrame
    func send(_ command: RpcCommand, timeout: Duration?) async throws -> RpcResponse
    func sendRaw(_ command: RpcCommand) async throws
    func shutdown() async
}

extension RpcClient: ProviderRPCClient {}

protocol ProviderManaging: ProviderAccountManaging {
    var events: AsyncStream<ProviderLoginEvent> { get }

    func providers() async throws -> [ProviderLoginProvider]
    func accountCapability(providerID: String) async throws -> ProviderAccountCapability
    func login(providerID: String, generation: Int) async throws
    func respond(requestID: String, body: [String: JSONValue]) async throws
    func cancelLogin() async
    func shutdown() async
}

extension ProviderManaging {
    func accountCapability(providerID: String) async throws -> ProviderAccountCapability {
        .providerOnly
    }

    func accounts(providerID: String) async throws -> [ProviderAccountSummary] {
        []
    }

    func accountUsage(providerID: String) async throws -> [ProviderAccountUsage] {
        []
    }

    func removeAccount(
        providerID: String,
        accountRef: String
    ) async throws -> ProviderAccountRemovalResult {
        ProviderAccountRemovalResult(removed: false, accounts: [])
    }
}

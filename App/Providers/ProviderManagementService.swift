import Foundation
import OmpKit

enum ProviderManagementServiceError: LocalizedError, Sendable {
    case invalidProviderResponse
    case loginInProgress

    var errorDescription: String? {
        switch self {
        case .invalidProviderResponse:
            "[Providers:ProviderManagementService] Invalid provider response — {providers}"
        case .loginInProgress:
            "[Providers:ProviderManagementService] Login already in progress — {login}"
        }
    }
}

private struct ProviderRPCClientBox: ProviderRPCClient {
    let events: AsyncStream<RpcFrame>
    private let onStart: @Sendable () async throws -> ReadyFrame
    private let onSend: @Sendable (RpcCommand, Duration?) async throws -> RpcResponse
    private let onSendRaw: @Sendable (RpcCommand) async throws -> Void
    private let onShutdown: @Sendable () async -> Void

    init<Client: ProviderRPCClient>(_ client: Client) {
        events = client.events
        onStart = { try await client.start() }
        onSend = { command, timeout in try await client.send(command, timeout: timeout) }
        onSendRaw = { command in try await client.sendRaw(command) }
        onShutdown = { await client.shutdown() }
    }

    func start() async throws -> ReadyFrame { try await onStart() }

    func send(_ command: RpcCommand, timeout: Duration?) async throws -> RpcResponse {
        try await onSend(command, timeout)
    }

    func sendRaw(_ command: RpcCommand) async throws {
        try await onSendRaw(command)
    }

    func shutdown() async {
        await onShutdown()
    }
}

actor ProviderManagementService: ProviderManaging {
    private typealias ClientFactory = @Sendable (RpcClientConfiguration) async -> ProviderRPCClientBox

    nonisolated let events: AsyncStream<ExtensionUIRequest>

    private let eventContinuation: AsyncStream<ExtensionUIRequest>.Continuation
    private let configuration: RpcClientConfiguration
    private let clientFactory: ClientFactory
    private var client: ProviderRPCClientBox?
    private var eventForwarder: Task<Void, Never>?
    private var clientGeneration = 0
    private var isLoginInProgress = false

    init<Client: ProviderRPCClient>(
        executableURL: URL,
        clientFactory: @escaping @Sendable (RpcClientConfiguration) async -> Client
    ) {
        var configuration = RpcClientConfiguration()
        configuration.executable = executableURL.path
        configuration.noSession = true
        self.configuration = configuration
        self.clientFactory = { configuration in
            ProviderRPCClientBox(await clientFactory(configuration))
        }
        (events, eventContinuation) = AsyncStream<ExtensionUIRequest>.makeStream()
    }

    init(executableURL: URL) {
        var configuration = RpcClientConfiguration()
        configuration.executable = executableURL.path
        configuration.noSession = true
        self.configuration = configuration
        self.clientFactory = { configuration in
            ProviderRPCClientBox(RpcClient(configuration: configuration))
        }
        (events, eventContinuation) = AsyncStream<ExtensionUIRequest>.makeStream()
    }

    func providers() async throws -> [ProviderLoginProvider] {
        let client = try await clientForRequest()
        let response = try await client.send(.getLoginProviders(), timeout: nil)
        return try parseProviders(response.data)
    }

    func login(providerID: String) async throws {
        guard !isLoginInProgress else { throw ProviderManagementServiceError.loginInProgress }
        isLoginInProgress = true
        defer { isLoginInProgress = false }

        let client = try await clientForRequest()
        _ = try await client.send(.login(providerID: providerID), timeout: .seconds(600))
    }

    func respond(requestID: String, body: [String: JSONValue]) async throws {
        let client = try await clientForRequest()
        try await client.sendRaw(.extensionUIResponse(id: requestID, body: body))
    }

    func cancelLogin() async {
        await closeClient()
    }

    func shutdown() async {
        await closeClient()
        eventContinuation.finish()
    }

    private func clientForRequest() async throws -> ProviderRPCClientBox {
        if let client { return client }

        let generation = clientGeneration
        let client = await clientFactory(configuration)
        self.client = client
        do {
            _ = try await client.start()
            guard generation == clientGeneration else {
                await client.shutdown()
                throw CancellationError()
            }
            startForwarding(events: client.events)
            return client
        } catch {
            if generation == clientGeneration {
                await closeClient()
            }
            throw error
        }
    }

    private func startForwarding(events: AsyncStream<RpcFrame>) {
        eventForwarder?.cancel()
        let continuation = eventContinuation
        eventForwarder = Task {
            for await frame in events {
                guard !Task.isCancelled else { return }
                if case .extensionUIRequest(let request) = frame {
                    continuation.yield(request)
                }
            }
        }
    }

    private func closeClient() async {
        clientGeneration += 1
        eventForwarder?.cancel()
        eventForwarder = nil
        guard let client else { return }
        self.client = nil
        await client.shutdown()
    }

    private func parseProviders(_ data: JSONValue?) throws -> [ProviderLoginProvider] {
        guard let values = data?["providers"]?.arrayValue else {
            throw ProviderManagementServiceError.invalidProviderResponse
        }

        return try values.map { value in
            guard let object = value.objectValue,
                  let id = object["id"]?.stringValue,
                  let name = object["name"]?.stringValue,
                  let isAvailable = object["available"]?.boolValue,
                  let isAuthenticated = object["authenticated"]?.boolValue
            else {
                throw ProviderManagementServiceError.invalidProviderResponse
            }
            return ProviderLoginProvider(
                id: id,
                name: name,
                isAvailable: isAvailable,
                isAuthenticated: isAuthenticated)
        }
    }
}

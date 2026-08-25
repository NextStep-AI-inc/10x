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

    private struct Startup {
        let id: UUID
        let generation: Int
        let task: Task<ProviderRPCClientBox, Error>
    }

    private enum ClientState {
        case idle
        case starting(Startup)
        case ready(ProviderRPCClientBox)
    }

    nonisolated let events: AsyncStream<ProviderLoginEvent>

    private let eventContinuation: AsyncStream<ProviderLoginEvent>.Continuation
    private let configuration: RpcClientConfiguration
    private let clientFactory: ClientFactory
    private let startupWaiterObserver: @Sendable () async -> Void
    private var clientState: ClientState = .idle
    private var eventForwarder: Task<Void, Never>?
    private var clientGeneration = 0
    private var isLoginInProgress = false
    private var activeLoginGeneration: Int?

    init<Client: ProviderRPCClient>(
        executableURL: URL,
        clientFactory: @escaping @Sendable (RpcClientConfiguration) async -> Client,
        startupWaiterObserver: @escaping @Sendable () async -> Void = {}
    ) {
        var configuration = RpcClientConfiguration()
        configuration.executable = executableURL.path
        configuration.noSession = true
        self.configuration = configuration
        self.clientFactory = { configuration in
            ProviderRPCClientBox(await clientFactory(configuration))
        }
        self.startupWaiterObserver = startupWaiterObserver
        (events, eventContinuation) = AsyncStream<ProviderLoginEvent>.makeStream()
    }

    init(executableURL: URL) {
        var configuration = RpcClientConfiguration()
        configuration.executable = executableURL.path
        configuration.noSession = true
        self.configuration = configuration
        self.clientFactory = { configuration in
            ProviderRPCClientBox(RpcClient(configuration: configuration))
        }
        self.startupWaiterObserver = {}
        (events, eventContinuation) = AsyncStream<ProviderLoginEvent>.makeStream()
    }

    func providers() async throws -> [ProviderLoginProvider] {
        let client = try await clientForRequest()
        let response = try await client.send(.getLoginProviders(), timeout: nil)
        return try parseProviders(response.data)
    }

    func login(providerID: String, generation: Int) async throws {
        guard !isLoginInProgress else { throw ProviderManagementServiceError.loginInProgress }
        isLoginInProgress = true
        activeLoginGeneration = generation
        defer {
            isLoginInProgress = false
            if activeLoginGeneration == generation {
                activeLoginGeneration = nil
            }
        }

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
        switch clientState {
        case .ready(let client):
            return client
        case .starting(let startup):
            await startupWaiterObserver()
            return try await awaitStartup(startup)
        case .idle:
            let startup = makeStartup()
            clientState = .starting(startup)
            await startupWaiterObserver()
            return try await awaitStartup(startup)
        }
    }

    private func makeStartup() -> Startup {
        let id = UUID()
        let generation = clientGeneration
        let configuration = configuration
        let clientFactory = clientFactory
        let task = Task {
            let client = await clientFactory(configuration)
            do {
                _ = try await client.start()
                return client
            } catch {
                await client.shutdown()
                throw error
            }
        }
        return Startup(id: id, generation: generation, task: task)
    }

    private func awaitStartup(_ startup: Startup) async throws -> ProviderRPCClientBox {
        do {
            let client = try await startup.task.value
            guard startup.generation == clientGeneration else {
                clearStarting(startup)
                throw CancellationError()
            }

            switch clientState {
            case .ready(let client):
                return client
            case .starting(let current) where current.id == startup.id:
                clientState = .ready(client)
                startForwarding(events: client.events)
                return client
            case .idle, .starting:
                await client.shutdown()
                throw CancellationError()
            }
        } catch {
            clearStarting(startup)
            throw error
        }
    }

    private func startForwarding(events: AsyncStream<RpcFrame>) {
        eventForwarder?.cancel()
        let continuation = eventContinuation
        eventForwarder = Task { [weak self] in
            for await frame in events {
                guard !Task.isCancelled else { return }
                if case .extensionUIRequest(let request) = frame {
                    await self?.forward(request, to: continuation)
                }
            }
        }
    }

    private func forward(
        _ request: ExtensionUIRequest,
        to continuation: AsyncStream<ProviderLoginEvent>.Continuation
    ) {
        guard let generation = activeLoginGeneration else { return }
        continuation.yield(ProviderLoginEvent(request: request, generation: generation))
    }

    private func closeClient() async {
        clientGeneration += 1
        activeLoginGeneration = nil
        eventForwarder?.cancel()
        eventForwarder = nil
        let state = clientState
        clientState = .idle

        switch state {
        case .idle:
            break
        case .starting(let startup):
            startup.task.cancel()
            if case .success(let client) = await startup.task.result {
                await client.shutdown()
            }
        case .ready(let client):
            await client.shutdown()
        }
    }

    private func clearStarting(_ startup: Startup) {
        guard case .starting(let current) = clientState, current.id == startup.id else { return }
        clientState = .idle
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

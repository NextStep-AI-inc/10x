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

    /// OMP refuses to start `--mode rpc` when the profile has no model source
    /// configured, which is exactly the state of a brand-new user — so a
    /// fresh profile can never even list login providers. As a one-shot
    /// retry, we start with a placeholder `ANTHROPIC_API_KEY` so RPC mode has
    /// a model source to boot with. The key is not real, so `parseProviders`
    /// forces this provider's `isAuthenticated` back to `false` whenever the
    /// placeholder is active — the user is not actually connected, and this
    /// reports the truth instead of a fabricated login.
    private static let placeholderEnvironmentKey = "ANTHROPIC_API_KEY"
    private static let placeholderEnvironmentValue = "10x-onboarding-placeholder-not-a-real-key"
    private static let placeholderProviderID = "anthropic"

    private struct StartupResult: Sendable {
        let client: ProviderRPCClientBox
        let usedPlaceholder: Bool
    }

    /// A ready client bundled with the mask that applies to whatever it
    /// returns. Binding these together — rather than reading a separate
    /// actor-global "is the placeholder active" field at response time — is
    /// what keeps the mask correct under concurrency: a concurrent
    /// `login()` can close this client and start a fresh, unmasked one
    /// while a `providers()` call is still awaiting a response from THIS
    /// client, and that response must still be masked according to the
    /// client that actually produced it, not whatever the actor holds by
    /// the time the response arrives.
    private struct ActiveClient: Sendable {
        let client: ProviderRPCClientBox
        let maskedProviderID: String?
    }

    private struct Startup {
        let id: UUID
        let generation: Int
        let task: Task<StartupResult, Error>
    }

    private struct Closing {
        let id: UUID
        let task: Task<Void, Never>
    }

    private enum ClientState {
        case idle
        case starting(Startup)
        case ready(ActiveClient)
        case closing(Closing)
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
        configuration.extraArguments += ProviderExtensionBundle.spawnArguments()
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
        configuration.extraArguments += ProviderExtensionBundle.spawnArguments()
        self.configuration = configuration
        self.clientFactory = { configuration in
            ProviderRPCClientBox(RpcClient(configuration: configuration))
        }
        self.startupWaiterObserver = {}
        (events, eventContinuation) = AsyncStream<ProviderLoginEvent>.makeStream()
    }

    func providers() async throws -> [ProviderLoginProvider] {
        let active = try await clientForRequest()
        let response = try await active.client.send(.getLoginProviders(), timeout: nil)
        return try parseProviders(response.data, maskedProviderID: active.maskedProviderID)
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

        let active = try await clientForRequest()
        _ = try await active.client.send(.login(providerID: providerID), timeout: .seconds(600))

        // The profile now has real credentials and will boot on its own.
        // Close the client so the next request starts a fresh one with no
        // placeholder: a real login must not stay masked, and a stale
        // placeholder key must never shadow the credentials just saved.
        await closeClient()
    }

    func respond(requestID: String, body: [String: JSONValue]) async throws {
        let active = try await clientForRequest()
        try await active.client.sendRaw(.extensionUIResponse(id: requestID, body: body))
    }

    func cancelLogin() async {
        await closeClient()
    }

    func shutdown() async {
        await closeClient()
        eventContinuation.finish()
    }

    private func clientForRequest() async throws -> ActiveClient {
        switch clientState {
        case .ready(let active):
            return active
        case .starting(let startup):
            await startupWaiterObserver()
            return try await awaitStartup(startup)
        case .closing(let closing):
            await closing.task.value
            clearClosing(closing)
            return try await clientForRequest()
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
                return StartupResult(client: client, usedPlaceholder: false)
            } catch {
                await client.shutdown()
                let originalError = error

                // Any start failure earns exactly one retry, with the
                // placeholder model source merged in — no inspecting the
                // error text, since OMP's refusal is the only case this can
                // plausibly fix and every other failure just repeats.
                var retryConfiguration = configuration
                var environment = OmpProcessEnvironment.resolved()
                environment[Self.placeholderEnvironmentKey] = Self.placeholderEnvironmentValue
                retryConfiguration.environment = environment

                let retryClient = await clientFactory(retryConfiguration)
                do {
                    _ = try await retryClient.start()
                    return StartupResult(client: retryClient, usedPlaceholder: true)
                } catch {
                    await retryClient.shutdown()
                    throw originalError
                }
            }
        }
        return Startup(id: id, generation: generation, task: task)
    }

    private func awaitStartup(_ startup: Startup) async throws -> ActiveClient {
        do {
            let result = try await startup.task.value
            guard startup.generation == clientGeneration else {
                clearStarting(startup)
                throw CancellationError()
            }

            switch clientState {
            case .ready(let active):
                return active
            case .starting(let current) where current.id == startup.id:
                let active = ActiveClient(
                    client: result.client,
                    maskedProviderID: result.usedPlaceholder ? Self.placeholderProviderID : nil)
                clientState = .ready(active)
                startForwarding(events: active.client.events)
                return active
            case .idle, .starting:
                await result.client.shutdown()
                throw CancellationError()
            case .closing:
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
        if case .closing(let closing) = clientState {
            await closing.task.value
            clearClosing(closing)
            return
        }

        clientGeneration += 1
        activeLoginGeneration = nil
        eventForwarder?.cancel()
        eventForwarder = nil
        let state = clientState

        switch state {
        case .idle:
            return
        case .starting(let startup):
            startup.task.cancel()
            let closing = Closing(id: UUID(), task: Task {
                if case .success(let result) = await startup.task.result {
                    await result.client.shutdown()
                }
            })
            clientState = .closing(closing)
            await closing.task.value
            clearClosing(closing)
        case .ready(let active):
            let closing = Closing(id: UUID(), task: Task {
                await active.client.shutdown()
            })
            clientState = .closing(closing)
            await closing.task.value
            clearClosing(closing)
        case .closing(let closing):
            await closing.task.value
            clearClosing(closing)
        }
    }

    private func clearClosing(_ closing: Closing) {
        guard case .closing(let current) = clientState, current.id == closing.id else { return }
        clientState = .idle
    }

    private func clearStarting(_ startup: Startup) {
        guard case .starting(let current) = clientState, current.id == startup.id else { return }
        clientState = .idle
    }

    /// `maskedProviderID` must come from the `ActiveClient` that produced
    /// `data` (see `ActiveClient`'s doc comment) — never re-read from actor
    /// state at parse time, since that state can have moved on to a
    /// different client by the time a slow response arrives.
    private func parseProviders(
        _ data: JSONValue?,
        maskedProviderID: String?
    ) throws -> [ProviderLoginProvider] {
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
            // The placeholder key makes OMP report this provider as
            // authenticated purely because the env var exists. Mask it back
            // to false: the user genuinely has not logged in.
            let isMasked = maskedProviderID == id
            return ProviderLoginProvider(
                id: id,
                name: name,
                isAvailable: isAvailable,
                isAuthenticated: isMasked ? false : isAuthenticated)
        }
    }
}

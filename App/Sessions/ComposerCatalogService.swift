import Foundation
import OmpKit

struct ComposerCatalogSnapshot: Equatable, Sendable {
    let models: [ComposerModelInfo]
    let selected: ComposerModelInfo?
    let thinkingLevel: String?
    let fastModeEnabled: Bool
    let fastModeActive: Bool
    let commandCatalog: ComposerCommandCatalogState

    init(
        models: [ComposerModelInfo],
        selected: ComposerModelInfo?,
        thinkingLevel: String?,
        fastModeEnabled: Bool,
        fastModeActive: Bool,
        commandCatalog: ComposerCommandCatalogState = .available([])
    ) {
        self.models = models
        self.selected = selected
        self.thinkingLevel = thinkingLevel
        self.fastModeEnabled = fastModeEnabled
        self.fastModeActive = fastModeActive
        self.commandCatalog = commandCatalog
    }
}

enum ComposerCatalogServiceError: LocalizedError, Sendable {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "[Sessions:ComposerCatalogService] Invalid catalog response — {catalog}"
        }
    }
}

private struct CatalogRPCClientBox: ProviderRPCClient {
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

// ponytail: one warm client per project until shutdown.
actor ComposerCatalogService {
    private typealias ClientFactory = @Sendable (RpcClientConfiguration) async -> CatalogRPCClientBox

    private struct ProjectRequest: Equatable, Sendable {
        let id: UUID
        let cwd: URL?
    }

    private struct Startup {
        let id: UUID
        let project: ProjectRequest
        let task: Task<CatalogRPCClientBox, Error>
    }

    private struct Closing {
        let id: UUID
        let task: Task<Void, Never>
    }

    private struct Ready {
        let startupID: UUID
        let project: ProjectRequest
        let client: CatalogRPCClientBox
    }

    private enum ClientState {
        case idle
        case starting(Startup)
        case ready(Ready)
        case closing(Closing)
    }

    nonisolated let commandUpdates: AsyncStream<ComposerCommandCatalogState>

    private var configuration: RpcClientConfiguration
    private let clientFactory: ClientFactory
    private let projectSelectionObserver: @Sendable () async -> Void
    private let projectRequestObserver: @Sendable () async -> Void
    private let startupResolutionObserver: @Sendable () async -> Void
    private let eventConsumptionObserver: @Sendable () async -> Void
    private let commandContinuation: AsyncStream<ComposerCommandCatalogState>.Continuation
    private var currentProject: ProjectRequest?
    private var clientState: ClientState = .idle
    private var eventTask: Task<Void, Never>?

    init<Client: ProviderRPCClient>(
        executableURL: URL,
        clientFactory: @escaping @Sendable (RpcClientConfiguration) async -> Client,
        projectSelectionObserver: @escaping @Sendable () async -> Void = {},
        projectRequestObserver: @escaping @Sendable () async -> Void = {},
        startupResolutionObserver: @escaping @Sendable () async -> Void = {},
        eventConsumptionObserver: @escaping @Sendable () async -> Void = {}
    ) {
        var configuration = RpcClientConfiguration()
        configuration.executable = executableURL.path
        configuration.noSession = true
        configuration.extraArguments += ProviderExtensionBundle.spawnArguments()
        self.configuration = configuration
        let updates = AsyncStream<ComposerCommandCatalogState>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        commandUpdates = updates.stream
        commandContinuation = updates.continuation
        self.clientFactory = { configuration in
            CatalogRPCClientBox(await clientFactory(configuration))
        }
        self.projectSelectionObserver = projectSelectionObserver
        self.projectRequestObserver = projectRequestObserver
        self.startupResolutionObserver = startupResolutionObserver
        self.eventConsumptionObserver = eventConsumptionObserver
    }

    init(executableURL: URL) {
        var configuration = RpcClientConfiguration()
        configuration.executable = executableURL.path
        configuration.noSession = true
        configuration.extraArguments += ProviderExtensionBundle.spawnArguments()
        self.configuration = configuration
        let updates = AsyncStream<ComposerCommandCatalogState>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        commandUpdates = updates.stream
        commandContinuation = updates.continuation
        self.clientFactory = { configuration in
            CatalogRPCClientBox(RpcClient(configuration: configuration))
        }
        projectSelectionObserver = {}
        projectRequestObserver = {}
        startupResolutionObserver = {}
        eventConsumptionObserver = {}
    }

    func load(projectURL: URL?) async throws -> ComposerCatalogSnapshot {
        let project = selectProject(projectURL)
        await projectRequestObserver()
        let ready = try await clientForLoad(project: project)
        try ensureCurrent(project, ready: ready)
        let stateResponse = try await ready.client.send(.getState(), timeout: nil)
        try ensureCurrent(project, ready: ready)
        let modelsResponse = try await ready.client.send(.getAvailableModels(), timeout: nil)
        try ensureCurrent(project, ready: ready)
        let commandCatalog: ComposerCommandCatalogState
        do {
            let commandsResponse = try await ready.client.send(.getAvailableCommands(), timeout: nil)
            try ensureCurrent(project, ready: ready)
            guard commandsResponse.success, let data = commandsResponse.data else {
                throw AvailableSlashCommandDecodingError.invalidSnapshot
            }
            commandCatalog = .available(try AvailableSlashCommandDecoder.decodeSnapshot(data))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try ensureCurrent(project, ready: ready)
            commandCatalog = .unavailable
        }
        try ensureCurrent(project, ready: ready)
        commandContinuation.yield(commandCatalog)
        try ensureCurrent(project, ready: ready)
        return try parseSnapshot(
            state: stateResponse.data,
            models: modelsResponse.data,
            commandCatalog: commandCatalog)
    }

    func shutdown() async {
        currentProject = nil
        await shutdownClient()
        commandContinuation.yield(.unavailable)
        commandContinuation.finish()
    }

    private func shutdownClient() async {
        if case .closing(let closing) = clientState {
            await closing.task.value
            clearClosing(closing)
            return
        }

        let state = clientState
        let existingEventTask = eventTask
        self.eventTask = nil
        existingEventTask?.cancel()
        let closing: Closing
        switch state {
        case .idle:
            return
        case .starting(let startup):
            startup.task.cancel()
            closing = Closing(id: UUID(), task: Task {
                if let existingEventTask { await existingEventTask.value }
                if case .success(let client) = await startup.task.result {
                    await client.shutdown()
                }
            })
        case .ready(let ready):
            closing = Closing(id: UUID(), task: Task {
                if let existingEventTask { await existingEventTask.value }
                await ready.client.shutdown()
            })
        case .closing:
            return
        }

        clientState = .closing(closing)
        await closing.task.value
        clearClosing(closing)
    }

    private func selectProject(_ projectURL: URL?) -> ProjectRequest {
        let cwd = projectURL?.standardizedFileURL
        if let currentProject, sameCwd(currentProject.cwd, cwd) {
            return currentProject
        }
        let project = ProjectRequest(id: UUID(), cwd: cwd)
        currentProject = project
        return project
    }

    private func clientForLoad(project: ProjectRequest) async throws -> Ready {
        guard project == currentProject else { throw CancellationError() }
        switch clientState {
        case .ready(let ready) where ready.project == project:
            return ready
        case .starting(let startup) where startup.project == project:
            let ready = try await awaitStartup(startup)
            try ensureCurrent(project, ready: ready)
            return ready
        case .closing(let closing):
            await closing.task.value
            clearClosing(closing)
            return try await clientForLoad(project: project)
        case .idle:
            configuration.cwd = project.cwd
            let startup = makeStartup(project: project)
            clientState = .starting(startup)
            let ready = try await awaitStartup(startup)
            try ensureCurrent(project, ready: ready)
            return ready
        case .starting, .ready:
            await shutdownClient()
            await projectSelectionObserver()
            return try await clientForLoad(project: project)
        }
    }

    private func makeStartup(project: ProjectRequest) -> Startup {
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
        return Startup(id: UUID(), project: project, task: task)
    }

    private func awaitStartup(_ startup: Startup) async throws -> Ready {
        do {
            let client = try await startup.task.value
            await startupResolutionObserver()
            switch clientState {
            case .ready(let ready)
                where ready.startupID == startup.id && ready.project == startup.project:
                return ready
            case .ready:
                throw CancellationError()
            case .starting(let current)
                where current.id == startup.id && current.project == startup.project:
                let ready = Ready(startupID: startup.id, project: startup.project, client: client)
                clientState = .ready(ready)
                startConsuming(events: client.events, ready: ready)
                return ready
            case .idle, .starting:
                // A closing task owns any startup that no longer occupies this state.
                throw CancellationError()
            case .closing:
                throw CancellationError()
            }
        } catch {
            clearStarting(startup)
            throw error
        }
    }

    private func startConsuming(events: AsyncStream<RpcFrame>, ready: Ready) {
        let eventConsumptionObserver = eventConsumptionObserver
        eventTask = Task { [weak self] in
            for await frame in events {
                guard !Task.isCancelled else { return }
                await eventConsumptionObserver()
                await self?.consume(frame, startupID: ready.startupID, project: ready.project)
            }
        }
    }

    private func clearStarting(_ startup: Startup) {
        guard case .starting(let current) = clientState, current.id == startup.id else { return }
        clientState = .idle
    }

    private func clearClosing(_ closing: Closing) {
        guard case .closing(let current) = clientState, current.id == closing.id else { return }
        clientState = .idle
    }

    private func sameCwd(_ lhs: URL?, _ rhs: URL?) -> Bool {
        lhs?.path == rhs?.path
    }

    private func ensureCurrent(_ project: ProjectRequest, ready: Ready) throws {
        guard currentProject == project,
              case .ready(let current) = clientState,
              current.startupID == ready.startupID,
              current.project == project
        else {
            throw CancellationError()
        }
    }

    private func parseSnapshot(
        state: JSONValue?,
        models: JSONValue?,
        commandCatalog: ComposerCommandCatalogState
    ) throws -> ComposerCatalogSnapshot {
        guard let modelsData = models else { throw ComposerCatalogServiceError.invalidResponse }
        let catalog = try parseModels(modelsData["models"]?.arrayValue ?? [])
        let selected = try state?["model"].flatMap { try parseModel($0) }
        return ComposerCatalogSnapshot(
            models: catalog,
            selected: selected,
            thinkingLevel: state?["thinkingLevel"]?.stringValue,
            fastModeEnabled: state?["fastModeEnabled"]?.boolValue ?? false,
            fastModeActive: state?["fastModeActive"]?.boolValue ?? false,
            commandCatalog: commandCatalog)
    }

    private func parseModels(_ values: [JSONValue]) throws -> [ComposerModelInfo] {
        try values.map { try parseModel($0) }
    }

    private func parseModel(_ value: JSONValue) throws -> ComposerModelInfo {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue,
              let name = object["name"]?.stringValue,
              let provider = object["provider"]?.stringValue
        else {
            throw ComposerCatalogServiceError.invalidResponse
        }
        let thinking = object["thinking"]?.objectValue
        return ComposerModelInfo(
            modelID: id,
            name: name,
            provider: provider,
            api: object["api"]?.stringValue,
            thinkingEfforts: thinking?["efforts"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            requiresEffort: thinking?["requiresEffort"]?.boolValue ?? false)
    }

    private func consume(_ frame: RpcFrame, startupID: UUID, project: ProjectRequest) {
        guard case .event("available_commands_update", let payload) = frame else { return }
        guard currentProject == project,
              case .ready(let ready) = clientState,
              ready.startupID == startupID,
              ready.project == project
        else {
            return
        }
        do {
            commandContinuation.yield(.available(
                try AvailableSlashCommandDecoder.decodeSnapshot(payload)))
        } catch {
            commandContinuation.yield(.unavailable)
        }
    }
}

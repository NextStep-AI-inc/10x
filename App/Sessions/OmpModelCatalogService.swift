import Foundation
import OmpKit

struct ComposerCatalogSnapshot: Equatable, Sendable {
    let models: [ComposerModelInfo]
    let selected: ComposerModelInfo?
    let thinkingLevel: String?
    let fastModeEnabled: Bool
    let fastModeActive: Bool
}

enum OmpModelCatalogServiceError: LocalizedError, Sendable {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "[Sessions:OmpModelCatalogService] Invalid catalog response — {catalog}"
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

// ponytail: one warm no-session client until shutdown; upgrade path is ProviderManagementService-style lifecycle if concurrent load/shutdown races show up.
actor OmpModelCatalogService {
    private typealias ClientFactory = @Sendable (RpcClientConfiguration) async -> CatalogRPCClientBox

    private let configuration: RpcClientConfiguration
    private let clientFactory: ClientFactory
    private var client: CatalogRPCClientBox?

    init<Client: ProviderRPCClient>(
        executableURL: URL,
        clientFactory: @escaping @Sendable (RpcClientConfiguration) async -> Client
    ) {
        var configuration = RpcClientConfiguration()
        configuration.executable = executableURL.path
        configuration.noSession = true
        self.configuration = configuration
        self.clientFactory = { configuration in
            CatalogRPCClientBox(await clientFactory(configuration))
        }
    }

    init(executableURL: URL) {
        var configuration = RpcClientConfiguration()
        configuration.executable = executableURL.path
        configuration.noSession = true
        self.configuration = configuration
        self.clientFactory = { configuration in
            CatalogRPCClientBox(RpcClient(configuration: configuration))
        }
    }

    func load() async throws -> ComposerCatalogSnapshot {
        let client = try await clientForLoad()
        let stateResponse = try await client.send(.getState(), timeout: nil)
        let modelsResponse = try await client.send(.getAvailableModels(), timeout: nil)
        return try parseSnapshot(state: stateResponse.data, models: modelsResponse.data)
    }

    func shutdown() async {
        if let client {
            await client.shutdown()
        }
        client = nil
    }

    private func clientForLoad() async throws -> CatalogRPCClientBox {
        if let client { return client }
        let newClient = await clientFactory(configuration)
        do {
            _ = try await newClient.start()
            client = newClient
            return newClient
        } catch {
            await newClient.shutdown()
            throw error
        }
    }

    private func parseSnapshot(
        state: JSONValue?,
        models: JSONValue?
    ) throws -> ComposerCatalogSnapshot {
        guard let modelsData = models else { throw OmpModelCatalogServiceError.invalidResponse }
        let catalog = try parseModels(modelsData["models"]?.arrayValue ?? [])
        let selected = try state?["model"].flatMap { try parseModel($0) }
        return ComposerCatalogSnapshot(
            models: catalog,
            selected: selected,
            thinkingLevel: state?["thinkingLevel"]?.stringValue,
            fastModeEnabled: state?["fastModeEnabled"]?.boolValue ?? false,
            fastModeActive: state?["fastModeActive"]?.boolValue ?? false)
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
            throw OmpModelCatalogServiceError.invalidResponse
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
}

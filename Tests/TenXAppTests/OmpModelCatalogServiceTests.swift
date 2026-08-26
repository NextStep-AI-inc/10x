import Foundation
import OmpKit
import Testing
@testable import TenXApp

private let stateResponse = RpcResponse(
    id: "state",
    command: "get_state",
    success: true,
    data: .object([
        "model": .object([
            "id": .string("claude-opus-4-8"),
            "name": .string("Claude Opus 4.8"),
            "provider": .string("anthropic"),
            "api": .string("anthropic-messages"),
            "thinking": .object([
                "efforts": .array([.string("low"), .string("high")]),
                "requiresEffort": .bool(false),
            ]),
        ]),
        "thinkingLevel": .string("high"),
        "fastModeEnabled": .bool(false),
        "fastModeActive": .bool(true),
    ]))

private let modelsResponse = RpcResponse(
    id: "models",
    command: "get_available_models",
    success: true,
    data: .object([
        "models": .array([
            .object([
                "id": .string("claude-opus-4-8"),
                "name": .string("Claude Opus 4.8"),
                "provider": .string("anthropic"),
                "api": .string("anthropic-messages"),
                "thinking": .object([
                    "efforts": .array([.string("low"), .string("high")]),
                    "requiresEffort": .bool(false),
                ]),
            ]),
            .object([
                "id": .string("claude-sonnet-4-5"),
                "name": .string("Claude Sonnet 4.5"),
                "provider": .string("anthropic"),
                "api": .string("anthropic-messages"),
                "thinking": .object([
                    "efforts": .array([]),
                    "requiresEffort": .bool(false),
                ]),
            ]),
        ]),
    ]))

@Test func catalogServiceDecodesStateAndModels() async throws {
    let fake = FakeCatalogRPCClient(responses: [stateResponse, modelsResponse])
    let service = OmpModelCatalogService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })

    let snapshot = try await service.load()

    #expect(snapshot.selected?.id == "claude-opus-4-8")
    #expect(snapshot.models.count == 2)
    #expect(snapshot.thinkingLevel == "high")
    #expect(snapshot.fastModeEnabled == false)
    #expect(snapshot.fastModeActive == true)
    #expect(await fake.commands.map(\.command.type) == ["get_state", "get_available_models"])
    #expect(await fake.startCount == 1)
}

private struct CatalogCommand: Sendable, Equatable {
    let command: RpcCommand
    let timeout: Duration?
}

private actor FakeCatalogRPCClient: ProviderRPCClient {
    private let eventStream: AsyncStream<RpcFrame>
    private var responses: [RpcResponse]

    private(set) var startCount = 0
    private(set) var commands: [CatalogCommand] = []
    private(set) var shutdownCount = 0

    init(responses: [RpcResponse]) {
        self.responses = responses
        (eventStream, _) = AsyncStream<RpcFrame>.makeStream()
    }

    nonisolated var events: AsyncStream<RpcFrame> { eventStream }

    func start() async throws -> ReadyFrame {
        startCount += 1
        return ReadyFrame(protocolVersion: 1)
    }

    func send(_ command: RpcCommand, timeout: Duration?) async throws -> RpcResponse {
        commands.append(CatalogCommand(command: command, timeout: timeout))
        return responses.removeFirst()
    }

    func sendRaw(_ command: RpcCommand) async throws {}

    func shutdown() async {
        shutdownCount += 1
    }
}

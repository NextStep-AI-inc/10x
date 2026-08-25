import Foundation
import OmpKit
import Testing
@testable import TenXApp

private let providerListResponse = RpcResponse(
    id: "providers",
    command: "get_login_providers",
    success: true,
    data: .object(["providers": .array([
        .object([
            "id": .string("cursor"),
            "name": .string("Cursor"),
            "available": .bool(true),
            "authenticated": .bool(true),
        ]),
    ])]))

private let loginResponse = RpcResponse(
    id: "login",
    command: "login",
    success: true,
    data: .object(["providerId": .string("cursor")]))

private let openURLFrame = RpcFrame.extensionUIRequest(ExtensionUIRequest(
    id: "open",
    method: "open_url",
    payload: .object([
        "type": .string("extension_ui_request"),
        "id": .string("open"),
        "method": .string("open_url"),
        "url": .string("https://example.com/login"),
    ])))

@Test func providerServiceDiscoversTypedProviders() async throws {
    let fake = FakeProviderRPCClient(responses: [providerListResponse])
    let configurations = ConfigurationRecorder()
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { configuration in
            await configurations.append(configuration)
            return fake
        })

    let providers = try await service.providers()

    #expect(providers == [
        ProviderLoginProvider(id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    #expect(await fake.commands.map(\.command.type) == ["get_login_providers"])
    #expect(await fake.startCount == 1)
    let configuration = try #require(await configurations.first)
    #expect(configuration.executable == "/tmp/omp")
    #expect(configuration.noSession)
}

@Test func providerServiceLogsInWithTheExpectedCommandAndTimeout() async throws {
    let fake = FakeProviderRPCClient(responses: [loginResponse])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })

    try await service.login(providerID: "cursor")

    #expect(await fake.commands == [
        ProviderCommand(command: .login(providerID: "cursor"), timeout: .seconds(600)),
    ])
}

@Test func providerServiceForwardsLoginExtensionRequests() async throws {
    let fake = FakeProviderRPCClient(responses: [providerListResponse])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })
    _ = try await service.providers()

    let eventTask = Task { await service.events.first { _ in true } }
    await fake.emit(openURLFrame)

    #expect(await eventTask.value?.method == "open_url")
}

@Test func providerServiceCancelsAndRecreatesTheDedicatedClient() async throws {
    let first = FakeProviderRPCClient(responses: [providerListResponse])
    let second = FakeProviderRPCClient(responses: [providerListResponse])
    let pool = ProviderClientPool(clients: [first, second])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in await pool.next() })

    _ = try await service.providers()
    await service.cancelLogin()
    let eventTask = Task { await service.events.first { _ in true } }
    _ = try await service.providers()
    await second.emit(openURLFrame)

    #expect(await first.shutdownCount == 1)
    #expect(await second.startCount == 1)
    #expect(await pool.callCount == 2)
    #expect(await eventTask.value?.method == "open_url")
}

@Test func providerServiceForwardsExtensionResponsesWithoutWaitingForAResponse() async throws {
    let fake = FakeProviderRPCClient(responses: [providerListResponse])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })
    _ = try await service.providers()

    try await service.respond(requestID: "open", body: ["confirmed": .bool(true)])

    #expect(await fake.rawCommands == [
        .extensionUIResponse(id: "open", body: ["confirmed": .bool(true)]),
    ])
}

@Test func providerServiceFinishesEventsOnlyDuringShutdown() async throws {
    let fake = FakeProviderRPCClient(responses: [providerListResponse])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })
    _ = try await service.providers()
    let eventTask = Task {
        var iterator = service.events.makeAsyncIterator()
        return await iterator.next()
    }

    await service.shutdown()

    #expect(await eventTask.value == nil)
    #expect(await fake.shutdownCount == 1)
}

private struct ProviderCommand: Sendable, Equatable {
    let command: RpcCommand
    let timeout: Duration?
}

private actor FakeProviderRPCClient: ProviderRPCClient {
    private let eventStream: AsyncStream<RpcFrame>
    private let eventContinuation: AsyncStream<RpcFrame>.Continuation
    private var responses: [RpcResponse]

    private(set) var startCount = 0
    private(set) var commands: [ProviderCommand] = []
    private(set) var rawCommands: [RpcCommand] = []
    private(set) var shutdownCount = 0

    init(responses: [RpcResponse]) {
        self.responses = responses
        (eventStream, eventContinuation) = AsyncStream<RpcFrame>.makeStream()
    }

    nonisolated var events: AsyncStream<RpcFrame> { eventStream }

    func start() async throws -> ReadyFrame {
        startCount += 1
        return ReadyFrame(protocolVersion: 1)
    }

    func send(_ command: RpcCommand, timeout: Duration?) async throws -> RpcResponse {
        commands.append(ProviderCommand(command: command, timeout: timeout))
        return responses.removeFirst()
    }

    func sendRaw(_ command: RpcCommand) async throws {
        rawCommands.append(command)
    }

    func shutdown() async {
        shutdownCount += 1
    }

    func emit(_ frame: RpcFrame) {
        eventContinuation.yield(frame)
    }
}

private actor ConfigurationRecorder {
    private var configurations: [RpcClientConfiguration] = []

    var first: RpcClientConfiguration? { configurations.first }

    func append(_ configuration: RpcClientConfiguration) {
        configurations.append(configuration)
    }
}

private actor ProviderClientPool {
    private var clients: [FakeProviderRPCClient]
    private(set) var callCount = 0

    init(clients: [FakeProviderRPCClient]) {
        self.clients = clients
    }

    func next() -> FakeProviderRPCClient {
        callCount += 1
        return clients.removeFirst()
    }
}

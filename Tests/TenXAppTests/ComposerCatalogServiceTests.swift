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

private let emptyCommandsResponse = RpcResponse(
    id: "commands",
    command: "get_available_commands",
    success: true,
    data: .object(["commands": .array([])]))

private let oldStateResponse = RpcResponse(
    id: "state",
    command: "get_state",
    success: true,
    data: .object([
        "model": .object([
            "id": .string("old-model"),
            "name": .string("Old Model"),
            "provider": .string("old-provider"),
        ]),
    ]))

private let oldModelsResponse = RpcResponse(
    id: "models",
    command: "get_available_models",
    success: true,
    data: .object([
        "models": .array([
            .object([
                "id": .string("old-model"),
                "name": .string("Old Model"),
                "provider": .string("old-provider"),
            ]),
        ]),
    ]))

private let oldCommandsResponse = RpcResponse(
    id: "commands",
    command: "get_available_commands",
    success: true,
    data: .object(["commands": .array([
        .object(["name": .string("old"), "source": .string("builtin")]),
    ])]))

@Test func catalogServiceDecodesStateAndModels() async throws {
    let fake = FakeCatalogRPCClient(responses: [stateResponse, modelsResponse, emptyCommandsResponse])
    let service = ComposerCatalogService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })

    let snapshot = try await service.load(projectURL: nil)

    #expect(snapshot.selected?.modelID == "claude-opus-4-8")
    #expect(snapshot.models.count == 2)
    #expect(snapshot.thinkingLevel == "high")
    #expect(snapshot.fastModeEnabled == false)
    #expect(snapshot.fastModeActive == true)
    #expect(await fake.commands.map(\.command.type) == ["get_state", "get_available_models", "get_available_commands"])
    #expect(await fake.startCount == 1)
}

@Test func composerCatalogLoadsModelsAndCommandsThroughOneClient() async throws {
    let commandsResponse = RpcResponse(
        id: "commands",
        command: "get_available_commands",
        success: true,
        data: .object(["commands": .array([
            .object(["name": .string("compact"), "source": .string("builtin")]),
        ])]))
    let fake = FakeCatalogRPCClient(responses: [stateResponse, modelsResponse, commandsResponse])
    let service = ComposerCatalogService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { configuration in
            await fake.record(configuration)
            return fake
        })

    let snapshot = try await service.load(
        projectURL: URL(fileURLWithPath: "/tmp/project", isDirectory: true))

    #expect(snapshot.models.count == 2)
    #expect(snapshot.commandCatalog == .available([
        AvailableSlashCommand(name: "compact", source: .builtin),
    ]))
    #expect(await fake.commands.map(\.command.type) == [
        "get_state", "get_available_models", "get_available_commands",
    ])
    #expect(await fake.configurations.map(\.cwd?.path) == ["/tmp/project"])
}

@Test func composerCatalogPublishesCompleteCommandUpdates() async throws {
    let fake = FakeCatalogRPCClient(
        responses: [stateResponse, modelsResponse, emptyCommandsResponse])
    let service = ComposerCatalogService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })
    let updates = service.commandUpdates
    _ = try await service.load(projectURL: URL(fileURLWithPath: "/tmp/project"))
    await fake.emit(.event(
        type: "available_commands_update",
        payload: .object(["commands": .array([
            .object(["name": .string("retry"), "source": .string("builtin")]),
        ])])))

    var iterator = updates.makeAsyncIterator()
    #expect(await iterator.next() == .available([]))
    #expect(await iterator.next() == .available([
        AvailableSlashCommand(name: "retry", source: .builtin),
    ]))
}

@Test func changingCatalogProjectReplacesTheWarmClient() async throws {
    let factory = CatalogClientFactory()
    let service = ComposerCatalogService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { configuration in await factory.make(configuration) })

    _ = try await service.load(projectURL: URL(fileURLWithPath: "/tmp/one"))
    _ = try await service.load(projectURL: URL(fileURLWithPath: "/tmp/two"))

    #expect(await factory.configurations.map(\.cwd?.path) == ["/tmp/one", "/tmp/two"])
    #expect(await factory.clients[0].shutdownCount == 1)
}

@Test func concurrentCatalogLoadsForOneProjectShareOneStartup() async throws {
    let gate = CatalogStartGate()
    let fake = FakeCatalogRPCClient(
        responses: [
            stateResponse, modelsResponse, emptyCommandsResponse,
            stateResponse, modelsResponse, emptyCommandsResponse,
        ],
        startGate: gate)
    let service = ComposerCatalogService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { configuration in
            await fake.record(configuration)
            return fake
        })
    let project = URL(fileURLWithPath: "/tmp/project", isDirectory: true)

    let first = Task { try await service.load(projectURL: project) }
    await gate.waitUntilStarted()
    let second = Task { try await service.load(projectURL: project) }
    await Task.yield()
    await gate.release()

    _ = try await first.value
    _ = try await second.value

    #expect(await fake.configurations.count == 1)
    #expect(await fake.startCount == 1)
}

@Test func changingProjectDuringStartupDiscardsTheStaleClient() async throws {
    let gate = CatalogStartGate()
    let factory = BlockedStartupCatalogFactory(startGate: gate)
    let service = ComposerCatalogService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { configuration in await factory.make(configuration) })
    let firstProject = URL(fileURLWithPath: "/tmp/one", isDirectory: true)
    let secondProject = URL(fileURLWithPath: "/tmp/two", isDirectory: true)

    let first = Task { try await service.load(projectURL: firstProject) }
    await gate.waitUntilStarted()
    let second = Task { try await service.load(projectURL: secondProject) }
    for _ in 0..<10 { await Task.yield() }
    await gate.release()

    _ = try? await first.value
    _ = try await second.value
    _ = try await service.load(projectURL: secondProject)

    #expect(await factory.configurations.map(\.cwd?.path) == ["/tmp/one", "/tmp/two"])
    #expect(await factory.clients[0].shutdownCount == 1)
    #expect(await factory.clients[1].commands.count == 6)
}

@Test func staleCatalogStartupWaiterCannotUseTheReplacementClient() async throws {
    let resolutionGate = CatalogStartupResolutionGate()
    let factory = CatalogClientFactory(responsesPerClient: 9)
    let service = ComposerCatalogService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { configuration in await factory.make(configuration) },
        startupResolutionObserver: { await resolutionGate.observe() })
    let firstProject = URL(fileURLWithPath: "/tmp/one", isDirectory: true)
    let secondProject = URL(fileURLWithPath: "/tmp/two", isDirectory: true)

    let staleLoad = Task { try await service.load(projectURL: firstProject) }
    await resolutionGate.waitForFirstResolution()
    let firstReplacementLoad = Task { try await service.load(projectURL: secondProject) }
    _ = try await firstReplacementLoad.value

    await resolutionGate.releaseFirstResolution()
    await #expect(throws: CancellationError.self) {
        try await staleLoad.value
    }
    _ = try await service.load(projectURL: secondProject)

    #expect(await factory.configurations.map(\.cwd?.path) == ["/tmp/one", "/tmp/two"])
    #expect(await factory.clients[1].commands.count == 6)
}

@Test func staleCatalogStartupWaiterDoesNotShutdownTheClosingOwnedClient() async throws {
    let resolutionGate = CatalogStartupResolutionGate()
    let factory = CatalogClientFactory()
    let service = ComposerCatalogService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { configuration in await factory.make(configuration) },
        startupResolutionObserver: { await resolutionGate.observe() })

    let staleLoad = Task {
        try await service.load(projectURL: URL(fileURLWithPath: "/tmp/one", isDirectory: true))
    }
    await resolutionGate.waitForFirstResolution()
    await service.shutdown()

    await resolutionGate.releaseFirstResolution()
    await #expect(throws: CancellationError.self) {
        try await staleLoad.value
    }

    #expect(await factory.clients[0].shutdownCount == 1)
}

@Test func overlappingProjectChangesDoNotReuseTheWrongReadyClient() async throws {
    let selectionGate = CatalogProjectSelectionGate(blockOnSelection: 1)
    let factory = CatalogClientFactory(responsesPerClient: 6)
    let service = ComposerCatalogService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { configuration in await factory.make(configuration) },
        projectSelectionObserver: { await selectionGate.observe() })
    let one = URL(fileURLWithPath: "/tmp/one", isDirectory: true)
    let two = URL(fileURLWithPath: "/tmp/two", isDirectory: true)
    let three = URL(fileURLWithPath: "/tmp/three", isDirectory: true)

    _ = try await service.load(projectURL: one)
    let twoLoad = Task { try await service.load(projectURL: two) }
    await selectionGate.waitUntilBlocked()
    _ = try await service.load(projectURL: three)

    await selectionGate.release()
    await #expect(throws: CancellationError.self) {
        try await twoLoad.value
    }

    #expect(await factory.configurations.map(\.cwd?.path) == ["/tmp/one", "/tmp/three"])
    #expect(await factory.commandCounts() == [3, 3])
}

@Test func staleRPCResultDoesNotPublishCommandsOrReturnASnapshot() async throws {
    let rpcGate = CatalogRPCGate()
    let factory = BlockedRPCCatalogFactory(rpcGate: rpcGate)
    let service = ComposerCatalogService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { configuration in await factory.make(configuration) })
    let updates = CatalogUpdateRecorder()
    let updateTask = Task {
        for await update in service.commandUpdates {
            await updates.record(update)
        }
    }
    defer { updateTask.cancel() }

    let staleLoad = Task {
        try await service.load(projectURL: URL(fileURLWithPath: "/tmp/one", isDirectory: true))
    }
    await rpcGate.waitUntilBlocked()

    _ = try await service.load(
        projectURL: URL(fileURLWithPath: "/tmp/two", isDirectory: true))
    let latestSnapshot = try await service.load(
        projectURL: URL(fileURLWithPath: "/tmp/one", isDirectory: true))
    await updates.waitForCount(2)
    await rpcGate.release()

    await #expect(throws: CancellationError.self) {
        try await staleLoad.value
    }
    for _ in 0..<10 { await Task.yield() }

    #expect(latestSnapshot.models.count == 2)
    #expect(await updates.values == [.available([]), .available([])])
    #expect(await factory.commandCounts() == [1, 3, 3])
}

@Test func staleEventFrameDoesNotPublishAfterProjectChanges() async throws {
    let eventGate = CatalogEventGate()
    let projectRequests = CatalogProjectRequestRecorder()
    let factory = CatalogClientFactory()
    let service = ComposerCatalogService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { configuration in await factory.make(configuration) },
        projectRequestObserver: { await projectRequests.recordRequest() },
        eventConsumptionObserver: { await eventGate.block() })
    let updates = CatalogUpdateRecorder()
    let updateTask = Task {
        for await update in service.commandUpdates {
            await updates.record(update)
        }
    }
    defer { updateTask.cancel() }

    _ = try await service.load(projectURL: URL(fileURLWithPath: "/tmp/one", isDirectory: true))
    await updates.waitForCount(1)
    await factory.clients[0].emit(.event(
        type: "available_commands_update",
        payload: .object(["commands": .array([
            .object(["name": .string("stale"), "source": .string("builtin")]),
        ])])))
    await eventGate.waitUntilBlocked()

    let latestLoad = Task {
        try await service.load(projectURL: URL(fileURLWithPath: "/tmp/two", isDirectory: true))
    }
    await projectRequests.waitForCount(2)
    await eventGate.release()
    _ = try await latestLoad.value
    await updates.waitForCount(2)
    for _ in 0..<10 { await Task.yield() }

    #expect(await updates.values == [.available([]), .available([])])
}

@Test func unsupportedCommandDiscoveryKeepsTheModelCatalogUsable() async throws {
    let fake = FakeCatalogRPCClient(responses: [
        stateResponse,
        modelsResponse,
        RpcResponse(
            id: "commands",
            command: "get_available_commands",
            success: false,
            error: "unsupported"),
    ])
    let service = ComposerCatalogService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })

    let snapshot = try await service.load(projectURL: nil)

    #expect(snapshot.models.count == 2)
    #expect(snapshot.commandCatalog == .unavailable)
}

private struct CatalogCommand: Sendable, Equatable {
    let command: RpcCommand
    let timeout: Duration?
}

private actor FakeCatalogRPCClient: ProviderRPCClient {
    private let eventStream: AsyncStream<RpcFrame>
    private let eventContinuation: AsyncStream<RpcFrame>.Continuation
    private var responses: [RpcResponse]
    private let startGate: CatalogStartGate?
    private let rpcGate: CatalogRPCGate?

    private(set) var startCount = 0
    private(set) var commands: [CatalogCommand] = []
    private(set) var shutdownCount = 0
    private(set) var configurations: [RpcClientConfiguration] = []

    init(
        responses: [RpcResponse],
        startGate: CatalogStartGate? = nil,
        rpcGate: CatalogRPCGate? = nil
    ) {
        self.responses = responses
        self.startGate = startGate
        self.rpcGate = rpcGate
        (eventStream, eventContinuation) = AsyncStream<RpcFrame>.makeStream()
    }

    nonisolated var events: AsyncStream<RpcFrame> { eventStream }

    func start() async throws -> ReadyFrame {
        startCount += 1
        if let startGate {
            await startGate.blockStart()
        }
        return ReadyFrame(protocolVersion: 1)
    }

    func send(_ command: RpcCommand, timeout: Duration?) async throws -> RpcResponse {
        commands.append(CatalogCommand(command: command, timeout: timeout))
        if let rpcGate {
            await rpcGate.blockIfNeeded(command.type)
        }
        return responses.removeFirst()
    }

    func sendRaw(_ command: RpcCommand) async throws {}

    func record(_ configuration: RpcClientConfiguration) {
        configurations.append(configuration)
    }

    func emit(_ frame: RpcFrame) {
        eventContinuation.yield(frame)
    }

    func shutdown() async {
        shutdownCount += 1
    }
}

private actor CatalogClientFactory {
    private(set) var configurations: [RpcClientConfiguration] = []
    private(set) var clients: [FakeCatalogRPCClient] = []

    private let responsesPerClient: Int

    init(responsesPerClient: Int = 3) {
        self.responsesPerClient = responsesPerClient
    }

    func make(_ configuration: RpcClientConfiguration) -> FakeCatalogRPCClient {
        configurations.append(configuration)
        let responses = Array(repeating: [stateResponse, modelsResponse, emptyCommandsResponse], count: responsesPerClient / 3)
            .flatMap { $0 }
        let client = FakeCatalogRPCClient(responses: responses)
        clients.append(client)
        return client
    }

    func commandCounts() async -> [Int] {
        var counts: [Int] = []
        for client in clients {
            counts.append(await client.commands.count)
        }
        return counts
    }
}

private actor BlockedStartupCatalogFactory {
    private let startGate: CatalogStartGate
    private(set) var configurations: [RpcClientConfiguration] = []
    private(set) var clients: [FakeCatalogRPCClient] = []

    init(startGate: CatalogStartGate) {
        self.startGate = startGate
    }

    func make(_ configuration: RpcClientConfiguration) -> FakeCatalogRPCClient {
        configurations.append(configuration)
        let client = FakeCatalogRPCClient(
            responses: [
                stateResponse, modelsResponse, emptyCommandsResponse,
                stateResponse, modelsResponse, emptyCommandsResponse,
            ],
            startGate: clients.isEmpty ? startGate : nil)
        clients.append(client)
        return client
    }
}

private actor BlockedRPCCatalogFactory {
    private let rpcGate: CatalogRPCGate
    private(set) var clients: [FakeCatalogRPCClient] = []

    init(rpcGate: CatalogRPCGate) {
        self.rpcGate = rpcGate
    }

    func make(_ configuration: RpcClientConfiguration) -> FakeCatalogRPCClient {
        let client = FakeCatalogRPCClient(
            responses: clients.isEmpty
                ? [oldStateResponse, oldModelsResponse, oldCommandsResponse]
                : [stateResponse, modelsResponse, emptyCommandsResponse],
            rpcGate: clients.isEmpty ? rpcGate : nil)
        clients.append(client)
        return client
    }

    func commandCounts() async -> [Int] {
        var counts: [Int] = []
        for client in clients {
            counts.append(await client.commands.count)
        }
        return counts
    }
}

private actor CatalogStartGate {
    private var hasStarted = false
    private var isReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func blockStart() async {
        hasStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor CatalogStartupResolutionGate {
    private var firstResolutionArrived = false
    private var isFirstResolutionReleased = false
    private var firstResolutionWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func observe() async {
        guard !firstResolutionArrived else { return }
        firstResolutionArrived = true
        let waiters = firstResolutionWaiters
        firstResolutionWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !isFirstResolutionReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitForFirstResolution() async {
        guard !firstResolutionArrived else { return }
        await withCheckedContinuation { continuation in
            firstResolutionWaiters.append(continuation)
        }
    }

    func releaseFirstResolution() {
        isFirstResolutionReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor CatalogProjectSelectionGate {
    private let blockOnSelection: Int
    private var selectionCount = 0
    private var isReleased = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(blockOnSelection: Int) {
        self.blockOnSelection = blockOnSelection
    }

    func observe() async {
        selectionCount += 1
        guard selectionCount == blockOnSelection else { return }
        let waiters = blockedWaiters
        blockedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilBlocked() async {
        guard selectionCount < blockOnSelection else { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor CatalogRPCGate {
    private var hasBlocked = false
    private var isReleased = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func blockIfNeeded(_ commandType: String) async {
        guard commandType == "get_state" else { return }
        hasBlocked = true
        let waiters = blockedWaiters
        blockedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilBlocked() async {
        guard !hasBlocked else { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor CatalogEventGate {
    private var hasBlocked = false
    private var isReleased = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func block() async {
        hasBlocked = true
        let waiters = blockedWaiters
        blockedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilBlocked() async {
        guard !hasBlocked else { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor CatalogUpdateRecorder {
    private(set) var values: [ComposerCommandCatalogState] = []
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func record(_ value: ComposerCommandCatalogState) {
        values.append(value)
        let ready = countWaiters.filter { values.count >= $0.0 }
        countWaiters.removeAll { values.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }

    func waitForCount(_ count: Int) async {
        guard values.count < count else { return }
        await withCheckedContinuation { continuation in
            countWaiters.append((count, continuation))
        }
    }
}

private actor CatalogProjectRequestRecorder {
    private var count = 0
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func recordRequest() {
        count += 1
        let ready = countWaiters.filter { count >= $0.0 }
        countWaiters.removeAll { count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }

    func waitForCount(_ expectedCount: Int) async {
        guard count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            countWaiters.append((expectedCount, continuation))
        }
    }
}

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

private let anthropicAuthenticatedResponse = RpcResponse(
    id: "providers",
    command: "get_login_providers",
    success: true,
    data: .object(["providers": .array([
        .object([
            "id": .string("anthropic"),
            "name": .string("Anthropic"),
            "available": .bool(true),
            "authenticated": .bool(true),
        ]),
    ])]))

private let mixedProviderListResponse = RpcResponse(
    id: "providers",
    command: "get_login_providers",
    success: true,
    data: .object(["providers": .array([
        .object([
            "id": .string("anthropic"),
            "name": .string("Anthropic"),
            "available": .bool(true),
            "authenticated": .bool(true),
        ]),
        .object([
            "id": .string("openai-codex"),
            "name": .string("OpenAI Codex"),
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

    try await service.login(providerID: "cursor", generation: 1)

    #expect(await fake.commands == [
        ProviderCommand(command: .login(providerID: "cursor"), timeout: .seconds(600)),
    ])
}

@Test func providerServiceForwardsExtensionRequestsOnlyForTheActiveLogin() async throws {
    let loginGate = StartGate()
    let fake = FakeProviderRPCClient(
        responses: [providerListResponse, loginResponse],
        loginGate: loginGate)
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })
    _ = try await service.providers()

    await fake.emit(RpcFrame.extensionUIRequest(ExtensionUIRequest(
        id: "unsolicited",
        method: "open_url",
        payload: .object(["launchUrl": .string("https://example.com/unsolicited")]))))
    for _ in 0..<20 { await Task.yield() }
    let eventTask = Task { await service.events.first { _ in true } }
    let loginTask = Task { try await service.login(providerID: "cursor", generation: 7) }
    await loginGate.waitForStart()
    await fake.emit(openURLFrame)

    #expect(await eventTask.value?.request.id == "open")
    #expect(await eventTask.value?.generation == 7)
    await loginGate.release()
    _ = try await loginTask.value
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
    _ = try await service.providers()

    #expect(await first.shutdownCount == 1)
    #expect(await second.startCount == 1)
    #expect(await pool.callCount == 2)
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

@Test func providerServiceSharesOneStartupBeforeSendingRequests() async throws {
    let startGate = StartGate()
    let startupWaiters = StartupWaiterGate(expectedCount: 2)
    let fake = FakeProviderRPCClient(
        responses: [providerListResponse, providerListResponse],
        startGate: startGate)
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake },
        startupWaiterObserver: { await startupWaiters.joined() })

    let firstProviders = Task { try await service.providers() }
    await startGate.waitForStart()
    let secondProviders = Task { try await service.providers() }
    await startupWaiters.waitForAll()

    #expect(await fake.commands.isEmpty)
    #expect(await fake.startCount == 1)
    await startGate.release()
    _ = try await firstProviders.value
    _ = try await secondProviders.value
}

@Test func providerServiceDiscardsACancelledFactoryClientBeforeRecreation() async throws {
    let first = FakeProviderRPCClient(responses: [providerListResponse])
    let second = FakeProviderRPCClient(responses: [providerListResponse])
    let factoryGate = FactoryGate(clients: [first, second])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in await factoryGate.makeClient() })

    let cancelledProviders = Task { try await service.providers() }
    await factoryGate.waitForFirstRequest()
    let cancellation = Task { await service.cancelLogin() }
    await factoryGate.release()
    await cancellation.value
    _ = await cancelledProviders.result

    _ = try await service.providers()

    #expect(await factoryGate.callCount == 2)
    #expect(await first.shutdownCount == 1)
    #expect(await second.startCount == 1)
}

@Test func providerServiceShutsDownAClientWhoseStartupFails() async {
    // A start failure now earns exactly one retry (see
    // providerServiceRetriesOnceWithAPlaceholderAfterAStartFailure), and the
    // same fake client is reused for both attempts here, so both counts
    // double relative to the pre-retry behavior.
    let fake = FakeProviderRPCClient(
        responses: [],
        startFailure: ProviderTestError.startFailed)
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })

    _ = await Task { try await service.providers() }.result

    #expect(await fake.startCount == 2)
    #expect(await fake.shutdownCount == 2)
}

@Test func providerServiceStartsWithoutAPlaceholderWhenTheFirstStartSucceeds() async throws {
    let fake = FakeProviderRPCClient(responses: [providerListResponse])
    let configurations = ConfigurationRecorder()
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { configuration in
            await configurations.append(configuration)
            return fake
        })

    _ = try await service.providers()

    let recorded = await configurations.all
    #expect(recorded.count == 1)
    #expect(recorded[0].environment?["ANTHROPIC_API_KEY"] == nil)
    #expect(await fake.startCount == 1)
}

@Test func providerServiceRetriesOnceWithAPlaceholderAfterAStartFailure() async throws {
    let failing = FakeProviderRPCClient(responses: [], startFailure: .startFailed)
    let succeeding = FakeProviderRPCClient(responses: [providerListResponse])
    let pool = ProviderClientPool(clients: [failing, succeeding])
    let configurations = ConfigurationRecorder()
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { configuration in
            await configurations.append(configuration)
            return await pool.next()
        })

    _ = try await service.providers()

    let recorded = await configurations.all
    #expect(recorded.count == 2)
    #expect(recorded[0].environment?["ANTHROPIC_API_KEY"] == nil)
    #expect(recorded[1].environment?["ANTHROPIC_API_KEY"] == "10x-onboarding-placeholder-not-a-real-key")
    #expect(recorded[1].environment?["PATH"] != nil)
    #expect(await failing.startCount == 1)
    #expect(await failing.shutdownCount == 1)
    #expect(await succeeding.startCount == 1)
    #expect(await pool.callCount == 2)
}

@Test func providerServicePropagatesTheOriginalErrorWhenTheRetryAlsoFails() async {
    let first = FakeProviderRPCClient(responses: [], startFailure: .startFailed)
    let second = FakeProviderRPCClient(responses: [], startFailure: .retryFailed)
    let pool = ProviderClientPool(clients: [first, second])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in await pool.next() })

    let result = await Task { try await service.providers() }.result

    switch result {
    case .success:
        Issue.record("expected the providers() call to fail")
    case .failure(let error):
        #expect(error as? ProviderTestError == .startFailed)
    }
    #expect(await pool.callCount == 2)
    #expect(await first.startCount == 1)
    #expect(await first.shutdownCount == 1)
    #expect(await second.startCount == 1)
    #expect(await second.shutdownCount == 1)
}

@Test func providerServiceMasksThePlaceholderProviderWhenActive() async throws {
    let failing = FakeProviderRPCClient(responses: [], startFailure: .startFailed)
    let succeeding = FakeProviderRPCClient(responses: [mixedProviderListResponse])
    let pool = ProviderClientPool(clients: [failing, succeeding])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in await pool.next() })

    let providers = try await service.providers()

    let anthropic = try #require(providers.first { $0.id == "anthropic" })
    #expect(anthropic.isAuthenticated == false)
    let codex = try #require(providers.first { $0.id == "openai-codex" })
    #expect(codex.isAuthenticated == true)
}

@Test func providerServiceDoesNotMaskAnthropicWhenThePlaceholderIsNotActive() async throws {
    let fake = FakeProviderRPCClient(responses: [anthropicAuthenticatedResponse])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })

    let providers = try await service.providers()

    let anthropic = try #require(providers.first { $0.id == "anthropic" })
    #expect(anthropic.isAuthenticated == true)
}

@Test func providerServiceStartsAFreshClientAfterASuccessfulLogin() async throws {
    let first = FakeProviderRPCClient(responses: [loginResponse])
    let second = FakeProviderRPCClient(responses: [providerListResponse])
    let pool = ProviderClientPool(clients: [first, second])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in await pool.next() })

    try await service.login(providerID: "cursor", generation: 1)
    _ = try await service.providers()

    #expect(await pool.callCount == 2)
    #expect(await first.shutdownCount == 1)
    #expect(await second.startCount == 1)
}

@Test func providerServiceMasksAResponseByTheClientThatProducedItEvenAfterAConcurrentLoginClearsThePlaceholder() async throws {
    // Regression for a race: parseProviders must not re-read actor-global
    // "is the placeholder active" state at response time, because a
    // concurrent login() can close the placeholder client and start a
    // fresh one in between this client producing its response and this
    // call actually observing it. The mask must travel bound to the
    // client that produced the response, not to whatever the actor holds
    // when the response is finally parsed.
    let failing = FakeProviderRPCClient(responses: [], startFailure: .startFailed)
    let providersGate = StartGate()
    let placeholderClient = FakeProviderRPCClient(
        responses: [loginResponse, mixedProviderListResponse],
        providersGate: providersGate)
    let pool = ProviderClientPool(clients: [failing, placeholderClient])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in await pool.next() })

    // Starts against the placeholder client (first client fails, forcing
    // the retry) and gates on the get_login_providers response.
    let providersTask = Task { try await service.providers() }
    await providersGate.waitForStart()

    // While that response is still held open, a concurrent login()
    // completes on the SAME (still-ready) client and closes it, clearing
    // whatever the actor holds for "the current placeholder".
    try await service.login(providerID: "cursor", generation: 1)

    // Only now does the providers() response resolve.
    await providersGate.release()
    let providers = try await providersTask.value

    let anthropic = try #require(providers.first { $0.id == "anthropic" })
    #expect(anthropic.isAuthenticated == false)
}

@Test func providerServiceShutsDownACancelledSharedStartupOnlyOnce() async {
    let startGate = StartGate()
    let startupWaiters = StartupWaiterGate(expectedCount: 2)
    let fake = FakeProviderRPCClient(
        responses: [providerListResponse, providerListResponse],
        startGate: startGate)
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake },
        startupWaiterObserver: { await startupWaiters.joined() })

    let firstProviders = Task { try await service.providers() }
    await startGate.waitForStart()
    let secondProviders = Task { try await service.providers() }
    await startupWaiters.waitForAll()
    let cancellation = Task { await service.cancelLogin() }
    await startGate.waitForCancellation()
    await startGate.release()
    await cancellation.value
    _ = await firstProviders.result
    _ = await secondProviders.result

    #expect(await fake.shutdownCount == 1)
}

@Test func providerServiceShutdownWaitsForCancellationResistantStartupCleanup() async throws {
    let startGate = StartGate()
    let fake = FakeProviderRPCClient(
        responses: [providerListResponse],
        startGate: startGate)
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })
    let providers = Task { try await service.providers() }
    await startGate.waitForStart()
    let completion = CompletionProbe()

    let shutdown = Task {
        await service.shutdown()
        await completion.finish()
    }
    await startGate.waitForCancellation()
    try await Task.sleep(for: .milliseconds(50))

    #expect(await completion.isFinished == false)
    await startGate.release()
    await shutdown.value
    _ = await providers.result
    #expect(await fake.shutdownCount == 1)
}

@Test func providerServiceConcurrentClosesJoinCancellationResistantStartupCleanup() async {
    let startGate = StartGate()
    let fake = FakeProviderRPCClient(
        responses: [providerListResponse],
        startGate: startGate)
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })
    let providers = Task { try await service.providers() }
    await startGate.waitForStart()

    let firstClose = Task { await service.cancelLogin() }
    await startGate.waitForCancellation()
    let secondCloseCompletion = CompletionProbe()
    let secondClose = Task {
        await service.shutdown()
        await secondCloseCompletion.finish()
    }
    for _ in 0..<100 { await Task.yield() }

    #expect(await secondCloseCompletion.isFinished == false)
    await startGate.release()
    await firstClose.value
    await secondClose.value
    _ = await providers.result
    #expect(await fake.shutdownCount == 1)
}

@Test func providerServiceDefersRecreationUntilCancelledStartupCleanupCompletes() async throws {
    let startGate = StartGate()
    let first = FakeProviderRPCClient(
        responses: [providerListResponse],
        startGate: startGate)
    let second = FakeProviderRPCClient(responses: [providerListResponse])
    let pool = ProviderClientPool(clients: [first, second])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in await pool.next() })
    let cancelledProviders = Task { try await service.providers() }
    await startGate.waitForStart()

    let cancellation = Task { await service.cancelLogin() }
    await startGate.waitForCancellation()
    let requestStarted = CompletionProbe()
    let replacementProviders = Task {
        await requestStarted.finish()
        return try await service.providers()
    }
    while await requestStarted.isFinished == false { await Task.yield() }
    for _ in 0..<100 { await Task.yield() }

    #expect(await pool.callCount == 1)
    await startGate.release()
    await cancellation.value
    _ = await cancelledProviders.result
    _ = try await replacementProviders.value
    #expect(await pool.callCount == 2)
    #expect(await first.shutdownCount == 1)
    #expect(await second.startCount == 1)
}

private struct ProviderCommand: Sendable, Equatable {
    let command: RpcCommand
    let timeout: Duration?
}

private enum FakeSendOutcome: Sendable {
    case response(RpcResponse)
    case failure(RpcClientError)
}

private actor FakeProviderRPCClient: ProviderRPCClient {
    private let eventStream: AsyncStream<RpcFrame>
    private let eventContinuation: AsyncStream<RpcFrame>.Continuation
    private var outcomes: [FakeSendOutcome]
    private let startGate: StartGate?
    private let loginGate: StartGate?
    /// Gates the response to a `get_login_providers` command specifically,
    /// mirroring `loginGate` for `login` commands — used to hold a
    /// providers() response open while a concurrent request completes, to
    /// exercise races against it.
    private let providersGate: StartGate?
    private let startFailure: ProviderTestError?

    private(set) var startCount = 0
    private(set) var commands: [ProviderCommand] = []
    private(set) var rawCommands: [RpcCommand] = []
    private(set) var shutdownCount = 0

    init(
        responses: [RpcResponse],
        startGate: StartGate? = nil,
        loginGate: StartGate? = nil,
        providersGate: StartGate? = nil,
        startFailure: ProviderTestError? = nil
    ) {
        self.outcomes = responses.map(FakeSendOutcome.response)
        self.startGate = startGate
        self.loginGate = loginGate
        self.providersGate = providersGate
        self.startFailure = startFailure
        (eventStream, eventContinuation) = AsyncStream<RpcFrame>.makeStream()
    }

    init(
        outcomes: [FakeSendOutcome],
        startGate: StartGate? = nil,
        loginGate: StartGate? = nil,
        providersGate: StartGate? = nil,
        startFailure: ProviderTestError? = nil
    ) {
        self.outcomes = outcomes
        self.startGate = startGate
        self.loginGate = loginGate
        self.providersGate = providersGate
        self.startFailure = startFailure
        (eventStream, eventContinuation) = AsyncStream<RpcFrame>.makeStream()
    }

    nonisolated var events: AsyncStream<RpcFrame> { eventStream }

    func start() async throws -> ReadyFrame {
        startCount += 1
        if let startGate {
            await startGate.started()
            await withTaskCancellationHandler {
                await startGate.waitForRelease()
            } onCancel: {
                Task { await startGate.cancelled() }
            }
        }
        if let startFailure { throw startFailure }
        return ReadyFrame(protocolVersion: 1)
    }

    func send(_ command: RpcCommand, timeout: Duration?) async throws -> RpcResponse {
        commands.append(ProviderCommand(command: command, timeout: timeout))
        if command.type == "login" {
            await loginGate?.started()
            await loginGate?.waitForRelease()
        }
        if command.type == "get_login_providers" {
            await providersGate?.started()
            await providersGate?.waitForRelease()
        }
        switch outcomes.removeFirst() {
        case .response(let response):
            return response
        case .failure(let error):
            throw error
        }
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
    var all: [RpcClientConfiguration] { configurations }

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

private actor StartGate {
    private var hasStarted = false
    private var isCancelled = false
    private var isReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func started() {
        hasStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForStart() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func cancelled() {
        isCancelled = true
        let waiters = cancellationWaiters
        cancellationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForCancellation() async {
        guard !isCancelled else { return }
        await withCheckedContinuation { cancellationWaiters.append($0) }
    }

    func waitForRelease() async {
        guard !isReleased else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor CompletionProbe {
    private(set) var isFinished = false

    func finish() {
        isFinished = true
    }
}

private actor FactoryGate {
    private var clients: [FakeProviderRPCClient]
    private var hasReceivedFirstRequest = false
    private var isReleased = false
    private var firstRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var callCount = 0

    init(clients: [FakeProviderRPCClient]) {
        self.clients = clients
    }

    func makeClient() async -> FakeProviderRPCClient {
        callCount += 1
        if !hasReceivedFirstRequest {
            hasReceivedFirstRequest = true
            let waiters = firstRequestWaiters
            firstRequestWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            guard !isReleased else { return clients.removeFirst() }
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        return clients.removeFirst()
    }

    func waitForFirstRequest() async {
        guard !hasReceivedFirstRequest else { return }
        await withCheckedContinuation { firstRequestWaiters.append($0) }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private enum ProviderTestError: Error, Equatable {
    case startFailed
    case retryFailed
}

private actor StartupWaiterGate {
    private let expectedCount: Int
    private var waiterCount = 0
    private var allArrivedWaiters: [CheckedContinuation<Void, Never>] = []

    init(expectedCount: Int) {
        self.expectedCount = expectedCount
    }

    func joined() {
        waiterCount += 1
        guard waiterCount == expectedCount else { return }
        let waiters = allArrivedWaiters
        allArrivedWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForAll() async {
        guard waiterCount < expectedCount else { return }
        await withCheckedContinuation { allArrivedWaiters.append($0) }
    }
}

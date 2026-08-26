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

private let accountListResponse = RpcResponse(
    id: "accounts",
    command: "list_provider_accounts",
    success: true,
    data: .object(["accounts": .array([
        .object([
            "providerId": .string("openai-codex"),
            "accountRef": .string("acct_A"),
            "displayLabel": .string("Tanner"),
            "detailLabel": .string("Pro"),
            "connectionOrder": .int(0),
            "availability": .string("available"),
            "isActiveForSession": .bool(false),
        ]),
        .object([
            "providerId": .string("openai-codex"),
            "accountRef": .string("acct_B"),
            "displayLabel": .string("Work"),
            "connectionOrder": .int(1),
            "availability": .string("mystery"),
        ]),
    ])]))

private let accountUsageResponse = RpcResponse(
    id: "usage",
    command: "get_provider_account_usage",
    success: true,
    data: .object(["accounts": .array([
        .object([
            "providerId": .string("openai-codex"),
            "accountRef": .string("acct_A"),
            "refreshedAt": .string("2026-08-26T12:34:56Z"),
            "usageWindows": .array([
                .object([
                    "id": .string("weekly"),
                    "label": .string("Weekly"),
                    "duration": .object([
                        "value": .int(1),
                        "unit": .string("week"),
                    ]),
                    "sourceIndex": .int(0),
                    "remainingFraction": .double(0.25),
                    "resetsAt": .string("2026-08-27T00:00:00Z"),
                    "status": .string("limited"),
                ]),
            ]),
        ]),
        .object([
            "providerId": .string("openai-codex"),
            "accountRef": .string("acct_B"),
            "refreshedAt": .string("2026-08-26T12:34:56Z"),
            "usageWindows": .array([]),
        ]),
    ])]))

private let accountRemovalResponse = RpcResponse(
    id: "remove",
    command: "remove_provider_account",
    success: true,
    data: .object([
        "removed": .bool(true),
        "accounts": .array([
            .object([
                "providerId": .string("openai-codex"),
                "accountRef": .string("acct_B"),
                "displayLabel": .string("Work"),
                "connectionOrder": .int(1),
                "availability": .string("limited"),
            ]),
        ]),
    ]))

private let unsupportedAccountsResponse = RpcResponse(
    id: "unsupported",
    command: "list_provider_accounts",
    success: false,
    error: "unsupported: list_provider_accounts",
    code: "unsupported_command")

private let failedAccountsResponse = RpcResponse(
    id: "failed",
    command: "list_provider_accounts",
    success: false,
    error: "backend unavailable",
    code: "internal_error")

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

@Test func providerServiceDetectsAccountRoutingCapabilityFromDecodedAccounts() async throws {
    let fake = FakeProviderRPCClient(responses: [accountListResponse])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })

    let capability = try await service.accountCapability(providerID: "openai-codex")

    #expect(capability == .accountRouting)
    #expect(await fake.commands == [
        ProviderCommand(command: .listProviderAccounts(providerID: "openai-codex"), timeout: nil),
    ])
}

@Test func providerServiceDecodesAccountSummaries() async throws {
    let fake = FakeProviderRPCClient(responses: [accountListResponse])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })

    let accounts = try await service.accounts(providerID: "openai-codex")

    #expect(accounts == [
        ProviderAccountSummary(
            providerID: "openai-codex",
            accountRef: "acct_A",
            displayLabel: "Tanner",
            detailLabel: "Pro",
            connectionOrder: 0,
            availability: .available,
            isActiveForSession: false),
        ProviderAccountSummary(
            providerID: "openai-codex",
            accountRef: "acct_B",
            displayLabel: "Work",
            connectionOrder: 1,
            availability: .unavailable),
    ])
}

@Test func providerServiceDecodesPartialAccountUsage() async throws {
    let fake = FakeProviderRPCClient(responses: [accountUsageResponse])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })

    let usage = try await service.accountUsage(providerID: "openai-codex")

    #expect(usage.map(\.accountRef) == ["acct_A", "acct_B"])
    #expect(usage[0].usageWindows.map(\.id) == ["weekly"])
    #expect(usage[0].usageWindows[0].remainingFraction == 0.25)
    #expect(usage[0].usageWindows[0].status == "limited")
    #expect(usage[1].usageWindows.isEmpty)
}

@Test func providerServiceRemovesTheExactAccountRef() async throws {
    let fake = FakeProviderRPCClient(responses: [accountRemovalResponse])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })

    let result = try await service.removeAccount(
        providerID: "openai-codex",
        accountRef: "acct_A")

    #expect(result.removed)
    #expect(result.accounts.map(\.accountRef) == ["acct_B"])
    #expect(await fake.commands == [
        ProviderCommand(
            command: .removeProviderAccount(providerID: "openai-codex", accountRef: "acct_A"),
            timeout: nil),
    ])
}

@Test func providerServiceFallsBackToProviderOnlyForExactUnsupportedAccountCommand() async throws {
    let fake = FakeProviderRPCClient(responses: [unsupportedAccountsResponse, providerListResponse, loginResponse])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })

    let firstCapability = try await service.accountCapability(providerID: "openai-codex")
    let secondCapability = try await service.accountCapability(providerID: "openai-codex")
    let providers = try await service.providers()
    try await service.login(providerID: "cursor", generation: 1)

    #expect(firstCapability == .providerOnly)
    #expect(secondCapability == .providerOnly)
    #expect(providers.map(\.id) == ["cursor"])
    #expect(await fake.commands == [
        ProviderCommand(command: .listProviderAccounts(providerID: "openai-codex"), timeout: nil),
        ProviderCommand(command: .getLoginProviders(), timeout: nil),
        ProviderCommand(command: .login(providerID: "cursor"), timeout: .seconds(600)),
    ])
}

@Test func providerServicePropagatesNonUnsupportedAccountFailures() async {
    let fake = FakeProviderRPCClient(responses: [failedAccountsResponse])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })

    let result = await Task {
        try await service.accountCapability(providerID: "openai-codex")
    }.result

    guard case .failure(let error) = result,
          case ProviderAccountResponseDecodingError.unsuccessful(
            let command, let message, let code) = error
    else {
        Issue.record("Expected account failure to propagate")
        return
    }
    #expect(command == "list_provider_accounts")
    #expect(message == "backend unavailable")
    #expect(code == "internal_error")
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
    let fake = FakeProviderRPCClient(
        responses: [],
        startFailure: ProviderTestError.startFailed)
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })

    _ = await Task { try await service.providers() }.result

    #expect(await fake.startCount == 1)
    #expect(await fake.shutdownCount == 1)
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

private actor FakeProviderRPCClient: ProviderRPCClient {
    private let eventStream: AsyncStream<RpcFrame>
    private let eventContinuation: AsyncStream<RpcFrame>.Continuation
    private var responses: [RpcResponse]
    private let startGate: StartGate?
    private let loginGate: StartGate?
    private let startFailure: ProviderTestError?

    private(set) var startCount = 0
    private(set) var commands: [ProviderCommand] = []
    private(set) var rawCommands: [RpcCommand] = []
    private(set) var shutdownCount = 0

    init(
        responses: [RpcResponse],
        startGate: StartGate? = nil,
        loginGate: StartGate? = nil,
        startFailure: ProviderTestError? = nil
    ) {
        self.responses = responses
        self.startGate = startGate
        self.loginGate = loginGate
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

private enum ProviderTestError: Error {
    case startFailed
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

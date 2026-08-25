import Testing
import Foundation
@testable import OmpKit

func makeClient(
    mode: String,
    startupTimeout: Duration = .seconds(30),
    requestTimeout: Duration = .seconds(30),
    beforeHandlingLine: @escaping @Sendable (Data) async -> Void = { _ in },
    maxBufferedEventBytes: Int? = nil
) -> RpcClient {
    var cfg = RpcClientConfiguration()
    cfg.executable = "/usr/bin/env"
    cfg.extraArguments = ["python3", fixtureURL("fake_server.py").path, mode]
    cfg.rawArgv = true   // extraArguments become the full argv — no omp flags prepended
    cfg.noSession = true
    cfg.startupTimeout = startupTimeout
    cfg.requestTimeout = requestTimeout
    if let maxBufferedEventBytes {
        return RpcClient(
            configuration: cfg,
            beforeHandlingLine: beforeHandlingLine,
            maxBufferedEventBytes: maxBufferedEventBytes)
    }
    return RpcClient(configuration: cfg, beforeHandlingLine: beforeHandlingLine)
}

@Test func startNegotiatesV2() async throws {
    let c = makeClient(mode: "basic")
    let ready = try await c.start()
    #expect(ready.supportedProtocolVersions?.contains(2) == true)
    #expect(await c.negotiatedProtocolVersion == 2)
    await c.shutdown()
}

@Test func getStateRoundTrip() async throws {
    let c = makeClient(mode: "basic")
    _ = try await c.start()
    let resp = try await c.send(.getState())
    #expect(resp.data?["sessionId"]?.stringValue == "fake-session")
    await c.shutdown()
}

@Test func chunkedResponseReassembles() async throws {
    let c = makeClient(mode: "chunked")
    _ = try await c.start()
    let resp = try await c.send(.getState())
    #expect(resp.data?["sessionId"]?.stringValue == "fake-session")
    await c.shutdown()
}

@Test func failureResponseThrowsCommandFailed() async throws {
    let c = makeClient(mode: "basic")
    _ = try await c.start()
    await #expect(throws: RpcClientError.self) {
        _ = try await c.send(RpcCommand(type: "bad_command_test"))
    }
    await c.shutdown()
}

@Test func failureResponseCarriesCode() async throws {
    let c = makeClient(mode: "basic")
    _ = try await c.start()
    do {
        _ = try await c.send(RpcCommand(type: "bad_command_test"))
        Issue.record("expected a failure")
    } catch let error as RpcClientError {
        guard case .commandFailed(let command, let message, let code) = error else {
            Issue.record("wrong error case: \(error)"); await c.shutdown(); return
        }
        #expect(command == "bad_command_test")
        #expect(message == "nope")
        #expect(code == "test_code")
    }
    await c.shutdown()
}

@Test func lateErrorRecordedNotThrown() async throws {
    let c = makeClient(mode: "late-error")
    _ = try await c.start()
    let ack = try await c.send(.prompt(message: "x", streamingBehavior: nil))
    #expect(ack.success)
    try await Task.sleep(for: .milliseconds(300))   // let the late frame arrive
    let errors = await c.protocolErrors
    #expect(errors.count == 1)
    #expect(errors.first?.remoteError == "late scheduling failure")
    await c.shutdown()
}

@Test func timeoutThrows() async throws {
    let c = makeClient(mode: "silent")
    _ = try await c.start()
    await #expect(throws: RpcClientError.self) {
        _ = try await c.send(.getState(), timeout: .milliseconds(200))
    }
    await c.shutdown()
}

@Test func unknownFramesFlowToEventsWithoutBreakingRequests() async throws {
    let c = makeClient(mode: "noisy")
    let stream = c.events
    let driver = Task {
        _ = try? await c.start()
        _ = try? await c.send(.getState())
    }
    defer { driver.cancel() }

    let seen = await withTimeout(.seconds(10)) { () -> [String] in
        var seen: [String] = []
        for await frame in stream {
            switch frame {
            case .event(let type, _): seen.append(type)
            case .extensionUIRequest: seen.append("extension_ui_request")
            default: break
            }
            if seen.count >= 3 { break }   // available_commands_update, setWidget, notice
        }
        return seen
    } ?? []
    #expect(seen.contains("available_commands_update"))
    #expect(seen.contains("extension_ui_request"))
    #expect(seen.contains("notice"))
    await c.shutdown()
}

@Test func eofFailsPendingRequests() async throws {
    let c = makeClient(mode: "eof-on-get-state")
    _ = try await c.start()
    let pending = Task { try await c.send(.getState(), timeout: .seconds(10)) }
    let result = await pending.result
    guard case .failure(let error) = result else {
        Issue.record("expected the pending request to fail on EOF"); return
    }
    guard case .processExited(let code, let stderr) = error as? RpcClientError else {
        Issue.record("wrong error: \(error)"); return
    }
    #expect(code == 5)
    #expect(stderr.contains("eof-on-get-state"))
    await c.shutdown()
}

@Test func sendBeforeStartThrows() async {
    let c = makeClient(mode: "basic")
    await #expect(throws: RpcClientError.self) { _ = try await c.send(.getState()) }
}

@Test func concurrentRequestsCorrelateByIdNotOrder() async throws {
    let c = makeClient(mode: "reverse")
    _ = try await c.start()
    async let a: RpcResponse = c.send(.getState())
    async let b: RpcResponse = c.send(RpcCommand(type: "get_session_stats"))
    async let d: RpcResponse = c.send(RpcCommand(type: "get_available_models"))
    let results = try await [a, b, d]
    #expect(results[0].command == "get_state")
    #expect(results[1].command == "get_session_stats")
    #expect(results[2].command == "get_available_models")
    await c.shutdown()
}

@Test func idlessErrorCorrelatesByUniqueCommand() async throws {
    let c = makeClient(mode: "basic")
    _ = try await c.start()
    do {
        _ = try await c.send(RpcCommand(type: "idless_error"))
        Issue.record("expected command failure")
    } catch let error as RpcClientError {
        guard case .commandFailed(let command, let message, _) = error else {
            Issue.record("wrong error: \(error)"); await c.shutdown(); return
        }
        #expect(command == "idless_error")
        #expect(message == "idless failure")
    }
    await c.shutdown()
}

@Test func idlessParseErrorCorrelatesToSolePendingRequest() async throws {
    let c = makeClient(mode: "parse-error")
    _ = try await c.start()
    do {
        _ = try await c.send(.getState())
        Issue.record("expected parse failure")
    } catch let error as RpcClientError {
        guard case .commandFailed(let command, _, _) = error else {
            Issue.record("wrong error: \(error)"); await c.shutdown(); return
        }
        #expect(command == "parse")
    }
    await c.shutdown()
}

@Test func malformedStartupFrameFailsImmediatelyAndReapsChild() async {
    let c = makeClient(mode: "malformed-startup", startupTimeout: .seconds(5))
    let clock = ContinuousClock()
    let started = clock.now
    await #expect(throws: RpcClientError.self) { _ = try await c.start() }
    #expect(clock.now - started < .seconds(2))
    #expect(await c.exitCode != nil)
}

@Test func prematureChunkIsTerminal() async {
    let c = makeClient(mode: "premature-chunk", startupTimeout: .seconds(5))
    let clock = ContinuousClock()
    let started = clock.now
    await #expect(throws: RpcClientError.self) { _ = try await c.start() }
    #expect(clock.now - started < .seconds(2))
    #expect(await c.protocolErrors.first?.remoteError?.contains("before protocol negotiation") == true)
}

@Test func runtimeDecoderFailureFailsPendingWithoutTimeout() async throws {
    let c = makeClient(mode: "malformed-runtime", requestTimeout: .seconds(5))
    _ = try await c.start()
    let clock = ContinuousClock()
    let started = clock.now
    do {
        _ = try await c.send(.getState())
        Issue.record("expected process exit")
    } catch let error as RpcClientError {
        guard case .processExited = error else {
            Issue.record("wrong error: \(error)"); return
        }
    } catch {
        Issue.record("wrong error: \(error)")
    }
    #expect(clock.now - started < .seconds(2))
}

@Test func failedNegotiationReapsChild() async {
    let c = makeClient(mode: "negotiation-fails", requestTimeout: .seconds(2))
    await #expect(throws: RpcClientError.self) { _ = try await c.start() }
    #expect(await c.exitCode != nil)
}

@Test func mismatchedTransportLimitsStayOnProtocolV1() async throws {
    let c = makeClient(mode: "wrong-limits")
    _ = try await c.start()
    #expect(await c.negotiatedProtocolVersion == 1)
    let response = try await c.send(.getState())
    #expect(response.success)
    await c.shutdown()
}

@Test func cancelledRequestDoesNotHangOrLeakAContinuation() async throws {
    let c = makeClient(mode: "silent", requestTimeout: .seconds(10))
    _ = try await c.start()
    let request = Task { try await c.send(.getState()) }
    request.cancel()
    let result = await withTimeout(.seconds(2)) { await request.result }
    guard case .failure(let error)? = result else {
        Issue.record("cancelled request did not finish"); await c.shutdown(); return
    }
    #expect(error is CancellationError)
    await c.shutdown()
}

@Test func rpcBacklogOverflowPoisonsTheConnectionWithoutSilentSuccess() async {
    let client = makeClient(
        mode: "backlog-overflow",
        startupTimeout: .seconds(5),
        requestTimeout: .seconds(5))
    let started = ContinuousClock.now
    let result = await withTimeout(.seconds(2)) {
        do {
            _ = try await client.start()
            return StartOutcome.success
        } catch {
            return StartOutcome.failure
        }
    }

    #expect(result != nil)
    #expect(result == .failure)
    #expect(ContinuousClock.now - started < .seconds(2.5))
    #expect(await client.protocolErrors.contains {
        $0.remoteError?.contains("backlog overflow") == true
    })
    #expect(await client.exitCode != nil)
}

@Test func reassembledEventsCrossingTheByteBudgetPoisonTheConnection() async throws {
    let client = makeClient(
        mode: "rpc-reassembled-byte-overflow",
        startupTimeout: .seconds(5),
        maxBufferedEventBytes: 1_500_000)
    _ = try await client.start()

    #expect(await waitForProtocolError(client, containing: "byte backlog overflow"))
    #expect(await waitForExit(client))
    let started = ContinuousClock.now
    #expect(await client.shutdown(
        deadline: started.advanced(by: .seconds(1))))
    #expect(ContinuousClock.now - started < .seconds(1.2))
}

@Test func rpcEventBudgetAcceptsOneMaximumReassembledFrame() async throws {
    let budget = QueuedByteBudget(limit: RpcClient.maxBufferedEventBytes)
    let storage = AsyncStream<ByteCounted<RpcFrame>>.makeStream(
        bufferingPolicy: .bufferingOldest(512))
    var control: ByteCounted<RpcFrame>? = ByteCounted(
        value: .ready(ReadyFrame(protocolVersion: 2)),
        byteCount: ChunkReassembler.maxPhysicalFrameBytes,
        budget: budget)
    storage.continuation.yield(try #require(control))
    control = nil
    let frame = RpcFrame.event(type: "notice", payload: .object([:]))
    var queued: ByteCounted<RpcFrame>? = ByteCounted(
        value: frame,
        byteCount: ChunkReassembler.maxReassembledFrameBytes,
        budget: budget)
    if case .dropped = storage.continuation.yield(try #require(queued)) {
        Issue.record("one maximum reassembled frame was rejected")
    }
    queued = nil

    var iterator = RpcEventSequence(stream: storage.stream).makeAsyncIterator()
    _ = await iterator.next()
    let received = await iterator.next()
    #expect(received == frame)
    #expect(budget.usedBytes == 0)
}

@Test func queuedByteBudgetReleasesBufferedValuesWhenStreamStorageTerminates() {
    let budget = QueuedByteBudget(limit: 10)

    func enqueueAndDestroyStream() {
        let storage = AsyncStream<ByteCounted<Int>>.makeStream(
            bufferingPolicy: .bufferingOldest(1))
        let queued = ByteCounted(value: 7, byteCount: 7, budget: budget)
        if let queued { storage.continuation.yield(queued) }
        #expect(budget.usedBytes == 7)
    }

    enqueueAndDestroyStream()
    #expect(budget.usedBytes == 0)
}

@Test func naturalShutdownDoesNotAwaitABlockedReaderPastTheDeadline() async throws {
    let gate = AsyncGate()
    let client = makeClient(
        mode: "trailing-exit-after-prompt",
        beforeHandlingLine: { line in
            if String(decoding: line, as: UTF8.self).contains(#""trailing":true"#) {
                await gate.wait()
            }
        })
    _ = try await client.start()
    _ = try await client.send(.prompt(message: "exit", streamingBehavior: nil))
    #expect(await waitForExit(client))

    let completion = ShutdownCompletion()
    let shutdownTask = Task {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(100))
        let stopped = await client.shutdown(deadline: deadline)
        completion.finish(stopped)
    }
    try await Task.sleep(for: .milliseconds(300))
    let completedByDeadline = completion.value
    await gate.open()
    await shutdownTask.value

    #expect(completedByDeadline == true)
}

@Test func naturalShutdownPreservesTrailingFramesWithinTheDeadline() async throws {
    let client = makeClient(mode: "trailing-exit-after-prompt")
    let events = client.events
    _ = try await client.start()
    let collector = Task { () -> Int in
        var notices = 0
        for await frame in events {
            if case .event(let type, let payload) = frame,
               type == "notice", payload["trailing"]?.boolValue == true {
                notices += 1
            }
        }
        return notices
    }
    _ = try await client.send(.prompt(message: "exit", streamingBehavior: nil))
    #expect(await waitForExit(client))

    #expect(await client.shutdown(
        deadline: ContinuousClock.now.advanced(by: .seconds(1))))
    #expect(await collector.value == 200)
}

@Test func realOmpArgvIsBuiltCorrectly() {
    var cfg = RpcClientConfiguration()
    cfg.cwd = URL(fileURLWithPath: "/tmp/project")
    cfg.resumeSessionPath = "/tmp/s.jsonl"
    #expect(cfg.resolvedArguments == ["--mode", "rpc", "--no-title", "-r", "/tmp/s.jsonl"])

    var fresh = RpcClientConfiguration()
    fresh.noSession = true
    #expect(fresh.resolvedArguments == ["--mode", "rpc", "--no-title", "--no-session"])

    var raw = RpcClientConfiguration()
    raw.rawArgv = true
    raw.extraArguments = ["python3", "x.py"]
    #expect(raw.resolvedArguments == ["python3", "x.py"])
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations { continuation.resume() }
    }
}

private enum StartOutcome: Sendable {
    case success
    case failure
}

private final class ShutdownCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped: Bool?
    func finish(_ value: Bool) { lock.withLock { stopped = value } }
    var value: Bool? { lock.withLock { stopped } }
}

private func waitForExit(_ client: RpcClient) async -> Bool {
    for _ in 0..<100 {
        if await client.exitCode != nil { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

private func waitForProtocolError(
    _ client: RpcClient,
    containing text: String
) async -> Bool {
    for _ in 0..<150 {
        if await client.protocolErrors.contains(where: {
            $0.remoteError?.contains(text) == true
        }) {
            return true
        }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return false
}

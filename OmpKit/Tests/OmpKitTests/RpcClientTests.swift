import Testing
import Foundation
@testable import OmpKit

func makeClient(
    mode: String,
    modeArguments: [String] = [],
    startupTimeout: Duration = .seconds(30),
    requestTimeout: Duration = .seconds(30),
    testHooks: RpcClientTestHooks = RpcClientTestHooks()
) -> RpcClient {
    var cfg = RpcClientConfiguration()
    cfg.executable = "/usr/bin/env"
    cfg.extraArguments = ["python3", fixtureURL("fake_server.py").path, mode]
        + modeArguments
    cfg.rawArgv = true   // extraArguments become the full argv — no omp flags prepended
    cfg.noSession = true
    cfg.startupTimeout = startupTimeout
    cfg.requestTimeout = requestTimeout
    return RpcClient(configuration: cfg, testHooks: testHooks)
}

private actor RpcCompletionProbe {
    private(set) var hasPendingFinished = false
    private(set) var hasTerminationFinished = false

    func markPendingFinished() { hasPendingFinished = true }
    func markTerminationFinished() { hasTerminationFinished = true }
}

private actor RpcSuspensionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private func waitForSuspensionGate(_ gate: RpcSuspensionGate) async -> Bool {
    await withTimeout(.seconds(5)) { () -> Bool in
        while !Task.isCancelled {
            if await gate.isWaiting { return true }
            await Task.yield()
        }
        return false
    } ?? false
}

private func waitUntilAwaitingAuthoritativeExit(_ client: RpcClient) async -> Bool {
    await withTimeout(.seconds(5)) { () -> Bool in
        while !Task.isCancelled {
            if await client.isAwaitingAuthoritativeExit { return true }
            await Task.yield()
        }
        return false
    } ?? false
}

private func waitForExitRelatedWriteFailure(_ client: RpcClient) async -> Bool {
    await withTimeout(.seconds(5)) { () -> Bool in
        while !Task.isCancelled {
            if await client.exitRelatedWriteFailureCount > 0 { return true }
            await Task.yield()
        }
        return false
    } ?? false
}

private func waitForReadyTimeoutAttempt(_ client: RpcClient) async -> Bool {
    await withTimeout(.seconds(5)) { () -> Bool in
        while !Task.isCancelled {
            if await client.readyTimeoutAttemptCount > 0 { return true }
            await Task.yield()
        }
        return false
    } ?? false
}

private func waitForReadyWaiter(_ client: RpcClient) async -> Bool {
    await withTimeout(.seconds(5)) { () -> Bool in
        while !Task.isCancelled {
            if await client.hasReadyWaiter { return true }
            await Task.yield()
        }
        return false
    } ?? false
}

@Test func startNegotiatesV2() async throws {
    let c = makeClient(mode: "basic")
    let ready = try await c.start()
    #expect(ready.supportedProtocolVersions?.contains(2) == true)
    #expect(await c.negotiatedProtocolVersion == 2)
    await c.shutdown()
}

@Test func queuedReadyTimeoutDefersToAuthoritativeExit() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("RpcReadyTimeoutGate-\(UUID().uuidString)", isDirectory: true)
    let closeStdout = root.appendingPathComponent("close-stdout")
    let releaseExit = root.appendingPathComponent("release-exit")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let timeoutGate = RpcSuspensionGate()
    var hooks = RpcClientTestHooks()
    hooks.readyTimeoutSleep = { _ in await timeoutGate.wait() }
    let client = makeClient(
        mode: "close-before-ready",
        modeArguments: [closeStdout.path, releaseExit.path],
        startupTimeout: .milliseconds(1),
        testHooks: hooks)
    let start = Task { () -> Result<ReadyFrame, any Error> in
        do { return .success(try await client.start()) }
        catch { return .failure(error) }
    }

    #expect(await waitForSuspensionGate(timeoutGate))
    FileManager.default.createFile(atPath: closeStdout.path, contents: nil)
    #expect(await waitUntilAwaitingAuthoritativeExit(client))
    await timeoutGate.release()
    #expect(await waitForReadyTimeoutAttempt(client))
    FileManager.default.createFile(atPath: releaseExit.path, contents: nil)

    guard case .failure(let error) = await start.value,
          case .processExited(let code, _) = error as? RpcClientError else {
        Issue.record("authoritative process exit should resolve startup")
        await client.shutdown()
        return
    }
    #expect(code == 24)
    await client.shutdown()
}

@Test func readyWaitStartedAfterStdoutEOFDoesNotArmTimeout() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("RpcReadyArmGate-\(UUID().uuidString)", isDirectory: true)
    let closeStdout = root.appendingPathComponent("close-stdout")
    let releaseExit = root.appendingPathComponent("release-exit")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let beforeReadyGate = RpcSuspensionGate()
    var hooks = RpcClientTestHooks()
    hooks.beforeWaitForReady = { await beforeReadyGate.wait() }
    let client = makeClient(
        mode: "close-before-ready",
        modeArguments: [closeStdout.path, releaseExit.path],
        testHooks: hooks)
    let start = Task { () -> Result<ReadyFrame, any Error> in
        do { return .success(try await client.start()) }
        catch { return .failure(error) }
    }

    #expect(await waitForSuspensionGate(beforeReadyGate))
    FileManager.default.createFile(atPath: closeStdout.path, contents: nil)
    #expect(await waitUntilAwaitingAuthoritativeExit(client))
    await beforeReadyGate.release()
    #expect(await waitForReadyWaiter(client))
    #expect(await !client.isReadyTimeoutArmed)
    FileManager.default.createFile(atPath: releaseExit.path, contents: nil)

    guard case .failure(let error) = await start.value,
          case .processExited(let code, _) = error as? RpcClientError else {
        Issue.record("authoritative process exit should resolve startup")
        await client.shutdown()
        return
    }
    #expect(code == 24)
    await client.shutdown()
}

@Test func getStateRoundTrip() async throws {
    let c = makeClient(mode: "basic")
    _ = try await c.start()
    let resp = try await c.send(.getState())
    #expect(resp.data?["sessionId"]?.stringValue == "fake-session")
    await c.shutdown()
}

@Test func responseEventFenceCountsEveryEarlierEventFrame() async throws {
    let client = makeClient(mode: "noisy")
    _ = try await client.start()

    let receipt = try await client.sendWithEventFence(.getState())
    #expect(receipt.response.data?["sessionId"]?.stringValue == "fake-session")
    #expect(receipt.precedingEventCount == 4)

    var iterator = client.events.makeAsyncIterator()
    var precedingFrames: [RpcFrame] = []
    for _ in 0..<receipt.precedingEventCount {
        precedingFrames.append(try #require(await iterator.next()))
    }
    #expect(precedingFrames.count == 4)
    #expect(precedingFrames.contains { frame in
        if case .event("notice", _) = frame { return true }
        return false
    })
    await client.shutdown()
}

@Test func responseEventFenceReturnsCommandFailureWithEarlierEventCount() async throws {
    let client = makeClient(mode: "noisy")
    _ = try await client.start()

    let receipt = try await client.sendWithEventFence(RpcCommand(type: "bad_command_test"))

    #expect(!receipt.response.success)
    #expect(receipt.response.error == "nope")
    #expect(receipt.precedingEventCount == 3)
    await client.shutdown()
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

@Test func providerAccountFailoverEventsFlowWithoutBreakingResponses() async throws {
    let c = makeClient(mode: "provider-account-failover")
    let stream = c.events
    _ = try await c.start()

    async let response = c.send(.getState())
    let event = await withTimeout(.seconds(10)) { () -> ProviderAccountChangedEvent? in
        for await frame in stream {
            if case .providerAccountChanged(let event) = frame {
                return event
            }
        }
        return nil
    } ?? nil

    let state = try await response
    #expect(state.success)
    #expect(state.command == "get_state")
    guard let failover = event else {
        Issue.record("provider account failover event was not yielded"); return
    }
    #expect(failover.providerID == "openai-codex")
    #expect(failover.accountRef == "acct_failover")
    #expect(failover.reason == .automaticFailover)
    #expect(failover.sequence == 4)
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

@Test func stdoutEOFWaitsForAuthoritativeExitStatus() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("RpcExitGate-\(UUID().uuidString)", isDirectory: true)
    let stdoutClosed = root.appendingPathComponent("stdout-closed")
    let release = root.appendingPathComponent("release")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let client = makeClient(
        mode: "close-stdout-before-exit",
        modeArguments: [stdoutClosed.path, release.path])
    _ = try await client.start()
    let probe = RpcCompletionProbe()
    let pending = Task { () -> Result<RpcResponse, any Error> in
        let result: Result<RpcResponse, any Error>
        do { result = .success(try await client.send(.getState(), timeout: .milliseconds(100))) }
        catch { result = .failure(error) }
        await probe.markPendingFinished()
        return result
    }
    let termination = Task {
        for await _ in client.termination {}
        await probe.markTerminationFinished()
    }

    let isAwaitingExit = await waitUntilAwaitingAuthoritativeExit(client)
    #expect(isAwaitingExit)
    // Cross the configured request deadline only after RpcClient confirms that
    // it drained stdout and suspended request timeouts for authoritative exit.
    try await Task.sleep(for: .milliseconds(200))
    #expect(await !probe.hasPendingFinished)
    #expect(await !probe.hasTerminationFinished)

    FileManager.default.createFile(atPath: release.path, contents: nil)
    let result = await pending.value
    await termination.value

    guard case .failure(let error) = result,
          case .processExited(let code, let stderr) = error as? RpcClientError else {
        Issue.record("expected the pending request to fail with processExited")
        await client.shutdown()
        return
    }
    #expect(code == 23)
    #expect(stderr.contains("close-stdout-before-exit"))
    #expect(await client.exitCode == 23)
    await client.shutdown()
}

@Test func writeFailureDuringStdoutEOFAwaitsAuthoritativeExit() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("RpcWriteExitGate-\(UUID().uuidString)", isDirectory: true)
    let stdoutClosed = root.appendingPathComponent("stdout-closed")
    let release = root.appendingPathComponent("release")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let client = makeClient(
        mode: "close-stdout-before-exit",
        modeArguments: [stdoutClosed.path, release.path])
    _ = try await client.start()
    let trigger = Task { try await client.send(.getState(), timeout: .seconds(10)) }
    let observedStdoutClose = await withTimeout(.seconds(5)) { () -> Bool in
        while !Task.isCancelled {
            if FileManager.default.fileExists(atPath: stdoutClosed.path) { return true }
            await Task.yield()
        }
        return false
    } ?? false
    #expect(observedStdoutClose)

    let probe = RpcCompletionProbe()
    let racedWrite = Task { () -> Result<RpcResponse, any Error> in
        let result: Result<RpcResponse, any Error>
        do {
            result = .success(try await client.send(
                RpcCommand(type: "get_session_stats"), timeout: .seconds(10)))
        } catch {
            result = .failure(error)
        }
        await probe.markPendingFinished()
        return result
    }
    #expect(await waitUntilAwaitingAuthoritativeExit(client))
    #expect(await waitForExitRelatedWriteFailure(client))
    #expect(await !probe.hasPendingFinished)

    FileManager.default.createFile(atPath: release.path, contents: nil)
    let triggerResult = await trigger.result
    let racedResult = await racedWrite.value

    for result in [triggerResult, racedResult] {
        guard case .failure(let error) = result,
              case .processExited(let code, _) = error as? RpcClientError else {
            Issue.record("expected processExited for pending request")
            continue
        }
        #expect(code == 23)
    }
    #expect(await client.exitCode == 23)
    await client.shutdown()
}

@Test func shutdownRemainsBoundedWhileAwaitingAuthoritativeExit() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("RpcShutdownExitGate-\(UUID().uuidString)", isDirectory: true)
    let stdoutClosed = root.appendingPathComponent("stdout-closed")
    let release = root.appendingPathComponent("release")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let client = makeClient(
        mode: "close-stdout-before-exit",
        modeArguments: [stdoutClosed.path, release.path])
    _ = try await client.start()
    let pending = Task { try await client.send(.getState(), timeout: .seconds(10)) }
    #expect(await waitUntilAwaitingAuthoritativeExit(client))

    let clock = ContinuousClock()
    let started = clock.now
    await client.shutdown()
    #expect(clock.now - started < .seconds(3))
    guard case .failure = await pending.result else {
        Issue.record("shutdown should fail the pending request")
        return
    }
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

@Test func spawnFlagsFollowProviderModelThinkingOrder() {
    var cfg = RpcClientConfiguration()
    cfg.provider = "anthropic"
    cfg.model = "claude-opus-4-8"
    cfg.thinking = "high"
    cfg.noSession = true
    #expect(cfg.resolvedArguments == [
        "--mode", "rpc", "--no-title",
        "--provider", "anthropic",
        "--model", "claude-opus-4-8",
        "--thinking", "high",
        "--no-session",
    ])
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

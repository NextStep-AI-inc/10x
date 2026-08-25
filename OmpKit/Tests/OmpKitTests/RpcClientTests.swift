import Testing
import Foundation
@testable import OmpKit

func makeClient(mode: String) -> RpcClient {
    var cfg = RpcClientConfiguration()
    cfg.executable = "/usr/bin/env"
    cfg.extraArguments = ["python3", fixtureURL("fake_server.py").path, mode]
    cfg.rawArgv = true   // extraArguments become the full argv — no omp flags prepended
    cfg.noSession = true
    return RpcClient(configuration: cfg)
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
    let collector = Task { () -> [String] in
        var seen: [String] = []
        for await frame in await c.events {
            switch frame {
            case .event(let type, _): seen.append(type)
            case .extensionUIRequest: seen.append("extension_ui_request")
            default: break
            }
            if seen.count >= 3 { break }
        }
        return seen
    }
    _ = try await c.start()
    _ = try await c.send(.getState())
    let seen = await withTimeout(.seconds(10)) { await collector.value } ?? []
    #expect(seen.contains("available_commands_update"))
    #expect(seen.contains("extension_ui_request"))
    #expect(seen.contains("notice"))
    await c.shutdown()
}

@Test func eofFailsPendingRequests() async throws {
    let c = makeClient(mode: "silent")
    _ = try await c.start()
    let pending = Task { try await c.send(.getState(), timeout: .seconds(10)) }
    try await Task.sleep(for: .milliseconds(100))
    await c.shutdown()   // closes stdin → fake exits → EOF
    let result = await pending.result
    guard case .failure(let error) = result else {
        Issue.record("expected the pending request to fail on EOF"); return
    }
    #expect(error is RpcClientError)
}

@Test func sendBeforeStartThrows() async {
    let c = makeClient(mode: "basic")
    await #expect(throws: RpcClientError.self) { _ = try await c.send(.getState()) }
}

@Test func concurrentRequestsCorrelateByIdNotOrder() async throws {
    let c = makeClient(mode: "basic")
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

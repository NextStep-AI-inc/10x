import Foundation
import OmpKit
import Testing
@testable import TenXApp

private actor StubChannel: ProviderAccountChannel {
    private(set) var sent: [ProviderAccountChannelCommand] = []
    private var replies: [String: Result<JSONValue, any Error>]

    init(replies: [String: Result<JSONValue, any Error>]) { self.replies = replies }

    func send(_ command: ProviderAccountChannelCommand) async throws -> JSONValue {
        sent.append(command)
        switch replies[command.command] {
        case .success(let value): return value
        case .failure(let error): throw error
        case nil: throw ProviderAccountChannelError.unavailable
        }
    }
}

/// A channel whose extension accepted the command but never answers —
/// `StubChannel` above always resolves immediately (success, failure, or
/// `.unavailable`), so it cannot exercise `hello`'s own timeout race; this
/// simulates the one case that can. `Task.sleep` is cancellation-aware, so
/// `hello`'s `group.cancelAll()` after the timeout wins does stop this
/// particular hang — unlike the real `ProviderAccountExtensionChannel`,
/// whose in-flight `withCheckedThrowingContinuation` is not
/// cancellation-aware (see `hello`'s own doc comment) — but that
/// distinction is the real channel's problem, not this test's: the goal
/// here is proving `hello`'s bound is real, not reproducing every property
/// of the concrete channel.
private actor HangingChannel: ProviderAccountChannel {
    func send(_ command: ProviderAccountChannelCommand) async throws -> JSONValue {
        try await Task.sleep(for: .seconds(3600))
        return .null
    }
}

@Suite struct ProviderAccountExtensionBackendTests {

@Test func routingAnIdleSessionAppliesImmediately() async throws {
    let channel = StubChannel(replies: ["pin_account": .success(.object(["applied": .bool(true)]))])
    let backend = ProviderAccountExtensionBackend(channel: channel)

    let outcome = try await backend.route(
        providerID: "anthropic", accountRef: "ref-a", sessionID: UUID())

    #expect(outcome == .applied)
}

@Test func routingAStreamingSessionQueuesInsteadOfFailing() async throws {
    let channel = StubChannel(replies: ["pin_account": .success(.object(["error": .string("streaming")]))])
    let backend = ProviderAccountExtensionBackend(channel: channel)

    let outcome = try await backend.route(
        providerID: "anthropic", accountRef: "ref-a", sessionID: UUID())

    #expect(outcome == .queued)
}

@Test func aDroppedChannelSurfacesAsUnavailable() async throws {
    let backend = ProviderAccountExtensionBackend(channel: StubChannel(replies: [:]))

    await #expect(throws: ProviderAccountChannelError.unavailable) {
        _ = try await backend.route(providerID: "anthropic", accountRef: "ref-a", sessionID: UUID())
    }
}

/// Task 10b: `remove_account` has no Swift caller yet — this is that wiring's
/// own coverage, exercised only through `ProviderAccountChannel` (a real
/// extension loop is never spun up in this suite; see the class doc comment
/// on `ProviderAccountExtensionChannel`). Also covers the Task 10 minor item
/// deferred "to return with Task 10b's decode wiring": an unrecognized
/// `availability` string on a returned account decodes to `.unavailable`
/// (`ProviderAccountAvailability.init(from:)`'s fail-closed fallback) rather
/// than throwing.
@Test func removingAnAccountDecodesTheRemovalResult() async throws {
    let channel = StubChannel(replies: ["remove_account": .success(.object([
        "removed": .bool(true),
        "accounts": .array([.object([
            "providerId": .string("anthropic"),
            "accountRef": .string("ref-b"),
            "displayLabel": .string("work@example.com"),
            "connectionOrder": .int(0),
            "availability": .string("some-future-value"),
        ])]),
    ]))])
    let backend = ProviderAccountExtensionBackend(channel: channel)

    let result = try await backend.removeAccount(providerID: "anthropic", accountRef: "ref-a")

    #expect(result.removed)
    #expect(result.accounts == [ProviderAccountSummary(
        providerID: "anthropic",
        accountRef: "ref-b",
        displayLabel: "work@example.com",
        connectionOrder: 0,
        availability: .unavailable)])
    let sent = await channel.sent
    #expect(sent.map(\.command) == ["remove_account"])
    #expect(sent.first?.params["providerId"] == .string("anthropic"))
    #expect(sent.first?.params["accountRef"] == .string("ref-a"))
}

@Test func removingAnAccountSurfacesACommandLevelErrorAsRejected() async throws {
    let channel = StubChannel(replies: ["remove_account": .success(.object(["error": .string("no such account")]))])
    let backend = ProviderAccountExtensionBackend(channel: channel)

    await #expect(throws: ProviderAccountChannelError.rejected("no such account")) {
        _ = try await backend.removeAccount(providerID: "anthropic", accountRef: "ref-a")
    }
}

@Test func removingAnAccountOnADroppedChannelSurfacesAsUnavailable() async throws {
    let backend = ProviderAccountExtensionBackend(channel: StubChannel(replies: [:]))

    await #expect(throws: ProviderAccountChannelError.unavailable) {
        _ = try await backend.removeAccount(providerID: "anthropic", accountRef: "ref-a")
    }
}

/// Task 10b fix round 1, Finding 1: `hello` had no Swift caller at all —
/// this is that wiring's own coverage, mirroring `removingAnAccountDecodesTheRemovalResult`.
/// `OmpExtension/index.ts`'s `case "hello": return { contractVersion: 1 }`
/// is the real reply shape this decodes.
@Test func helloDecodesACompatibleContractVersion() async throws {
    let channel = StubChannel(replies: ["hello": .success(.object(["contractVersion": .int(1)]))])
    let backend = ProviderAccountExtensionBackend(channel: channel)

    let hello = await backend.hello()

    #expect(hello == ProviderExtensionHello(contractVersion: 1))
    let sent = await channel.sent
    #expect(sent.map(\.command) == ["hello"])
}

/// `detect`'s own fail-closed comparison is already covered exhaustively by
/// `ProviderAccountTierTests` — this only proves `hello()` itself decodes an
/// unrecognized version rather than choking on it, since `detect` needs the
/// raw value (not a pre-filtered one) to tell "incompatible" apart from
/// "absent" the same way it already does for a `nil` hello.
@Test func helloDecodesAnUnrecognizedContractVersionRatherThanDiscardingIt() async throws {
    let channel = StubChannel(replies: ["hello": .success(.object(["contractVersion": .int(99)]))])
    let backend = ProviderAccountExtensionBackend(channel: channel)

    let hello = await backend.hello()

    #expect(hello == ProviderExtensionHello(contractVersion: 99))
}

@Test func helloOnADroppedChannelReturnsNilRatherThanThrowing() async throws {
    let backend = ProviderAccountExtensionBackend(channel: StubChannel(replies: [:]))

    let hello = await backend.hello()

    #expect(hello == nil)
}

/// Mirrors `aChannelThatNeverOpensDegradesWithinTheTimeoutInsteadOfHanging`'s
/// evidentiary bar: measures wall-clock elapsed time, not just "eventually
/// returned," to prove `hello`'s own bound (independent of
/// `ProviderAccountExtensionChannel`'s 30s `openRequestTimeout`) is real.
/// `HangingChannel` never resolves `send` at all, simulating a channel whose
/// extension accepted the command but never answers — the case
/// `helloTimeout` exists to bound.
@Test func helloThatNeverAnswersDegradesWithinTheTimeoutInsteadOfHanging() async throws {
    let backend = ProviderAccountExtensionBackend(channel: HangingChannel())

    let clock = ContinuousClock()
    let start = clock.now
    let hello = await backend.hello(timeout: .milliseconds(50))
    let elapsed = clock.now - start

    #expect(hello == nil)
    // Generous relative to the 50ms timeout, same reasoning as the channel
    // test this mirrors: asserts "degraded promptly," not "at exactly
    // 50ms," so it stays robust to scheduler jitter under load while still
    // failing hard on an accidental return to an unbounded wait.
    #expect(elapsed < .seconds(2))
}

@MainActor
@Test func channelRegistryAnyChannelReturnsAnAttachedChannel() async throws {
    let registry = ProviderAccountChannelRegistry()
    #expect(registry.anyChannel() == nil)
    let channel = StubChannel(replies: [:])
    let sessionID = UUID()

    registry.attach(sessionID: sessionID, channel: channel, sessionFile: nil)

    #expect(registry.anyChannel() != nil)

    registry.detach(sessionID: sessionID)

    #expect(registry.anyChannel() == nil)
}

@Test func firstSendSucceedsEvenWhenTheOpeningFrameWasAlreadyBuffered() async throws {
    let (stream, continuation) = AsyncStream<RpcFrame>.makeStream()

    // Simulate the extension's session_start handler opening its first
    // request before anything ever calls `send` — `AsyncStream` buffers
    // this (unbounded by default), exactly like the real gap between a
    // session's omp process starting and 10x's first `pin_account` call.
    continuation.yield(.extensionUIRequest(ExtensionUIRequest(
        id: "req-1",
        method: "input",
        payload: .object([
            "type": .string("extension_ui_request"),
            "id": .string("req-1"),
            "method": .string("input"),
            "title": .string(ExtensionUIRouter.providerAccountChannelTitle),
        ]))))

    let channel = ProviderAccountExtensionChannel(events: stream) { _, body in
        guard let value = body["value"]?.stringValue,
              let sent = try? JSONDecoder().decode(JSONValue.self, from: Data(value.utf8)),
              let commandID = sent["id"]?.stringValue
        else { return }
        let reply = JSONValue.object([
            "id": .string(commandID),
            "ok": .bool(true),
            "data": .object(["applied": .bool(true)]),
        ])
        let replyData = try JSONEncoder().encode(reply)
        continuation.yield(.extensionUIRequest(ExtensionUIRequest(
            id: "req-2",
            method: "input",
            payload: .object([
                "type": .string("extension_ui_request"),
                "id": .string("req-2"),
                "method": .string("input"),
                "title": .string(ExtensionUIRouter.providerAccountChannelTitle),
                "placeholder": .string(String(decoding: replyData, as: UTF8.self)),
            ]))))
    }

    let result = try await channel.send(ProviderAccountChannelCommand(
        id: "cmd-1", command: "pin_account", params: [:]))

    #expect(result == .object(["applied": .bool(true)]))
}

/// Task 8's own comment on `claimOpenRequestID` warns this is exactly the
/// method a naive fix could turn into a spurious-failure trap; this test
/// instead targets the opposite failure mode a reviewer flagged in fix
/// round 1: an extension that never opens even one request must not hang
/// `send()` forever. `openRequestTimeout` is injected tiny so the test
/// itself stays fast — proven empirically to actually matter (not just
/// "eventually pass") by measuring wall-clock elapsed time, not merely
/// awaiting the call.
@Test func aChannelThatNeverOpensDegradesWithinTheTimeoutInsteadOfHanging() async throws {
    let (stream, _) = AsyncStream<RpcFrame>.makeStream()
    // The continuation is deliberately dropped unused rather than finished
    // or yielded on — simulating an extension that spawned but never
    // opened its first `ctx.ui.input()` request. Confirmed separately that
    // an `AsyncStream` does NOT auto-terminate when its continuation goes
    // out of scope (a standalone `for await` against exactly this pattern
    // hangs indefinitely) — so this exercises the timeout path, not
    // `handleStreamEnded`'s stream-end path.
    let channel = ProviderAccountExtensionChannel(
        events: stream,
        openRequestTimeout: .milliseconds(50),
        respond: { _, _ in })

    let clock = ContinuousClock()
    let start = clock.now
    await #expect(throws: ProviderAccountChannelError.unavailable) {
        _ = try await channel.send(ProviderAccountChannelCommand(
            id: "cmd-1", command: "pin_account", params: [:]))
    }
    let elapsed = clock.now - start

    // Generous relative to the 50ms timeout — this asserts "degraded
    // promptly," not "degraded at exactly 50ms," so it stays robust to
    // scheduler jitter under load while still failing hard on an
    // accidental return to the old unbounded wait.
    #expect(elapsed < .seconds(2))
}

}

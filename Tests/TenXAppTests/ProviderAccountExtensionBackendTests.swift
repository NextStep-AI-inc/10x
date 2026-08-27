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

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

}

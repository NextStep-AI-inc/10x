import Testing
import Foundation
@testable import OmpKit

func fixtureURL(_ name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
        ?? Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(name)")
}

func makeFakeTransport(mode: String) -> LineTransport {
    LineTransport(executable: "/usr/bin/env",
                  arguments: ["python3", fixtureURL("fake_server.py").path, mode],
                  currentDirectory: nil, environment: nil)
}

/// Fails the test rather than hanging forever when a stream never yields.
func withTimeout<T: Sendable>(
    _ duration: Duration, operation: @escaping @Sendable () async -> T
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask { try? await Task.sleep(for: duration); return nil }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

@Test func readsReadyLineAndShutsDown() async throws {
    let t = makeFakeTransport(mode: "basic")
    try await t.start()
    let first = await withTimeout(.seconds(10)) {
        var it = t.lines.makeAsyncIterator()
        return await it.next()
    }
    let text = first.flatMap { $0 }.map { String(decoding: $0, as: UTF8.self) }
    #expect(text?.contains(#""type":"ready""#) == true)
    await t.shutdown()
    #expect(await t.exitStatus != nil)
}

@Test func writeAfterExitThrowsClosed() async throws {
    let t = makeFakeTransport(mode: "basic")
    try await t.start()
    await t.shutdown()
    await #expect(throws: TransportError.closed) { try await t.write(Data("{}\n".utf8)) }
}

@Test func deliversMultipleLinesInOrder() async throws {
    let t = makeFakeTransport(mode: "noisy")
    try await t.start()
    let collected = await withTimeout(.seconds(10)) {
        var out: [String] = []
        for await line in t.lines {
            out.append(String(decoding: line, as: UTF8.self))
            if out.count >= 3 { break }
        }
        return out
    }
    let lines = collected ?? []
    #expect(lines.count == 3)
    #expect(lines[0].contains(#""type":"ready""#))
    #expect(lines[1].contains("available_commands_update"))
    #expect(lines[2].contains("extension_ui_request"))
    await t.shutdown()
}

@Test func roundTripsAWrittenCommand() async throws {
    let t = makeFakeTransport(mode: "basic")
    try await t.start()
    let response = await withTimeout(.seconds(10)) {
        var it = t.lines.makeAsyncIterator()
        _ = await it.next()   // ready
        try? await t.write(Data(#"{"id":"x1","type":"get_state"}"# .utf8 + [UInt8(ascii: "\n")]))
        return await it.next()
    }
    let text = response.flatMap { $0 }.map { String(decoding: $0, as: UTF8.self) }
    #expect(text?.contains("fake-session") == true)
    await t.shutdown()
}

@Test func exitStreamFiresWhenProcessEnds() async throws {
    let t = makeFakeTransport(mode: "basic")
    try await t.start()
    let exited = await withTimeout(.seconds(10)) {
        async let code = { () -> Int32? in
            for await c in t.onExit { return c }
            return nil
        }()
        await t.shutdown()
        return await code
    }
    #expect(exited != nil)
}

@Test func spawnFailureIsReported() async {
    let t = LineTransport(executable: "/nonexistent/binary/xyz", arguments: [],
                          currentDirectory: nil, environment: nil)
    await #expect(throws: (any Error).self) { try await t.start() }
}

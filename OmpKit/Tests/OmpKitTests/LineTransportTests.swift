import Testing
import Foundation
@testable import OmpKit

func fixtureURL(_ name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
        ?? Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(name)")
}

func makeFakeTransport(mode: String, arguments: [String] = []) -> LineTransport {
    LineTransport(executable: "/usr/bin/env",
                  arguments: ["python3", fixtureURL("fake_server.py").path, mode] + arguments,
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
    let exited = await withTimeout(.seconds(10)) { () -> Int32 in
        async let code = { () -> Int32 in
            for await c in t.onExit { return c }
            return Int32.min
        }()
        await t.shutdown()
        return await code
    }
    #expect(exited == 0)
}

@Test func spawnFailureIsReported() async {
    let t = LineTransport(executable: "/nonexistent/binary/xyz", arguments: [],
                          currentDirectory: nil, environment: nil)
    await #expect(throws: (any Error).self) { try await t.start() }
}

@Test func lineBufferReassemblesSplitReadsAndStripsCRLF() {
    let buffer = LineBuffer()
    #expect(buffer.append(Data(#"{"a":"hel"# .utf8), maxLineBytes: 100).isEmpty)
    let completed = buffer.append(
        Data("lo\"}\r\n\n{\"b\":2}\r\n".utf8), maxLineBytes: 100)
    #expect(completed.map { String(decoding: $0, as: UTF8.self) } == [
        #"{"a":"hello"}"#, #"{"b":2}"#,
    ])
}

@Test func lineBufferDropsOneOverflowingLineThenResynchronizes() {
    let buffer = LineBuffer()
    #expect(buffer.append(Data(repeating: UInt8(ascii: "x"), count: 9), maxLineBytes: 8).isEmpty)
    let completed = buffer.append(Data("tail\n{\"ok\":true}\n".utf8), maxLineBytes: 8)
    #expect(completed.map { String(decoding: $0, as: UTF8.self) } == [#"{"ok":true}"#])
}

@Test func shutdownUnblocksAFullStdinPipe() async throws {
    let transport = LineTransport(
        executable: "/bin/sleep", arguments: ["60"],
        currentDirectory: nil, environment: nil)
    try await transport.start()
    let writer = Task { try await transport.write(Data(repeating: 0x61, count: 1_048_576)) }
    try await Task.sleep(for: .milliseconds(100))
    let clock = ContinuousClock()
    let started = clock.now
    await transport.shutdown()
    #expect(clock.now - started < .seconds(3))
    _ = await writer.result
}

@Test func shutdownKillsGrandchildrenAfterTheLeaderExitsOnEOF() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ompkit-heartbeat-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let transport = LineTransport(
        executable: "/usr/bin/env",
        arguments: ["python3", fixtureURL("fake_server.py").path, "grandchild", root.path],
        currentDirectory: nil, environment: nil)
    try await transport.start()

    let before = await withTimeout(.seconds(2)) { () -> Int in
        while !Task.isCancelled {
            let count = (try? Data(contentsOf: root))?.count ?? 0
            if count > 0 { return count }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return 0
    } ?? 0
    #expect(before > 0)
    await transport.shutdown()
    try await Task.sleep(for: .milliseconds(300))
    let after = (try? Data(contentsOf: root))?.count ?? 0
    try await Task.sleep(for: .milliseconds(300))
    let settled = (try? Data(contentsOf: root))?.count ?? 0
    #expect(after == settled)
}

@Test func drainsTrailingFramesWhenChildExits() async throws {
    let transport = makeFakeTransport(mode: "burst-exit")
    try await transport.start()
    let lines = await withTimeout(.seconds(5)) { () -> [Data] in
        var lines: [Data] = []
        for await line in transport.lines { lines.append(line) }
        return lines
    } ?? []
    #expect(lines.count == 201)  // ready + 200 notices
    let exitCode = await withTimeout(.seconds(5)) { () -> Int32 in
        for await code in transport.onExit { return code }
        return Int32.min
    }
    #expect(exitCode == 0)
    #expect(await transport.exitStatus == exitCode)
}

@Test func exitCapturesFinalStderrWithoutWaitingForInheritedWriters() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("StderrExitGate-\(UUID().uuidString)", isDirectory: true)
    let holding = root.appendingPathComponent("holding-stderr")
    let release = root.appendingPathComponent("release")
    let released = root.appendingPathComponent("released")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let transport = makeFakeTransport(
        mode: "stderr-held-open-exit",
        arguments: [holding.path, release.path, released.path])
    try await transport.start()
    let exitCode = await withTimeout(.seconds(1)) { () -> Int32 in
        for await code in transport.onExit { return code }
        return Int32.min
    }
    FileManager.default.createFile(atPath: release.path, contents: nil)
    let holderReleased = await withTimeout(.seconds(5)) { () -> Bool in
        while !Task.isCancelled {
            if FileManager.default.fileExists(atPath: released.path) { return true }
            await Task.yield()
        }
        return false
    } ?? false
    if exitCode == nil {
        _ = await withTimeout(.seconds(5)) { () -> Int32 in
            for await code in transport.onExit { return code }
            return Int32.min
        }
    }

    #expect(holderReleased)
    #expect(exitCode == 31)
    #expect(await transport.stderrSnapshot().hasSuffix("final-stderr-marker\n"))
}

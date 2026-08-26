import Testing
import Foundation
@testable import OmpKit

private func providerAccountResponse(from line: String) throws -> RpcResponse {
    guard case .response(let response) = try RpcFrame.decode(line: Data(line.utf8)) else {
        throw RpcFrameError.malformedFrame(type: "response", underlying: "not a response")
    }
    return response
}

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

private func openGateAndWaitForProducer(_ gate: URL, producer: URL) {
    FileManager.default.createFile(atPath: gate.path, contents: nil)
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if FileManager.default.fileExists(atPath: producer.path) { return }
        usleep(1_000)
    }
}

private func fixturePID(at url: URL) -> pid_t? {
    guard let data = try? Data(contentsOf: url),
          let value = pid_t(String(decoding: data, as: UTF8.self)) else { return nil }
    return value
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

@Test func exitDrainSnapshotsBytesBeforeContinuouslyWritingDescendants() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ContinuousExitDrain-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        for stream in ["stdout", "stderr"] {
            FileManager.default.createFile(
                atPath: root.appendingPathComponent("\(stream)-stop").path,
                contents: nil)
            let stopped = root.appendingPathComponent("\(stream)-stopped")
            if !FileManager.default.fileExists(atPath: stopped.path),
               let pid = fixturePID(at: root.appendingPathComponent("\(stream)-pid")) {
                kill(pid, SIGKILL)
            }
        }
        try? FileManager.default.removeItem(at: root)
    }

    let transport = makeFakeTransport(
        mode: "continuous-inherited-output-exit", arguments: [root.path])
    await transport.installTestHooks(LineTransportTestHooks(
        afterStdoutFinalDrainSnapshot: {
            openGateAndWaitForProducer(
                root.appendingPathComponent("stdout-start"),
                producer: root.appendingPathComponent("stdout-primed"))
        },
        afterStderrFinalDrainSnapshot: {
            openGateAndWaitForProducer(
                root.appendingPathComponent("stderr-start"),
                producer: root.appendingPathComponent("stderr-primed"))
        }))
    try await transport.start()

    let parentReachedExit = await withTimeout(.seconds(2)) { () -> Bool in
        let marker = root.appendingPathComponent("parent-exiting")
        while !Task.isCancelled {
            if FileManager.default.fileExists(atPath: marker.path) { return true }
            await Task.yield()
        }
        return false
    } ?? false
    let exitCode = await withTimeout(.seconds(1)) { () -> Int32 in
        for await code in transport.onExit { return code }
        return Int32.min
    }
    let stdoutPID = fixturePID(at: root.appendingPathComponent("stdout-pid"))
    let stderrPID = fixturePID(at: root.appendingPathComponent("stderr-pid"))
    let writersWereAlive = [stdoutPID, stderrPID].allSatisfy {
        guard let pid = $0 else { return false }
        return kill(pid, 0) == 0
    }

    for stream in ["stdout", "stderr"] {
        FileManager.default.createFile(
            atPath: root.appendingPathComponent("\(stream)-stop").path,
            contents: nil)
    }
    let writersStopped = await withTimeout(.seconds(2)) { () -> Bool in
        while !Task.isCancelled {
            if ["stdout", "stderr"].allSatisfy({
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent("\($0)-stopped").path)
            }) { return true }
            await Task.yield()
        }
        return false
    } ?? false
    let lines = await withTimeout(.seconds(2)) { () -> [String] in
        var lines: [String] = []
        for await line in transport.lines {
            lines.append(String(decoding: line, as: UTF8.self))
        }
        return lines
    } ?? []
    let stderr = await transport.stderrSnapshot()

    #expect(parentReachedExit)
    #expect(FileManager.default.fileExists(
        atPath: root.appendingPathComponent("stdout-primed").path))
    #expect(FileManager.default.fileExists(
        atPath: root.appendingPathComponent("stderr-primed").path))
    #expect(exitCode == 37)
    #expect(writersWereAlive)
    #expect(writersStopped)
    #expect(lines.contains { $0.contains(#""type":"parent-final""#) })
    #expect(!lines.contains { $0.contains("late-stdout-marker") })
    #expect(stderr.contains("parent-final-stderr\n"))
    #expect(!stderr.contains("late-stderr-marker"))
    #expect(stderr.utf8.count < 1_024)
}

@Test func providerAccountSummaryLineDecodesFullOMPContract() throws {
    let response = try providerAccountResponse(from: """
    {"id":"list","type":"response","command":"list_provider_accounts","success":true,"data":{"accounts":[{"providerId":"openai-codex","accountRef":"acct_B","displayLabel":"Tanner","detailLabel":"tanner@example.com","connectionOrder":2,"availability":"limited","isActiveForSession":true,"ignored":"future"}]}}
    """)
    let result = try response.providerAccountListResult()
    let account = try #require(result.accounts.first)

    #expect(account.providerID == "openai-codex")
    #expect(account.accountRef == "acct_B")
    #expect(account.displayLabel == "Tanner")
    #expect(account.detailLabel == "tanner@example.com")
    #expect(account.connectionOrder == 2)
    #expect(account.availability == .limited)
    #expect(account.isActiveForSession == true)
    #expect(account.id == "openai-codex:acct_B")
}

@Test func providerAccountSummaryUnknownAvailabilityFallsBackToUnavailable() throws {
    let response = try providerAccountResponse(from: """
    {"id":"list","type":"response","command":"list_provider_accounts","success":true,"data":{"accounts":[{"providerId":"openai-codex","accountRef":"acct_future","displayLabel":"Future","connectionOrder":3,"availability":"temporarilyUnavailable"}]}}
    """)
    let result = try response.providerAccountListResult()

    #expect(result.accounts.first?.accountRef == "acct_future")
    #expect(result.accounts.first?.availability == .unavailable)
}

@Test func providerAccountUsageLineDecodesWindowsAndIgnoresUnknownFields() throws {
    let response = try providerAccountResponse(from: """
    {"id":"usage","type":"response","command":"get_provider_account_usage","success":true,"data":{"accounts":[{"providerId":"openai-codex","accountRef":"acct_B","refreshedAt":"2026-08-26T09:30:00.000Z","usageWindows":[{"id":"five-hour","label":"5h","duration":{"value":5,"unit":"hour"},"sourceIndex":0,"remainingFraction":0.75,"resetsAt":"2026-08-26T14:30:00.000Z","status":"available","ignored":"future"}],"ignored":"future"}]}}
    """)
    let result = try response.providerAccountUsageResult()
    let account = try #require(result.accounts.first)
    let window = try #require(account.usageWindows.first)

    #expect(account.providerID == "openai-codex")
    #expect(account.accountRef == "acct_B")
    #expect(ISO8601DateFormatter().string(from: account.refreshedAt) == "2026-08-26T09:30:00Z")
    #expect(window.id == "five-hour")
    #expect(window.duration == ProviderAccountUsageWindow.Duration(value: 5, unit: .hour))
    #expect(window.sourceIndex == 0)
    #expect(window.remainingFraction == 0.75)
    #expect(window.resetsAt.map { ISO8601DateFormatter().string(from: $0) } == "2026-08-26T14:30:00Z")
    #expect(window.status == "available")
}

@Test func providerAccountMutationResponsesDecodeFromRpcResponseData() throws {
    let pinResponse = try providerAccountResponse(from: """
    {"id":"pin","type":"response","command":"set_session_provider_account","success":true,"data":{"account":{"providerId":"openai-codex","accountRef":"acct_B","displayLabel":"Tanner","connectionOrder":2,"availability":"available","isActiveForSession":true},"sequence":12,"ignored":"future"}}
    """)
    let pin = try pinResponse.setSessionProviderAccountResult()
    #expect(pin.account.accountRef == "acct_B")
    #expect(pin.account.isActiveForSession == true)
    #expect(pin.sequence == 12)

    let removalResponse = try providerAccountResponse(from: """
    {"id":"remove","type":"response","command":"remove_provider_account","success":true,"data":{"removed":true,"accounts":[{"providerId":"openai-codex","accountRef":"acct_C","displayLabel":"Backup","connectionOrder":3,"availability":"limited"}],"ignored":"future"}}
    """)
    let removal = try removalResponse.removeProviderAccountResult()
    #expect(removal.removed)
    #expect(removal.accounts.map { $0.accountRef } == ["acct_C"])
}

@Test func providerAccountChangedLineDecodesTypedEventAndUnknownReason() throws {
    let manual = Data("""
    {"type":"provider_account_changed","providerId":"openai-codex","accountRef":"acct_B","reason":"manual","sequence":7}
    """.utf8)
    guard case .providerAccountChanged(let event) = try RpcFrame.decode(line: manual) else {
        Issue.record("not a provider account event"); return
    }
    #expect(event.providerID == "openai-codex")
    #expect(event.accountRef == "acct_B")
    #expect(event.reason == .manual)
    #expect(event.sequence == 7)

    let future = Data("""
    {"type":"provider_account_changed","providerId":"openai-codex","accountRef":"acct_future","reason":"serverSideMigration","sequence":8}
    """.utf8)
    guard case .providerAccountChanged(let unknown) = try RpcFrame.decode(line: future) else {
        Issue.record("future provider account event was dropped"); return
    }
    #expect(unknown.accountRef == "acct_future")
    #expect(unknown.reason == .unknown("serverSideMigration"))
}

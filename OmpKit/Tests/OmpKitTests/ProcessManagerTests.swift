import Testing
import Foundation
@testable import OmpKit

private func fakeManager(mode: String = "basic") -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        var c = configuration
        c.executable = "/usr/bin/env"
        c.extraArguments = ["python3", fixtureURL("fake_server.py").path, mode]
        c.rawArgv = true
        return RpcClient(configuration: c)
    })
}

@Test func openIsIdempotentPerPath() async throws {
    let manager = fakeManager()
    let first = try await manager.open(sessionPath: "/tmp/s.jsonl", cwd: "/tmp")
    let second = try await manager.open(sessionPath: "/tmp/s.jsonl", cwd: "/tmp")
    #expect(first.client === second.client)
    await manager.closeAll()
}

@Test func closeRemovesTheHandle() async throws {
    let manager = fakeManager()
    _ = try await manager.open(sessionPath: "/tmp/gone.jsonl", cwd: "/tmp")
    #expect(await manager.handle(for: "/tmp/gone.jsonl") != nil)
    await manager.close(sessionPath: "/tmp/gone.jsonl")
    #expect(await manager.handle(for: "/tmp/gone.jsonl") == nil)
}

@Test func distinctPathsGetDistinctChildren() async throws {
    let manager = fakeManager()
    let a = try await manager.open(sessionPath: "/tmp/a.jsonl", cwd: "/tmp")
    let b = try await manager.open(sessionPath: "/tmp/b.jsonl", cwd: "/tmp")
    #expect(a.client !== b.client)
    await manager.closeAll()
}

@Test func unexpectedExitIsSurfaced() async throws {
    let manager = fakeManager()
    let handle = try await manager.open(sessionPath: "/tmp/dies.jsonl", cwd: "/tmp")
    let stream = manager.unexpectedExits

    let killer = Task {
        try? await Task.sleep(for: .milliseconds(150))
        await handle.client.shutdown()   // dies behind the manager's back
    }
    defer { killer.cancel() }

    let path = await withTimeout(.seconds(5)) { () -> String? in
        for await exit in stream { return exit.sessionPath }
        return nil
    } ?? nil
    #expect(path == "/tmp/dies.jsonl")
    await manager.closeAll()
}

@Test func deliberateCloseDoesNotReportAnExit() async throws {
    let manager = fakeManager()
    _ = try await manager.open(sessionPath: "/tmp/quiet.jsonl", cwd: "/tmp")
    let stream = manager.unexpectedExits
    await manager.close(sessionPath: "/tmp/quiet.jsonl")

    // No event should arrive; the timeout expiring is the passing outcome.
    let path = await withTimeout(.seconds(1)) { () -> String? in
        for await exit in stream { return exit.sessionPath }
        return nil
    } ?? nil
    #expect(path == nil)
}

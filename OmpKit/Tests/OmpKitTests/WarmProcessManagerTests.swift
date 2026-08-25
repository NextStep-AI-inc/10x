import Foundation
import Testing
@testable import OmpKit

@Test func warmStartsOneNoSessionClientPerCanonicalProject() async throws {
    let capture = ConfigurationCapture()
    let manager = capturingManager(capture)
    let firstProject = URL(filePath: "/tmp/project-a").resolvingSymlinksInPath().path
    let secondProject = URL(filePath: "/tmp/project-b").resolvingSymlinksInPath().path

    async let first = manager.warm(projectDirectory: firstProject)
    async let second = manager.warm(projectDirectory: secondProject)
    let handles = try await [first, second]
    let configurations = capture.snapshot()
    let allNoSession = configurations.allSatisfy(\.noSession)

    #expect(handles.count == 2)
    #expect(configurations.count == 2)
    #expect(allNoSession)
    #expect(Set(configurations.compactMap { $0.cwd?.path }) == [
        firstProject, secondProject,
    ])
    await manager.closeAll()
}

@Test func concurrentWarmForOneProjectSharesOneChild() async throws {
    let capture = ConfigurationCapture()
    let manager = capturingManager(capture)
    async let first = manager.warm(projectDirectory: "/tmp/shared")
    async let second = manager.warm(projectDirectory: "/tmp/shared")
    let handles = try await [first, second]

    #expect(handles[0].client === handles[1].client)
    #expect(capture.snapshot().count == 1)
    await manager.closeAll()
}

@Test func warmExitIsReportedAndRemovedBeforeCheckout() async throws {
    let manager = capturingManager(ConfigurationCapture(), mode: "crash-after-negotiation")
    let project = URL(filePath: "/tmp/dies").resolvingSymlinksInPath().path
    _ = try await manager.warm(projectDirectory: project)
    let event = await withTimeout(.seconds(5)) { () -> SessionProcessManager.WarmExit? in
        for await exit in manager.unexpectedWarmExits { return exit }
        return nil
    } ?? nil

    #expect(event?.projectDirectory == project)
    #expect(event?.code == 7)
    #expect(await !manager.isWarm(projectDirectory: project))
    await manager.closeAll()
}

@Test func closeAllReapsWarmAndActiveClients() async throws {
    let manager = capturingManager(ConfigurationCapture())
    let warm = try await manager.warm(projectDirectory: "/tmp/warm")
    let active = try await manager.open(sessionPath: "/tmp/active.jsonl", cwd: "/tmp")

    await manager.closeAll()

    #expect(await warm.client.exitCode != nil)
    #expect(await active.client.exitCode != nil)
}

@Test func cancelWarmingsReapsAnInflightChildWithoutEvictingReadyWarmClients() async throws {
    let configurations = ConfigurationCapture()
    let clients = ClientCapture()
    let readyProject = URL(filePath: "/tmp/ready").resolvingSymlinksInPath().path
    let blockedProject = URL(filePath: "/tmp/blocked").resolvingSymlinksInPath().path
    let manager = SessionProcessManager(clientFactory: { configuration in
        configurations.append(configuration)
        var fake = configuration
        fake.executable = "/usr/bin/env"
        let mode = configuration.cwd?.path == readyProject ? "basic" : "never-ready"
        fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, mode]
        fake.rawArgv = true
        fake.cwd = nil
        fake.startupTimeout = .seconds(30)
        let client = RpcClient(configuration: fake)
        clients.append(client)
        return client
    })
    _ = try await manager.warm(projectDirectory: readyProject)
    let blocked = Task {
        try? await manager.warm(projectDirectory: blockedProject)
    }
    while configurations.snapshot().count < 2 { await Task.yield() }

    let canceled = await manager.cancelWarmings()
    _ = await blocked.value

    #expect(canceled == [blockedProject])
    #expect(await manager.isWarm(projectDirectory: readyProject))
    #expect(await !manager.isWarm(projectDirectory: blockedProject))
    #expect(await clients.snapshot()[1].exitCode != nil)
    await manager.closeAll()
}

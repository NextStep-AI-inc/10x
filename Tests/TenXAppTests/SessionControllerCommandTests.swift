import Darwin
import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor
@Test func activeSessionLoadsAndReplacesAvailableCommands() async throws {
    let manager = commandFakeManager(mode: "catalog-update")
    let controller = SessionController(processManager: manager)
    var updates = controller.commandUpdates.makeAsyncIterator()
    let project = try commandTemporaryDirectory()
    defer { commandRemove(project) }
    let opening = Task { await controller.openNew(projectURL: project) }

    #expect(try #require(await updates.next()) == .loading)
    #expect(try #require(await updates.next()) == .available([
        AvailableSlashCommand(name: "compact", source: .builtin),
    ]))
    _ = await opening.value
    #expect(try #require(await updates.next()) == .available([
        AvailableSlashCommand(name: "retry", source: .builtin),
    ]))
    #expect(controller.commandCatalogState == .available([
        AvailableSlashCommand(name: "retry", source: .builtin),
    ]))
    #expect(controller.availableCommands == [
        AvailableSlashCommand(name: "retry", source: .builtin),
    ])
    await manager.closeAll()
}

@MainActor
@Test func staleSessionCommandUpdateCannotReplaceRestartedCatalog() async throws {
    let manager = commandFakeManager(mode: "delayed-catalog-update")
    let controller = SessionController(processManager: manager)
    let project = try commandTemporaryDirectory()
    defer { commandRemove(project) }

    await controller.openNew(projectURL: project)
    let staleFrame = try commandEvent(#"{"type":"available_commands_update","commands":[{"name":"stale","source":"builtin"}]}"#)
    let staleConsumer = try #require(controller.testingCapturedAccountEventConsumer(staleFrame))
    await controller.restart()
    await staleConsumer()

    #expect(await commandEventually {
        controller.commandCatalogState == .available([
            AvailableSlashCommand(name: "compact", source: .builtin),
        ])
    })
    #expect(!controller.availableCommands.contains { $0.name == "stale" })
    await manager.closeAll()
}

@MainActor
@Test func unavailableCommandDiscoveryDoesNotFailTheSession() async throws {
    for mode in ["malformed-catalog", "unsupported-catalog"] {
        let manager = commandFakeManager(mode: mode)
        let controller = SessionController(processManager: manager)
        let project = try commandTemporaryDirectory()
        defer { commandRemove(project) }

        await controller.openNew(projectURL: project)

        #expect(controller.commandCatalogState == .unavailable)
        #expect(controller.runtimeState == .idle)
        #expect(controller.isComposerAvailable)
        await manager.closeAll()
    }
}

@MainActor
@Test func malformedCommandUpdateMakesTheCatalogUnavailable() async throws {
    let manager = commandFakeManager(mode: "malformed-catalog-update")
    let controller = SessionController(processManager: manager)
    let project = try commandTemporaryDirectory()
    defer { commandRemove(project) }

    await controller.openNew(projectURL: project)

    #expect(await commandEventually { controller.commandCatalogState == .unavailable })
    #expect(controller.runtimeState == .idle)
    await manager.closeAll()
}

@MainActor
@Test func stoppedAndFailedPipelinesMakeCommandsUnavailable() async throws {
    let stoppedManager = commandFakeManager(mode: "basic")
    let stoppedController = SessionController(processManager: stoppedManager)
    let stoppedProject = try commandTemporaryDirectory()
    defer { commandRemove(stoppedProject) }

    await stoppedController.openNew(projectURL: stoppedProject)
    stoppedController.handleUnexpectedExit(code: 9, stderrTail: "boom")
    #expect(stoppedController.commandCatalogState == .unavailable)
    await stoppedManager.closeAll()

    let failedManager = commandFakeManager(mode: "prompt-failure")
    let failedController = SessionController(processManager: failedManager)
    let failedProject = try commandTemporaryDirectory()
    defer { commandRemove(failedProject) }

    await failedController.openNew(projectURL: failedProject)
    failedController.draft = "prompt"
    await failedController.sendPrompt()
    #expect(failedController.commandCatalogState == .unavailable)
    await failedManager.closeAll()
}

@MainActor
@Test func openingANewPipelinePublishesLoadingBeforeItsCatalog() async throws {
    let manager = commandFakeManager(mode: "basic")
    let controller = SessionController(processManager: manager)
    var updates = controller.commandUpdates.makeAsyncIterator()
    let project = try commandTemporaryDirectory()
    defer { commandRemove(project) }
    let opening = Task { await controller.openNew(projectURL: project) }

    #expect(try #require(await updates.next()) == .loading)
    #expect(try #require(await updates.next()) == .available([]))
    _ = await opening.value
    await manager.closeAll()
}

@MainActor
@Test func startupCommandUpdateAppliesBeforeAndYieldsToInitialCatalogSnapshot() async throws {
    let manager = commandFakeManager(mode: "startup-catalog-update")
    let controller = SessionController(processManager: manager)
    var updates = controller.commandUpdates.makeAsyncIterator()
    let project = try commandTemporaryDirectory()
    defer { commandRemove(project) }
    let opening = Task { await controller.openNew(projectURL: project) }

    #expect(try #require(await updates.next()) == .loading)
    let startup = try #require(await updates.next())
    #expect(startup == .available([
        AvailableSlashCommand(name: "startup", source: .builtin),
    ]))
    let rpc = try #require(await updates.next())
    #expect(rpc == .available([
        AvailableSlashCommand(name: "rpc", source: .builtin),
    ]))
    _ = await opening.value
    #expect(controller.commandCatalogState == .available([
        AvailableSlashCommand(name: "rpc", source: .builtin),
    ]))
    #expect(controller.items.count == 1)
    guard case .threadStart = controller.items[0] else {
        Issue.record("Catalog control frames must not add transcript items")
        return
    }
    #expect(controller.runtimeState == .idle)
    await manager.closeAll()
}

@MainActor
@Test func startupCommandUpdateYieldsToUnsupportedInitialDiscovery() async throws {
    let manager = commandFakeManager(mode: "startup-unsupported-catalog")
    let controller = SessionController(processManager: manager)
    var updates = controller.commandUpdates.makeAsyncIterator()
    let project = try commandTemporaryDirectory()
    defer { commandRemove(project) }
    let opening = Task { await controller.openNew(projectURL: project) }

    #expect(try #require(await updates.next()) == .loading)
    #expect(try #require(await updates.next()) == .available([
        AvailableSlashCommand(name: "startup", source: .builtin),
    ]))
    #expect(try #require(await updates.next()) == .unavailable)
    _ = await opening.value
    #expect(controller.commandCatalogState == .unavailable)
    #expect(controller.runtimeState == .idle)
    await manager.closeAll()
}

@MainActor
@Test func restartPublishesLoadingBeforeItsReplacementPipelineOpens() async throws {
    let manager = commandFakeManager(mode: "basic")
    let controller = SessionController(processManager: manager)
    let project = try commandTemporaryDirectory()
    defer { commandRemove(project) }

    await controller.openNew(projectURL: project)
    let restarting = Task { await controller.restart() }
    await Task.yield()

    #expect(controller.commandCatalogState == .loading)
    await restarting.value
    await manager.closeAll()
}

@MainActor
@Test func closingDuringAnOpeningTaskPublishesUnavailable() async throws {
    let marker = FileManager.default.temporaryDirectory
        .appendingPathComponent("command-ready-pid-\(UUID().uuidString)")
    let manager = commandFakeManager(mode: "blocked-ready", readyPIDURL: marker)
    let controller = SessionController(processManager: manager)
    let project = try commandTemporaryDirectory()
    defer {
        commandRemove(project)
        commandRemove(marker)
    }
    let opening = Task { await controller.openNew(projectURL: project) }

    #expect(await commandEventually({
        controller.commandCatalogState == .loading
            && FileManager.default.fileExists(atPath: marker.path)
    }, timeout: .seconds(10)))
    let closing = try #require(controller.dispose())
    #expect(controller.commandCatalogState == .unavailable)
    let processID = try #require(Int32(String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
    #expect(kill(processID, SIGUSR1) == 0)
    await closing.value
    _ = await opening.value
    await manager.closeAll()
}

private func commandFakeManager(mode: String, readyPIDURL: URL? = nil) -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        var fake = configuration
        fake.executable = "/usr/bin/python3"
        fake.extraArguments = [commandFakeServerURL().path, mode]
        fake.rawArgv = true
        fake.cwd = nil
        if let readyPIDURL {
            fake.environment = ["OMP_FAKE_READY_PID": readyPIDURL.path]
        }
        return RpcClient(configuration: fake)
    })
}

private func commandFakeServerURL() -> URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/composer_fake_server.py")
}

private func commandTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("session-controller-command-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func commandRemove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private func commandEvent(_ json: String) throws -> RpcFrame {
    try RpcFrame.decode(line: Data(json.utf8))
}

@MainActor
private func commandEventually(
    _ condition: @MainActor () -> Bool,
    timeout: Duration = .seconds(2)
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        await Task.yield()
    }
    return condition()
}

import Darwin
import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func configServiceUsesTheExactOMPCommands() async throws {
    let runner = FakeConfigRunner()
    let service = OmpConfigService(runner: runner)

    let list = try await service.list()
    #expect(list["autoResume"]?["value"]?.boolValue == false)
    try await service.set(key: "advisor.enabled", value: .bool(false))
    let path = try await service.path()

    #expect(path == "/tmp/omp/config.json")
    #expect(await runner.calls == [
        ["config", "list", "--json"],
        ["config", "set", "advisor.enabled", "false"],
        ["config", "path"],
    ])
}

@Test func configServiceResetsToAnUnsetOMPDefault() async throws {
    let runner = FakeConfigRunner()
    let service = OmpConfigService(runner: runner)

    let value = try await service.reset(key: "shellPath")

    #expect(value == nil)
    #expect(await runner.calls == [["config", "reset", "shellPath", "--json"]])
}

@Test func configServiceRejectsAnInvalidCustomShellPath() async {
    let runner = FakeConfigRunner()
    let service = OmpConfigService(runner: runner)

    do {
        try await service.set(key: "shellPath", value: .string("20"))
        Issue.record("Expected invalid shell path to fail")
    } catch {
        #expect(error.localizedDescription.contains("Shell path must point to an executable file"))
    }

    #expect(await runner.calls.isEmpty)
}

@MainActor
@Test func restoringAnUnsetDefaultClearsTheDisplayedValue() async throws {
    let runner = FakeConfigRunner()
    let model = SettingsViewModel(service: OmpConfigService(runner: runner))
    await model.load()
    let definition = try #require(model.catalog.definition(key: "shellPath"))
    #expect(definition.value == .string("20"))

    let didRestore = await model.restoreDefault(definition)

    #expect(didRestore)
    #expect(model.catalog.definition(key: "shellPath")?.value == nil)
}

@MainActor
@Test func invalidShellPathUsesAUserFacingError() async throws {
    let runner = FakeConfigRunner()
    let model = SettingsViewModel(service: OmpConfigService(runner: runner))
    await model.load()
    let definition = try #require(model.catalog.definition(key: "shellPath"))

    let didSave = await model.save(definition, value: .string("20"))

    #expect(!didSave)
    #expect(model.error(for: "shellPath") == "Choose an executable shell file, such as /bin/zsh.")
}

@MainActor
@Test func preferredIDEFocusClearsAQueryThatWouldHideTheRow() {
    let model = SettingsViewModel(service: OmpConfigService(runner: FakeConfigRunner()))
    model.query = "sleep prevention"

    let shouldRelinquishSearchFocus = model.prepareForFocus(.preferredIDE)

    #expect(model.query.isEmpty)
    #expect(shouldRelinquishSearchFocus)
}

@MainActor
@Test func settingsLoadReportsWhetherCatalogAndPathAreReady() async {
    let ready = SettingsViewModel(service: OmpConfigService(runner: FakeConfigRunner()))
    let failed = SettingsViewModel(service: OmpConfigService(runner: FailingConfigRunner()))

    #expect(await ready.load())
    #expect(ready.settingCount > 0)
    #expect(!ready.configPath.isEmpty)
    #expect(await !failed.load())
    #expect(failed.loadError != nil)
}

@Test func configErrorsNeverIncludeTheSecretValue() async {
    let service = OmpConfigService(runner: FailingConfigRunner())
    do {
        try await service.set(key: "auth.broker.token", value: .string("do-not-leak"))
        Issue.record("Expected config set to fail")
    } catch {
        #expect(error.localizedDescription.contains("auth.broker.token"))
        #expect(!error.localizedDescription.contains("do-not-leak"))
    }
}

@Test func cancellingConfigServiceReapsTheCommand() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let pidFile = fixture.root.appending(path: "config.pid")
    let executable = try fixture.executable(
        name: "blocked-config",
        body: "printf '%s' $$ > '\(pidFile.path)'; printf 'token=secret\\n' >&2; trap '' TERM; while :; do sleep 1; done")
    let service = OmpConfigService(
        runner: OmpConfigProcessRunner(executableURL: executable))
    let operation = Task { try await service.path() }
    let pids = try await fixture.waitForPIDs(
        in: pidFile, count: 1, cancelling: operation)
    let pid = try #require(pids.first)

    operation.cancel()
    await #expect(throws: CancellationError.self) {
        _ = try await operation.value
    }

    #expect(kill(pid, 0) == -1)
    #expect(errno == ESRCH)
}

private actor FakeConfigRunner: OmpConfigRunning {
    private(set) var calls: [[String]] = []

    func run(arguments: [String]) async throws -> Data {
        calls.append(arguments)
        if arguments == ["config", "list", "--json"] {
            return Data(#"{"autoResume":{"value":false,"type":"boolean","description":"Automatically resume"},"shellPath":{"value":"20","type":"string","description":""}}"#.utf8)
        }
        if arguments == ["config", "path"] {
            return Data("/tmp/omp/config.json\n".utf8)
        }
        if arguments == ["config", "reset", "shellPath", "--json"] {
            return Data(#"{"key":"shellPath"}"#.utf8)
        }
        return Data()
    }
}

private struct FailingConfigRunner: OmpConfigRunning {
    func run(arguments: [String]) async throws -> Data {
        throw FakeFailure()
    }
}

private struct FakeFailure: Error {}

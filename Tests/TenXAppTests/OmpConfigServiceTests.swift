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
    try await service.reset(key: "advisor.enabled")
    let path = try await service.path()

    #expect(path == "/tmp/omp/config.json")
    #expect(await runner.calls == [
        ["config", "list", "--json"],
        ["config", "set", "advisor.enabled", "false"],
        ["config", "reset", "advisor.enabled"],
        ["config", "path"],
    ])
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

private actor FakeConfigRunner: OmpConfigRunning {
    private(set) var calls: [[String]] = []

    func run(arguments: [String]) async throws -> Data {
        calls.append(arguments)
        if arguments == ["config", "list", "--json"] {
            return Data(#"{"autoResume":{"value":false,"type":"boolean","description":"Automatically resume"}}"#.utf8)
        }
        if arguments == ["config", "path"] {
            return Data("/tmp/omp/config.json\n".utf8)
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

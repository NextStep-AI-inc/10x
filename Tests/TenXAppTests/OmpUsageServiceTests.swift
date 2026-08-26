import Darwin
import Foundation
import Testing
@testable import TenXApp

@Test func usageServiceRunsTheExactJSONCommand() async throws {
    let runner = FakeUsageRunner(result: Data(#"{"generatedAt":1,"reports":[],"accountsWithoutUsage":[],"disabledCredentials":[],"capacity":{}}"#.utf8))

    let snapshot = try await OmpUsageService(runner: runner).loadUsage()

    #expect(snapshot.generatedAt == 1)
    #expect(await runner.calls == [["usage", "--json"]])
}

@Test func usageServiceErrorDoesNotExposeStderr() async {
    let service = OmpUsageService(runner: FailingUsageRunner())

    do {
        _ = try await service.loadUsage()
        Issue.record("Expected usage loading to fail")
    } catch {
        #expect(error is OmpUsageServiceError)
        #expect(!error.localizedDescription.contains("token=secret"))
        #expect(!error.localizedDescription.contains("/Users/example/.omp"))
    }
}

@Test func cancellingUsageServiceReapsTheCommand() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let pidFile = fixture.root.appending(path: "usage.pid")
    let executable = try fixture.executable(
        name: "blocked-usage",
        body: "printf '%s' $$ > '\(pidFile.path)'; printf 'token=secret\\n' >&2; trap '' TERM; while :; do sleep 1; done")
    let service = OmpUsageService(
        runner: OmpUsageProcessRunner(executableURL: executable))
    let operation = Task { try await service.loadUsage() }
    let pids = try await fixture.waitForPIDs(in: pidFile, count: 1)
    let pid = try #require(pids.first)

    operation.cancel()
    await #expect(throws: CancellationError.self) {
        _ = try await operation.value
    }

    #expect(kill(pid, 0) == -1)
    #expect(errno == ESRCH)
}

private actor FakeUsageRunner: OmpUsageRunning {
    private let result: Data
    private(set) var calls: [[String]] = []

    init(result: Data) {
        self.result = result
    }

    func run(arguments: [String]) async throws -> Data {
        calls.append(arguments)
        return result
    }
}

private struct FailingUsageRunner: OmpUsageRunning {
    func run(arguments: [String]) async throws -> Data {
        throw FakeUsageFailure("token=secret at /Users/example/.omp")
    }
}

private struct FakeUsageFailure: Error {
    let detail: String

    init(_ detail: String) {
        self.detail = detail
    }
}

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

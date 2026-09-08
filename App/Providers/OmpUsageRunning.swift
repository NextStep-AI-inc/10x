import Foundation

protocol OmpUsageRunning: Sendable {
    func run(arguments: [String]) async throws -> Data
}

struct OmpUsageProcessRunner: OmpUsageRunning {
    let executableURL: URL

    func run(arguments: [String]) async throws -> Data {
        try await OmpCommandRunner().run(
            executableURL: executableURL,
            arguments: arguments)
    }
}

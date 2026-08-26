import Foundation

protocol OmpConfigRunning: Sendable {
    func run(arguments: [String]) async throws -> Data
}

struct OmpConfigProcessRunner: OmpConfigRunning {
    let executableURL: URL

    func run(arguments: [String]) async throws -> Data {
        try await OmpCommandRunner().run(
            executableURL: executableURL,
            arguments: arguments)
    }
}

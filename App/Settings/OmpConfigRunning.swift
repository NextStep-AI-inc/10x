import Foundation

protocol OmpConfigRunning: Sendable {
    func run(arguments: [String]) async throws -> Data
}

struct OmpConfigProcessRunner: OmpConfigRunning {
    let executableURL: URL

    func run(arguments: [String]) async throws -> Data {
        let executableURL = executableURL
        return try await Task.detached {
            let output = Pipe()
            let error = Pipe()
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = error

            try process.run()
            async let outputData = output.fileHandleForReading.readToEnd() ?? Data()
            async let errorData = error.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            let data = try await outputData
            _ = try await errorData
            guard process.terminationStatus == 0 else {
                throw OmpConfigRunError.nonzeroExit(process.terminationStatus)
            }
            return data
        }.value
    }
}

private enum OmpConfigRunError: Error {
    case nonzeroExit(Int32)
}

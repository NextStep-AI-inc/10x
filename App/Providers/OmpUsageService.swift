import Foundation

protocol OmpUsageLoading: Sendable {
    func loadUsage() async throws -> OmpUsageSnapshot
}

actor OmpUsageService<Runner: OmpUsageRunning>: OmpUsageLoading {
    private let runner: Runner

    init(runner: Runner) {
        self.runner = runner
    }

    func loadUsage() async throws -> OmpUsageSnapshot {
        do {
            let data = try await runner.run(arguments: ["usage", "--json"])
            try Task.checkCancellation()
            let snapshot = try JSONDecoder().decode(OmpUsageSnapshot.self, from: data)
            try Task.checkCancellation()
            return snapshot
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OmpUsageServiceError.loadFailed
        }
    }
}

enum OmpUsageServiceError: LocalizedError, Sendable {
    case loadFailed

    var errorDescription: String? {
        "[Providers:OmpUsageService] Unable to load provider usage — {usage}"
    }
}

import Foundation
import OmpKit

actor OmpConfigService {
    private let runner: any OmpConfigRunning

    init(runner: any OmpConfigRunning) {
        self.runner = runner
    }

    func list() async throws -> [String: JSONValue] {
        let data = try await perform(arguments: ["config", "list", "--json"], action: "list")
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let object = value.objectValue else {
            throw OmpConfigServiceError.commandFailed(action: "list", key: nil)
        }
        return object
    }

    func set(key: String, value: JSONValue) async throws {
        _ = try await perform(
            arguments: ["config", "set", key, try Self.argument(for: value)],
            action: "set",
            key: key)
    }

    func reset(key: String) async throws {
        _ = try await perform(
            arguments: ["config", "reset", key],
            action: "reset",
            key: key)
    }

    func path() async throws -> String {
        let data = try await perform(arguments: ["config", "path"], action: "path")
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func perform(
        arguments: [String],
        action: String,
        key: String? = nil
    ) async throws -> Data {
        do {
            return try await runner.run(arguments: arguments)
        } catch {
            throw OmpConfigServiceError.commandFailed(action: action, key: key)
        }
    }

    private static func argument(for value: JSONValue) throws -> String {
        if let string = value.stringValue { return string }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

private enum OmpConfigServiceError: LocalizedError {
    case commandFailed(action: String, key: String?)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let action, let key):
            let context = key.map { "\(action), \($0)" } ?? action
            return "[Settings:OmpConfigService] Command failed — {\(context)}"
        }
    }
}

import Foundation
import OmpKit

protocol ComposerDefaultPersisting: Sendable {
    func setDefaultModel(provider: String, modelID: String) async throws
    func setDefaultThinkingLevel(_ level: String) async throws
}

struct OmpComposerDefaultStore: ComposerDefaultPersisting {
    private let config: OmpConfigService

    init(config: OmpConfigService) {
        self.config = config
    }

    func setDefaultModel(provider: String, modelID: String) async throws {
        let settings = try await config.list()
        var roles = settings["modelRoles"]?["value"]?.objectValue ?? [:]
        roles["default"] = .string(
            ComposerControlsPresentation.roleDefaultValue(provider: provider, modelID: modelID))
        try await config.set(key: "modelRoles", value: .object(roles))
    }

    func setDefaultThinkingLevel(_ level: String) async throws {
        try await config.set(key: "defaultThinkingLevel", value: .string(level))
    }
}

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
        var roles: [String: JSONValue]
        if let raw = settings["modelRoles"]?["value"] {
            // Fail closed: a non-object value must not coerce to [:] and wipe sibling roles.
            guard let object = raw.objectValue else {
                throw OmpComposerDefaultStoreError.malformedModelRoles
            }
            roles = object
        } else {
            roles = [:]
        }
        roles["default"] = .string(
            ComposerControlsPresentation.roleDefaultValue(provider: provider, modelID: modelID))
        try await config.set(key: "modelRoles", value: .object(roles))
    }

    func setDefaultThinkingLevel(_ level: String) async throws {
        try await config.set(key: "defaultThinkingLevel", value: .string(level))
    }
}

enum OmpComposerDefaultStoreError: LocalizedError, Sendable {
    case malformedModelRoles

    var errorDescription: String? {
        switch self {
        case .malformedModelRoles:
            "[Sessions:OmpComposerDefaultStore] modelRoles.value is not an object — {modelRoles}"
        }
    }
}

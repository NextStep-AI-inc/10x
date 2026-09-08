import Foundation

enum SessionMapModelSelection: Codable, Equatable, Sendable {
    case role(String)
    case model(id: String, effort: String?)
}

struct SessionMapResolvedModel: Codable, Equatable, Sendable {
    let provider: String
    let modelID: String
    let effort: String?
    let acceptsImages: Bool
}

enum SessionMapModelResolver {
    static func resolve(
        selection: SessionMapModelSelection,
        catalog: [ComposerModelInfo],
        roles: [String: String]
    ) -> SessionMapResolvedModel? {
        switch selection {
        case .model(let id, let effort):
            return resolve(id: id, effort: effort, catalog: catalog)
        case .role(let role):
            guard let configured = roles[role] else { return nil }
            if let exact = resolve(id: configured, effort: nil, catalog: catalog) {
                return exact
            }
            for model in catalog {
                let prefix = "\(model.id):"
                guard configured.hasPrefix(prefix) else { continue }
                let effort = String(configured.dropFirst(prefix.count))
                guard model.thinkingEfforts.contains(effort) else { continue }
                return resolved(model, effort: effort)
            }
            return nil
        }
    }

    private static func resolve(
        id: String,
        effort: String?,
        catalog: [ComposerModelInfo]
    ) -> SessionMapResolvedModel? {
        guard let model = catalog.first(where: { $0.id == id }) else { return nil }
        if let effort, !model.thinkingEfforts.contains(effort) { return nil }
        if effort == nil, model.requiresEffort { return nil }
        return resolved(model, effort: effort)
    }

    private static func resolved(
        _ model: ComposerModelInfo,
        effort: String?
    ) -> SessionMapResolvedModel {
        SessionMapResolvedModel(
            provider: model.provider,
            modelID: model.modelID,
            effort: effort,
            acceptsImages: model.acceptsImages)
    }
}

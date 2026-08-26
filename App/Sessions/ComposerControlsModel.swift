import Foundation
import Observation

protocol ComposerCatalogLoading: Sendable {
    func load() async throws -> ComposerCatalogSnapshot
}

extension OmpModelCatalogService: ComposerCatalogLoading {}

@MainActor
protocol ComposerSessionControlling: AnyObject {
    func setModel(provider: String, modelID: String) async
    func setThinkingLevel(_ level: String) async
    func setFastMode(_ enabled: Bool) async -> Bool
}

enum ComposerControlsMode {
    case newSession
    case activeSession
}

struct ComposerSpawnSelection: Equatable, Sendable {
    let provider: String?
    let modelID: String?
    let thinking: String?
    let fastModeEnabled: Bool
}

@MainActor
@Observable
final class ComposerControlsModel {
    private(set) var models: [ComposerModelInfo] = []
    private(set) var selectedModel: ComposerModelInfo?
    private(set) var thinkingLevel: String = "auto"
    private(set) var isFastModeEnabled: Bool = false
    private(set) var isFastModeVisible: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var isMutating: Bool = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let catalog: any ComposerCatalogLoading
    @ObservationIgnored private let defaults: any ComposerDefaultPersisting
    @ObservationIgnored private weak var activeSession: (any ComposerSessionControlling)?

    init(catalog: any ComposerCatalogLoading, defaults: any ComposerDefaultPersisting) {
        self.catalog = catalog
        self.defaults = defaults
    }

    var thinkingOptions: [String] {
        ComposerControlsPresentation.thinkingOptions(for: selectedModel)
    }

    var spawnSelection: ComposerSpawnSelection {
        ComposerSpawnSelection(
            provider: selectedModel?.provider,
            modelID: selectedModel?.id,
            thinking: thinkingLevel,
            fastModeEnabled: isFastModeEnabled)
    }

    func refresh(authenticatedProviderIDs: Set<String>) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = try await catalog.load()
            models = ComposerControlsPresentation.authenticatedModels(
                catalog: snapshot.models,
                authenticatedProviderIDs: authenticatedProviderIDs)
            if let selected = snapshot.selected,
               models.contains(where: { $0.id == selected.id && $0.provider == selected.provider })
            {
                selectedModel = selected
            } else {
                selectedModel = models.first
            }
            thinkingLevel = snapshot.thinkingLevel ?? "auto"
            applyFastModeVisibility(preservingEnabled: snapshot.fastModeEnabled)
            errorMessage = nil
        } catch {
            errorMessage = "Models couldn’t be loaded."
        }
    }

    func selectModel(_ model: ComposerModelInfo, mode: ComposerControlsMode) async {
        guard !isMutating else { return }
        switch mode {
        case .newSession:
            isMutating = true
            defer { isMutating = false }
            do {
                try await defaults.setDefaultModel(provider: model.provider, modelID: model.id)
                selectedModel = model
                applyFastModeVisibility(preservingEnabled: isFastModeEnabled)
                errorMessage = nil
            } catch {
                errorMessage = "Couldn’t update the default model."
            }
        case .activeSession:
            guard let activeSession else { return }
            isMutating = true
            defer { isMutating = false }
            await activeSession.setModel(provider: model.provider, modelID: model.id)
            selectedModel = model
            applyFastModeVisibility(preservingEnabled: isFastModeEnabled)
            errorMessage = nil
        }
    }

    func selectThinking(_ level: String, mode: ComposerControlsMode) async {
        guard !isMutating else { return }
        switch mode {
        case .newSession:
            isMutating = true
            defer { isMutating = false }
            do {
                try await defaults.setDefaultThinkingLevel(level)
                thinkingLevel = level
                errorMessage = nil
            } catch {
                errorMessage = "Couldn’t update the default thinking level."
            }
        case .activeSession:
            guard let activeSession else { return }
            isMutating = true
            defer { isMutating = false }
            await activeSession.setThinkingLevel(level)
            thinkingLevel = level
            errorMessage = nil
        }
    }

    func setFastMode(_ enabled: Bool, mode: ComposerControlsMode) async {
        guard isFastModeVisible else { return }
        switch mode {
        case .newSession:
            isFastModeEnabled = enabled
            errorMessage = nil
        case .activeSession:
            guard let activeSession else { return }
            isMutating = true
            defer { isMutating = false }
            let supported = await activeSession.setFastMode(enabled)
            if supported {
                isFastModeEnabled = enabled
                errorMessage = nil
            } else {
                isFastModeEnabled = false
                isFastModeVisible = false
                errorMessage = "Fast mode isn’t available for this model."
            }
        }
    }

    func attachActiveSession(_ controller: any ComposerSessionControlling) {
        activeSession = controller
    }

    func detachActiveSession() {
        activeSession = nil
    }

    private func applyFastModeVisibility(preservingEnabled enabled: Bool) {
        isFastModeVisible = ComposerControlsPresentation.supportsFastMode(model: selectedModel)
        if isFastModeVisible {
            isFastModeEnabled = enabled
        } else {
            isFastModeEnabled = false
        }
    }
}

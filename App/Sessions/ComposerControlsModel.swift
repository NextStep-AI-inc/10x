import Foundation
import Observation

protocol ComposerCatalogLoading: AnyObject, Sendable {
    var commandUpdates: AsyncStream<ComposerCommandCatalogState> { get }
    func load(projectURL: URL?) async throws -> ComposerCatalogSnapshot
    func shutdown() async
}

extension ComposerCatalogService: ComposerCatalogLoading {}

@MainActor
protocol ComposerSessionControlling: AnyObject {
    var liveComposerSelection: ComposerLiveSelection { get }
    func setModel(provider: String, modelID: String) async throws
    func setThinkingLevel(_ level: String) async throws
    /// Returns `false` only when Fast mode is unsupported for the current model.
    /// Transport / OMP command failures must throw — do not report them as unsupported.
    func setFastMode(_ enabled: Bool) async throws -> Bool
}

enum ComposerControlsMode {
    case newSession
    case activeSession
}

enum ComposerControlsMutationOutcome: Equatable, Sendable {
    case success
    case failure(String)
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
    private(set) var recentModels: [ComposerModelInfo] = []

    @ObservationIgnored let catalog: any ComposerCatalogLoading
    @ObservationIgnored private let defaults: any ComposerDefaultPersisting
    @ObservationIgnored private let recents: RecentModelStore
    @ObservationIgnored private weak var activeSession: (any ComposerSessionControlling)?
    @ObservationIgnored private var refreshGeneration = 0

    init(
        catalog: any ComposerCatalogLoading,
        defaults: any ComposerDefaultPersisting,
        recents: RecentModelStore = RecentModelStore()
    ) {
        self.catalog = catalog
        self.defaults = defaults
        self.recents = recents
    }

    var thinkingOptions: [String] {
        ComposerControlsPresentation.thinkingOptions(for: selectedModel)
    }

    var spawnSelection: ComposerSpawnSelection {
        ComposerSpawnSelection(
            provider: selectedModel?.provider,
            modelID: selectedModel?.modelID,
            // Spec: --thinking only when the selected model has thinking options.
            thinking: thinkingOptions.isEmpty ? nil : thinkingLevel,
            fastModeEnabled: isFastModeEnabled)
    }

    func refresh(authenticatedProviderIDs: Set<String>, projectURL: URL?) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        isLoading = true
        defer {
            if refreshGeneration == generation {
                isLoading = false
            }
        }
        do {
            let snapshot = try await catalog.load(projectURL: projectURL)
            guard refreshGeneration == generation else { return }
            models = ComposerControlsPresentation.authenticatedModels(
                catalog: snapshot.models,
                authenticatedProviderIDs: authenticatedProviderIDs)
            recentModels = recents.rankedModels(from: models)
            if let activeSession {
                applyLiveSelection(activeSession.liveComposerSelection)
            } else {
                if let selected = snapshot.selected,
                   models.contains(where: { $0.id == selected.id })
                {
                    selectedModel = selected
                } else {
                    selectedModel = models.first
                }
                thinkingLevel = snapshot.thinkingLevel ?? "auto"
                applyFastModeVisibility(preservingEnabled: snapshot.fastModeEnabled)
            }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard refreshGeneration == generation else { return }
            errorMessage = "Models couldn’t be loaded."
        }
    }

    /// Seeds / mirrors chips from live session `get_state` / `config_update` / model events.
    func applyLiveSelection(_ selection: ComposerLiveSelection) {
        guard !isMutating else { return }
        if let provider = selection.provider, let modelID = selection.modelID,
           let match = models.first(where: { $0.provider == provider && $0.modelID == modelID })
        {
            selectedModel = match
        }
        if let thinking = selection.thinkingLevel {
            thinkingLevel = thinking
        }
        applyFastModeVisibility(preservingEnabled: selection.fastModeEnabled)
    }

    @discardableResult
    func selectModel(
        _ model: ComposerModelInfo,
        mode: ComposerControlsMode
    ) async -> ComposerControlsMutationOutcome {
        guard !isMutating else { return .failure(Self.mutationUnavailableMessage) }
        switch mode {
        case .newSession:
            isMutating = true
            defer { isMutating = false }
            do {
                try await defaults.setDefaultModel(provider: model.provider, modelID: model.modelID)
                selectedModel = model
                recordRecent(model)
                thinkingLevel = ComposerControlsPresentation.resolvedThinkingLevel(
                    current: thinkingLevel,
                    for: model)
                applyFastModeVisibility(preservingEnabled: isFastModeEnabled)
                errorMessage = nil
                return .success
            } catch {
                let message = "Couldn’t update the default model."
                errorMessage = message
                return .failure(message)
            }
        case .activeSession:
            guard let activeSession else { return .failure(Self.mutationUnavailableMessage) }
            isMutating = true
            defer { isMutating = false }
            let prior = selectedModel
            let priorThinking = thinkingLevel
            let priorFastEnabled = isFastModeEnabled
            selectedModel = model
            thinkingLevel = ComposerControlsPresentation.resolvedThinkingLevel(
                current: thinkingLevel,
                for: model)
            applyFastModeVisibility(preservingEnabled: isFastModeEnabled)
            // Two RPCs, two failure domains: each rolls back only what it
            // actually invalidated.
            do {
                try await activeSession.setModel(provider: model.provider, modelID: model.modelID)
            } catch {
                // Nothing reached the runtime, so the whole optimistic switch goes back.
                selectedModel = prior
                thinkingLevel = priorThinking
                applyFastModeVisibility(preservingEnabled: priorFastEnabled)
                let message = Self.sanitizedMessage(
                    from: error,
                    fallback: "Couldn’t update the model.")
                errorMessage = message
                return .failure(message)
            }
            recordRecent(model)

            // OMP's model echo carries provider and id only, so a reconciled
            // level would never reach the runtime. Send it, and only when it
            // actually moved — a same-value RPC per switch is waste.
            if thinkingLevel != priorThinking {
                do {
                    try await activeSession.setThinkingLevel(thinkingLevel)
                } catch {
                    // The switch already landed: the runtime IS on the new model,
                    // so reverting the chip would misname what the user is talking
                    // to. Only the level is untrue — revert that alone, and leave
                    // Fast mode computed from the new model.
                    thinkingLevel = priorThinking
                    let message = Self.sanitizedMessage(
                        from: error,
                        fallback: "Couldn’t update the thinking level.")
                    errorMessage = message
                    return .failure(message)
                }
            }
            errorMessage = nil
            return .success
        }
    }

    @discardableResult
    func selectThinking(
        _ level: String,
        mode: ComposerControlsMode
    ) async -> ComposerControlsMutationOutcome {
        guard !isMutating else { return .failure(Self.mutationUnavailableMessage) }
        switch mode {
        case .newSession:
            isMutating = true
            defer { isMutating = false }
            do {
                try await defaults.setDefaultThinkingLevel(level)
                thinkingLevel = level
                errorMessage = nil
                return .success
            } catch {
                let message = "Couldn’t update the default thinking level."
                errorMessage = message
                return .failure(message)
            }
        case .activeSession:
            guard let activeSession else { return .failure(Self.mutationUnavailableMessage) }
            isMutating = true
            defer { isMutating = false }
            let prior = thinkingLevel
            thinkingLevel = level
            do {
                try await activeSession.setThinkingLevel(level)
                errorMessage = nil
                return .success
            } catch {
                thinkingLevel = prior
                let message = Self.sanitizedMessage(
                    from: error,
                    fallback: "Couldn’t update the thinking level.")
                errorMessage = message
                return .failure(message)
            }
        }
    }

    @discardableResult
    func setFastMode(
        _ enabled: Bool,
        mode: ComposerControlsMode
    ) async -> ComposerControlsMutationOutcome {
        guard !isMutating else { return .failure(Self.mutationUnavailableMessage) }
        guard isFastModeVisible else { return .failure(Self.fastModeUnavailableMessage) }
        switch mode {
        case .newSession:
            isFastModeEnabled = enabled
            errorMessage = nil
            return .success
        case .activeSession:
            guard let activeSession else { return .failure(Self.mutationUnavailableMessage) }
            isMutating = true
            defer { isMutating = false }
            let priorEnabled = isFastModeEnabled
            isFastModeEnabled = enabled
            do {
                let supported = try await activeSession.setFastMode(enabled)
                if supported {
                    errorMessage = nil
                    return .success
                } else {
                    // Soft unsupported only — hide chip and clear intent.
                    isFastModeEnabled = false
                    isFastModeVisible = false
                    errorMessage = Self.fastModeUnavailableMessage
                    return .failure(Self.fastModeUnavailableMessage)
                }
            } catch {
                // Transport / OMP failure — keep chip; restore prior intent.
                isFastModeEnabled = priorEnabled
                let message = Self.sanitizedMessage(
                    from: error,
                    fallback: "Couldn’t update Fast mode.")
                errorMessage = message
                return .failure(message)
            }
        }
    }

    func attachActiveSession(_ controller: any ComposerSessionControlling) {
        if let previous = activeSession as? SessionController {
            previous.bindComposerControls(nil)
        }
        activeSession = controller
        if let session = controller as? SessionController {
            session.bindComposerControls(self)
        } else {
            applyLiveSelection(controller.liveComposerSelection)
        }
    }

    func detachActiveSession() {
        if let session = activeSession as? SessionController {
            session.bindComposerControls(nil)
        }
        activeSession = nil
    }

    func shutdown() async {
        detachActiveSession()
        await catalog.shutdown()
    }

    private func recordRecent(_ model: ComposerModelInfo) {
        recents.recordSelection(model)
        recentModels = recents.rankedModels(from: models)
    }

    private func applyFastModeVisibility(preservingEnabled enabled: Bool) {
        isFastModeVisible = ComposerControlsPresentation.supportsFastMode(model: selectedModel)
        if isFastModeVisible {
            isFastModeEnabled = enabled
        } else {
            isFastModeEnabled = false
        }
    }

    private static let mutationUnavailableMessage = "Couldn’t update this setting."
    private static let fastModeUnavailableMessage = "Fast mode isn’t available for this model."

    /// One-line user copy; strips absolute paths so raw OMP text stays out of the footer.
    private static func sanitizedMessage(from error: Error, fallback: String) -> String {
        let raw = error.localizedDescription
            .replacingOccurrences(of: #"/[^\s]+"#, with: "…", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.count <= 120 else { return fallback }
        return raw
    }
}

import Foundation
import Observation
import OmpKit

@MainActor
@Observable
final class SettingsViewModel {
    var query = ""
    private(set) var catalog = SettingsCatalog.empty
    private(set) var configPath = ""
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var keyErrors: [String: String] = [:]
    private(set) var sessionMapModels: [ComposerModelInfo] = []
    private(set) var isSessionMapCatalogLoading = false
    private(set) var sessionMapCatalogError: String?
    let sessionMapPreferences: SessionMapPreferenceStore

    var sections: [SettingsSection] { catalog.sections(query: query) }
    var settingCount: Int { catalog.definitions.count }

    @ObservationIgnored private let service: OmpConfigService
    @ObservationIgnored private let sessionMapCatalog: (any ComposerCatalogLoading)?
    @ObservationIgnored private var sessionMapCatalogGeneration = 0
    @ObservationIgnored private var sessionMapCatalogProjectURL: URL?
    @ObservationIgnored private var sessionMapCatalogLoadingProjectURL: URL?
    @ObservationIgnored private var sessionMapCatalogTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Bool, Never>?

    init(
        service: OmpConfigService,
        sessionMapCatalog: (any ComposerCatalogLoading)? = nil,
        sessionMapPreferences: SessionMapPreferenceStore = SessionMapPreferenceStore()
    ) {
        self.service = service
        self.sessionMapCatalog = sessionMapCatalog
        self.sessionMapPreferences = sessionMapPreferences
    }

    var sessionMapRoles: [String: String] {
        guard let values = catalog.definition(key: "modelRoles")?.value?.objectValue else {
            return [:]
        }
        return values.compactMapValues(\.stringValue)
    }

    @discardableResult
    func loadSessionMapCatalog(projectURL: URL?) async -> Bool {
        let projectURL = projectURL?.standardizedFileURL
        if sessionMapCatalogProjectURL == projectURL, !sessionMapModels.isEmpty { return true }
        if sessionMapCatalogLoadingProjectURL == projectURL, let task = sessionMapCatalogTask {
            await task.value
            return sessionMapCatalogProjectURL == projectURL
        }
        guard let sessionMapCatalog else { return false }
        sessionMapCatalogGeneration += 1
        let generation = sessionMapCatalogGeneration
        isSessionMapCatalogLoading = true
        sessionMapCatalogLoadingProjectURL = projectURL
        sessionMapCatalogError = nil
        let task = Task { @MainActor [weak self] in
            do {
                let models = try await sessionMapCatalog.load(projectURL: projectURL).models
                guard let self, self.sessionMapCatalogGeneration == generation else { return }
                self.sessionMapModels = models
                self.sessionMapCatalogProjectURL = projectURL
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.sessionMapCatalogGeneration == generation else { return }
                self.sessionMapCatalogError = "Models couldn’t be loaded."
            }
        }
        sessionMapCatalogTask = task
        await task.value
        if sessionMapCatalogGeneration == generation {
            sessionMapCatalogTask = nil
            sessionMapCatalogLoadingProjectURL = nil
            isSessionMapCatalogLoading = false
        }
        return sessionMapCatalogProjectURL == projectURL
    }

    func shutdownSessionMapCatalog() async {
        sessionMapCatalogGeneration += 1
        sessionMapModels = []
        sessionMapCatalogProjectURL = nil
        sessionMapCatalogLoadingProjectURL = nil
        sessionMapCatalogTask?.cancel()
        sessionMapCatalogTask = nil
        sessionMapCatalogError = nil
        isSessionMapCatalogLoading = false
        await sessionMapCatalog?.shutdown()
    }

    @discardableResult
    func load() async -> Bool {
        if let loadTask { return await loadTask.value }
        let task = Task { @MainActor [weak self] in
            await self?.performLoad() ?? false
        }
        loadTask = task
        let result = await task.value
        loadTask = nil
        return result
    }

    private func performLoad() async -> Bool {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            async let values = service.list()
            async let path = service.path()
            catalog = SettingsCatalog.build(from: .object(try await values))
            configPath = try await path
            return true
        } catch {
            loadError = "[Settings:SettingsViewModel] Unable to load settings — \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func save(_ definition: SettingDefinition, value: JSONValue) async -> Bool {
        keyErrors[definition.key] = nil
        do {
            try await service.set(key: definition.key, value: value)
            catalog.update(key: definition.key, value: value)
            return true
        } catch OmpConfigServiceError.invalidShellPath {
            keyErrors[definition.key] = "Choose an executable shell file, such as /bin/zsh."
            return false
        } catch {
            keyErrors[definition.key] = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func restoreDefault(_ definition: SettingDefinition) async -> Bool {
        keyErrors[definition.key] = nil
        do {
            let value = try await service.reset(key: definition.key)
            catalog.update(key: definition.key, value: value)
            return true
        } catch {
            keyErrors[definition.key] = error.localizedDescription
            return false
        }
    }

    func error(for key: String) -> String? {
        keyErrors[key]
    }

    @discardableResult
    func prepareForFocus(_ target: SettingsFocusTarget?) -> Bool {
        guard target == .preferredIDE || target == .sessionMap else { return false }
        query = ""
        return true
    }
}

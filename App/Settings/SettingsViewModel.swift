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

    var sections: [SettingsSection] { catalog.sections(query: query) }
    var settingCount: Int { catalog.definitions.count }

    @ObservationIgnored private let service: OmpConfigService
    @ObservationIgnored private let catalogService: OmpModelCatalogService?
    // ponytail: per-key write chain serializes saves/restores; a failed write returns
    // false but does not block subsequent writes on the same key.
    @ObservationIgnored private var writeChains: [String: Task<Bool, Never>] = [:]
    private(set) var catalogModels: [ComposerModelInfo] = []

    init(service: OmpConfigService, catalog: OmpModelCatalogService? = nil) {
        self.service = service
        self.catalogService = catalog
    }

    func loadCatalogIfNeeded() async {
        guard catalogModels.isEmpty, let catalogService else { return }
        if let snapshot = try? await catalogService.load() {
            catalogModels = snapshot.models
        }
    }

    @discardableResult
    func load() async -> Bool {
        guard !isLoading else { return loadError == nil && !configPath.isEmpty }
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
        let key = definition.key
        let prior = writeChains[key]
        let task = Task<Bool, Never> {
            _ = await prior?.value
            return await self.performSave(definition, value: value)
        }
        writeChains[key] = task
        return await task.value
    }

    @discardableResult
    func restoreDefault(_ definition: SettingDefinition) async -> Bool {
        let key = definition.key
        let prior = writeChains[key]
        let task = Task<Bool, Never> {
            _ = await prior?.value
            return await self.performRestoreDefault(definition)
        }
        writeChains[key] = task
        return await task.value
    }

    func error(for key: String) -> String? {
        keyErrors[key]
    }

    @discardableResult
    func prepareForFocus(_ target: SettingsFocusTarget?) -> Bool {
        guard target == .preferredIDE else { return false }
        query = ""
        return true
    }

    private func performSave(_ definition: SettingDefinition, value: JSONValue) async -> Bool {
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

    private func performRestoreDefault(_ definition: SettingDefinition) async -> Bool {
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
}

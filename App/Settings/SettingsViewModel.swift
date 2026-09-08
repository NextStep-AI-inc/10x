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

    func loadSessionMapCatalog(projectURL: URL?) async {
        guard sessionMapModels.isEmpty,
              !isSessionMapCatalogLoading,
              let sessionMapCatalog
        else { return }
        isSessionMapCatalogLoading = true
        sessionMapCatalogError = nil
        defer { isSessionMapCatalogLoading = false }
        do {
            sessionMapModels = try await sessionMapCatalog.load(projectURL: projectURL).models
        } catch is CancellationError {
            return
        } catch {
            sessionMapCatalogError = "Models couldn’t be loaded."
        }
    }

    func shutdownSessionMapCatalog() async {
        await sessionMapCatalog?.shutdown()
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

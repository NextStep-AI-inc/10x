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

    init(service: OmpConfigService) {
        self.service = service
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        do {
            async let values = service.list()
            async let path = service.path()
            catalog = SettingsCatalog.build(from: .object(try await values))
            configPath = try await path
        } catch {
            loadError = "[Settings:SettingsViewModel] Unable to load settings — \(error.localizedDescription)"
        }
        isLoading = false
    }

    @discardableResult
    func save(_ definition: SettingDefinition, value: JSONValue) async -> Bool {
        keyErrors[definition.key] = nil
        do {
            try await service.set(key: definition.key, value: value)
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
}

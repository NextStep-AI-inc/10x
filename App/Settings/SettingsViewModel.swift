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

    var sections: [SettingsSection] { catalog.sections(query: query) }
    var settingCount: Int { catalog.definitions.count }

    @ObservationIgnored private let service: OmpConfigService
    @ObservationIgnored private let catalogService: ComposerCatalogService?
    // ponytail: per-key write chain serializes saves/restores; a failed write returns
    // false but does not block subsequent writes on the same key.
    @ObservationIgnored private var writeChains: [String: Task<Bool, Never>] = [:]
    @ObservationIgnored private var writeTokens: [String: UUID] = [:]
    @ObservationIgnored private var pendingWrites: [String: Int] = [:]
    @ObservationIgnored private var ownEchoes: [String: [JSONValue]] = [:]
    private(set) var catalogModels: [ComposerModelInfo] = []

    init(service: OmpConfigService, catalog: ComposerCatalogService? = nil) {
        self.service = service
        self.catalogService = catalog
    }

    func loadCatalogIfNeeded() async {
        guard catalogModels.isEmpty, let catalogService else { return }
        if let snapshot = try? await catalogService.load(projectURL: nil) {
            catalogModels = snapshot.models
        }
    }

    @discardableResult
    func load() async -> Bool {
        guard !isLoading else { return loadError == nil && !configPath.isEmpty }
        isLoading = true
        loadError = nil
        ownEchoes = [:]
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
        pendingWrites[key, default: 0] += 1
        let token = UUID()
        writeTokens[key] = token
        let prior = writeChains[key]
        let task = Task<Bool, Never> {
            _ = await prior?.value
            return await self.performSave(definition, value: value)
        }
        writeChains[key] = task
        let result = await task.value
        if writeTokens[key] == token {
            writeChains[key] = nil
            writeTokens[key] = nil
        }
        return result
    }

    @discardableResult
    func restoreDefault(_ definition: SettingDefinition) async -> Bool {
        let key = definition.key
        pendingWrites[key, default: 0] += 1
        let token = UUID()
        writeTokens[key] = token
        let prior = writeChains[key]
        let task = Task<Bool, Never> {
            _ = await prior?.value
            return await self.performRestoreDefault(definition)
        }
        writeChains[key] = task
        let result = await task.value
        if writeTokens[key] == token {
            writeChains[key] = nil
            writeTokens[key] = nil
        }
        return result
    }

    func error(for key: String) -> String? {
        keyErrors[key]
    }

    func hasPendingWrite(for key: String) -> Bool {
        (pendingWrites[key] ?? 0) > 0
    }

    /// Consumes one queued echo of our own save. Editors call this from
    /// onChange(of: definition.value): SwiftUI delivers the value change on a
    /// later render pass than the synchronous performSave block, so
    /// hasPendingWrite is already false when our own echo arrives — the echo
    /// queue is what actually distinguishes our writes from external changes.
    /// Saves queue echoes; restores clear the queue so editors resync to the default.
    func isOwnEcho(for key: String, value: JSONValue?) -> Bool {
        guard let value, var queue = ownEchoes[key],
              let index = queue.firstIndex(of: value) else { return false }
        queue.remove(at: index)
        ownEchoes[key] = queue.isEmpty ? nil : queue
        return true
    }

    @discardableResult
    func prepareForFocus(_ target: SettingsFocusTarget?) -> Bool {
        guard target == .preferredIDE else { return false }
        query = ""
        return true
    }

    private func performSave(_ definition: SettingDefinition, value: JSONValue) async -> Bool {
        let key = definition.key
        keyErrors[key] = nil
        do {
            try await service.set(key: key, value: value)
            ownEchoes[key, default: []].append(value)
            catalog.update(key: key, value: value)
            pendingWrites[key, default: 0] -= 1
            return true
        } catch OmpConfigServiceError.invalidShellPath {
            pendingWrites[key, default: 0] -= 1
            keyErrors[key] = "Choose an executable shell file, such as /bin/zsh."
            return false
        } catch {
            pendingWrites[key, default: 0] -= 1
            keyErrors[key] = error.localizedDescription
            return false
        }
    }

    private func performRestoreDefault(_ definition: SettingDefinition) async -> Bool {
        let key = definition.key
        keyErrors[key] = nil
        do {
            let value = try await service.reset(key: key)
            ownEchoes[key] = nil
            catalog.update(key: key, value: value)
            pendingWrites[key, default: 0] -= 1
            return true
        } catch {
            pendingWrites[key, default: 0] -= 1
            keyErrors[key] = error.localizedDescription
            return false
        }
    }
}

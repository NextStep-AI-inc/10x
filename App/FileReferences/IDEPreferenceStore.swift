import Foundation
import Observation

@MainActor
@Observable
final class IDEPreferenceStore {
    private(set) var state: IDEPreferenceState = .none
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let registry: IDERegistry
    @ObservationIgnored private let key = "tenx.preferredIDE.v1"

    init(defaults: UserDefaults = .standard, registry: IDERegistry) {
        self.defaults = defaults
        self.registry = registry
        reload()
    }

    func select(_ application: IDEApplication) throws {
        let selection = try registry.selection(for: application)
        defaults.set(try JSONEncoder().encode(selection), forKey: key)
        state = .available(application)
    }

    func clear() {
        defaults.removeObject(forKey: key)
        state = .none
    }

    func reload() {
        guard let data = defaults.data(forKey: key),
              let selection = try? JSONDecoder().decode(IDESelection.self, from: data)
        else {
            state = .none
            return
        }
        state = registry.resolve(selection).map(IDEPreferenceState.available)
            ?? .unavailable(displayName: selection.displayName)
    }
}

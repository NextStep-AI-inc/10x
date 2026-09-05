import Foundation
import Observation

@MainActor
@Observable
final class ToolDetailPreferenceStore {
    nonisolated static let defaultsKey = "tenx.toolDetailMode.v1"

    private(set) var mode: ToolDetailMode
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // An absent, stale, or wrong-typed value degrades to today's behavior
        // rather than to a mode the reader never chose.
        mode = defaults.string(forKey: Self.defaultsKey)
            .flatMap(ToolDetailMode.init(rawValue:)) ?? .auto
    }

    func select(_ mode: ToolDetailMode) {
        self.mode = mode
        defaults.set(mode.rawValue, forKey: Self.defaultsKey)
    }
}

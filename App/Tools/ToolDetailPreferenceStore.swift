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
        // Absent, stale, or remapped values land on Standard: Auto became
        // Standard, Compact became Slim, and an unknown raw value is not a choice.
        mode = ToolDetailMode.resolving(defaults.string(forKey: Self.defaultsKey))
    }

    func select(_ mode: ToolDetailMode) {
        self.mode = mode
        defaults.set(mode.rawValue, forKey: Self.defaultsKey)
    }
}

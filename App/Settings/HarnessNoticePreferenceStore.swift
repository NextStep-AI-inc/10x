import Foundation
import Observation

@MainActor
@Observable
final class HarnessNoticePreferenceStore {
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    /// Minimum hidden-message size (characters) that earns a notice. 0 = everything.
    var threshold: Int {
        didSet { defaults.set(threshold, forKey: Self.thresholdKey) }
    }

    /// Model id for summaries; nil = OMP's configured smol role.
    var modelOverride: String? {
        didSet { defaults.set(modelOverride, forKey: Self.modelOverrideKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let enabledKey = "tenx.harnessNotices.enabled.v1"
    private static let thresholdKey = "tenx.harnessNotices.threshold.v1"
    private static let modelOverrideKey = "tenx.harnessNotices.modelOverride.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        threshold = defaults.object(forKey: Self.thresholdKey) as? Int ?? 0
        modelOverride = defaults.string(forKey: Self.modelOverrideKey)
    }
}

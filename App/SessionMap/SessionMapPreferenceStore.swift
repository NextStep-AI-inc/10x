import Foundation
import Observation

@MainActor
@Observable
final class SessionMapPreferenceStore {
    var writerSelection: SessionMapModelSelection {
        didSet { persist(writerSelection, key: Self.writerKey) }
    }
    var checkerSelection: SessionMapModelSelection? {
        didSet { persist(checkerSelection, key: Self.checkerKey) }
    }
    var isUnattendedGenerationEnabled: Bool {
        didSet { defaults.set(isUnattendedGenerationEnabled, forKey: Self.unattendedKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        writerSelection = Self.selection(defaults.data(forKey: Self.writerKey)) ?? .role("smol")
        checkerSelection = Self.selection(defaults.data(forKey: Self.checkerKey))
        isUnattendedGenerationEnabled = defaults.object(forKey: Self.unattendedKey) as? Bool ?? true
    }

    private static let writerKey = "session-map.writer-selection"
    private static let checkerKey = "session-map.checker-selection"
    private static let unattendedKey = "session-map.unattended-generation"

    private func persist(_ selection: SessionMapModelSelection?, key: String) {
        guard let selection else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(try? JSONEncoder().encode(selection), forKey: key)
    }

    private static func selection(_ data: Data?) -> SessionMapModelSelection? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(SessionMapModelSelection.self, from: data)
    }
}

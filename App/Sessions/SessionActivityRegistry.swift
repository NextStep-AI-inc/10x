import Foundation
import Observation

@MainActor
@Observable
final class SessionActivityRegistry {
    private struct State: Equatable {
        let providerID: String?
        let isGenerating: Bool
    }

    private(set) var activeCounts: [String: Int] = [:]
    @ObservationIgnored private var states: [UUID: State] = [:]

    func update(sessionID: UUID, providerID: String?, isGenerating: Bool) {
        states[sessionID] = State(providerID: providerID, isGenerating: isGenerating)
        activeCounts = Self.counts(states.values)
    }

    func remove(sessionID: UUID) {
        states.removeValue(forKey: sessionID)
        activeCounts = Self.counts(states.values)
    }

    private static func counts(_ states: Dictionary<UUID, State>.Values) -> [String: Int] {
        states.reduce(into: [:]) { counts, state in
            guard state.isGenerating,
                  let providerID = state.providerID,
                  !providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            counts[providerID, default: 0] += 1
        }
    }
}

import Observation
import SwiftUI

@Observable
final class ToolDisclosureState: @unchecked Sendable {
    private(set) var mode: ToolDetailMode
    private var choices: [String: Bool] = [:]

    init(mode: ToolDetailMode = .auto) {
        self.mode = mode
    }

    /// A new mode discards the per-card choices taken under the old one, so
    /// switching to Expanded cannot leave hand-closed cards shut.
    func setMode(_ mode: ToolDetailMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        choices.removeAll()
    }

    func isExpanded(for presentation: ToolPresentation) -> Bool {
        isExpanded(id: presentation.id, traits: presentation.disclosureTraits)
    }

    func isExpanded(for presentation: SubagentPresentation) -> Bool {
        isExpanded(id: presentation.id, traits: presentation.disclosureTraits)
    }

    func isExpanded(id: String, traits: ToolDisclosureTraits) -> Bool {
        choices[id] ?? mode.isExpandedByDefault(traits)
    }

    func setExpanded(_ isExpanded: Bool, for presentation: ToolPresentation) {
        setExpanded(isExpanded, id: presentation.id)
    }

    func setExpanded(_ isExpanded: Bool, id: String) {
        choices[id] = isExpanded
    }
}

private struct ToolDisclosureStateKey: EnvironmentKey {
    static let defaultValue: ToolDisclosureState? = nil
}

extension EnvironmentValues {
    var toolDisclosureState: ToolDisclosureState? {
        get { self[ToolDisclosureStateKey.self] }
        set { self[ToolDisclosureStateKey.self] = newValue }
    }
}

import Observation
import SwiftUI

@Observable
final class ToolDisclosureState: @unchecked Sendable {
    private(set) var mode: ToolDetailMode
    // Per-row boxes: toggling one card must not invalidate the whole transcript.
    @ObservationIgnored private var choices: [String: DisclosureChoice] = [:]
    @ObservationIgnored private var groupChoices: [String: DisclosureChoice] = [:]

    init(mode: ToolDetailMode = .auto) {
        self.mode = mode
    }

    /// A new mode discards the per-card choices taken under the old one, so
    /// switching to Expanded cannot leave hand-closed cards shut. Group
    /// expansion is a separate axis and is left alone.
    func setMode(_ mode: ToolDetailMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        for choice in choices.values { choice.value = nil }
    }

    func isExpanded(for presentation: ToolPresentation) -> Bool {
        isExpanded(id: presentation.id, traits: presentation.disclosureTraits)
    }

    func isExpanded(for presentation: SubagentPresentation) -> Bool {
        isExpanded(id: presentation.id, traits: presentation.disclosureTraits)
    }

    func isExpanded(id: String, traits: ToolDisclosureTraits) -> Bool {
        choice(for: id, in: &choices).value ?? mode.isExpandedByDefault(traits)
    }

    func setExpanded(_ isExpanded: Bool, for presentation: ToolPresentation) {
        setExpanded(isExpanded, id: presentation.id)
    }

    func setExpanded(_ isExpanded: Bool, id: String) {
        choice(for: id, in: &choices).value = isExpanded
    }

    func isGroupExpanded(id: String) -> Bool {
        choice(for: id, in: &groupChoices).value ?? true
    }

    func setGroupExpanded(_ isExpanded: Bool, id: String) {
        choice(for: id, in: &groupChoices).value = isExpanded
    }

    private func choice(
        for id: String,
        in choices: inout [String: DisclosureChoice]
    ) -> DisclosureChoice {
        if let choice = choices[id] { return choice }
        let choice = DisclosureChoice()
        choices[id] = choice
        return choice
    }
}

@Observable
private final class DisclosureChoice: @unchecked Sendable {
    var value: Bool?
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

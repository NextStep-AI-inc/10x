import Observation
import SwiftUI

@Observable
final class ToolDisclosureState: @unchecked Sendable {
    @ObservationIgnored private var choices: [String: DisclosureChoice] = [:]
    @ObservationIgnored private var groupChoices: [String: DisclosureChoice] = [:]

    func isExpanded(for presentation: ToolPresentation) -> Bool {
        isExpanded(
            id: presentation.id,
            defaultValue: Self.defaultExpanded(for: presentation))
    }

    func isExpanded(id: String, defaultValue: Bool) -> Bool {
        choice(for: id, in: &choices).value ?? defaultValue
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

    func collapseAll(ids: [String]) {
        for id in ids { setExpanded(false, id: id) }
    }

    func expand(ids: [String]) {
        for id in ids { setExpanded(true, id: id) }
    }

    nonisolated static func defaultExpanded(for presentation: ToolPresentation) -> Bool {
        presentation.phase != .complete
            || ToolCardRegistry.kind(for: presentation.name).startsExpandedWhenComplete
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

import Observation
import SwiftUI

@Observable
final class ToolDisclosureState: @unchecked Sendable {
    private var choices: [String: Bool] = [:]

    func isExpanded(for presentation: ToolPresentation) -> Bool {
        isExpanded(
            id: presentation.id,
            defaultValue: Self.defaultExpanded(for: presentation))
    }

    func isExpanded(id: String, defaultValue: Bool) -> Bool {
        choices[id] ?? defaultValue
    }

    func setExpanded(_ isExpanded: Bool, for presentation: ToolPresentation) {
        setExpanded(isExpanded, id: presentation.id)
    }

    func setExpanded(_ isExpanded: Bool, id: String) {
        choices[id] = isExpanded
    }

    func collapseAll(ids: [String]) {
        for id in ids { choices[id] = false }
    }

    func expand(ids: [String]) {
        for id in ids { choices[id] = true }
    }

    nonisolated static func defaultExpanded(for presentation: ToolPresentation) -> Bool {
        presentation.phase != .complete || ToolCardRegistry.kind(for: presentation.name) == .edit
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

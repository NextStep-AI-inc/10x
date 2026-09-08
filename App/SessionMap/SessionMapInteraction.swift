import Foundation

struct SessionMapFocus: Equatable, Sendable {
    var selectedNodeID: String?
    var hoveredNodeID: String?
    var focusedNodeID: String?
    var flowStepIndex: Int?
}

enum SessionMapAction: Equatable, Sendable {
    case jump(ref: String)
    case openFile(path: String)
    case usePrompt(String)
}

struct SessionMapActivity: Equatable, Sendable {
    var activeNodeIDs: Set<String>
    var unmappedDescriptions: [String]

    static let empty = SessionMapActivity(activeNodeIDs: [], unmappedDescriptions: [])
}

struct SessionMapEdgeKey: Equatable, Hashable, Sendable {
    let from: String
    let to: String
    let kind: SessionMapEdgeKind

    init(_ edge: SessionMapEdge) {
        from = edge.from
        to = edge.to
        kind = edge.kind
    }
}

struct SessionMapChanges: Equatable, Sendable {
    var addedNodeIDs: Set<String>
    var changedNodeIDs: Set<String>
    var removedNodeIDs: Set<String>
    var addedEdgeKeys: Set<SessionMapEdgeKey>
    var changedEdgeKeys: Set<SessionMapEdgeKey>
    var removedEdgeKeys: Set<SessionMapEdgeKey>

    static let empty = SessionMapChanges(
        addedNodeIDs: [],
        changedNodeIDs: [],
        removedNodeIDs: [],
        addedEdgeKeys: [],
        changedEdgeKeys: [],
        removedEdgeKeys: [])
}

enum SessionMapInteraction {
    static func highlightedNodeIDs(
        graph: SessionMapGraph,
        focus: SessionMapFocus
    ) -> Set<String> {
        guard let anchor = focus.hoveredNodeID
            ?? focus.focusedNodeID
            ?? focus.selectedNodeID,
              graph.nodes.contains(where: { $0.id == anchor })
        else { return [] }

        var highlighted: Set<String> = [anchor]
        for edge in graph.edges where edge.from == anchor || edge.to == anchor {
            highlighted.insert(edge.from)
            highlighted.insert(edge.to)
        }
        return highlighted
    }

    static func reconciledFocus(
        _ focus: SessionMapFocus,
        replacing previous: SessionMapDocument,
        with replacement: SessionMapDocument
    ) -> SessionMapFocus {
        let replacementNodeIDs = Set(replacement.graph.nodes.map(\.id))
        var reconciled = focus
        reconciled.selectedNodeID = focus.selectedNodeID.flatMap {
            replacementNodeIDs.contains($0) ? $0 : nil
        }
        reconciled.hoveredNodeID = focus.hoveredNodeID.flatMap {
            replacementNodeIDs.contains($0) ? $0 : nil
        }
        reconciled.focusedNodeID = focus.focusedNodeID.flatMap {
            replacementNodeIDs.contains($0) ? $0 : nil
        }

        guard let oldIndex = focus.flowStepIndex,
              let oldSteps = previous.flow?.steps,
              oldSteps.indices.contains(oldIndex),
              let newSteps = replacement.flow?.steps,
              let newIndex = newSteps.firstIndex(where: { $0.node == oldSteps[oldIndex].node })
        else {
            reconciled.flowStepIndex = nil
            return reconciled
        }
        reconciled.flowStepIndex = newIndex
        return reconciled
    }

    static func accessibilityLabel(
        for node: SessionMapNode,
        graph: SessionMapGraph,
        isActive: Bool = false
    ) -> String {
        let status = node.status.displayName
        let group = node.group.map { ", \($0) group" } ?? ""
        let activity = isActive ? " Live activity." : ""
        let relationships = relationshipDescriptions(for: node, graph: graph)
        guard !relationships.isEmpty else {
            return "\(node.label), \(status)\(group).\(activity) No connections."
        }
        return "\(node.label), \(status)\(group).\(activity) \(relationships.joined(separator: " "))"
    }

    static func relationshipDescriptions(
        for node: SessionMapNode,
        graph: SessionMapGraph
    ) -> [String] {
        let labels = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.label) })
        return graph.edges.compactMap { edge in
            if edge.from == node.id, let label = labels[edge.to] {
                return "Connects to \(label)\(relationshipLabel(edge.label))."
            }
            if edge.to == node.id, let label = labels[edge.from] {
                return "Receives from \(label)\(relationshipLabel(edge.label))."
            }
            return nil
        }
    }

    private static func relationshipLabel(_ label: String?) -> String {
        label.map { " via \($0)" } ?? ""
    }
}

extension SessionMapNodeStatus {
    var displayName: String {
        switch self {
        case .exists: "Exists"
        case .proposed: "Proposed"
        case .planned: "Planned"
        case .active: "Active"
        case .done: "Done"
        case .failed: "Failed"
        }
    }
}

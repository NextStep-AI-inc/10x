import Foundation

struct TranscriptToolGroup: Equatable, Sendable {
    let id: String
    let tools: [ToolPresentation]

    init?(_ tools: [ToolPresentation]) {
        guard let first = tools.first else { return nil }
        id = "tool-group-\(first.id)"
        self.tools = tools
    }

    var phase: ToolPhase {
        if tools.contains(where: { $0.phase == .failed }) { return .failed }
        if tools.contains(where: { $0.phase == .running }) { return .running }
        if tools.contains(where: { $0.phase == .interrupted }) { return .interrupted }
        return .complete
    }
}

enum TranscriptPresentationRow: Identifiable, Equatable, Sendable {
    case item(TranscriptItem)
    case toolGroup(TranscriptToolGroup)
    case groupedTool(groupID: String, tool: ToolPresentation)
    case delegation(id: String, tool: ToolPresentation, workers: [SubagentPresentation])

    var id: String {
        switch self {
        case .item(let item): item.viewID
        case .toolGroup(let group): group.id
        case .groupedTool(_, let tool): "tool:\(tool.id)"
        case .delegation(let id, _, _): id
        }
    }

    var isGroupedTool: Bool {
        if case .groupedTool = self { return true }
        return false
    }

    static func rows(from items: [TranscriptItem]) -> [Self] {
        let delegateToolIDs = Set(items.compactMap { item -> String? in
            guard case .tool(let tool) = item, tool.name == "task" else { return nil }
            return tool.id
        })

        var workerOrderByParent: [String: [String]] = [:]
        var latestWorkersByParent: [String: [String: SubagentPresentation]] = [:]
        var ownedSubagentIDs = Set<String>()

        for item in items {
            guard case .subagent(let sub) = item,
                  let parentID = sub.parentToolCallID,
                  delegateToolIDs.contains(parentID)
            else { continue }
            if !(workerOrderByParent[parentID]?.contains(sub.id) ?? false) {
                workerOrderByParent[parentID, default: []].append(sub.id)
            }
            latestWorkersByParent[parentID, default: [:]][sub.id] = sub
            ownedSubagentIDs.insert(sub.id)
        }

        func workers(for parentID: String) -> [SubagentPresentation] {
            (workerOrderByParent[parentID] ?? []).compactMap { latestWorkersByParent[parentID]?[$0] }
        }

        var rows: [Self] = []
        var pendingTools: [ToolPresentation] = []

        func appendPendingTools() {
            guard let group = TranscriptToolGroup(pendingTools) else { return }
            rows.append(.toolGroup(group))
            rows.append(contentsOf: group.tools.map {
                .groupedTool(groupID: group.id, tool: $0)
            })
            pendingTools.removeAll(keepingCapacity: true)
        }

        for item in items {
            switch item {
            case .tool(let tool) where tool.name == "task":
                appendPendingTools()
                rows.append(.delegation(
                    id: "delegation:\(tool.id)",
                    tool: tool,
                    workers: workers(for: tool.id)))
            case .tool(let tool):
                pendingTools.append(tool)
            case .subagent(let sub) where ownedSubagentIDs.contains(sub.id):
                continue
            default:
                appendPendingTools()
                rows.append(.item(item))
            }
        }
        appendPendingTools()
        return rows
    }

    static func visibleRows(
        from rows: [Self],
        isGroupExpanded: (String) -> Bool
    ) -> [Self] {
        rows.filter { row in
            if case .item(.message(let message)) = row, message.role == .assistant,
               message.document.blocks.isEmpty { return false }
            guard case .groupedTool(let groupID, _) = row else { return true }
            return isGroupExpanded(groupID)
        }
    }
}

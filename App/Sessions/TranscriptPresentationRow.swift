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
        return .complete
    }
}

enum TranscriptPresentationRow: Identifiable, Equatable, Sendable {
    case item(TranscriptItem)
    case toolGroup(TranscriptToolGroup)

    var id: String {
        switch self {
        case .item(let item): item.viewID
        case .toolGroup(let group): group.id
        }
    }

    static func rows(from items: [TranscriptItem]) -> [Self] {
        var rows: [Self] = []
        var pendingTools: [ToolPresentation] = []

        func appendPendingTools() {
            guard let group = TranscriptToolGroup(pendingTools) else { return }
            rows.append(.toolGroup(group))
            pendingTools.removeAll(keepingCapacity: true)
        }

        for item in items {
            if case .tool(let tool) = item {
                pendingTools.append(tool)
                continue
            }
            appendPendingTools()
            rows.append(.item(item))
        }
        appendPendingTools()
        return rows
    }
}

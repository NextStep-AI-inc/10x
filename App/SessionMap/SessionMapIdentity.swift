import Foundation
import CryptoKit

enum SessionMapIdentity {
    static func reconcile(
        _ candidate: SessionMapDocument,
        previous: SessionMapDocument
    ) -> SessionMapDocument {
        let candidateIDs = Set(candidate.graph.nodes.map(\.id))
        let previousIDs = Set(previous.graph.nodes.map(\.id))
        let unmatchedCandidates = candidate.graph.nodes.filter { !previousIDs.contains($0.id) }
        let unmatchedPrevious = previous.graph.nodes.filter { !candidateIDs.contains($0.id) }
        var replacements: [String: String] = [:]

        matchUnique(
            candidates: unmatchedCandidates,
            previous: unmatchedPrevious,
            key: { node in
                node.file.map { MatchKey(value: normalizedFile($0), kind: node.kind) }
            },
            replacements: &replacements
        )

        let usedPreviousIDs = Set(replacements.values)
        matchUnique(
            candidates: unmatchedCandidates.filter { replacements[$0.id] == nil },
            previous: unmatchedPrevious.filter { !usedPreviousIDs.contains($0.id) },
            key: { node in
                guard node.file == nil else { return nil }
                return MatchKey(value: node.label, kind: node.kind)
            },
            replacements: &replacements
        )

        guard !replacements.isEmpty else { return candidate }
        let nodes = candidate.graph.nodes.map { node in
            SessionMapNode(
                id: replacements[node.id] ?? node.id,
                label: node.label,
                kind: node.kind,
                file: node.file,
                status: node.status,
                group: node.group,
                ref: node.ref,
                note: node.note
            )
        }
        let edges = candidate.graph.edges.map { edge in
            SessionMapEdge(
                from: replacements[edge.from] ?? edge.from,
                to: replacements[edge.to] ?? edge.to,
                kind: edge.kind,
                label: edge.label
            )
        }
        let flow = candidate.flow.map { flow in
            SessionMapFlow(
                title: flow.title,
                steps: flow.steps.map { step in
                    SessionMapFlowStep(
                        node: replacements[step.node] ?? step.node,
                        ref: step.ref,
                        text: step.text
                    )
                }
            )
        }
        let plan = candidate.plan.map { plan in
            SessionMapPlan(
                title: plan.title,
                tasks: plan.tasks.map { task in
                    SessionMapPlanTask(
                        status: task.status,
                        node: task.node.map { replacements[$0] ?? $0 },
                        ref: task.ref,
                        text: task.text
                    )
                }
            )
        }
        return SessionMapDocument(
            headline: candidate.headline,
            phase: candidate.phase,
            summary: candidate.summary,
            graph: SessionMapGraph(nodes: nodes, edges: edges),
            flow: flow,
            plan: plan,
            blocks: candidate.blocks
        )
    }

    static func structureSignature(_ document: SessionMapDocument) -> String {
        let nodeRecords = document.graph.nodes.map { node in
            record(["node", node.id, node.kind.rawValue, node.group ?? ""])
        }.sorted()
        let edgeRecords = document.graph.edges.map { edge in
            record(["edge", edge.from, edge.to, edge.kind.rawValue])
        }.sorted()
        let bytes = Data((nodeRecords + edgeRecords).joined().utf8)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private struct MatchKey: Hashable {
        let value: String
        let kind: SessionMapNodeKind
    }

    private static func matchUnique(
        candidates: [SessionMapNode],
        previous: [SessionMapNode],
        key: (SessionMapNode) -> MatchKey?,
        replacements: inout [String: String]
    ) {
        let candidateGroups = Dictionary(grouping: candidates, by: key)
        let previousGroups = Dictionary(grouping: previous, by: key)
        for (matchKey, candidateGroup) in candidateGroups {
            guard let matchKey,
                  candidateGroup.count == 1,
                  let previousGroup = previousGroups[matchKey],
                  previousGroup.count == 1
            else { continue }
            replacements[candidateGroup[0].id] = previousGroup[0].id
        }
    }

    private static func record(_ fields: [String]) -> String {
        fields.map { field in "\(field.utf8.count):\(field)" }.joined()
    }

    private static func normalizedFile(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return path.hasPrefix("/") ? standardized : String(standardized.dropFirst())
    }
}

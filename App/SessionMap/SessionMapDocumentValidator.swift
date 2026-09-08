import Foundation

enum SessionMapDocumentValidator {
    static func validate(
        _ candidate: SessionMapDocument,
        context: SessionMapValidationContext
    ) -> SessionMapValidation {
        var validator = Validator(context: context)
        return validator.validate(candidate)
    }
}

private struct Validator {
    let context: SessionMapValidationContext
    private var warnings: [SessionMapDiagnostic] = []
    private var fatal: [SessionMapDiagnostic] = []

    init(context: SessionMapValidationContext) {
        self.context = context
    }

    mutating func validate(_ candidate: SessionMapDocument) -> SessionMapValidation {
        var document = candidate
        if let previous = context.previous {
            document = SessionMapIdentity.reconcile(document, previous: previous)
        }

        let nodeIDs = document.graph.nodes.map(\.id)
        guard Set(nodeIDs).count == nodeIDs.count else {
            addFatal("duplicate-node-id", "Node IDs must be unique.")
            return result(nil)
        }

        var nodes: [SessionMapNode] = []
        for node in document.graph.nodes {
            nodes.append(validateNode(node))
        }
        let validNodeIDs = Set(nodes.map(\.id))
        var edgeKeys = Set<EdgeKey>()
        var edges: [SessionMapEdge] = []
        for edge in document.graph.edges {
            guard validNodeIDs.contains(edge.from), validNodeIDs.contains(edge.to) else {
                warn("danglingReference", "An edge references a missing node.")
                continue
            }
            let key = EdgeKey(from: edge.from, to: edge.to, kind: edge.kind)
            if edgeKeys.insert(key).inserted { edges.append(edge) }
        }
        let connectedIDs = Set(edges.flatMap { [$0.from, $0.to] })
        for node in nodes where !connectedIDs.contains(node.id) {
            warn("orphanNode", "A node has no valid relationship.", elementID: node.id)
        }
        nodes = validateStatuses(nodes)

        let flow = document.flow.map { flow in
            SessionMapFlow(
                title: flow.title,
                steps: flow.steps.compactMap { step in
                        guard validNodeIDs.contains(step.node) else {
                            warn("danglingReference", "A flow step references a missing node.")
                            return nil
                        }
                        return step
                    }
            )
        }
        let plan = document.plan.map { plan in
            SessionMapPlan(
                title: plan.title,
                tasks: plan.tasks.map { task in
                        let node = task.node.flatMap { nodeID -> String? in
                            guard validNodeIDs.contains(nodeID) else {
                                warn("danglingReference", "A plan task references a missing node.")
                                return nil
                            }
                            return nodeID
                        }
                        return SessionMapPlanTask(
                            status: task.status,
                            node: node,
                            ref: task.ref,
                            text: task.text
                        )
                    }
            )
        }
        let blocks = document.blocks.compactMap { validateBlock($0, position: .root) }

        let validated = SessionMapDocument(
            headline: document.headline,
            phase: document.phase,
            summary: document.summary,
            graph: SessionMapGraph(nodes: nodes, edges: edges),
            flow: flow,
            plan: plan,
            blocks: blocks
        )
        if validated.summary == nil && validated.graph.nodes.isEmpty && validated.blocks.isEmpty {
            addFatal("no-usable-content", "A summary, map node, or supporting block is required.")
            return result(nil)
        }

        if let previous = context.previous, !previous.graph.nodes.isEmpty {
            let survivingIDs = Set(validated.graph.nodes.map(\.id))
            let removed = previous.graph.nodes.filter { !survivingIDs.contains($0.id) }.count
            if 3 * removed > previous.graph.nodes.count {
                warn("identityChurn", "More than one third of prior node identities disappeared.")
            }
        }
        return result(validated)
    }

    private mutating func validateNode(_ node: SessionMapNode) -> SessionMapNode {
        let file: String?
        if let path = node.file {
            file = validatedPath(path)
        } else {
            file = nil
        }
        return SessionMapNode(
            id: node.id,
            label: node.label,
            kind: node.kind,
            file: file,
            status: node.status,
            group: node.group,
            ref: node.ref,
            note: node.note
        )
    }

    private mutating func validateStatuses(_ nodes: [SessionMapNode]) -> [SessionMapNode] {
        let previousByID = Dictionary(
            uniqueKeysWithValues: (context.previous?.graph.nodes ?? []).map { ($0.id, $0) }
        )
        return nodes.map { node in
            let previous = previousByID[node.id]
            if previous?.status == node.status, node.status == .done || node.status == .failed {
                return replacingStatus(node, status: node.status, ref: previous?.ref)
            }

            let needsEvidence = previous?.status != node.status
                && (previous != nil || node.status == .done || node.status == .failed)
            guard needsEvidence else { return node }
            guard let evidence = supportingEvidence(for: node, among: nodes) else {
                warn("unsupportedStatus", "A node status change has no matching source evidence.", elementID: node.id)
                return replacingStatus(
                    node,
                    status: previous?.status ?? .planned,
                    ref: previous?.ref
                )
            }
            return replacingStatus(node, status: node.status, ref: evidence.sourceRef)
        }
    }

    private func supportingEvidence(
        for node: SessionMapNode,
        among nodes: [SessionMapNode]
    ) -> SessionMapStatusEvidence? {
        context.statusEvidence.first { evidence in
            guard evidence.status == node.status,
                  evidence.sourceRef == node.ref,
                  context.knownRefs.contains(evidence.sourceRef)
            else { return false }
            switch evidence.target {
            case let .file(path):
                return node.file == normalizedRelativePath(path)
            case let .label(label):
                guard node.file == nil else { return false }
                let matches = nodes.filter {
                    $0.file == nil && $0.label == label && $0.kind == node.kind
                }.count
                return node.label == label && matches == 1
            }
        }
    }

    private func replacingStatus(
        _ node: SessionMapNode,
        status: SessionMapNodeStatus,
        ref: String?
    ) -> SessionMapNode {
        SessionMapNode(
            id: node.id,
            label: node.label,
            kind: node.kind,
            file: node.file,
            status: status,
            group: node.group,
            ref: ref,
            note: node.note
        )
    }

    private enum BlockPosition {
        case root
        case section
        case row
    }

    private mutating func validateBlock(
        _ block: SessionMapBlock,
        position: BlockPosition
    ) -> SessionMapBlock? {
        switch block {
        case let .section(title, blocks):
            guard position == .root else {
                warn("limitExceeded", "Nested sections were dropped.")
                return nil
            }
            return .section(
                title: title,
                blocks: blocks.compactMap { validateBlock($0, position: .section) }
            )
        case let .row(blocks):
            guard position != .row else {
                warn("limitExceeded", "Nested rows were dropped.")
                return nil
            }
            let leaves = blocks.compactMap { validateBlock($0, position: .row) }
            guard leaves.count >= 2 else {
                warn("limitExceeded", "Rows with fewer than two valid leaves were dropped.")
                return nil
            }
            return .row(blocks: leaves)
        case let .text(text):
            return .text(text: text)
        case let .stat(fact, label, value, tone):
            return .stat(fact: fact, label: label, value: value, tone: tone)
        case let .timeline(events):
            guard position != .row else { return invalidRowLeaf() }
            return .timeline(events: events)
        case let .files(files):
            guard position != .row else { return invalidRowLeaf() }
            return .files(files: files.compactMap { file in
                guard let path = validatedPath(file.path) else { return nil }
                return SessionMapFile(path: path, change: file.change, note: file.note)
            })
        case let .chart(kind, points):
            return .chart(kind: kind, points: points)
        case let .checklist(items):
            guard position != .row else { return invalidRowLeaf() }
            return .checklist(items: items)
        case let .callout(title, tone, ref, text):
            guard position != .row else { return invalidRowLeaf() }
            return .callout(title: title, tone: tone, ref: ref, text: text)
        case let .next(steps):
            guard position != .row else { return invalidRowLeaf() }
            return .next(steps: steps)
        }
    }

    private mutating func invalidRowLeaf() -> SessionMapBlock? {
        warn("limitExceeded", "A row may contain only text, stat, or chart leaves.")
        return nil
    }

    private mutating func validatedPath(_ path: String) -> String? {
        guard let normalized = normalizedRelativePath(path) else {
            warn("danglingReference", "A file path falls outside the project.")
            return nil
        }
        return normalized
    }

    private func normalizedRelativePath(_ path: String) -> String? {
        guard !path.isEmpty, !path.hasPrefix("/"), let projectURL = context.projectURL else {
            return nil
        }
        let base = projectURL.standardizedFileURL.resolvingSymlinksInPath()
        let resolved = URL(fileURLWithPath: path, relativeTo: base)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        guard resolved.path.hasPrefix(prefix) else { return nil }
        return String(resolved.path.dropFirst(prefix.count))
    }

    private mutating func warn(_ code: String, _ detail: String, elementID: String? = nil) {
        warnings.append(SessionMapDiagnostic(
            code: code,
            elementID: elementID,
            detail: String(detail.prefix(SessionMapLimits.diagnosticDetail))
        ))
    }

    private mutating func addFatal(_ code: String, _ detail: String) {
        fatal.append(SessionMapDiagnostic(
            code: code,
            elementID: nil,
            detail: String(detail.prefix(SessionMapLimits.diagnosticDetail))
        ))
    }

    private func result(_ document: SessionMapDocument?) -> SessionMapValidation {
        SessionMapValidation(document: document, warnings: warnings, fatal: fatal)
    }

    private struct EdgeKey: Hashable {
        let from: String
        let to: String
        let kind: SessionMapEdgeKind
    }
}

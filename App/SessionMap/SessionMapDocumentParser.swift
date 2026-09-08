import Foundation

struct SessionMapFact: Equatable, Sendable {
    let value: String
    let number: Double?
}

struct SessionMapStatusEvidence: Equatable, Sendable {
    enum Target: Equatable, Sendable {
        case file(String)
        case label(String)
    }

    let sourceRef: String
    let status: SessionMapNodeStatus
    let target: Target
}

struct SessionMapValidationContext: Sendable {
    let knownRefs: Set<String>
    let facts: [String: SessionMapFact]
    let previous: SessionMapDocument?
    let projectURL: URL?
    let statusEvidence: [SessionMapStatusEvidence]

    init(
        knownRefs: Set<String>,
        facts: [String: SessionMapFact],
        previous: SessionMapDocument?,
        projectURL: URL?,
        statusEvidence: [SessionMapStatusEvidence] = []
    ) {
        self.knownRefs = knownRefs
        self.facts = facts
        self.previous = previous
        self.projectURL = projectURL
        self.statusEvidence = statusEvidence
    }
}

struct SessionMapDiagnostic: Equatable, Sendable {
    let code: String
    let elementID: String?
    let detail: String
}

struct SessionMapValidation: Equatable, Sendable {
    let document: SessionMapDocument?
    let warnings: [SessionMapDiagnostic]
    let fatal: [SessionMapDiagnostic]
}

enum SessionMapDocumentParser {
    static func parse(_ data: Data, context: SessionMapValidationContext) -> SessionMapValidation {
        guard data.count <= SessionMapLimits.xmlBytes else {
            return failed("limitExceeded", "XML exceeds \(SessionMapLimits.xmlBytes) bytes.")
        }
        guard let source = String(data: data, encoding: .utf8) else {
            return failed("invalid-utf8", "XML is not valid UTF-8.")
        }
        let declarationPattern = "<!\\s*(DOCTYPE|ENTITY)"
        if source.range(of: declarationPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return failed("xml-declaration-forbidden", "DTD and entity declarations are not allowed.")
        }

        let delegate = SessionMapXMLDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.error == nil, let root = delegate.root else {
            let detail = delegate.error ?? parser.parserError?.localizedDescription ?? "Malformed XML."
            return failed("malformed-xml", detail)
        }

        var builder = SessionMapDocumentBuilder(context: context)
        let parsed = builder.build(root)
        guard let document = parsed.document else { return parsed }
        let validated = SessionMapDocumentValidator.validate(document, context: context)
        return SessionMapValidation(
            document: validated.document,
            warnings: parsed.warnings + validated.warnings,
            fatal: parsed.fatal + validated.fatal
        )
    }

    private static func failed(_ code: String, _ detail: String) -> SessionMapValidation {
        SessionMapValidation(
            document: nil,
            warnings: [],
            fatal: [SessionMapDiagnostic(
                code: code,
                elementID: nil,
                detail: String(detail.prefix(SessionMapLimits.diagnosticDetail))
            )]
        )
    }
}

private struct SessionMapXMLElement {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [SessionMapXMLElement] = []
}

private final class SessionMapXMLDelegate: NSObject, XMLParserDelegate {
    private var stack: [SessionMapXMLElement] = []
    private(set) var root: SessionMapXMLElement?
    private(set) var error: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard stack.count < SessionMapLimits.xmlDepth else {
            error = "XML exceeds the supported nesting depth of \(SessionMapLimits.xmlDepth)."
            parser.abortParsing()
            return
        }
        stack.append(SessionMapXMLElement(name: elementName, attributes: attributeDict))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].text.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard let element = stack.popLast(), element.name == elementName else {
            error = "XML element nesting is invalid."
            parser.abortParsing()
            return
        }
        if stack.isEmpty {
            guard root == nil else {
                error = "XML must contain one root element."
                parser.abortParsing()
                return
            }
            root = element
        } else {
            stack[stack.count - 1].children.append(element)
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if error == nil { error = parseError.localizedDescription }
    }
}

private struct SessionMapDocumentBuilder {
    let context: SessionMapValidationContext
    private(set) var warnings: [SessionMapDiagnostic] = []
    private(set) var fatal: [SessionMapDiagnostic] = []

    mutating func build(_ root: SessionMapXMLElement) -> SessionMapValidation {
        guard root.name == "sessionmap" else {
            addFatal("invalid-root", "The root element must be sessionmap.")
            return result(nil)
        }
        warnUnknownAttributes(root, allowed: ["headline", "phase"])
        guard let headline = required(root.attributes["headline"], limit: SessionMapLimits.headline) else {
            addFatal("missing-headline", "Session map headline is required.")
            return result(nil)
        }
        guard let phaseValue = root.attributes["phase"], let phase = SessionMapPhase(rawValue: phaseValue) else {
            addFatal("invalid-phase", "Session map phase is missing or invalid.")
            return result(nil)
        }

        let summaryElements = root.children.filter { $0.name == "summary" }
        if summaryElements.count > 1 { warn("duplicate-summary", "Only the first summary is used.") }
        let summary = summaryElements.first.flatMap { boundedText($0, limit: SessionMapLimits.summary) }

        let mapElements = root.children.filter { $0.name == "map" }
        if mapElements.count > 1 { warn("duplicate-map", "Only the first map is used.") }
        let graph = parseGraph(mapElements.first)

        let flowElements = root.children.filter { $0.name == "flow" }
        if flowElements.count > 1 { warn("duplicate-flow", "Only the first flow is used.") }
        let flow = flowElements.first.flatMap { parseFlow($0, nodeIDs: Set(graph.nodes.map(\.id))) }

        let planElements = root.children.filter { $0.name == "plan" }
        if planElements.count > 1 { warn("duplicate-plan", "Only the first plan is used.") }
        let plan = planElements.first.flatMap { parsePlan($0, nodeIDs: Set(graph.nodes.map(\.id))) }

        let structuralNames: Set<String> = ["summary", "map", "flow", "plan"]
        var blocks: [SessionMapBlock] = []
        for child in root.children where !structuralNames.contains(child.name) {
            guard blocks.count < SessionMapLimits.blocks else {
                warn("limitExceeded", "Supporting blocks beyond \(SessionMapLimits.blocks) were dropped.")
                break
            }
            if let block = parseBlock(child) { blocks.append(block) }
        }

        if !fatal.isEmpty { return result(nil) }
        guard summary != nil || !graph.nodes.isEmpty || !blocks.isEmpty else {
            addFatal("no-usable-content", "A summary, map node, or supporting block is required.")
            return result(nil)
        }
        return result(SessionMapDocument(
            headline: headline,
            phase: phase,
            summary: summary,
            graph: graph,
            flow: flow,
            plan: plan,
            blocks: blocks
        ))
    }

    private mutating func parseGraph(_ element: SessionMapXMLElement?) -> SessionMapGraph {
        guard let element else { return SessionMapGraph(nodes: [], edges: []) }
        warnUnknownAttributes(element, allowed: [])
        var nodes: [SessionMapNode] = []
        var ids = Set<String>()
        var didWarnNodeLimit = false
        for child in element.children where child.name == "node" {
            guard let node = parseNode(child) else { continue }
            guard ids.insert(node.id).inserted else {
                addFatal("duplicate-node-id", "Node ID \(node.id) appears more than once.", elementID: node.id)
                continue
            }
            guard nodes.count < SessionMapLimits.nodes else {
                if !didWarnNodeLimit {
                    warn("limitExceeded", "Nodes beyond \(SessionMapLimits.nodes) were dropped.")
                    didWarnNodeLimit = true
                }
                continue
            }
            nodes.append(node)
        }

        var edges: [SessionMapEdge] = []
        var identities = Set<SessionMapEdgeIdentity>()
        var didWarnEdgeLimit = false
        for child in element.children where child.name == "edge" {
            guard edges.count < SessionMapLimits.edges else {
                if !didWarnEdgeLimit {
                    warn("limitExceeded", "Edges beyond \(SessionMapLimits.edges) were dropped.")
                    didWarnEdgeLimit = true
                }
                continue
            }
            guard let edge = parseEdge(child) else { continue }
            guard ids.contains(edge.from), ids.contains(edge.to) else {
                warn("danglingReference", "Edge \(edge.from) to \(edge.to) references a missing node.")
                continue
            }
            let identity = SessionMapEdgeIdentity(from: edge.from, to: edge.to, kind: edge.kind)
            if identities.insert(identity).inserted { edges.append(edge) }
        }
        for child in element.children where child.name != "node" && child.name != "edge" {
            warn("unknown-element", "Unknown map element \(child.name) was dropped.")
        }
        return SessionMapGraph(nodes: nodes, edges: edges)
    }

    private mutating func parseNode(_ element: SessionMapXMLElement) -> SessionMapNode? {
        warnUnknownAttributes(element, allowed: ["id", "label", "kind", "file", "status", "group", "ref"])
        guard let id = required(element.attributes["id"], limit: SessionMapLimits.nodeID),
              let label = required(element.attributes["label"], limit: SessionMapLimits.nodeLabel),
              let kindValue = element.attributes["kind"],
              let kind = SessionMapNodeKind(rawValue: kindValue),
              let statusValue = element.attributes["status"],
              let status = SessionMapNodeStatus(rawValue: statusValue)
        else {
            warn("invalid-node", "A node with missing or invalid required fields was dropped.", elementID: element.attributes["id"])
            return nil
        }
        return SessionMapNode(
            id: id,
            label: label,
            kind: kind,
            file: optional(element.attributes["file"]),
            status: status,
            group: bounded(element.attributes["group"], limit: SessionMapLimits.nodeGroup, field: "node group"),
            ref: validRef(element.attributes["ref"]),
            note: boundedText(element, limit: SessionMapLimits.nodeNote)
        )
    }

    private mutating func parseEdge(_ element: SessionMapXMLElement) -> SessionMapEdge? {
        warnUnknownAttributes(element, allowed: ["from", "to", "kind", "label"])
        guard let from = required(element.attributes["from"], limit: SessionMapLimits.nodeID),
              let to = required(element.attributes["to"], limit: SessionMapLimits.nodeID),
              let kindValue = element.attributes["kind"],
              let kind = SessionMapEdgeKind(rawValue: kindValue)
        else {
            warn("invalid-edge", "An edge with missing or invalid required fields was dropped.")
            return nil
        }
        return SessionMapEdge(
            from: from,
            to: to,
            kind: kind,
            label: bounded(element.attributes["label"], limit: SessionMapLimits.edgeLabel, field: "edge label")
        )
    }

    private mutating func parseFlow(_ element: SessionMapXMLElement, nodeIDs: Set<String>) -> SessionMapFlow? {
        warnUnknownAttributes(element, allowed: ["title"])
        guard let title = required(element.attributes["title"], limit: SessionMapLimits.title) else {
            warn("invalid-flow", "Flow without a title was dropped.")
            return nil
        }
        var steps: [SessionMapFlowStep] = []
        for child in element.children where child.name == "step" {
            guard steps.count < SessionMapLimits.flowSteps else {
                warn("limitExceeded", "Flow steps beyond \(SessionMapLimits.flowSteps) were dropped.")
                break
            }
            warnUnknownAttributes(child, allowed: ["node", "ref"])
            guard let node = child.attributes["node"], nodeIDs.contains(node),
                  let text = boundedText(child, limit: SessionMapLimits.stepText)
            else {
                warn("invalid-flow-step", "A flow step with a missing node or text was dropped.")
                continue
            }
            steps.append(SessionMapFlowStep(node: node, ref: validRef(child.attributes["ref"]), text: text))
        }
        return SessionMapFlow(title: title, steps: steps)
    }

    private mutating func parsePlan(_ element: SessionMapXMLElement, nodeIDs: Set<String>) -> SessionMapPlan? {
        warnUnknownAttributes(element, allowed: ["title"])
        guard let title = required(element.attributes["title"], limit: SessionMapLimits.title) else {
            warn("invalid-plan", "Plan without a title was dropped.")
            return nil
        }
        var tasks: [SessionMapPlanTask] = []
        for child in element.children where child.name == "task" {
            guard tasks.count < SessionMapLimits.planTasks else {
                warn("limitExceeded", "Plan tasks beyond \(SessionMapLimits.planTasks) were dropped.")
                break
            }
            warnUnknownAttributes(child, allowed: ["status", "node", "ref"])
            guard let statusValue = child.attributes["status"],
                  let status = SessionMapPlanTaskStatus(rawValue: statusValue),
                  let text = boundedText(child, limit: SessionMapLimits.taskText)
            else {
                warn("invalid-plan-task", "A plan task with a missing status or text was dropped.")
                continue
            }
            let requestedNode = optional(child.attributes["node"])
            let node = requestedNode.flatMap { nodeIDs.contains($0) ? $0 : nil }
            if requestedNode != nil && node == nil { warn("missing-task-node", "A plan task references a missing node.") }
            tasks.append(SessionMapPlanTask(
                status: status,
                node: node,
                ref: validRef(child.attributes["ref"]),
                text: text
            ))
        }
        return SessionMapPlan(title: title, tasks: tasks)
    }

    private mutating func parseBlock(_ element: SessionMapXMLElement) -> SessionMapBlock? {
        switch element.name {
        case "section":
            warnUnknownAttributes(element, allowed: ["title"])
            guard let title = required(element.attributes["title"], limit: SessionMapLimits.title) else {
                warn("invalid-section", "Section without a title was dropped.")
                return nil
            }
            return .section(title: title, blocks: element.children.compactMap { parseBlock($0) })
        case "row":
            warnUnknownAttributes(element, allowed: [])
            return .row(blocks: element.children.compactMap { parseBlock($0) })
        case "text":
            warnUnknownAttributes(element, allowed: [])
            return boundedText(element, limit: SessionMapLimits.text).map(SessionMapBlock.text)
        case "stat":
            warnUnknownAttributes(element, allowed: ["fact", "label", "value", "tone"])
            guard let fact = optional(element.attributes["fact"]),
                  let label = required(element.attributes["label"], limit: SessionMapLimits.statLabel),
                  let value = required(element.attributes["value"], limit: SessionMapLimits.statValue),
                  let expected = context.facts[fact], expected.value == value
            else {
                warn("factMismatch", "A stat without a matching fact was dropped.")
                return nil
            }
            return .stat(fact: fact, label: label, value: value, tone: tone(element.attributes["tone"]))
        case "timeline":
            warnUnknownAttributes(element, allowed: [])
            return .timeline(events: limitedValues(
                element.children.compactMap { parseTimelineEvent($0) },
                limit: SessionMapLimits.timelineEvents,
                field: "timeline events"
            ))
        case "files":
            warnUnknownAttributes(element, allowed: [])
            return .files(files: element.children.compactMap { parseFile($0) })
        case "chart":
            warnUnknownAttributes(element, allowed: ["kind"])
            guard let value = element.attributes["kind"], let kind = SessionMapChartKind(rawValue: value) else {
                warn("invalid-chart", "Chart without a valid kind was dropped.")
                return nil
            }
            return .chart(kind: kind, points: limitedValues(
                element.children.compactMap { parsePoint($0) },
                limit: SessionMapLimits.chartPoints,
                field: "chart points"
            ))
        case "checklist":
            warnUnknownAttributes(element, allowed: [])
            return .checklist(items: limitedValues(
                element.children.compactMap { parseChecklistItem($0) },
                limit: SessionMapLimits.checklistItems,
                field: "checklist items"
            ))
        case "callout":
            warnUnknownAttributes(element, allowed: ["title", "tone", "ref"])
            guard let title = required(element.attributes["title"], limit: SessionMapLimits.title),
                  let text = boundedText(element, limit: SessionMapLimits.calloutText)
            else {
                warn("invalid-callout", "Callout without a title or text was dropped.")
                return nil
            }
            return .callout(title: title, tone: tone(element.attributes["tone"]), ref: validRef(element.attributes["ref"]), text: text)
        case "next":
            warnUnknownAttributes(element, allowed: [])
            return .next(steps: limitedValues(
                element.children.compactMap { parseNextStep($0) },
                limit: SessionMapLimits.nextSteps,
                field: "next steps"
            ))
        default:
            warn("unknown-element", "Unknown supporting element \(element.name) was dropped.")
            return nil
        }
    }

    private mutating func parseTimelineEvent(_ element: SessionMapXMLElement) -> SessionMapTimelineEvent? {
        guard element.name == "event" else {
            warn("unknown-element", "Unknown timeline element \(element.name) was dropped.")
            return nil
        }
        warnUnknownAttributes(element, allowed: ["time", "ref", "tone"])
        guard let time = optional(element.attributes["time"]),
              let text = boundedText(element, limit: SessionMapLimits.timelineText)
        else {
            warn("invalid-timeline-event", "A timeline event without a time or text was dropped.")
            return nil
        }
        return SessionMapTimelineEvent(time: time, ref: validRef(element.attributes["ref"]), tone: tone(element.attributes["tone"]), text: text)
    }

    private mutating func parseFile(_ element: SessionMapXMLElement) -> SessionMapFile? {
        guard element.name == "file" else {
            warn("unknown-element", "Unknown files element \(element.name) was dropped.")
            return nil
        }
        warnUnknownAttributes(element, allowed: ["path", "change"])
        guard let path = optional(element.attributes["path"]),
              let value = element.attributes["change"],
              let change = SessionMapFileChange(rawValue: value)
        else {
            warn("invalid-file", "A file with a missing path or change was dropped.")
            return nil
        }
        return SessionMapFile(path: path, change: change, note: boundedText(element, limit: SessionMapLimits.fileNote))
    }

    private mutating func parsePoint(_ element: SessionMapXMLElement) -> SessionMapChartPoint? {
        guard element.name == "point" else {
            warn("unknown-element", "Unknown chart element \(element.name) was dropped.")
            return nil
        }
        warnUnknownAttributes(element, allowed: ["fact", "label", "value"])
        guard let fact = optional(element.attributes["fact"]),
              let label = required(element.attributes["label"], limit: SessionMapLimits.pointLabel),
              let rawValue = element.attributes["value"],
              let value = Double(rawValue), value.isFinite,
              let expected = context.facts[fact], expected.value == rawValue,
              let number = expected.number, number.isFinite, number == value
        else {
            warn("factMismatch", "A chart point without a matching numeric fact was dropped.")
            return nil
        }
        return SessionMapChartPoint(fact: fact, label: label, value: value)
    }

    private mutating func parseChecklistItem(_ element: SessionMapXMLElement) -> SessionMapChecklistItem? {
        guard element.name == "item" else {
            warn("unknown-element", "Unknown checklist element \(element.name) was dropped.")
            return nil
        }
        warnUnknownAttributes(element, allowed: ["done"])
        guard let done = bool(element.attributes["done"]),
              let text = boundedText(element, limit: SessionMapLimits.checklistText)
        else {
            warn("invalid-checklist-item", "A checklist item without a boolean done value or text was dropped.")
            return nil
        }
        return SessionMapChecklistItem(done: done, text: text)
    }

    private mutating func parseNextStep(_ element: SessionMapXMLElement) -> SessionMapNextStep? {
        guard element.name == "step" else {
            warn("unknown-element", "Unknown next element \(element.name) was dropped.")
            return nil
        }
        warnUnknownAttributes(element, allowed: ["prompt"])
        guard let prompt = required(element.attributes["prompt"], limit: SessionMapLimits.nextPrompt),
              let text = boundedText(element, limit: SessionMapLimits.nextText)
        else {
            warn("invalid-next-step", "A next step without a prompt or text was dropped.")
            return nil
        }
        return SessionMapNextStep(prompt: prompt, text: text)
    }

    private mutating func validRef(_ value: String?) -> String? {
        guard let value = optional(value) else { return nil }
        guard context.knownRefs.contains(value) else {
            warn("danglingReference", "Reference \(value) is not present in the source context.")
            return nil
        }
        return value
    }

    private func tone(_ value: String?) -> SessionMapTone {
        value.flatMap(SessionMapTone.init(rawValue:)) ?? .neutral
    }

    private func bool(_ value: String?) -> Bool? {
        switch value {
        case "true": true
        case "false": false
        default: nil
        }
    }

    private mutating func boundedText(_ element: SessionMapXMLElement, limit: Int) -> String? {
        bounded(element.text.trimmingCharacters(in: .whitespacesAndNewlines), limit: limit, field: element.name)
    }

    private mutating func required(_ value: String?, limit: Int) -> String? {
        guard let value = optional(value) else { return nil }
        return bounded(value, limit: limit, field: "required field")
    }

    private func optional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private mutating func bounded(_ value: String?, limit: Int, field: String) -> String? {
        guard let value = optional(value) else { return nil }
        guard value.count > limit else { return value }
        warn("limitExceeded", "The \(field) was truncated to \(limit) characters.")
        return String(value.prefix(limit))
    }

    private mutating func limitedValues<Value>(
        _ values: [Value],
        limit: Int,
        field: String
    ) -> [Value] {
        if values.count > limit {
            warn("limitExceeded", "Items beyond the \(field) limit of \(limit) were dropped.")
        }
        return Array(values.prefix(limit))
    }

    private mutating func warnUnknownAttributes(_ element: SessionMapXMLElement, allowed: Set<String>) {
        for name in element.attributes.keys.sorted() where !allowed.contains(name) {
            warn("unknown-attribute", "Unknown \(element.name) attribute \(name) was ignored.")
        }
    }

    private mutating func warn(_ code: String, _ detail: String, elementID: String? = nil) {
        warnings.append(SessionMapDiagnostic(
            code: code,
            elementID: elementID,
            detail: String(detail.prefix(SessionMapLimits.diagnosticDetail))
        ))
    }

    private mutating func addFatal(_ code: String, _ detail: String, elementID: String? = nil) {
        fatal.append(SessionMapDiagnostic(
            code: code,
            elementID: elementID,
            detail: String(detail.prefix(SessionMapLimits.diagnosticDetail))
        ))
    }

    private func result(_ document: SessionMapDocument?) -> SessionMapValidation {
        SessionMapValidation(document: document, warnings: warnings, fatal: fatal)
    }
}

private struct SessionMapEdgeIdentity: Hashable {
    let from: String
    let to: String
    let kind: SessionMapEdgeKind
}

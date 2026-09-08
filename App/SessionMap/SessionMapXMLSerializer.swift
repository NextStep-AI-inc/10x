import Foundation

enum SessionMapXMLSerializer {
    static func serialize(
        _ document: SessionMapDocument,
        facts: [String: SessionMapFact] = [:]
    ) -> String {
        var children: [String] = []
        if let summary = document.summary { children.append(element("summary", text: summary)) }
        if !document.graph.nodes.isEmpty || !document.graph.edges.isEmpty {
            let nodes = document.graph.nodes.map { node in
                element("node", attributes: compact([
                    "id": node.id, "label": node.label, "kind": node.kind.rawValue,
                    "file": node.file, "status": node.status.rawValue, "group": node.group,
                    "ref": node.ref,
                ]), text: node.note)
            }
            let edges = document.graph.edges.map { edge in
                element("edge", attributes: compact([
                    "from": edge.from, "to": edge.to, "kind": edge.kind.rawValue,
                    "label": edge.label,
                ]))
            }
            children.append(element("map", children: nodes + edges))
        }
        if let flow = document.flow {
            children.append(element(
                "flow", attributes: ["title": flow.title],
                children: flow.steps.map { step in
                    element("step", attributes: compact([
                        "node": step.node, "ref": step.ref,
                    ]), text: step.text)
                }))
        }
        if let plan = document.plan {
            children.append(element(
                "plan", attributes: ["title": plan.title],
                children: plan.tasks.map { task in
                    element("task", attributes: compact([
                        "status": task.status.rawValue, "node": task.node, "ref": task.ref,
                    ]), text: task.text)
                }))
        }
        children.append(contentsOf: document.blocks.map { serializeBlock($0, facts: facts) })
        return element("sessionmap", attributes: [
            "headline": document.headline,
            "phase": document.phase.rawValue,
        ], children: children)
    }

    private static func serializeBlock(
        _ block: SessionMapBlock,
        facts: [String: SessionMapFact]
    ) -> String {
        switch block {
        case .section(let title, let blocks):
            element("section", attributes: ["title": title], children: blocks.map {
                serializeBlock($0, facts: facts)
            })
        case .row(let blocks):
            element("row", children: blocks.map { serializeBlock($0, facts: facts) })
        case .text(let text):
            element("text", text: text)
        case .stat(let fact, let label, let value, let tone):
            element("stat", attributes: [
                "fact": fact, "label": label, "value": value, "tone": tone.rawValue,
            ])
        case .timeline(let events):
            element("timeline", children: events.map { event in
                element("event", attributes: compact([
                    "time": event.time, "ref": event.ref, "tone": event.tone.rawValue,
                ]), text: event.text)
            })
        case .files(let files):
            element("files", children: files.map { file in
                element("file", attributes: [
                    "path": file.path, "change": file.change.rawValue,
                ], text: file.note)
            })
        case .chart(let kind, let points):
            element("chart", attributes: ["kind": kind.rawValue], children: points.map { point in
                element("point", attributes: [
                    "fact": point.fact, "label": point.label,
                    "value": facts[point.fact]?.value ?? String(point.value),
                ])
            })
        case .checklist(let items):
            element("checklist", children: items.map { item in
                element("item", attributes: ["done": String(item.done)], text: item.text)
            })
        case .callout(let title, let tone, let ref, let text):
            element("callout", attributes: compact([
                "title": title, "tone": tone.rawValue, "ref": ref,
            ]), text: text)
        case .next(let steps):
            element("next", children: steps.map { step in
                element("step", attributes: ["prompt": step.prompt], text: step.text)
            })
        }
    }

    private static func element(
        _ name: String,
        attributes: [String: String] = [:],
        text: String? = nil,
        children: [String] = []
    ) -> String {
        let attributes = attributes.sorted { $0.key < $1.key }
            .map { " \($0.key)=\"\(escape($0.value))\"" }
            .joined()
        let body = text.map(escape) ?? children.joined()
        return body.isEmpty ? "<\(name)\(attributes)/>" : "<\(name)\(attributes)>\(body)</\(name)>"
    }

    private static func compact(_ values: [String: String?]) -> [String: String] {
        values.compactMapValues { $0 }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

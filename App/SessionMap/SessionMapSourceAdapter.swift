import Foundation
import CryptoKit
import OmpKit

enum SessionMapSourceAdapter {
    static func make(
        items: [TranscriptItem],
        sessionKey: String,
        lineage: String
    ) -> SessionMapSource {
        var entries: [SessionMapSourceEntry] = []
        var messageIndexes: [String: Int] = [:]
        var toolIndexes: [String: Int] = [:]
        var terminalAssistantIDs: Set<String> = []
        var finishedTurnIDs: [String] = []

        for item in items {
            switch item {
            case .threadStart:
                continue
            case .message(let message):
                guard TranscriptMessage.isDisplayable(message.raw) else { continue }
                let id = message.renderLineageKey.baseMessageID
                let text = message.visibleText
                guard !text.isEmpty else {
                    recordTerminal(message, id: id, seen: &terminalAssistantIDs, into: &finishedTurnIDs)
                    continue
                }
                if let index = messageIndexes[id] {
                    let previous = entries[index]
                    let mergedText = [previous.text, text]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                    entries[index] = makeEntry(
                        id: id,
                        timestamp: previous.timestamp ?? message.timestamp,
                        kind: previous.kind,
                        text: mergedText)
                } else {
                    messageIndexes[id] = entries.count
                    entries.append(makeEntry(
                        id: id,
                        timestamp: message.timestamp,
                        kind: message.role == .user ? .prompt : .assistant,
                        text: text))
                }
                recordTerminal(message, id: id, seen: &terminalAssistantIDs, into: &finishedTurnIDs)
            case .tool(let tool):
                let entry = toolEntry(tool)
                if let index = toolIndexes[tool.id] {
                    entries[index] = entry
                } else {
                    toolIndexes[tool.id] = entries.count
                    entries.append(entry)
                }
            case .annotation(let annotation):
                let detail = [annotation.title, annotation.detail]
                    .compactMap { $0 }
                    .joined(separator: ": ")
                let kind: SessionMapSourceEntry.Kind = switch annotation.tone {
                case .warning, .error: .attention
                case .neutral, .interactive: .annotation
                }
                entries.append(makeEntry(
                    id: annotation.id,
                    timestamp: annotation.timestamp,
                    kind: kind,
                    text: detail))
            case .notice(let id, let level, let message):
                let normalizedLevel = level.lowercased()
                entries.append(makeEntry(
                    id: id,
                    kind: normalizedLevel == "warning" || normalizedLevel == "error"
                        ? .attention : .annotation,
                    text: "\(level.capitalized): \(message)"))
            case .subagent(let subagent):
                entries.append(subagentEntry(subagent))
            case .extensionUI(let state):
                if let entry = attentionEntry(state) { entries.append(entry) }
            }
        }

        let knownRefs = Set(entries.map(\.id))
        let evidence = entries.flatMap(\.statusEvidence).filter {
            knownRefs.contains($0.sourceRef)
        }
        return SessionMapSource(
            sessionKey: sessionKey,
            lineage: lineage,
            entries: entries,
            finishedTurnIDs: finishedTurnIDs,
            knownRefs: knownRefs,
            statusEvidence: evidence)
    }

    private static func recordTerminal(
        _ message: TranscriptMessage,
        id: String,
        seen: inout Set<String>,
        into ids: inout [String]
    ) {
        guard message.role == .assistant,
              message.isFinal,
              let stopReason = message.stopReason?.lowercased(),
              !stopReason.isEmpty,
              stopReason != "tooluse",
              seen.insert(id).inserted
        else { return }
        ids.append(id)
    }

    private static func toolEntry(_ tool: ToolPresentation) -> SessionMapSourceEntry {
        let primary = tool.content.primary
        let outcome = exitCode(in: tool.content.body).map { "Exit \($0)" }
            ?? tool.content.outcome
            ?? tool.phase.label
        var facts: [String: SessionMapFact] = [:]
        if tool.phase == .failed {
            facts["failedTool.\(tool.id)"] = SessionMapFact(value: tool.name, number: nil)
        }
        let evidence = toolStatusEvidence(tool)
        return makeEntry(
            id: tool.id,
            timestamp: tool.startDate,
            kind: tool.phase == .failed ? .attention : .tool,
            text: tool.name,
            primary: primary,
            outcome: outcome,
            facts: facts,
            statusEvidence: evidence,
            fingerprintDetail: bodyText(tool.content.body))
    }

    private static func toolStatusEvidence(_ tool: ToolPresentation) -> [SessionMapStatusEvidence] {
        if tool.phase == .failed,
           let file = ToolContentExtractor.file(tool)?.path
                ?? ToolContentExtractor.edit(tool)?.path {
            return [SessionMapStatusEvidence(
                sourceRef: tool.id,
                status: .failed,
                target: .file(file))]
        }
        guard tool.result != nil, tool.phase != .running else { return [] }
        let name = tool.name.lowercased()
        if name == "todo" {
            guard tool.phase == .complete, hasReturnedTodoSnapshot(tool.result) else {
                return []
            }
            return ToolContentExtractor.todos(tool).compactMap { todo in
                statusEvidence(
                    sourceRef: tool.id,
                    target: .label(todo.text),
                    status: todo.status)
            }
        }
        guard name == "task" else { return [] }
        guard let task = ToolContentExtractor.task(tool) else { return [] }
        let authoritativeStatus = tool.phase == .failed
            ? "failed"
            : tool.result?["details"]?["status"]?.stringValue
                ?? tool.result?["status"]?.stringValue
        guard let authoritativeStatus else { return [] }
        return statusEvidence(
            sourceRef: tool.id,
            target: .label(task.title),
            status: authoritativeStatus).map { [$0] } ?? []
    }

    private static func hasReturnedTodoSnapshot(_ result: JSONValue?) -> Bool {
        result?["details"]?["phases"]?.arrayValue != nil
            || result?["phases"]?.arrayValue != nil
            || result?["details"]?["todos"]?.arrayValue != nil
            || result?["todos"]?.arrayValue != nil
    }

    private static func statusEvidence(
        sourceRef: String,
        target: SessionMapStatusEvidence.Target,
        status: String
    ) -> SessionMapStatusEvidence? {
        let nodeStatus: SessionMapNodeStatus? = switch status.lowercased() {
        case "complete", "completed", "done": .done
        case "failed", "failure", "error": .failed
        default: nil
        }
        return nodeStatus.map {
            SessionMapStatusEvidence(sourceRef: sourceRef, status: $0, target: target)
        }
    }

    private static func subagentEntry(
        _ subagent: SubagentPresentation
    ) -> SessionMapSourceEntry {
        var facts: [String: SessionMapFact] = [:]
        if let cost = subagent.cost {
            facts["subagentCost.\(subagent.id)"] = SessionMapFact(
                value: String(format: "%.4f", cost),
                number: cost)
        }
        let detail = [subagent.task, subagent.status.label, subagent.resultText]
            .compactMap { $0 }
            .joined(separator: ": ")
        return makeEntry(
            id: subagent.id,
            kind: subagent.status.isError ? .attention : .tool,
            text: detail,
            primary: subagent.assignment,
            outcome: subagent.status.label,
            facts: facts)
    }

    private static func attentionEntry(
        _ state: ExtensionUIState
    ) -> SessionMapSourceEntry? {
        let text: String
        switch state {
        case .confirm(_, let title, let message, _):
            text = "Pending approval: \(title): \(message)"
        case .select(_, let title, _, _),
             .input(_, let title, _, _),
             .editor(_, let title, _, _):
            text = "Pending input: \(title)"
        case .openURL(_, let target, let instructions):
            text = "Pending approval: \(instructions ?? target.host() ?? "Open link")"
        case .cancel, .notification, .status, .widget, .title, .setEditorText:
            return nil
        }
        return makeEntry(
            id: state.id,
            kind: .attention,
            text: text,
            facts: ["pendingAttention.\(state.id)": SessionMapFact(value: "true", number: nil)])
    }

    private static func makeEntry(
        id: String,
        timestamp: Date? = nil,
        kind: SessionMapSourceEntry.Kind,
        text: String,
        primary: String? = nil,
        outcome: String? = nil,
        facts: [String: SessionMapFact] = [:],
        statusEvidence: [SessionMapStatusEvidence] = [],
        fingerprintDetail: String = ""
    ) -> SessionMapSourceEntry {
        let semantic = [
            kind.rawValue,
            text,
            primary ?? "",
            outcome ?? "",
            facts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.value)" }.joined(separator: "\n"),
            statusEvidence.map(evidenceRecord).sorted().joined(separator: "\n"),
            fingerprintDetail,
        ].map { "\($0.utf8.count):\($0)" }.joined()
        return SessionMapSourceEntry(
            id: id,
            timestamp: timestamp,
            kind: kind,
            text: text,
            primary: primary,
            outcome: outcome,
            facts: facts,
            statusEvidence: statusEvidence,
            contentFingerprint: sha256(semantic))
    }

    private static func bodyText(_ body: ToolBody) -> String {
        switch body {
        case .document(let document):
            document.source
        case .source(let source, _):
            source.text
        case .diff(let diff, _):
            diff.raw
        case .console(let command, let output, let exitCode):
            [command ?? "", output, exitCode.map { "exit=\($0)" } ?? ""]
                .joined(separator: "\n")
        case .collection(let items):
            items.map { item in
                [item.label, item.detail ?? "", item.state ?? ""].joined(separator: " | ")
            }.joined(separator: "\n")
        case .media(_, let caption):
            caption?.source ?? ""
        case .progress(let progress):
            [
                progress.title,
                progress.status,
                progress.detail ?? "",
                progress.history.joined(separator: "\n"),
                progress.document?.source ?? "",
            ].joined(separator: "\n")
        case .data(let label, _):
            label
        case .stack(let bodies):
            bodies.map(bodyText).joined(separator: "\n")
        case .empty(let text):
            text
        case .privateActivity:
            ""
        }
    }

    private static func exitCode(in body: ToolBody) -> Int? {
        switch body {
        case .console(_, _, let exitCode):
            exitCode
        case .stack(let bodies):
            bodies.lazy.compactMap(exitCode).first
        case .document, .source, .diff, .collection, .media, .progress, .data, .empty,
             .privateActivity:
            nil
        }
    }

    private static func evidenceRecord(_ evidence: SessionMapStatusEvidence) -> String {
        let target = switch evidence.target {
        case .file(let file): "file:\(file)"
        case .label(let label): "label:\(label)"
        }
        return "\(evidence.sourceRef)|\(evidence.status.rawValue)|\(target)"
    }

    private static func sha256(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

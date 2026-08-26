import Foundation
import OmpKit

struct ToolCardContent: Equatable, Sendable {
    let title: String
    let verb: String
    let primary: String?
    let outcome: String?
    let reference: TranscriptReference?
    let body: ToolBody
}

indirect enum ToolBody: Equatable, Sendable {
    case document(ContentDocument)
    case source(SourcePresentation, previewLines: Int?)
    case diff(UnifiedDiff, fallbackPath: String?)
    case console(command: String?, output: String, exitCode: Int?)
    case collection([ToolCollectionItem])
    case media([ToolMediaItem], caption: ContentDocument?)
    case progress(ToolProgress)
    case data(label: String, value: JSONValue)
    case stack([ToolBody])
    case empty(String)
    case privateActivity
}

struct ToolCollectionItem: Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let detail: String?
    let reference: TranscriptReference?
    let state: String?
}

struct ToolMediaItem: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case image
        case audio
        case other
    }

    let id: String
    let kind: Kind
    let name: String?
    let mimeType: String?
    let data: String?
    let url: String?
}

struct ToolResourceItem: Equatable, Sendable {
    let name: String
    let uri: String
    let mimeType: String?
    let text: String?
}

struct ToolProgress: Equatable, Sendable {
    let title: String
    let status: String
    let detail: String?
    let completed: Int?
    let total: Int?
    let history: [String]
    let document: ContentDocument?
}

enum ToolResultBlock: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case text
        case image
        case resource
        case data
    }

    case text(String)
    case image(ToolMediaItem)
    case resource(ToolResourceItem)
    case data(label: String, value: JSONValue)

    var kind: Kind {
        switch self {
        case .text: .text
        case .image: .image
        case .resource: .resource
        case .data: .data
        }
    }
}

struct ToolResultEnvelope: Equatable, Sendable {
    let blocks: [ToolResultBlock]
    let details: [String: JSONValue]?
    let error: String?
    let raw: JSONValue?

    init(result: JSONValue?) {
        raw = result
        details = result?["details"]?.objectValue
        error = Self.errorText(in: result)

        var parsed: [ToolResultBlock] = []
        var seenText: Set<String> = []
        func appendText(_ text: String) {
            guard !text.isEmpty, seenText.insert(text).inserted else { return }
            parsed.append(.text(text))
        }

        if let text = result?.stringValue {
            appendText(text)
        } else if let content = result?["content"]?.stringValue {
            appendText(content)
        } else if let content = result?["content"]?.arrayValue {
            for (index, block) in content.enumerated() {
                switch block["type"]?.stringValue?.lowercased() {
                case "text":
                    if let text = block["text"]?.stringValue { appendText(text) }
                case "image", "image_url":
                    parsed.append(.image(Self.mediaItem(block, index: index)))
                case "resource_link":
                    if let resource = Self.resourceItem(block) {
                        parsed.append(.resource(resource))
                    } else {
                        parsed.append(.data(label: "Resource", value: block))
                    }
                case "resource":
                    let resourceValue = block["resource"] ?? block
                    if let resource = Self.resourceItem(resourceValue) {
                        parsed.append(.resource(resource))
                    } else {
                        parsed.append(.data(label: "Resource", value: block))
                    }
                case .none:
                    parsed.append(.data(label: "Content", value: block))
                case .some(let type):
                    parsed.append(.data(label: type.replacingOccurrences(
                        of: "_",
                        with: " ").capitalized, value: block))
                }
            }
        } else if let text = Self.firstString(
            in: result,
            keys: ["text", "output", "stdout"])
        {
            appendText(text)
        }

        blocks = parsed
    }

    var text: String? {
        let value = blocks.compactMap { block -> String? in
            guard case .text(let text) = block else { return nil }
            return text
        }.joined(separator: "\n")
        return value.isEmpty ? nil : value
    }

    private static func mediaItem(_ value: JSONValue, index: Int) -> ToolMediaItem {
        let mimeType = firstString(in: value, keys: ["mimeType", "mime_type"])
        let url = firstString(in: value, keys: ["url", "image_url"])
        return ToolMediaItem(
            id: "media-\(index)-\(url ?? mimeType ?? "item")",
            kind: mimeType?.lowercased().hasPrefix("audio/") == true ? .audio : .image,
            name: firstString(in: value, keys: ["name", "title", "alt"]),
            mimeType: mimeType,
            data: firstString(in: value, keys: ["data", "base64"]),
            url: url)
    }

    private static func resourceItem(_ value: JSONValue) -> ToolResourceItem? {
        guard let uri = firstString(in: value, keys: ["uri", "url"]) else { return nil }
        return ToolResourceItem(
            name: firstString(in: value, keys: ["name", "title"])
                ?? URL(string: uri)?.lastPathComponent
                ?? uri,
            uri: uri,
            mimeType: firstString(in: value, keys: ["mimeType", "mime_type"]),
            text: firstString(in: value, keys: ["text"]))
    }

    private static func errorText(in result: JSONValue?) -> String? {
        result?["error"]?.stringValue
            ?? result?["error"]?["message"]?.stringValue
            ?? result?["message"]?.stringValue
    }

    private static func firstString(
        in value: JSONValue?,
        keys: [String]
    ) -> String? {
        guard let value else { return nil }
        for key in keys {
            if let string = value[key]?.stringValue, !string.isEmpty { return string }
        }
        return nil
    }
}

struct FileToolContent: Equatable {
    let path: String
    let summary: String
    let preview: String
}

struct BashToolContent: Equatable {
    let command: String
    let output: String
}

struct EditToolContent: Equatable {
    let path: String
    let diff: String
    let unifiedDiff: UnifiedDiff?
    let additions: Int
    let removals: Int
}

struct SearchToolContent: Equatable {
    let query: String
    let matches: [String]
}

struct TaskToolContent: Equatable {
    let title: String
    let role: String?
    let model: String?
    let status: String
    let progress: String?
}

struct TodoToolItem: Equatable, Identifiable {
    let id: Int
    let text: String
    let status: String
    var isComplete: Bool { status == "completed" || status == "complete" || status == "done" }
}

struct WebToolResult: Equatable, Identifiable {
    var id: String { url + title }
    let title: String
    let url: String
    let summary: String?
}

struct WebToolContent: Equatable {
    let queryOrURL: String
    let results: [WebToolResult]
    let summary: String?
}

enum ToolContentExtractor {
    static func card(
        name: String,
        arguments: JSONValue,
        result: JSONValue?,
        phase: ToolPhase
    ) -> ToolCardContent {
        let kind = ToolCardRegistry.kind(for: name)
        let envelope = ToolResultEnvelope(result: result)
        let base: ToolCardContent = switch kind {
        case .read:
            fileCard(
                title: "Read",
                verb: "Read",
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase,
                prefersArgumentContent: false)
        case .write:
            fileCard(
                title: "Write",
                verb: "Write",
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase,
                prefersArgumentContent: true)
        case .edit:
            editCard(
                title: "Edit",
                verb: "Edit",
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .astEdit:
            editCard(
                title: "AST edit",
                verb: "Edit",
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .bash:
            consoleCard(
                title: "Command",
                verb: "Run",
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .eval:
            evalCard(
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .astGrep:
            collectionCard(
                title: "AST search",
                verb: "Search",
                primary: firstString(in: arguments, keys: ["pattern", "query"]),
                values: firstArray(in: result, paths: [
                    ["details", "matches"], ["matches"], ["results"],
                ]),
                envelope: envelope,
                arguments: arguments,
                result: result,
                phase: phase,
                emptyText: "No matches")
        case .grep:
            collectionCard(
                title: "Search",
                verb: "Search",
                primary: firstString(in: arguments, keys: ["pattern", "query"]),
                values: firstArray(in: result, paths: [
                    ["details", "matches"], ["matches"], ["results"],
                ]),
                envelope: envelope,
                arguments: arguments,
                result: result,
                phase: phase,
                emptyText: "No matches")
        case .glob:
            collectionCard(
                title: "Find files",
                verb: "Find",
                primary: firstString(in: arguments, keys: ["pattern", "glob", "path"]),
                values: firstArray(in: result, paths: [
                    ["details", "paths"], ["paths"], ["files"], ["results"],
                ]),
                envelope: envelope,
                arguments: arguments,
                result: result,
                phase: phase,
                emptyText: "No paths found")
        case .lsp:
            collectionCard(
                title: "Language service",
                verb: "Inspect",
                primary: firstString(in: arguments, keys: ["operation", "path", "symbol"]),
                values: firstArray(in: result, paths: [
                    ["details", "results"], ["results"], ["symbols"], ["diagnostics"],
                ]),
                envelope: envelope,
                arguments: arguments,
                result: result,
                phase: phase,
                emptyText: "No results")
        case .webSearch:
            collectionCard(
                title: "Web search",
                verb: "Search",
                primary: firstString(in: arguments, keys: ["query"]),
                values: firstArray(in: result, paths: [
                    ["details", "results"], ["results"],
                ]),
                envelope: envelope,
                arguments: arguments,
                result: result,
                phase: phase,
                emptyText: "No sources found")
        case .github:
            collectionCard(
                title: "GitHub",
                verb: "Inspect",
                primary: firstString(in: arguments, keys: [
                    "repository", "repo", "operation", "url",
                ]),
                values: firstArray(in: result, paths: [
                    ["details", "results"], ["results"], ["items"], ["checks"],
                ]),
                envelope: envelope,
                arguments: arguments,
                result: result,
                phase: phase,
                emptyText: completionText(phase))
        case .recall:
            collectionCard(
                title: "Recall",
                verb: "Recall",
                primary: firstString(in: arguments, keys: ["query", "text"]),
                values: firstArray(in: result, paths: [
                    ["details", "memories"], ["memories"], ["results"],
                ]),
                envelope: envelope,
                arguments: arguments,
                result: result,
                phase: phase,
                emptyText: "No memories found")
        case .retain:
            collectionCard(
                title: "Retain",
                verb: "Retain",
                primary: firstString(in: arguments, keys: ["memory", "text", "title"]),
                values: firstArray(in: result, paths: [
                    ["details", "memories"], ["memories"], ["results"],
                ]),
                envelope: envelope,
                arguments: arguments,
                result: result,
                phase: phase,
                emptyText: completionText(phase))
        case .todo:
            collectionCard(
                title: "Tasks",
                verb: "Update",
                primary: nil,
                values: arguments["todos"]?.arrayValue
                    ?? firstArray(in: result, paths: [["details", "todos"], ["todos"]]),
                envelope: envelope,
                arguments: arguments,
                result: result,
                phase: phase,
                emptyText: "No tasks")
        case .task:
            progressCard(
                title: "Task",
                verb: "Delegate",
                primary: firstString(in: arguments, keys: [
                    "title", "task", "description", "prompt",
                ]),
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .hub:
            progressCard(
                title: "Hub",
                verb: "Coordinate",
                primary: firstString(in: arguments, keys: [
                    "worker", "job", "task", "operation",
                ]),
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .debug:
            progressCard(
                title: "Debug",
                verb: "Debug",
                primary: firstString(in: arguments, keys: ["target", "operation", "path"]),
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .securityScan:
            progressCard(
                title: "Security scan",
                verb: "Scan",
                primary: firstString(in: arguments, keys: ["target", "path", "scope"]),
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .goal:
            progressCard(
                title: "Goal",
                verb: "Track",
                primary: firstString(in: arguments, keys: ["objective", "goal", "operation"]),
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .yield:
            progressCard(
                title: "Waiting",
                verb: "Wait",
                primary: firstString(in: arguments, keys: ["reason", "target"]),
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .checkpoint:
            progressCard(
                title: "Checkpoint",
                verb: "Save",
                primary: firstString(in: arguments, keys: ["goal", "title", "id"]),
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .rewind:
            progressCard(
                title: "Rewind",
                verb: "Restore",
                primary: firstString(in: arguments, keys: ["checkpoint", "id", "goal"]),
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .vibe(let action):
            progressCard(
                title: "Hub",
                verb: vibeLabel(action),
                primary: firstString(in: arguments, keys: ["worker", "task", "message"]),
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .resolution(let action):
            progressCard(
                title: "Proposal",
                verb: resolutionLabel(action),
                primary: firstString(in: arguments, keys: ["path", "proposal", "reason"]),
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .ask:
            documentCard(
                title: "Question",
                verb: "Ask",
                primary: firstString(in: arguments, keys: ["question", "title"]),
                preferredText: firstString(in: arguments, keys: ["question", "prompt"]),
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .reflect:
            documentCard(
                title: "Reflection",
                verb: "Reflect",
                primary: firstString(in: arguments, keys: ["query", "topic"]),
                preferredText: envelope.text,
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .memoryEdit:
            documentCard(
                title: "Memory",
                verb: "Edit",
                primary: firstString(in: arguments, keys: ["id", "memoryId", "operation"]),
                preferredText: firstString(in: arguments, keys: ["content", "text"])
                    ?? envelope.text,
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .learn:
            documentCard(
                title: "Learn",
                verb: "Learn",
                primary: firstString(in: arguments, keys: ["lesson", "title"]),
                preferredText: firstString(in: arguments, keys: ["lesson", "content"])
                    ?? envelope.text,
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .manageSkill:
            documentCard(
                title: "Skill",
                verb: "Manage",
                primary: firstString(in: arguments, keys: ["name", "skill", "operation"]),
                preferredText: firstString(in: arguments, keys: ["content", "description"])
                    ?? envelope.text,
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .inspectImage:
            mediaCard(
                title: "Image",
                verb: "Inspect",
                primary: firstString(in: arguments, keys: ["path", "url", "name"]),
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .browser:
            mediaCard(
                title: "Browser",
                verb: firstString(in: arguments, keys: ["action"]) ?? "Browse",
                primary: firstString(in: arguments, keys: ["url", "title", "target"]),
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .computer:
            mediaCard(
                title: "Computer",
                verb: firstString(in: arguments, keys: ["action", "gesture"]) ?? "Control",
                primary: firstString(in: arguments, keys: ["application", "app", "target"]),
                arguments: arguments,
                result: result,
                envelope: envelope,
                phase: phase)
        case .mcp(let server, let tool):
            ToolCardContent(
                title: humanized(tool),
                verb: "Use",
                primary: server,
                outcome: envelopeOutcome(envelope, phase: phase),
                reference: nil,
                body: envelopeBody(
                    envelope,
                    arguments: arguments,
                    result: result,
                    phase: phase,
                    includesArguments: true))
        case .custom(let customName):
            ToolCardContent(
                title: customName,
                verb: "Run",
                primary: nil,
                outcome: envelopeOutcome(envelope, phase: phase),
                reference: nil,
                body: customBody(arguments: arguments, result: result, phase: phase))
        case .think:
            ToolCardContent(
                title: "Working",
                verb: "Work",
                primary: nil,
                outcome: phase == .running ? "In progress" : phase.label,
                reference: nil,
                body: .privateActivity)
        }

        guard phase == .failed, kind != .think else { return base }
        let error = envelope.error ?? envelope.text ?? "Tool failed"
        return ToolCardContent(
            title: base.title,
            verb: base.verb,
            primary: base.primary,
            outcome: error,
            reference: base.reference,
            body: .stack([
                .document(MessageContentParser.parse(error)),
                base.body,
            ]))
    }

    static func file(_ presentation: ToolPresentation) -> FileToolContent? {
        guard let path = firstString(
            in: presentation.arguments,
            keys: ["path", "filePath", "file_path", "absolutePath"])
        else { return nil }
        let writtenContent = firstString(
            in: presentation.arguments,
            keys: ["content", "text"])
        let preview = presentation.name.lowercased() == "write"
            ? (writtenContent ?? outputText(presentation.result) ?? "")
            : (outputText(presentation.result) ?? writtenContent ?? "")
        let lineCount = preview.isEmpty ? 0 : preview.split(separator: "\n", omittingEmptySubsequences: false).count
        let summary = lineCount > 0
            ? "\(lineCount) \(lineCount == 1 ? "line" : "lines")"
            : "\(preview.utf8.count) bytes"
        return FileToolContent(path: path, summary: summary, preview: preview)
    }

    static func bash(_ presentation: ToolPresentation) -> BashToolContent? {
        guard let command = firstString(
            in: presentation.arguments,
            keys: ["command", "cmd", "script"])
        else { return nil }
        return BashToolContent(
            command: command,
            output: outputText(presentation.result) ?? "")
    }

    static func edit(_ presentation: ToolPresentation) -> EditToolContent? {
        guard let path = firstString(
            in: presentation.arguments,
            keys: ["path", "filePath", "file_path", "absolutePath"])
            ?? nestedString(in: presentation.result, paths: [["details", "path"]])
        else { return nil }
        let diff = nestedString(
            in: presentation.result,
            paths: [["details", "diff"], ["diff"]])
            ?? outputText(presentation.result)
            ?? ""
        guard !diff.isEmpty else { return nil }
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false)
        let additions = lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
        let removals = lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count
        return EditToolContent(
            path: path,
            diff: diff,
            unifiedDiff: UnifiedDiffParser.parse(diff, fallbackPath: path),
            additions: additions,
            removals: removals)
    }

    static func search(_ presentation: ToolPresentation) -> SearchToolContent? {
        guard let query = firstString(
            in: presentation.arguments,
            keys: ["pattern", "query", "glob", "path"])
        else { return nil }
        let detailMatches = nestedValue(
            in: presentation.result,
            path: ["details", "matches"])?.arrayValue?.compactMap(matchText)
        let outputMatches = outputText(presentation.result)?
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
        return SearchToolContent(
            query: query,
            matches: detailMatches ?? outputMatches ?? [])
    }

    static func task(_ presentation: ToolPresentation) -> TaskToolContent? {
        guard let title = firstString(
            in: presentation.arguments,
            keys: ["title", "task", "description", "prompt"])
        else { return nil }
        let status = nestedString(
            in: presentation.result,
            paths: [["details", "status"], ["status"]])
            ?? presentation.phase.label.lowercased()
        let progress = nestedString(
            in: presentation.result,
            paths: [["details", "progress"], ["progress"]])
            ?? outputText(presentation.result)
        return TaskToolContent(
            title: title,
            role: firstString(in: presentation.arguments, keys: ["role", "agentType"]),
            model: firstString(in: presentation.arguments, keys: ["model"]),
            status: status,
            progress: progress)
    }

    static func todos(_ presentation: ToolPresentation) -> [TodoToolItem] {
        let values = presentation.arguments["todos"]?.arrayValue
            ?? nestedValue(in: presentation.result, path: ["details", "todos"])?.arrayValue
            ?? []
        return values.enumerated().compactMap { index, value in
            guard let text = firstString(
                in: value,
                keys: ["content", "text", "title"])
            else { return nil }
            return TodoToolItem(
                id: index,
                text: text,
                status: firstString(in: value, keys: ["status"]) ?? "pending")
        }
    }

    static func web(_ presentation: ToolPresentation) -> WebToolContent? {
        guard let query = firstString(
            in: presentation.arguments,
            keys: ["query", "url", "href"])
        else { return nil }
        let values = nestedValue(in: presentation.result, path: ["details", "results"])?.arrayValue
            ?? presentation.result?["results"]?.arrayValue
            ?? []
        let results = values.compactMap { value -> WebToolResult? in
            guard let title = firstString(in: value, keys: ["title", "name"]),
                  let url = firstString(in: value, keys: ["url", "href"])
            else { return nil }
            return WebToolResult(
                title: title,
                url: url,
                summary: firstString(in: value, keys: ["snippet", "summary", "description"]))
        }
        return WebToolContent(
            queryOrURL: query,
            results: results,
            summary: outputText(presentation.result))
    }

    private static func fileCard(
        title: String,
        verb: String,
        arguments: JSONValue,
        result: JSONValue?,
        envelope: ToolResultEnvelope,
        phase: ToolPhase,
        prefersArgumentContent: Bool
    ) -> ToolCardContent {
        let path = firstString(
            in: arguments,
            keys: ["path", "filePath", "file_path", "absolutePath"])
            ?? nestedString(in: result, paths: [["details", "path"], ["path"]])
        let argumentText = firstString(in: arguments, keys: ["content", "text"])
        let text = prefersArgumentContent
            ? (argumentText ?? envelope.text)
            : (envelope.text ?? argumentText)
        let body: ToolBody
        if let text, !text.isEmpty {
            body = .source(SourcePresentation(
                language: path.flatMap(SourceTokenizer.languageIdentifier),
                text: text), previewLines: 20)
        } else {
            body = envelopeBody(
                envelope,
                arguments: arguments,
                result: result,
                phase: phase)
        }
        return ToolCardContent(
            title: title,
            verb: verb,
            primary: path,
            outcome: text.map(lineSummary) ?? envelopeOutcome(envelope, phase: phase),
            reference: path.map { .file(path: $0, line: nil) },
            body: body)
    }

    private static func editCard(
        title: String,
        verb: String,
        arguments: JSONValue,
        result: JSONValue?,
        envelope: ToolResultEnvelope,
        phase: ToolPhase
    ) -> ToolCardContent {
        let path = firstString(
            in: arguments,
            keys: ["path", "filePath", "file_path", "absolutePath"])
            ?? nestedString(in: result, paths: [["details", "path"], ["path"]])
        let patch = nestedString(
            in: result,
            paths: [["details", "diff"], ["diff"], ["patch"]])
            ?? firstString(in: arguments, keys: ["diff", "patch"])
            ?? envelope.text
        let unified = patch.flatMap { UnifiedDiffParser.parse($0, fallbackPath: path) }
        let body = unified.map { ToolBody.diff($0, fallbackPath: path) }
            ?? envelopeBody(
                envelope,
                arguments: arguments,
                result: result,
                phase: phase)
        let outcome = unified.map { diff in
            let additions = diff.files.reduce(0) { $0 + $1.additions }
            let removals = diff.files.reduce(0) { $0 + $1.removals }
            return "+\(additions) −\(removals)"
        } ?? envelopeOutcome(envelope, phase: phase)
        return ToolCardContent(
            title: title,
            verb: verb,
            primary: path,
            outcome: outcome,
            reference: path.map { .file(path: $0, line: nil) },
            body: body)
    }

    private static func consoleCard(
        title: String,
        verb: String,
        arguments: JSONValue,
        result: JSONValue?,
        envelope: ToolResultEnvelope,
        phase: ToolPhase
    ) -> ToolCardContent {
        let command = firstString(in: arguments, keys: ["command", "cmd", "script"])
        let streams = [
            nestedString(in: result, paths: [["details", "stdout"], ["stdout"]]),
            nestedString(in: result, paths: [["details", "stderr"], ["stderr"]]),
        ].compactMap { $0 }.filter { !$0.isEmpty }
        let output = streams.isEmpty ? (envelope.text ?? "") : streams.joined(separator: "\n")
        let exitCode = firstInt(in: result, paths: [
            ["details", "exitCode"], ["details", "exit_code"], ["exitCode"], ["exit_code"],
        ])
        return ToolCardContent(
            title: title,
            verb: verb,
            primary: command,
            outcome: exitCode.map { "Exit \($0)" } ?? envelopeOutcome(envelope, phase: phase),
            reference: nil,
            body: .console(command: command, output: output, exitCode: exitCode))
    }

    private static func evalCard(
        arguments: JSONValue,
        result: JSONValue?,
        envelope: ToolResultEnvelope,
        phase: ToolPhase
    ) -> ToolCardContent {
        let input = firstString(in: arguments, keys: ["code", "expression", "input", "script"])
        let language = firstString(in: arguments, keys: ["language", "lang"])
        var bodies: [ToolBody] = []
        if let input, !input.isEmpty {
            bodies.append(.source(SourcePresentation(language: language, text: input), previewLines: 12))
        }
        bodies.append(.console(
            command: nil,
            output: envelope.text ?? "",
            exitCode: firstInt(in: result, paths: [["details", "exitCode"], ["exitCode"]])))
        return ToolCardContent(
            title: "Evaluate",
            verb: "Evaluate",
            primary: language,
            outcome: envelopeOutcome(envelope, phase: phase),
            reference: nil,
            body: bodies.count == 1 ? bodies[0] : .stack(bodies))
    }

    private static func collectionCard(
        title: String,
        verb: String,
        primary: String?,
        values: [JSONValue]?,
        envelope: ToolResultEnvelope,
        arguments: JSONValue,
        result: JSONValue?,
        phase: ToolPhase,
        emptyText: String
    ) -> ToolCardContent {
        let items: [ToolCollectionItem]
        if let values {
            items = values.enumerated().map(collectionItem)
        } else {
            items = envelope.text?
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { !$0.isEmpty }
                .enumerated()
                .map { index, line in
                    ToolCollectionItem(
                        id: "\(index)-\(line)",
                        label: line,
                        detail: nil,
                        reference: reference(for: line),
                        state: nil)
                } ?? []
        }
        let body: ToolBody = items.isEmpty
            ? (result == nil && phase == .running
                ? envelopeBody(
                    envelope,
                    arguments: arguments,
                    result: result,
                    phase: phase)
                : .empty(emptyText))
            : .collection(items)
        return ToolCardContent(
            title: title,
            verb: verb,
            primary: primary,
            outcome: items.isEmpty ? emptyText : itemCount(items.count),
            reference: primary.flatMap { reference(for: $0) },
            body: body)
    }

    private static func collectionItem(
        _ offsetAndValue: EnumeratedSequence<[JSONValue]>.Element
    ) -> ToolCollectionItem {
        let (index, value) = offsetAndValue
        if let label = value.stringValue {
            return ToolCollectionItem(
                id: "\(index)-\(label)",
                label: label,
                detail: nil,
                reference: reference(for: label),
                state: nil)
        }
        let label = firstString(in: value, keys: [
            "title", "name", "path", "file", "url", "text", "content", "id",
        ]) ?? "Item \(index + 1)"
        let line = value["line"]?.intValue
        let target = firstString(in: value, keys: ["path", "file", "url", "uri"])
        let itemReference: TranscriptReference? = if let target,
                                                    target.hasPrefix("/") || target.contains("/") {
            target.hasPrefix("http")
                ? reference(for: target)
                : .file(path: target, line: line)
        } else {
            nil
        }
        return ToolCollectionItem(
            id: "\(index)-\(label)",
            label: label,
            detail: firstString(in: value, keys: [
                "snippet", "summary", "description", "detail", "message",
            ]),
            reference: itemReference,
            state: firstString(in: value, keys: ["status", "state", "severity"]))
    }

    private static func progressCard(
        title: String,
        verb: String,
        primary: String?,
        arguments: JSONValue,
        result: JSONValue?,
        envelope: ToolResultEnvelope,
        phase: ToolPhase
    ) -> ToolCardContent {
        let status = nestedString(
            in: result,
            paths: [["details", "status"], ["status"], ["details", "stage"]])
            ?? phase.label.lowercased()
        let detail = nestedString(
            in: result,
            paths: [["details", "progress"], ["progress"], ["details", "detail"]])
            ?? envelope.text
        let historyValues = firstArray(in: result, paths: [
            ["details", "history"], ["history"], ["messages"],
        ]) ?? []
        let history = historyValues.compactMap { value in
            value.stringValue ?? firstString(in: value, keys: ["text", "message", "title"])
        }
        let completed = firstInt(in: result, paths: [
            ["details", "completed"], ["completed"], ["usage", "used"],
        ])
        let total = firstInt(in: result, paths: [
            ["details", "total"], ["total"], ["usage", "budget"],
        ])
        let progress = ToolProgress(
            title: primary ?? title,
            status: status,
            detail: detail,
            completed: completed,
            total: total,
            history: history,
            document: detail.map(MessageContentParser.parse))
        return ToolCardContent(
            title: title,
            verb: verb,
            primary: primary,
            outcome: status,
            reference: primary.flatMap { reference(for: $0) },
            body: .progress(progress))
    }

    private static func documentCard(
        title: String,
        verb: String,
        primary: String?,
        preferredText: String?,
        arguments: JSONValue,
        result: JSONValue?,
        envelope: ToolResultEnvelope,
        phase: ToolPhase
    ) -> ToolCardContent {
        let body = preferredText.flatMap { text in
            text.isEmpty ? nil : ToolBody.document(MessageContentParser.parse(text))
        } ?? envelopeBody(
            envelope,
            arguments: arguments,
            result: result,
            phase: phase)
        return ToolCardContent(
            title: title,
            verb: verb,
            primary: primary,
            outcome: envelopeOutcome(envelope, phase: phase),
            reference: primary.flatMap { reference(for: $0) },
            body: body)
    }

    private static func mediaCard(
        title: String,
        verb: String,
        primary: String?,
        arguments: JSONValue,
        result: JSONValue?,
        envelope: ToolResultEnvelope,
        phase: ToolPhase
    ) -> ToolCardContent {
        var media = envelope.blocks.compactMap { block -> ToolMediaItem? in
            guard case .image(let item) = block else { return nil }
            return item
        }
        if media.isEmpty, let primary {
            media.append(ToolMediaItem(
                id: "media-primary-\(primary)",
                kind: .image,
                name: URL(filePath: primary).lastPathComponent,
                mimeType: nil,
                data: nil,
                url: primary))
        }
        let caption = envelope.text.map(MessageContentParser.parse)
        let body = media.isEmpty
            ? envelopeBody(
                envelope,
                arguments: arguments,
                result: result,
                phase: phase)
            : ToolBody.media(media, caption: caption)
        return ToolCardContent(
            title: title,
            verb: verb,
            primary: primary,
            outcome: media.isEmpty ? envelopeOutcome(envelope, phase: phase) : itemCount(media.count),
            reference: primary.flatMap { reference(for: $0) },
            body: body)
    }

    private static func envelopeBody(
        _ envelope: ToolResultEnvelope,
        arguments: JSONValue,
        result: JSONValue?,
        phase: ToolPhase,
        includesArguments: Bool = false
    ) -> ToolBody {
        var bodies = envelope.blocks.map(body)
        if let details = envelope.details, !details.isEmpty {
            bodies.append(.data(label: "Details", value: .object(details)))
        }
        if bodies.isEmpty, let result {
            bodies.append(.data(label: "Result", value: result))
        }
        if includesArguments, isMeaningful(arguments) {
            bodies.append(.data(label: "Arguments", value: arguments))
        }
        if bodies.isEmpty { return .empty(completionText(phase)) }
        return bodies.count == 1 ? bodies[0] : .stack(bodies)
    }

    private static func body(_ block: ToolResultBlock) -> ToolBody {
        switch block {
        case .text(let text):
            .document(MessageContentParser.parse(text))
        case .image(let media):
            .media([media], caption: nil)
        case .resource(let resource):
            .collection([ToolCollectionItem(
                id: resource.uri,
                label: resource.name,
                detail: resource.text ?? resource.mimeType,
                reference: reference(forResourceURI: resource.uri),
                state: nil)])
        case .data(let label, let value):
            .data(label: label, value: value)
        }
    }

    private static func customBody(
        arguments: JSONValue,
        result: JSONValue?,
        phase: ToolPhase
    ) -> ToolBody {
        var bodies: [ToolBody] = []
        if isMeaningful(arguments) {
            bodies.append(.data(label: "Arguments", value: arguments))
        }
        if let result {
            bodies.append(.data(label: "Result", value: result))
        }
        if bodies.isEmpty { return .empty(completionText(phase)) }
        return bodies.count == 1 ? bodies[0] : .stack(bodies)
    }

    private static func envelopeOutcome(
        _ envelope: ToolResultEnvelope,
        phase: ToolPhase
    ) -> String? {
        if let error = envelope.error { return error }
        if envelope.blocks.isEmpty, envelope.details?.isEmpty != false {
            return completionText(phase)
        }
        return nil
    }

    private static func completionText(_ phase: ToolPhase) -> String {
        switch phase {
        case .running: "Waiting for output"
        case .complete: "Completed without output"
        case .failed: "No error details"
        }
    }

    private static func lineSummary(_ text: String) -> String {
        let count = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return "\(count) \(count == 1 ? "line" : "lines")"
    }

    private static func itemCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "item" : "items")"
    }

    private static func reference(for value: String) -> TranscriptReference? {
        TranscriptReference.parseInline(value)
    }

    private static func reference(forResourceURI value: String) -> TranscriptReference? {
        if let url = URL(string: value), url.isFileURL {
            return .file(path: url.path, line: nil)
        }
        return reference(for: value)
    }

    private static func firstArray(
        in value: JSONValue?,
        paths: [[String]]
    ) -> [JSONValue]? {
        for path in paths {
            if let array = nestedValue(in: value, path: path)?.arrayValue { return array }
        }
        return nil
    }

    private static func firstInt(
        in value: JSONValue?,
        paths: [[String]]
    ) -> Int? {
        for path in paths {
            if let number = nestedValue(in: value, path: path)?.intValue { return number }
        }
        return nil
    }

    private static func isMeaningful(_ value: JSONValue) -> Bool {
        switch value {
        case .null: false
        case .object(let object): !object.isEmpty
        case .array(let array): !array.isEmpty
        case .string(let string): !string.isEmpty
        default: true
        }
    }

    private static func humanized(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func vibeLabel(_ action: VibeToolAction) -> String {
        switch action {
        case .spawn: "Start"
        case .send: "Message"
        case .wait: "Wait"
        case .kill: "Stop"
        case .list: "List"
        }
    }

    private static func resolutionLabel(_ action: ResolutionToolAction) -> String {
        switch action {
        case .resolve: "Apply"
        case .reject: "Discard"
        case .propose: "Propose"
        }
    }

    static func outputText(_ result: JSONValue?) -> String? {
        ToolResultEnvelope(result: result).text
    }

    private static func firstString(in value: JSONValue, keys: [String]) -> String? {
        for key in keys {
            if let string = value[key]?.stringValue, !string.isEmpty { return string }
        }
        return nil
    }

    private static func matchText(_ value: JSONValue) -> String? {
        if let string = value.stringValue { return string }
        let path = firstString(in: value, keys: ["path", "file", "url"])
        let line = value["line"]?.intValue.map(String.init)
        let text = firstString(in: value, keys: ["text", "match", "snippet"])
        let pieces = [path, line, text].compactMap { $0 }
        return pieces.isEmpty ? nil : pieces.joined(separator: ":")
    }

    private static func nestedString(
        in value: JSONValue?,
        paths: [[String]]
    ) -> String? {
        for path in paths {
            if let string = nestedValue(in: value, path: path)?.stringValue { return string }
        }
        return nil
    }

    private static func nestedValue(in value: JSONValue?, path: [String]) -> JSONValue? {
        path.reduce(value) { partial, key in partial?[key] }
    }
}

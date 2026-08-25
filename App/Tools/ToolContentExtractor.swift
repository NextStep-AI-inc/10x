import Foundation
import OmpKit

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
            matches: Array((detailMatches ?? outputMatches ?? []).prefix(20)))
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
            results: Array(results.prefix(8)),
            summary: outputText(presentation.result))
    }

    static func outputText(_ result: JSONValue?) -> String? {
        guard let result else { return nil }
        if let string = result.stringValue { return string }
        let text = result["content"]?.arrayValue?.compactMap { block in
            block["text"]?.stringValue
        }.joined(separator: "\n")
        return text.flatMap { $0.isEmpty ? nil : $0 }
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

import Foundation
import OmpKit

enum ToolPayloadBudget {
    enum Limits {
        static let scalarBytes = 8 * 1_024
        static let arrayChildren = 32
        static let containerDepth = 4
        static let totalNodes = 256
        static let inlineMediaBytes = 256 * 1_024
    }

    static let truncatedKey = "_truncated"
    static let omittedCountKey = "_omittedCount"
    static let itemsKey = "_items"

    /// ponytail: single-pass cap; upgrade path is streaming field extraction per tool family.
    static func limit(_ value: JSONValue) -> JSONValue {
        var context = Context()
        return limitValue(value, depth: 0, context: &context)
    }

    private struct Context {
        var nodesUsed = 0
        var truncated = false
        var omittedCount = 0

        mutating func consumeNode() -> Bool {
            guard nodesUsed < Limits.totalNodes else {
                truncated = true
                return false
            }
            nodesUsed += 1
            return true
        }
    }

    private static let summaryKeys: Set<String> = [
        "path", "filePath", "file_path", "absolutePath",
        "command", "cmd", "script", "pattern", "query", "glob",
        "title", "task", "description", "prompt", "toolName", "name",
        "error", "message", "type", "content", "text", "details",
        "isError", "exitCode", "exit_code", "url", "mimeType", "mime_type",
        "partialResult", "result", "args", "toolCallId", "toolName",
    ]

    private static func limitValue(
        _ value: JSONValue,
        depth: Int,
        context: inout Context
    ) -> JSONValue {
        guard context.consumeNode() else {
            return .string("[truncated: node limit]")
        }

        switch value {
        case .null, .bool, .int, .double:
            return value
        case .string(let text):
            return .string(limitScalar(text, context: &context))
        case .array(let values):
            return limitArray(values, depth: depth, context: &context)
        case .object(let object):
            return limitObject(object, depth: depth, context: &context)
        }
    }

    private static func limitScalar(_ text: String, context: inout Context) -> String {
        guard Data(text.utf8).count > Limits.scalarBytes else { return text }
        context.truncated = true
        return truncateUTF8(text, to: Limits.scalarBytes)
    }

    private static func limitArray(
        _ values: [JSONValue],
        depth: Int,
        context: inout Context
    ) -> JSONValue {
        guard depth < Limits.containerDepth else {
            context.truncated = true
            return .string("[truncated: depth limit]")
        }

        let kept = values.prefix(Limits.arrayChildren)
        var limited = kept.map { limitValue($0, depth: depth + 1, context: &context) }
        if values.count > Limits.arrayChildren {
            context.truncated = true
            context.omittedCount += values.count - Limits.arrayChildren
            return .object([
                truncatedKey: .bool(true),
                omittedCountKey: .int(values.count - Limits.arrayChildren),
                itemsKey: .array(limited),
            ])
        }
        return .array(limited)
    }

    private static func limitObject(
        _ object: [String: JSONValue],
        depth: Int,
        context: inout Context
    ) -> JSONValue {
        guard depth < Limits.containerDepth else {
            context.truncated = true
            return .string("[truncated: depth limit]")
        }

        let prioritized = object.keys.sorted { lhs, rhs in
            let leftPriority = summaryKeys.contains(lhs)
            let rightPriority = summaryKeys.contains(rhs)
            if leftPriority != rightPriority { return leftPriority }
            return lhs < rhs
        }

        var limited: [String: JSONValue] = [:]
        for key in prioritized {
            guard context.nodesUsed < Limits.totalNodes else {
                context.truncated = true
                break
            }
            guard let child = object[key] else { continue }
            if isInlineMediaField(key: key, in: object, value: child) {
                let mime = object["mimeType"]?.stringValue ?? object["mime_type"]?.stringValue
                limited[key] = limitInlineMedia(child, mimeType: mime, context: &context)
            } else {
                limited[key] = limitValue(child, depth: depth + 1, context: &context)
            }
        }
        if context.truncated {
            limited[truncatedKey] = .bool(true)
            if context.omittedCount > 0 {
                limited[omittedCountKey] = .int(context.omittedCount)
            }
        }
        return .object(limited)
    }

    private static func isInlineMediaField(
        key: String,
        in object: [String: JSONValue],
        value: JSONValue
    ) -> Bool {
        guard key == "data" || key == "base64" else { return false }
        guard value.stringValue != nil else { return false }
        let type = object["type"]?.stringValue?.lowercased()
        let mime = object["mimeType"]?.stringValue ?? object["mime_type"]?.stringValue
        return type == "image" || type == "image_url" || mime?.hasPrefix("image/") == true
            || mime?.hasPrefix("audio/") == true
    }

    private static func limitInlineMedia(
        _ value: JSONValue,
        mimeType: String?,
        context: inout Context
    ) -> JSONValue {
        guard let text = value.stringValue else { return value }
        guard Data(text.utf8).count > Limits.inlineMediaBytes else { return value }
        context.truncated = true
        let kilobytes = Double(text.utf8.count) / 1_024
        let mime = mimeType ?? "application/octet-stream"
        return .string(String(format: "[Inline media omitted: %.1f KiB, %@]", kilobytes, mime))
    }

    private static func truncateUTF8(_ text: String, to byteLimit: Int) -> String {
        guard Data(text.utf8).count > byteLimit else { return text }
        var result = ""
        for character in text {
            let candidate = result + String(character)
            if Data(candidate.utf8).count > byteLimit {
                break
            }
            result = candidate
        }
        guard !result.isEmpty, result.count < text.count else { return result }
        let ellipsis = "…"
        while !result.isEmpty {
            let candidate = result + ellipsis
            if Data(candidate.utf8).count <= byteLimit {
                return candidate
            }
            result.removeLast()
        }
        return ellipsis
    }
}

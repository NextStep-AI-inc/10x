import Foundation
import OmpKit

enum ToolPayloadBudget {
    enum Limits {
        static let scalarBytes = 8 * 1_024
        static let arrayChildren = 32
        // Normal OMP todo snapshots: root → details → phases[] → phase → tasks[] → task
        // object (depths 0…5). Scalars inside tasks are not container levels.
        static let containerDepth = 6
        static let totalNodes = 256
        static let inlineMediaBytes = 256 * 1_024
    }

    static let truncatedKey = "_truncated"
    static let omittedCountKey = "_omittedCount"

    /// ponytail: single-pass cap; upgrade path is streaming field extraction per tool family.
    static func limit(_ value: JSONValue) -> JSONValue {
        var context = Context()
        return limitValue(value, depth: 0, context: &context) ?? .null
    }

    static func isTruncationMarker(_ value: JSONValue) -> Bool {
        guard let text = value.stringValue else { return false }
        return text.hasPrefix("[truncated:") && text.contains("omitted]")
    }

    private struct Context {
        var nodesUsed = 0
        var truncated = false
        var lastArrayOmission = 0

        var hasNodeBudget: Bool { nodesUsed < Limits.totalNodes }

        mutating func consumeNode() -> Bool {
            guard nodesUsed < Limits.totalNodes else {
                truncated = true
                return false
            }
            nodesUsed += 1
            return true
        }

        mutating func beginArrayLimit() {
            lastArrayOmission = 0
        }
    }

    private static let summaryKeyOrder: [String] = [
        "path", "filePath", "file_path", "absolutePath",
        "command", "cmd", "script", "pattern", "query", "glob",
        "title", "task", "description", "prompt", "toolName", "name",
        "error", "message", "type", "content", "text", "details",
        "isError", "exitCode", "exit_code", "url", "mimeType", "mime_type",
        "partialResult", "result", "args", "toolCallId",
        "matches", "paths", "files", "results", "tasks", "phases", "todos",
    ]

    private static let summaryKeys = Set(summaryKeyOrder)

    private static func limitValue(
        _ value: JSONValue,
        depth: Int,
        context: inout Context
    ) -> JSONValue? {
        guard context.consumeNode() else { return nil }

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

    private static func limitKey(_ key: String, context: inout Context) -> String {
        limitScalar(key, context: &context)
    }

    private static func limitArray(
        _ values: [JSONValue],
        depth: Int,
        context: inout Context
    ) -> JSONValue {
        context.beginArrayLimit()

        guard depth < Limits.containerDepth else {
            context.truncated = true
            return .string(limitScalar("[truncated: depth limit]", context: &context))
        }

        let isRoot = depth == 0
        let reserveMarkerSlot = isRoot && values.count > Limits.arrayChildren
        let dataCap = reserveMarkerSlot
            ? Limits.arrayChildren - 1
            : Limits.arrayChildren

        var limited: [JSONValue] = []
        var omitted = 0

        for (index, value) in values.enumerated() {
            if limited.count >= dataCap {
                omitted = values.count - index
                break
            }
            guard context.hasNodeBudget else {
                omitted = values.count - index
                context.truncated = true
                break
            }
            guard let limitedChild = limitValue(value, depth: depth + 1, context: &context) else {
                omitted = values.count - index
                break
            }
            limited.append(limitedChild)
        }

        if omitted > 0 {
            context.truncated = true
            context.lastArrayOmission = omitted
            if isRoot, limited.count < Limits.arrayChildren, context.consumeNode() {
                limited.append(truncationMarker(omittedCount: omitted, context: &context))
            }
        }

        return .array(limited)
    }

    private static func limitObject(
        _ object: [String: JSONValue],
        depth: Int,
        context: inout Context
    ) -> JSONValue {
        context.beginArrayLimit()

        guard depth < Limits.containerDepth else {
            context.truncated = true
            return .string(limitScalar("[truncated: depth limit]", context: &context))
        }

        var limited: [String: JSONValue] = [:]
        var processed = Set<String>()
        var objectOmitted = 0

        func insertEntry(key: String, value: JSONValue) -> Bool {
            guard context.hasNodeBudget else {
                context.truncated = true
                return false
            }
            let limitedKey = limitKey(key, context: &context)
            let limitedValue: JSONValue?
            if isInlineMediaField(key: key, in: object, value: value) {
                guard context.consumeNode() else {
                    context.truncated = true
                    return false
                }
                let mime = object["mimeType"]?.stringValue ?? object["mime_type"]?.stringValue
                limitedValue = limitInlineMedia(value, mimeType: mime, context: &context)
            } else {
                context.beginArrayLimit()
                limitedValue = limitValue(value, depth: depth + 1, context: &context)
            }
            guard let limitedValue else {
                context.truncated = true
                return false
            }
            limited[limitedKey] = limitedValue
            if context.lastArrayOmission > 0 {
                context.truncated = true
                objectOmitted = max(objectOmitted, context.lastArrayOmission)
            }
            return true
        }

        for key in summaryKeyOrder {
            guard let value = object[key] else { continue }
            processed.insert(key)
            guard insertEntry(key: key, value: value) else { break }
        }

        if context.hasNodeBudget {
            for (key, value) in object where !processed.contains(key) {
                guard insertEntry(key: key, value: value) else { break }
            }
        } else {
            context.truncated = true
        }

        appendTruncationMetadata(
            to: &limited,
            omittedCount: objectOmitted,
            context: &context)

        return .object(limited)
    }

    private static func appendTruncationMetadata(
        to object: inout [String: JSONValue],
        omittedCount: Int,
        context: inout Context
    ) {
        guard context.truncated || omittedCount > 0 else { return }
        guard context.consumeNode() else { return }
        object[truncatedKey] = .bool(true)
        guard omittedCount > 0, context.consumeNode() else { return }
        object[omittedCountKey] = .int(omittedCount)
    }

    private static func truncationMarker(
        omittedCount: Int,
        context: inout Context
    ) -> JSONValue {
        .string(limitScalar("[truncated: \(omittedCount) omitted]", context: &context))
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
        let cappedMIME = mimeType.map { limitScalar($0, context: &context) }
            ?? limitScalar("application/octet-stream", context: &context)
        let label = limitScalar(
            String(format: "[Inline media omitted: %.1f KiB, %@]", kilobytes, cappedMIME),
            context: &context)
        return .string(label)
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

import Foundation
import OmpKit

struct GuidancePresentation: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case advisor
        case agentGuidance
        case referencedFile
    }

    enum Visibility: Equatable, Sendable {
        case always
        case whenEnabled
    }

    let id: String
    let kind: Kind
    let visibility: Visibility
    let byteCount: Int
    let preview: String
}

enum BoundaryText {
    static func preview(_ text: String, byteLimit: Int, lineLimit: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let limited = lines.prefix(lineLimit).map(String.init).joined(separator: "\n")
        return truncateUTF8(limited, to: byteLimit)
    }

    static func sanitizeTitle(_ text: String) -> String {
        truncateUTF8(text, to: GuidanceLimits.titleByteLimit)
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
        return ""
    }
}

enum GuidanceClassifier {
    static func classify(id: String, message: JSONValue) -> GuidancePresentation? {
        if message["role"]?.stringValue == "fileMention" {
            return referencedFilePresentation(id: id, message: message)
        }
        if isUserAttributedDeveloperFileReference(message) {
            return referencedFilePresentation(id: id, message: message)
        }
        if message["customType"]?.stringValue == "advisor" {
            return advisorPresentation(id: id, message: message)
        }
        if message["role"]?.stringValue == "developer" {
            return agentGuidancePresentation(id: id, message: message)
        }
        if isHiddenHarnessMessage(message) {
            return agentGuidancePresentation(id: id, message: message)
        }
        return nil
    }

    private static func advisorPresentation(id: String, message: JSONValue) -> GuidancePresentation? {
        let source = advisorSource(from: message)
        guard !source.isEmpty else { return nil }
        return GuidancePresentation(
            id: id,
            kind: .advisor,
            visibility: .whenEnabled,
            byteCount: Data(source.utf8).count,
            preview: BoundaryText.preview(
                source,
                byteLimit: GuidanceLimits.previewByteLimit,
                lineLimit: GuidanceLimits.previewLineLimit))
    }

    private static func agentGuidancePresentation(id: String, message: JSONValue) -> GuidancePresentation? {
        let source = plainText(from: message["content"])
        guard !source.isEmpty else { return nil }
        return GuidancePresentation(
            id: id,
            kind: .agentGuidance,
            visibility: .whenEnabled,
            byteCount: Data(source.utf8).count,
            preview: BoundaryText.preview(
                source,
                byteLimit: GuidanceLimits.previewByteLimit,
                lineLimit: GuidanceLimits.previewLineLimit))
    }

    private static func referencedFilePresentation(id: String, message: JSONValue) -> GuidancePresentation? {
        let files = message["files"]?.arrayValue ?? []
        let paths = files.compactMap { file -> String? in
            guard let path = file["path"]?.stringValue else { return nil }
            return BoundaryText.sanitizeTitle(path)
        }
        guard !paths.isEmpty else { return nil }
        let previewSource = paths.joined(separator: "\n")
        let byteCount = files.reduce(into: 0) { total, file in
            total += Data(plainText(from: file["content"]).utf8).count
        }
        return GuidancePresentation(
            id: id,
            kind: .referencedFile,
            visibility: .always,
            byteCount: byteCount,
            preview: BoundaryText.preview(
                previewSource,
                byteLimit: GuidanceLimits.previewByteLimit,
                lineLimit: GuidanceLimits.previewLineLimit))
    }

    private static func isUserAttributedDeveloperFileReference(_ message: JSONValue) -> Bool {
        message["role"]?.stringValue == "developer"
            && message["attribution"]?.stringValue == "user"
            && !(message["files"]?.arrayValue ?? []).isEmpty
    }

    private static func isHiddenHarnessMessage(_ message: JSONValue) -> Bool {
        switch message["role"]?.stringValue {
        case "custom", "hookMessage":
            return message["display"]?.boolValue != true
        default:
            return false
        }
    }

    private static func advisorSource(from message: JSONValue) -> String {
        let notes = (message["details"]?["notes"]?.arrayValue ?? [])
            .compactMap { $0["note"]?.stringValue }
            .filter { !$0.isEmpty }
        if !notes.isEmpty {
            return notes.joined(separator: "\n")
        }
        let content = message["content"]?.stringValue ?? ""
        return strippingAdvisoryEnvelope(from: content)
    }

    private static func strippingAdvisoryEnvelope(from content: String) -> String {
        content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("<advisory") && trimmed != "</advisory>"
            }
            .map(String.init)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func plainText(from content: JSONValue?) -> String {
        guard let content else { return "" }
        if let source = content.stringValue {
            return source
        }
        guard let blocks = content.arrayValue else { return "" }
        return blocks.compactMap { block -> String? in
            if let source = block.stringValue { return source }
            guard block["type"]?.stringValue?.lowercased() == "text" else { return nil }
            return block["text"]?.stringValue
        }.joined(separator: "\n")
    }
}

private enum GuidanceLimits {
    static let previewByteLimit = 512
    static let previewLineLimit = 6
    static let titleByteLimit = 80
}

import CryptoKit
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
    /// Stable digest of selected source metadata for reconcile dedup; not a view id.
    let reconcileFingerprint: String
    /// When set, this item is the single omission marker for evicted guidance.
    let omittedEarlierCount: Int?

    init(
        id: String,
        kind: Kind,
        visibility: Visibility,
        byteCount: Int,
        preview: String,
        reconcileFingerprint: String,
        omittedEarlierCount: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.visibility = visibility
        self.byteCount = byteCount
        self.preview = preview
        self.reconcileFingerprint = reconcileFingerprint
        self.omittedEarlierCount = omittedEarlierCount
    }

    static func earlierOmitted(count: Int) -> GuidancePresentation {
        GuidancePresentation(
            id: GuidanceTranscript.omissionItemID,
            kind: .agentGuidance,
            visibility: .whenEnabled,
            byteCount: 0,
            preview: "",
            reconcileFingerprint: "",
            omittedEarlierCount: count)
    }
}

enum GuidanceReconcileFingerprint {
    static func digest(kind: GuidancePresentation.Kind, message: JSONValue, source: String) -> String {
        var parts: [String] = [kindToken(kind)]
        if let role = message["role"]?.stringValue { parts.append("role:\(role)") }
        if let customType = message["customType"]?.stringValue { parts.append("custom:\(customType)") }
        if let attribution = message["attribution"]?.stringValue { parts.append("attr:\(attribution)") }
        parts.append("bytes:\(Data(source.utf8).count)")
        parts.append(source)
        let input = parts.joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func kindToken(_ kind: GuidancePresentation.Kind) -> String {
        switch kind {
        case .advisor: "advisor"
        case .agentGuidance: "agentGuidance"
        case .referencedFile: "referencedFile"
        }
    }
}

enum GuidanceTranscript {
    static let maxRetainedItems = 128
    static let omissionItemID = "guidance-earlier-omitted"

    static func classify(id: String, message: JSONValue) -> GuidancePresentation? {
        GuidanceClassifier.classify(id: id, message: message)
    }

    @discardableResult
    static func upsert(
        _ presentation: GuidancePresentation,
        into items: inout [TranscriptItem]
    ) -> Bool {
        let item = TranscriptItem.guidance(presentation)
        if let index = items.firstIndex(where: { existing in
            guard case .guidance(let guidance) = existing else { return false }
            return guidance.id == presentation.id
        }) {
            guard items[index] != item else { return false }
            items[index] = item
        } else {
            items.append(item)
        }
        enforceCap(on: &items)
        return true
    }

    static func enforceCap(on items: inout [TranscriptItem]) {
        let previousOmittedCount = currentOmittedCount(in: items)
        removeOmissionMarker(from: &items)

        var guidanceIndices: [Int] = []
        for (index, item) in items.enumerated() {
            guard case .guidance = item else { continue }
            guidanceIndices.append(index)
        }

        let excess = max(0, guidanceIndices.count - maxRetainedItems)
        let totalOmitted = previousOmittedCount + excess

        if excess > 0 {
            for index in guidanceIndices.prefix(excess).sorted(by: >) {
                items.remove(at: index)
            }
        }

        guard totalOmitted > 0 else { return }

        guard let firstGuidanceIndex = items.firstIndex(where: { item in
            guard case .guidance(let presentation) = item else { return false }
            return presentation.omittedEarlierCount == nil
        }) else { return }

        items.insert(
            .guidance(.earlierOmitted(count: totalOmitted)),
            at: firstGuidanceIndex)
    }

    private static func currentOmittedCount(in items: [TranscriptItem]) -> Int {
        for item in items {
            guard case .guidance(let presentation) = item,
                  let count = presentation.omittedEarlierCount
            else { continue }
            return count
        }
        return 0
    }

    private static func removeOmissionMarker(from items: inout [TranscriptItem]) {
        items.removeAll { item in
            guard case .guidance(let guidance) = item else { return false }
            return guidance.omittedEarlierCount != nil
        }
    }
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
        if isUserAttributedDeveloperInMemoryFileProjection(message) {
            return inMemoryReferencedFilePresentation(id: id, message: message)
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
                lineLimit: GuidanceLimits.previewLineLimit),
            reconcileFingerprint: GuidanceReconcileFingerprint.digest(
                kind: .advisor,
                message: message,
                source: source))
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
                lineLimit: GuidanceLimits.previewLineLimit),
            reconcileFingerprint: GuidanceReconcileFingerprint.digest(
                kind: .agentGuidance,
                message: message,
                source: source))
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
        let fingerprintSource = referencedFileSource(from: message)
        return GuidancePresentation(
            id: id,
            kind: .referencedFile,
            visibility: .always,
            byteCount: byteCount,
            preview: BoundaryText.preview(
                previewSource,
                byteLimit: GuidanceLimits.previewByteLimit,
                lineLimit: GuidanceLimits.previewLineLimit),
            reconcileFingerprint: GuidanceReconcileFingerprint.digest(
                kind: .referencedFile,
                message: message,
                source: fingerprintSource))
    }

    private static func isUserAttributedDeveloperFileReference(_ message: JSONValue) -> Bool {
        message["role"]?.stringValue == "developer"
            && message["attribution"]?.stringValue == "user"
            && !(message["files"]?.arrayValue ?? []).isEmpty
    }

    private static func isUserAttributedDeveloperInMemoryFileProjection(_ message: JSONValue) -> Bool {
        message["role"]?.stringValue == "developer"
            && message["attribution"]?.stringValue == "user"
            && (message["files"]?.arrayValue ?? []).isEmpty
    }

    private static func inMemoryReferencedFilePresentation(
        id: String,
        message: JSONValue
    ) -> GuidancePresentation? {
        let source = plainText(from: message["content"])
        guard !source.isEmpty else { return nil }
        return GuidancePresentation(
            id: id,
            kind: .referencedFile,
            visibility: .always,
            byteCount: Data(source.utf8).count,
            preview: "",
            reconcileFingerprint: GuidanceReconcileFingerprint.digest(
                kind: .referencedFile,
                message: message,
                source: source))
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

    private static func referencedFileSource(from message: JSONValue) -> String {
        let files = message["files"]?.arrayValue ?? []
        return files.map { file -> String in
            let path = file["path"]?.stringValue ?? ""
            let content = plainText(from: file["content"])
            return "\(path)\u{1F}\(content)"
        }.sorted().joined(separator: "\n")
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

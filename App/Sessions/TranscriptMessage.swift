import Foundation
import OmpKit

enum TranscriptMessageRole: String, Equatable, Sendable {
    case user
    case assistant
    case other
}

struct TranscriptResponseAttribution: Equatable, Sendable {
    let provider: String?
    let model: String?
    let mode: String?
    let agent: String?
    let modelRole: String?

    static let none = TranscriptResponseAttribution(
        provider: nil,
        model: nil,
        mode: nil,
        agent: nil,
        modelRole: nil)
}

struct TranscriptMessage: Identifiable, Equatable, Sendable {
    let id: String
    let role: TranscriptMessageRole
    let raw: JSONValue
    let timestamp: Date?
    let attribution: TranscriptResponseAttribution
    let isFinal: Bool
    let showsResponseMetadata: Bool
    let stopReason: String?
    let document: ContentDocument

    var visibleText: String {
        document.source
    }

    init(
        id: String,
        raw: JSONValue,
        timestamp: Date? = nil,
        attribution: TranscriptResponseAttribution = .none,
        isFinal: Bool,
        showsResponseMetadata: Bool = true,
        previousDocument: ContentDocument? = nil
    ) {
        self.id = id
        let rawRole = raw["role"]?.stringValue
        role = switch rawRole {
        case "user": .user
        case "assistant": .assistant
        default: .other
        }
        self.raw = raw
        self.timestamp = Self.messageDate(raw) ?? timestamp
        self.attribution = TranscriptResponseAttribution(
            provider: raw["provider"]?.stringValue ?? attribution.provider,
            model: raw["model"]?.stringValue ?? attribution.model,
            mode: attribution.mode,
            agent: attribution.agent,
            modelRole: attribution.modelRole)
        self.isFinal = isFinal
        self.showsResponseMetadata = showsResponseMetadata
        stopReason = raw["stopReason"]?.stringValue
        let normalizedDocument = Self.contentDocument(from: raw)
        let displayText: String
        if !normalizedDocument.source.isEmpty {
            displayText = normalizedDocument.source
        } else if let errorMessage = raw["errorMessage"]?.stringValue,
                  !errorMessage.isEmpty {
            displayText = errorMessage
        } else {
            displayText = switch stopReason?.lowercased() {
            case "error": "Response failed."
            case "aborted": "Response aborted."
            default: ""
            }
        }
        // Keyed on blocks, not source: an image-only message has parsed content
        // and no text, and re-parsing would throw the image away.
        let candidateDocument = normalizedDocument.blocks.isEmpty
            ? MessageContentParser.parse(displayText)
            : normalizedDocument
        document = previousDocument.map(candidateDocument.assigningRenderLineage(after:))
            ?? candidateDocument
    }

    /// omp injects steering text into the run as `custom` / `hookMessage`
    /// entries. Its own client renders one only when the message asks to be
    /// shown, and the rest are context for the model, not conversation. Without
    /// this gate they land in the transcript as walls of instruction the user
    /// never wrote.
    nonisolated static func isDisplayable(_ raw: JSONValue) -> Bool {
        switch raw["role"]?.stringValue {
        case "custom", "hookMessage":
            return raw["display"]?.boolValue == true
        default:
            return true
        }
    }

    static func visibleText(from message: JSONValue) -> String {
        contentDocument(from: message).source
    }

    private static func contentDocument(from message: JSONValue) -> ContentDocument {
        guard let content = message["content"] else { return .empty }
        if let source = content.stringValue {
            return MessageContentParser.parse(source)
        }
        guard let contentBlocks = content.arrayValue else { return .empty }

        var blocks: [ContentBlock] = []
        var sourceParts: [String] = []
        for contentBlock in contentBlocks {
            if let source = contentBlock.stringValue {
                let document = MessageContentParser.parse(source)
                blocks.append(contentsOf: document.blocks)
                sourceParts.append(source)
                continue
            }

            let type = contentBlock["type"]?.stringValue?.lowercased()
            if type == "text", let source = contentBlock["text"]?.stringValue {
                let document = MessageContentParser.parse(source)
                blocks.append(contentsOf: document.blocks)
                sourceParts.append(source)
            } else if type == "image", let image = imageContent(contentBlock) {
                // Deliberately not added to `sourceParts`: the label is a
                // stand-in for a picture, not text the user wrote, and it would
                // otherwise show up as a line inside their message bubble.
                blocks.append(.image(image))
            } else if let type, isPrivateOrToolContent(type) {
                continue
            } else {
                let label = unsupportedLabel(for: contentBlock, type: type)
                blocks.append(.unsupported(label: label))
                sourceParts.append(label)
            }
        }
        return ContentDocument(
            source: sourceParts.joined(separator: "\n"),
            blocks: blocks)
    }

    private static func imageContent(_ block: JSONValue) -> ContentImage? {
        guard let encoded = block["data"]?.stringValue,
              let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
              !data.isEmpty
        else { return nil }
        return ContentImage(
            data: data,
            mimeType: block["mimeType"]?.stringValue ?? "image/png")
    }

    private static func isPrivateOrToolContent(_ type: String) -> Bool {
        let compactType = type.filter(\.isLetter)
        return compactType == "analysis"
            || compactType.contains("thinking")
            || compactType.contains("reasoning")
            || compactType.contains("toolcall")
            || compactType.contains("tooluse")
            || compactType.contains("toolresult")
    }

    private static func unsupportedLabel(for block: JSONValue, type: String?) -> String {
        switch type {
        case "image":
            return "Image attachment"
        case "audio":
            return "Audio attachment"
        case "resource", "resource_link":
            let name = block["name"]?.stringValue ?? block["title"]?.stringValue
            return name.map { "Resource attachment: \($0)" } ?? "Resource attachment"
        case .some(let type):
            return "Unsupported \(type.replacingOccurrences(of: "_", with: " ")) content"
        case nil:
            return "Unsupported message content"
        }
    }

    static func messageDate(_ message: JSONValue) -> Date? {
        guard let milliseconds = message["timestamp"]?.doubleValue else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }
}

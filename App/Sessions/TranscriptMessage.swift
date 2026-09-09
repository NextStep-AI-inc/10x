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

struct TranscriptRenderLineageKey: Hashable, Sendable {
    let baseMessageID: String
    let precedingToolCallID: String?
    let followingToolCallID: String?

    static func base(messageID: String) -> Self {
        Self(
            baseMessageID: messageID,
            precedingToolCallID: nil,
            followingToolCallID: nil)
    }
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
    /// Renderer continuity metadata, deliberately excluded from semantic equality.
    let renderLineageKey: TranscriptRenderLineageKey

    var visibleText: String {
        document.source
    }

    func settledAfterStop(at date: Date) -> Self {
        guard role == .assistant, !isFinal, var raw = raw.objectValue else { return self }
        raw["stopReason"] = .string("aborted")
        raw["completedAt"] = .double(date.timeIntervalSince1970 * 1_000)
        return Self(
            id: id,
            role: role,
            raw: .object(raw),
            timestamp: timestamp,
            attribution: attribution,
            isFinal: true,
            showsResponseMetadata: showsResponseMetadata,
            stopReason: "aborted",
            document: document,
            renderLineageKey: renderLineageKey)
    }

    init(
        id: String,
        raw: JSONValue,
        timestamp: Date? = nil,
        attribution: TranscriptResponseAttribution = .none,
        isFinal: Bool,
        showsResponseMetadata: Bool = true,
        renderLineageKey: TranscriptRenderLineageKey? = nil,
        previousDocument: ContentDocument? = nil
    ) {
        self.id = id
        self.renderLineageKey = renderLineageKey ?? .base(messageID: id)
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
        let parsedDocument = Self.advisorDocument(from: raw) ?? Self.contentDocument(from: raw)
        let normalizedDocument = role == .other
            && raw["customType"]?.stringValue != "skill-prompt"
            ? Self.boundingHarnessDocument(parsedDocument)
            : parsedDocument
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

    private init(
        id: String,
        role: TranscriptMessageRole,
        raw: JSONValue,
        timestamp: Date?,
        attribution: TranscriptResponseAttribution,
        isFinal: Bool,
        showsResponseMetadata: Bool,
        stopReason: String?,
        document: ContentDocument,
        renderLineageKey: TranscriptRenderLineageKey
    ) {
        self.id = id
        self.role = role
        self.raw = raw
        self.timestamp = timestamp
        self.attribution = attribution
        self.isFinal = isFinal
        self.showsResponseMetadata = showsResponseMetadata
        self.stopReason = stopReason
        self.document = document
        self.renderLineageKey = renderLineageKey
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.role == rhs.role
            && lhs.raw == rhs.raw
            && lhs.timestamp == rhs.timestamp
            && lhs.attribution == rhs.attribution
            && lhs.isFinal == rhs.isFinal
            && lhs.showsResponseMetadata == rhs.showsResponseMetadata
            && lhs.stopReason == rhs.stopReason
            && lhs.document == rhs.document
    }

    /// Conversation roles render; `toolResult` must pass so the live pipeline
    /// can route it onto its tool card. omp injects steering text into the run
    /// as `custom` / `hookMessage` entries, and its own client renders one only
    /// when the message asks to be shown. Everything else — `developer`
    /// instruction walls, `fileMention` payloads, execution records, and any
    /// role a future omp adds — is context for the model, not conversation.
    /// Without this gate those land in the transcript as walls of text the
    /// user never wrote.
    nonisolated static func isDisplayable(_ raw: JSONValue) -> Bool {
        switch raw["role"]?.stringValue {
        case "user", "assistant", "toolResult":
            return true
        case "custom", "hookMessage":
            return raw["display"]?.boolValue == true
        default:
            return false
        }
    }

    /// Opted-in harness messages (`display: true` customs) can still carry
    /// multi-KB model-facing dumps — a 10 KB job-result envelope renders as one
    /// giant selectable `Text` and stalls layout. The transcript shows a
    /// bounded prefix; the full text stays in the session file.
    // ponytail: the cap flattens to source text, so image blocks inside a huge
    // custom message would be dropped with it — none exist in the wild; the
    // upgrade path is per-block budgeting.
    private static let harnessTextLimit = 4_000

    private static func boundingHarnessDocument(_ document: ContentDocument) -> ContentDocument {
        guard document.source.count > harnessTextLimit else { return document }
        return MessageContentParser.parse(
            String(document.source.prefix(harnessTextLimit)) + "\n…")
    }

    static func visibleText(from message: JSONValue) -> String {
        (advisorDocument(from: message) ?? contentDocument(from: message)).source
    }

    /// omp's advisor emits `custom` messages whose `content` is the model-facing
    /// `<advisory>` XML envelope; the note meant for display is structured in
    /// `details.notes`. Rendering the envelope leaks raw markup into the chat,
    /// and a large one stalls text layout.
    private static func advisorDocument(from message: JSONValue) -> ContentDocument? {
        guard message["customType"]?.stringValue == "advisor" else { return nil }
        let notes = (message["details"]?["notes"]?.arrayValue ?? [])
            .compactMap { $0["note"]?.stringValue }
            .filter { !$0.isEmpty }
        if !notes.isEmpty {
            return MessageContentParser.parse(notes.joined(separator: "\n"))
        }
        let content = message["content"]?.stringValue ?? ""
        return MessageContentParser.parse(strippingAdvisoryEnvelope(from: content))
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
    }

    static func advisoryContent(from message: JSONValue) -> AdvisoryContentParser.Result? {
        guard let content = message["content"] else { return nil }
        if let source = content.stringValue {
            return AdvisoryContentParser.parseSuffix(in: source)
        }
        guard let contentBlocks = content.arrayValue else { return nil }
        let source = contentBlocks.compactMap { block -> String? in
            if let source = block.stringValue { return source }
            guard block["type"]?.stringValue?.lowercased() == "text" else { return nil }
            return block["text"]?.stringValue
        }.joined(separator: "\n")
        return AdvisoryContentParser.parseSuffix(in: source)
    }

    private static func contentDocument(from message: JSONValue) -> ContentDocument {
        guard let content = message["content"] else { return .empty }
        if let source = content.stringValue {
            return displayDocument(for: source)
        }
        guard let contentBlocks = content.arrayValue else { return .empty }

        var blocks: [ContentBlock] = []
        var sourceParts: [String] = []
        for contentBlock in contentBlocks {
            if let source = contentBlock.stringValue {
                let document = displayDocument(for: source)
                blocks.append(contentsOf: document.blocks)
                sourceParts.append(document.source)
                continue
            }

            let type = contentBlock["type"]?.stringValue?.lowercased()
            if type == "text", let source = contentBlock["text"]?.stringValue {
                let document = displayDocument(for: source)
                blocks.append(contentsOf: document.blocks)
                sourceParts.append(document.source)
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

    private static func displayDocument(for source: String) -> ContentDocument {
        guard let advisory = AdvisoryContentParser.parseSuffix(in: source) else {
            return MessageContentParser.parse(source)
        }
        let display = MessageContentParser.parse(advisory.displaySource)
        return display
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
            || compactType == "fallback"
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

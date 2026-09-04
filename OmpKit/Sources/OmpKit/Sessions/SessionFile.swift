import Foundation

public enum SessionFileError: Error, Sendable, Equatable {
    case invalidHeader
    case empty
}

public struct ParsedSessionFile: Sendable, Equatable {
    public let header: SessionHeader
    public let entries: [SessionEntry]
    /// Lines that were not valid JSON. omp appends line-at-a-time, so a crash
    /// can leave a partial final line; skipping is the documented behavior.
    public let malformedLineCount: Int

    public init(header: SessionHeader, entries: [SessionEntry], malformedLineCount: Int) {
        self.header = header
        self.entries = entries
        self.malformedLineCount = malformedLineCount
    }
}

/// Reads omp's session JSONL format.
///
/// Layout: an optional 256-byte title slot, then the session header, then one
/// entry per line. Parsing is deliberately lenient about entry content and
/// strict only about the header, matching omp's own loader.
public enum SessionFileParser {
    public static let titleSlotBytes = 256
    public static let currentSessionVersion = 3
    public static let listPrefixBytes = 4096

    public static func parse(data: Data) throws -> ParsedSessionFile {
        try Task.checkCancellation()
        guard !data.isEmpty else { throw SessionFileError.empty }
        let lines = try splitLines(data)
        guard !lines.isEmpty else { throw SessionFileError.empty }

        var index = 0
        var slot: SessionTitleSlot?
        if let candidate = decodeObject(lines[0]), let parsed = titleSlot(from: candidate) {
            slot = parsed
            index = 1
        }

        guard index < lines.count, let headerObject = decodeObject(lines[index]),
              let header = sessionHeader(from: headerObject, slot: slot)
        else {
            throw SessionFileError.invalidHeader
        }
        index += 1

        var entries: [SessionEntry] = []
        var malformed = 0
        // v1 files predate entry ids; omp synthesizes a straight chain in file
        // order so the tree walk has something to follow.
        let needsSyntheticIds = header.version == nil
        var previousId: String?

        for (offset, line) in lines[index...].enumerated() {
            if offset.isMultiple(of: 64) { try Task.checkCancellation() }
            guard let object = decodeObject(line), let type = object["type"]?.stringValue else {
                malformed += 1
                continue
            }
            let base: SessionEntryBase
            if needsSyntheticIds {
                let syntheticId = object["id"]?.stringValue
                    ?? String(format: "gen-%06d", entries.count)
                base = SessionEntryBase(
                    id: syntheticId,
                    parentId: object["parentId"]?.stringValue ?? previousId,
                    timestamp: object["timestamp"]?.stringValue ?? "")
                previousId = syntheticId
            } else {
                guard let id = object["id"]?.stringValue else {
                    malformed += 1
                    continue
                }
                base = SessionEntryBase(
                    id: id,
                    parentId: object["parentId"]?.stringValue,
                    timestamp: object["timestamp"]?.stringValue ?? "")
            }
            var parsedEntry = entry(type: type, base: base, object: object, raw: .object(object))
            if needsSyntheticIds,
               case .compaction(let compactionBase, let compaction) = parsedEntry,
               let sourceIndex = object["firstKeptEntryIndex"]?.intValue {
                // v1 indices address the complete JSONL array, including the
                // session header at index zero. Parsed entries omit that line.
                let entryIndex = sourceIndex - 1
                if entries.indices.contains(entryIndex) {
                    parsedEntry = .compaction(
                        base: compactionBase,
                        value: SessionCompaction(
                            summary: compaction.summary,
                            shortSummary: compaction.shortSummary,
                            firstKeptEntryId: entries[entryIndex].base.id,
                            tokensBefore: compaction.tokensBefore,
                            tokensAfter: compaction.tokensAfter,
                            method: compaction.method,
                            warning: compaction.warning))
                }
            }
            entries.append(parsedEntry)
        }

        try Task.checkCancellation()

        return ParsedSessionFile(
            header: header, entries: entries, malformedLineCount: malformed)
    }

    /// Metadata-only parse for listing: reads just the slot and header out of a
    /// file prefix, so listing never loads whole transcripts.
    public static func parseHeader(
        prefix: Data
    ) throws -> (slot: SessionTitleSlot?, header: SessionHeader) {
        guard !prefix.isEmpty else { throw SessionFileError.empty }
        let lines = try splitLines(prefix)
        guard !lines.isEmpty else { throw SessionFileError.empty }

        var index = 0
        var slot: SessionTitleSlot?
        if let candidate = decodeObject(lines[0]), let parsed = titleSlot(from: candidate) {
            slot = parsed
            index = 1
        }
        guard index < lines.count else { throw SessionFileError.invalidHeader }

        if let object = decodeObject(lines[index]),
           let header = sessionHeader(from: object, slot: slot) {
            return (slot, header)
        }
        // The window may have cut the header mid-line; recover the fields we
        // need by scanning the raw text.
        if let header = salvagedHeader(from: lines[index], slot: slot) {
            return (slot, header)
        }
        throw SessionFileError.invalidHeader
    }

    // MARK: - Pieces

    private static func entry(
        type: String, base: SessionEntryBase, object: [String: JSONValue], raw: JSONValue
    ) -> SessionEntry {
        switch type {
        case "message":
            return .message(base: base, message: object["message"] ?? .null)
        case "model_change":
            return .modelChange(
                base: base,
                selection: SessionModelSelection(
                    model: object["model"]?.stringValue ?? "",
                    role: object["role"]?.stringValue,
                    resolvedModelIsFallback: object["resolvedModelIsFallback"]?.boolValue == true))
        case "thinking_level_change":
            return .thinkingLevelChange(
                base: base,
                selection: SessionThinkingSelection(
                    effective: object["thinkingLevel"]?.stringValue,
                    configured: object["configured"]?.stringValue))
        case "compaction":
            return .compaction(
                base: base,
                value: SessionCompaction(
                    summary: object["summary"]?.stringValue ?? "",
                    shortSummary: object["shortSummary"]?.stringValue,
                    firstKeptEntryId: object["firstKeptEntryId"]?.stringValue ?? "",
                    tokensBefore: object["tokensBefore"]?.intValue,
                    tokensAfter: object["tokensAfter"]?.intValue,
                    method: object["method"]?.stringValue,
                    warning: object["warning"]?.stringValue))
        case "branch_summary":
            return .branchSummary(
                base: base,
                value: SessionBranchSummary(
                    fromId: object["fromId"]?.stringValue ?? "",
                    summary: object["summary"]?.stringValue ?? ""))
        case "mode_change":
            return .modeChange(
                base: base,
                selection: SessionModeSelection(
                    mode: object["mode"]?.stringValue ?? "none",
                    data: object["data"]))
        case "session_init":
            return .sessionInit(
                base: base,
                metadata: SessionInitMetadata(
                    task: object["task"]?.stringValue ?? "",
                    agent: object["agent"]?.stringValue,
                    modelRole: object["modelRole"]?.stringValue,
                    resolvedModel: object["resolvedModel"]?.stringValue,
                    isReadOnly: object["readOnly"]?.boolValue == true,
                    advisor: object["advisor"]?.stringValue))
        case "label":
            return .labelEntry(
                base: base,
                targetId: object["targetId"]?.stringValue ?? "",
                label: object["label"]?.stringValue)
        case "reset_boundary":
            return .resetBoundary(base: base)
        default:
            return .unknown(type: type, base: base, raw: raw)
        }
    }

    private static func titleSlot(from object: [String: JSONValue]) -> SessionTitleSlot? {
        guard object["type"]?.stringValue == "title",
              object["v"]?.intValue == 1,
              let title = object["title"]?.stringValue,
              let updatedAt = object["updatedAt"]?.stringValue,
              object["pad"]?.stringValue != nil
        else { return nil }
        return SessionTitleSlot(
            title: title, source: object["source"]?.stringValue, updatedAt: updatedAt)
    }

    private static func sessionHeader(
        from object: [String: JSONValue], slot: SessionTitleSlot?
    ) -> SessionHeader? {
        guard object["type"]?.stringValue == "session",
              let id = object["id"]?.stringValue, !id.isEmpty
        else { return nil }
        let folded = foldedTitle(headerTitle: object["title"]?.stringValue, slot: slot)
        return SessionHeader(
            id: id,
            cwd: object["cwd"]?.stringValue ?? "",
            timestamp: object["timestamp"]?.stringValue ?? "",
            version: object["version"]?.intValue,
            title: folded.title,
            // A cleared title has no source; keeping the header's would describe
            // a title that no longer exists.
            titleSource: folded.title == nil
                ? nil : (folded.source ?? object["titleSource"]?.stringValue),
            parentSession: object["parentSession"]?.stringValue)
    }

    /// The slot is authoritative over the header's copy of the title, including
    /// when it is empty — that means the title was cleared.
    private static func foldedTitle(
        headerTitle: String?, slot: SessionTitleSlot?
    ) -> (title: String?, source: String?) {
        guard let slot else { return (headerTitle, nil) }
        return slot.title.isEmpty ? (nil, nil) : (slot.title, slot.source)
    }

    private static func salvagedHeader(
        from line: Data, slot: SessionTitleSlot?
    ) -> SessionHeader? {
        let text = String(decoding: line, as: UTF8.self)
        guard text.contains("\"type\":\"session\"") || text.contains("\"type\": \"session\"") else {
            return nil
        }
        guard let id = stringProperty("id", in: text), !id.isEmpty else { return nil }
        let folded = foldedTitle(headerTitle: stringProperty("title", in: text), slot: slot)
        return SessionHeader(
            id: id,
            cwd: stringProperty("cwd", in: text) ?? "",
            timestamp: stringProperty("timestamp", in: text) ?? "",
            version: intProperty("version", in: text),
            title: folded.title,
            titleSource: folded.title == nil
                ? nil : (folded.source ?? stringProperty("titleSource", in: text)),
            parentSession: stringProperty("parentSession", in: text))
    }

    private static func stringProperty(_ key: String, in text: String) -> String? {
        guard let range = text.range(of: "\"\(key)\":\"") ?? text.range(of: "\"\(key)\": \"") else {
            return nil
        }
        let rest = text[range.upperBound...]
        var value = ""
        var escaped = false
        for character in rest {
            if escaped {
                value.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                return value
            } else {
                value.append(character)
            }
        }
        return nil
    }

    private static func intProperty(_ key: String, in text: String) -> Int? {
        guard let range = text.range(of: "\"\(key)\":") else {
            return nil
        }
        let digits = text[range.upperBound...]
            .drop(while: { $0.isWhitespace })
            .prefix { $0.isNumber }
        return Int(digits)
    }

    private static func splitLines(_ data: Data) throws -> [Data] {
        var lines: [Data] = []
        for (index, slice) in data.split(
            separator: UInt8(ascii: "\n"),
            omittingEmptySubsequences: false
        ).enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            let line = slice.last == UInt8(ascii: "\r") ? Data(slice.dropLast()) : Data(slice)
            if !line.isEmpty { lines.append(line) }
        }
        try Task.checkCancellation()
        return lines
    }

    private static func decodeObject(_ line: Data) -> [String: JSONValue]? {
        guard let value = try? JSONValue.decode(from: line) else { return nil }
        return value.objectValue
    }
}

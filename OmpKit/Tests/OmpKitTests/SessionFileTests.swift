import Testing
import Foundation
@testable import OmpKit

/// Builds omp's fixed-width first line: the JSON plus its newline is exactly
/// 256 bytes, space-padded via `pad`.
func makeTitleSlotLine(title: String) -> String {
    var pad = ""
    while true {
        let line = #"{"type":"title","v":1,"title":"\#(title)","source":"auto","updatedAt":"2026-07-01T23:07:41.244Z","pad":"\#(pad)"}"#
        let bytes = line.utf8.count + 1  // +1 for the newline
        if bytes == 256 { return line }
        precondition(bytes < 256, "title too long for the slot")
        pad += " "
    }
}

func fixtureSessionV3(title: String = "Fixture") -> Data {
    let body = try! String(contentsOf: fixtureURL("session_v3.jsonl"), encoding: .utf8)
    return Data((makeTitleSlotLine(title: title) + "\n" + body).utf8)
}

@Test func titleSlotIsExactly256Bytes() {
    #expect(makeTitleSlotLine(title: "Fixture").utf8.count + 1 == 256)
}

@Test func parsesV3FileWithSlot() throws {
    let parsed = try SessionFileParser.parse(data: fixtureSessionV3())
    #expect(parsed.header.id == "019f1feb-011a-7000-8ccc-3b1d8e69df68")
    #expect(parsed.header.cwd == "/tmp")
    #expect(parsed.header.title == "Fixture")            // slot folded in
    #expect(parsed.header.version == 3)
    #expect(parsed.entries.count == 4)                    // unknown kept, non-JSON skipped
    #expect(parsed.malformedLineCount == 1)
    guard case .unknown(let type, _, _) = parsed.entries[2] else {
        Issue.record("expected an unknown entry"); return
    }
    #expect(type == "future_entry_kind")
}

@Test func headerOnlyParseFromPrefix() throws {
    let (slot, header) = try SessionFileParser.parseHeader(
        prefix: fixtureSessionV3().prefix(4096))
    #expect(slot?.title == "Fixture")
    #expect(header.cwd == "/tmp")
    #expect(header.id == "019f1feb-011a-7000-8ccc-3b1d8e69df68")
}

@Test func emptySlotTitleClearsHeaderTitle() throws {
    let withTitle = #"{"type":"session","version":3,"id":"x","timestamp":"t","cwd":"/c","title":"stale"}"#
    let data = Data((makeTitleSlotLine(title: "") + "\n" + withTitle + "\n").utf8)
    let parsed = try SessionFileParser.parse(data: data)
    #expect(parsed.header.title == nil)   // an empty slot deletes the header title
}

@Test func headerTitleSurvivesWhenNoSlotPresent() throws {
    let data = Data((#"{"type":"session","version":3,"id":"x","timestamp":"t","cwd":"/c","title":"kept"}"# + "\n").utf8)
    let parsed = try SessionFileParser.parse(data: data)
    #expect(parsed.header.title == "kept")
}

@Test func v1FileGetsSyntheticIdChain() throws {
    let v1 = Data("""
    {"type":"session","id":"old","timestamp":"2025-01-01T00:00:00Z","cwd":"/x"}
    {"type":"message","timestamp":"2025-01-01T00:01:00Z","message":{"role":"user","content":"a"}}
    {"type":"message","timestamp":"2025-01-01T00:02:00Z","message":{"role":"assistant","content":"b"}}
    """.utf8)
    let parsed = try SessionFileParser.parse(data: v1)
    #expect(parsed.header.version == nil)
    #expect(parsed.entries.count == 2)
    #expect(parsed.entries[0].base.parentId == nil)
    #expect(parsed.entries[1].base.parentId == parsed.entries[0].base.id)
}

@Test func nonSessionFirstEntryIsInvalid() {
    #expect(throws: SessionFileError.invalidHeader) {
        _ = try SessionFileParser.parse(data: Data(#"{"type":"message","id":"x"}"#.utf8))
    }
}

@Test func emptyFileThrows() {
    #expect(throws: SessionFileError.self) { _ = try SessionFileParser.parse(data: Data()) }
}

@Test func typedEntriesCarryTheirPayloads() throws {
    let parsed = try SessionFileParser.parse(data: fixtureSessionV3())
    guard case .modelChange(_, let model) = parsed.entries[0] else {
        Issue.record("expected a model change"); return
    }
    #expect(model == "anthropic/claude-opus-4-8")

    guard case .message(let base, let message) = parsed.entries[1] else {
        Issue.record("expected a message"); return
    }
    #expect(base.id == "aa11bb22")
    #expect(message["role"]?.stringValue == "user")
}

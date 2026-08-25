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
    let withTitle = #"{"type":"session","version":3,"id":"x","timestamp":"t","cwd":"/c","title":"stale","titleSource":"auto"}"#
    let data = Data((makeTitleSlotLine(title: "") + "\n" + withTitle + "\n").utf8)
    let parsed = try SessionFileParser.parse(data: data)
    #expect(parsed.header.title == nil)   // an empty slot deletes the header title
    #expect(parsed.header.titleSource == nil)
}

@Test func v1CompactionIndexMigratesToSyntheticEntryId() throws {
    let v1 = Data("""
    {"type":"session","id":"old","timestamp":"t","cwd":"/x"}
    {"type":"message","timestamp":"t1","message":{"role":"user","content":"a"}}
    {"type":"message","timestamp":"t2","message":{"role":"assistant","content":"b"}}
    {"type":"compaction","timestamp":"t3","summary":"summary","firstKeptEntryIndex":1}
    """.utf8)
    let parsed = try SessionFileParser.parse(data: v1)
    guard case .compaction(_, let compaction) = parsed.entries[2] else {
        Issue.record("expected compaction"); return
    }
    #expect(compaction.firstKeptEntryId == parsed.entries[0].base.id)
}

@Test func salvagesAHeaderCutMidLine() throws {
    let history = String(repeating: #""/a/very/long/previous/session/file","#, count: 200)
    let header = #"{"type":"session","id":"long","cwd":"/tmp/a\"b","timestamp":"t","version": 3,"previousSessionFiles":["#
        + history
    let (_, parsed) = try SessionFileParser.parseHeader(prefix: Data(header.utf8).prefix(4096))
    #expect(parsed.id == "long")
    #expect(parsed.cwd == #"/tmp/a"b"#)
    #expect(parsed.version == 3)
}

@Test func truncatedHeaderWithoutAnIdIsRejected() {
    let prefix = Data((#"{"type":"session","padding":""# + String(repeating: "x", count: 5000)).utf8)
        .prefix(4096)
    #expect(throws: SessionFileError.invalidHeader) {
        _ = try SessionFileParser.parseHeader(prefix: prefix)
    }
}

@Test func loneSurrogateDoesNotDropAnInteriorSessionEntry() throws {
    let data = Data(#"""
    {"type":"session","version":3,"id":"s","timestamp":"t","cwd":"/x"}
    {"type":"message","id":"a","parentId":null,"timestamp":"t1","message":{"role":"user","content":"before"}}
    {"type":"message","id":"b","parentId":"a","timestamp":"t2","message":{"role":"assistant","content":"bad \uD800 text"}}
    {"type":"message","id":"c","parentId":"b","timestamp":"t3","message":{"role":"user","content":"after"}}
    """#.utf8)
    let parsed = try SessionFileParser.parse(data: data)
    #expect(parsed.entries.count == 3)
    #expect(SessionTree.activePath(of: parsed).map(\.base.id) == ["a", "b", "c"])
    guard case .message(_, let message) = parsed.entries[1] else {
        Issue.record("expected message"); return
    }
    #expect(message["content"]?.stringValue == "bad � text")
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
    guard case .modelChange(_, let selection) = parsed.entries[0] else {
        Issue.record("expected a model change"); return
    }
    #expect(selection.model == "anthropic/claude-opus-4-8")

    guard case .message(let base, let message) = parsed.entries[1] else {
        Issue.record("expected a message"); return
    }
    #expect(base.id == "aa11bb22")
    #expect(message["role"]?.stringValue == "user")
}

@Test func parsesDisplaySafeTimelineMetadata() throws {
    let data = Data(#"""
    {"type":"session","version":3,"id":"s","timestamp":"2026-08-24T20:00:00Z","cwd":"/x"}
    {"type":"model_change","id":"a","parentId":null,"timestamp":"2026-08-24T20:00:01Z","model":"openai-codex/gpt-5.6-sol","role":"temporary","resolvedModelIsFallback":true}
    {"type":"thinking_level_change","id":"b","parentId":"a","timestamp":"2026-08-24T20:00:02Z","thinkingLevel":"high","configured":"auto"}
    {"type":"mode_change","id":"c","parentId":"b","timestamp":"2026-08-24T20:00:03Z","mode":"plan","data":{"planFilePath":"/tmp/plan.md"}}
    {"type":"session_init","id":"d","parentId":"c","timestamp":"2026-08-24T20:00:04Z","systemPrompt":"must stay private","task":"Review transcript","tools":["read"],"agent":"reviewer","modelRole":"review","resolvedModel":"anthropic/claude-opus-4-8","readOnly":true,"advisor":"product"}
    {"type":"branch_summary","id":"e","parentId":"d","timestamp":"2026-08-24T20:00:05Z","fromId":"a","summary":"Earlier work"}
    {"type":"compaction","id":"f","parentId":"e","timestamp":"2026-08-24T20:00:06Z","summary":"Compact work","shortSummary":"Work","firstKeptEntryId":"c","tokensBefore":4000,"tokensAfter":900,"method":"snapcompact","warning":"Near limit"}
    """#.utf8)

    let entries = try SessionFileParser.parse(data: data).entries

    guard case .modelChange(_, let model) = entries[0] else {
        Issue.record("expected model metadata"); return
    }
    #expect(model.model == "openai-codex/gpt-5.6-sol")
    #expect(model.role == "temporary")
    #expect(model.resolvedModelIsFallback)

    guard case .thinkingLevelChange(_, let thinking) = entries[1] else {
        Issue.record("expected thinking metadata"); return
    }
    #expect(thinking.effective == "high")
    #expect(thinking.configured == "auto")

    guard case .modeChange(_, let mode) = entries[2] else {
        Issue.record("expected mode metadata"); return
    }
    #expect(mode.mode == "plan")
    #expect(mode.data?["planFilePath"]?.stringValue == "/tmp/plan.md")

    guard case .sessionInit(_, let metadata) = entries[3] else {
        Issue.record("expected session init metadata"); return
    }
    #expect(metadata.task == "Review transcript")
    #expect(metadata.agent == "reviewer")
    #expect(metadata.resolvedModel == "anthropic/claude-opus-4-8")
    #expect(metadata.isReadOnly)
    #expect(metadata.advisor == "product")

    guard case .branchSummary(_, let branch) = entries[4] else {
        Issue.record("expected branch summary"); return
    }
    #expect(branch.fromId == "a")
    #expect(branch.summary == "Earlier work")

    guard case .compaction(_, let compaction) = entries[5] else {
        Issue.record("expected compaction metadata"); return
    }
    #expect(compaction.shortSummary == "Work")
    #expect(compaction.tokensBefore == 4000)
    #expect(compaction.tokensAfter == 900)
    #expect(compaction.method == "snapcompact")
    #expect(compaction.warning == "Near limit")

    let encodedEntries = String(data: data, encoding: .utf8) ?? ""
    #expect(encodedEntries.contains("must stay private"))
    #expect(!String(describing: metadata).contains("must stay private"))
}

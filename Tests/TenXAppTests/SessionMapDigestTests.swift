import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func sessionMapDigestKeepsAttentionWithinByteBudget() {
    let reads = (0..<200).map { index in
        digestEntry(
            id: "read-\(index)",
            kind: .tool,
            text: "read",
            outcome: String(repeating: "routine ", count: 30),
            fingerprint: "read-\(index)")
    }
    let assistant = digestEntry(
        id: "assistant",
        kind: .assistant,
        text: String(repeating: "🧭", count: 1_000),
        fingerprint: "assistant")
    let failure = digestEntry(
        id: "failed-tool",
        kind: .attention,
        text: "Tests failed",
        outcome: "exit 1",
        facts: ["failedTool.failed-tool": SessionMapFact(value: "test", number: nil)],
        fingerprint: "failed")
    let approval = digestEntry(
        id: "approval-1",
        kind: .attention,
        text: "Pending approval: Continue?",
        facts: ["pendingAttention.approval-1": SessionMapFact(value: "true", number: nil)],
        fingerprint: "approval")
    let entries = reads + [assistant, failure, approval]
    let source = SessionMapSource(
        sessionKey: "session",
        lineage: "lineage",
        entries: entries,
        finishedTurnIDs: ["assistant"],
        knownRefs: Set(entries.map(\.id)),
        statusEvidence: [])

    let digest = SessionMapDigestBuilder.build(source: source, scope: .wholeSession)

    #expect(digest.text.utf8.count <= 12_288)
    #expect(digest.text.contains("failed-tool"))
    #expect(digest.text.contains("approval-1"))
    #expect(digest.text.contains("[omitted]"))
    #expect(digest.facts["cost"] == nil)
    #expect(digest.knownRefs.count == entries.count)
}

@Test func sessionMapDigestIncludesChangedExistingTool() {
    let beforeSource = SessionMapSourceAdapter.make(
        items: [.tool(changedTool(output: "still running", exitCode: 0))],
        sessionKey: "session",
        lineage: "lineage")
    let afterSource = SessionMapSourceAdapter.make(
        items: [.tool(changedTool(output: "assertion failed", exitCode: 1))],
        sessionKey: "session",
        lineage: "lineage")
    let before = SessionMapDigestBuilder.build(
        source: beforeSource,
        scope: .sinceCaughtUp)
    let after = SessionMapDigestBuilder.build(
        source: afterSource,
        previousManifest: before.sourceFingerprintManifest,
        scope: .sinceCaughtUp)

    #expect(after.hash != before.hash)
    #expect(after.text.contains("tool-1"))
    #expect(after.text.contains("Exit 1"))
    #expect(after.sourceFingerprintManifest["tool-1"]
        != before.sourceFingerprintManifest["tool-1"])
}

@Test func sessionMapDigestHashIsDeterministicAndIncludesScopeAndFacts() {
    let entry = digestEntry(
        id: "u1",
        kind: .prompt,
        text: "Build it",
        facts: ["z": SessionMapFact(value: "2", number: 2)],
        fingerprint: "one")
    let source = digestSource([entry])
    let first = SessionMapDigestBuilder.build(source: source, scope: .wholeSession)
    let same = SessionMapDigestBuilder.build(source: source, scope: .wholeSession)
    let scoped = SessionMapDigestBuilder.build(source: source, scope: .sinceCaughtUp)

    #expect(first.hash == same.hash)
    #expect(first.hash != scoped.hash)
}

private func digestSource(_ entries: [SessionMapSourceEntry]) -> SessionMapSource {
    SessionMapSource(
        sessionKey: "session",
        lineage: "lineage",
        entries: entries,
        finishedTurnIDs: [],
        knownRefs: Set(entries.map(\.id)),
        statusEvidence: entries.flatMap(\.statusEvidence))
}

private func digestEntry(
    id: String,
    kind: SessionMapSourceEntry.Kind,
    text: String,
    outcome: String? = nil,
    facts: [String: SessionMapFact] = [:],
    fingerprint: String
) -> SessionMapSourceEntry {
    SessionMapSourceEntry(
        id: id,
        kind: kind,
        text: text,
        outcome: outcome,
        facts: facts,
        contentFingerprint: fingerprint)
}

private func changedTool(output: String, exitCode: Int) -> ToolPresentation {
    ToolPresentation(
        id: "tool-1",
        name: "bash",
        arguments: .object(["command": .string("swift test")]),
        result: .object(["details": .object([
            "stdout": .string(output),
            "exitCode": .int(exitCode),
        ])]),
        phase: exitCode == 0 ? .complete : .failed,
        startDate: .distantPast,
        endDate: .distantPast)
}

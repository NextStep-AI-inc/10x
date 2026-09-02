import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func burstUpdatesNormalizeOnlyNewestPayloadOnManualFlush() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    _ = await processor.load(
        .history(TranscriptHistory(items: [])),
        threadStartDate: nil,
        hasReconciliationWarning: false,
        runtimeState: .idle)

    for index in 1...1_000 {
        await processor.consume(try event("""
            {"type":"message_update","message":{"id":"burst-message","role":"assistant","content":[{"type":"text","text":"token-\(index)"}]}}
            """))
    }

    #expect(await processor.testingMessageUpdateReductionCount() == 0)
    let snapshot = try #require(await processor.flush())
    #expect(await processor.testingMessageUpdateReductionCount() == 1)
    #expect(snapshot.revision == 2)
    #expect(snapshot.items.count == 1)
    #expect(snapshot.visibleText(for: "burst-message") == "token-1000")
    await processor.stop()
}

@Test func replacementUpdateReusesPendingSlotAndTimer() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    _ = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)

    await processor.consume(try event("""
        {"type":"message_update","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"First"}]}}
        """))
    let originalTimer = await processor.testingTimerGeneration()
    await processor.consume(try event("""
        {"type":"message_update","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Second"}]}}
        """))

    #expect(await processor.testingMessageUpdateReductionCount() == 0)
    #expect(await processor.testingTimerGeneration() == originalTimer)
    let snapshot = try #require(await processor.flush())
    #expect(await processor.testingMessageUpdateReductionCount() == 1)
    #expect(snapshot.visibleText(for: "m1") == "Second")
    await processor.stop()
}

@Test func differentMessageIdentitiesRemainLossless() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    _ = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)

    await processor.consume(try event("""
        {"type":"message_update","message":{"id":"skill-1","role":"custom","customType":"skill-prompt","display":true,"content":"# Skill\\n\\nComplete instructions."}}
        """))
    await processor.consume(try event("""
        {"type":"message_update","message":{"id":"assistant-1","role":"assistant","content":[{"type":"text","text":"Starting work."}]}}
        """))

    let snapshot = try #require(await processor.flush())
    let messages = snapshot.items.compactMap { item -> TranscriptMessage? in
        guard case .message(let message) = item else { return nil }
        return message
    }
    #expect(await processor.testingMessageUpdateReductionCount() == 2)
    #expect(messages.map(\.id) == ["skill-1", "assistant-1"])
    #expect(messages.map(\.visibleText) == ["# Skill\n\nComplete instructions.", "Starting work."])
    await processor.stop()
}

@Test func currentSnapshotDrainsPendingUpdateWithoutAdvancingRevision() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    let initial = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)

    await processor.consume(try event("""
        {"type":"message_update","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Current"}]}}
        """))
    let timerToken = await processor.testingTimerGeneration()
    #expect(await processor.testingMessageUpdateReductionCount() == 0)

    let current = await processor.currentSnapshot()
    #expect(current.revision == initial.revision)
    #expect(current.visibleText(for: "m1") == "Current")
    #expect(await processor.testingMessageUpdateReductionCount() == 1)

    let published = try #require(await processor.flush())
    #expect(published.revision == initial.revision + 1)
    #expect(published.visibleText(for: "m1") == "Current")
    await processor.testingPublishScheduled(token: timerToken)
    #expect(await processor.flush() == nil)
    await processor.stop()
}

@Test func reconciliationDrainsPendingUpdateBeforeApplyingHistory() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    _ = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)

    await processor.consume(try event("""
        {"type":"message_update","message":{"id":"live","role":"assistant","content":[{"type":"text","text":"Live draft"}]}}
        """))
    await processor.reconcile(
        TranscriptHistory(items: [messageItem(id: "persisted", text: "Persisted")]),
        hasWarning: false,
        generation: 1)

    let snapshot = await processor.currentSnapshot()
    #expect(await processor.testingMessageUpdateReductionCount() == 1)
    #expect(snapshot.items.map(\.id) == ["persisted", "live"])
    #expect(snapshot.visibleText(for: "live") == "Live draft")
    await processor.stop()
}

@Test func stoppingProcessorPublishesNewestPendingUpdateBeforeFinishing() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    _ = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)
    var snapshots = processor.snapshots.makeAsyncIterator()

    await processor.consume(try event("""
        {"type":"message_update","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Newest before stop"}]}}
        """))
    #expect(await processor.testingMessageUpdateReductionCount() == 0)
    await processor.stop()

    let final = try #require(await snapshots.next())
    #expect(await processor.testingMessageUpdateReductionCount() == 1)
    #expect(final.visibleText(for: "m1") == "Newest before stop")
    #expect(await snapshots.next() == nil)
}

@Test func authoritativeLoadDiscardsPreloadPendingUpdate() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    _ = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)
    await processor.consume(try event("""
        {"type":"message_update","message":{"id":"stale","role":"assistant","content":[{"type":"text","text":"Stale"}]}}
        """))

    let loaded = await processor.load(
        .history(TranscriptHistory(items: [messageItem(id: "authoritative", text: "Loaded")])),
        threadStartDate: nil,
        hasReconciliationWarning: false,
        runtimeState: .idle)

    #expect(await processor.testingMessageUpdateReductionCount() == 0)
    #expect(loaded.items.map(\.id) == ["authoritative"])
    #expect(loaded.visibleText(for: "stale") == nil)
    await processor.stop()
}

@Test func directTranscriptMutationCannotOvertakePendingUpdate() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    _ = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)
    await processor.consume(try event("""
        {"type":"message_update","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Earlier"}]}}
        """))

    await processor.appendNotice(level: "info", message: "Later")

    let snapshot = await processor.currentSnapshot()
    #expect(await processor.testingMessageUpdateReductionCount() == 1)
    #expect(snapshot.items.map(\.id) == ["thread-start-fallback", "m1", "notice-1"])
    await processor.stop()
}

@Test func coalescedPublicationNeverExceedsTwentyPerSecond() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .milliseconds(50))
    _ = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)
    let observed = PublicationTally()
    let collector = Task {
        await collectSnapshotDates(from: processor.snapshots, tally: observed)
    }
    let windowStart = Date()
    let windowEnd = windowStart.addingTimeInterval(1)
    var index = 0

    while Date() < windowEnd {
        index += 1
        await processor.consume(try event("""
            {"type":"message_update","message":{"id":"rate-message","role":"assistant","content":[{"type":"text","text":"tick-\(index)"}]}}
            """))
        try await Task.sleep(for: .milliseconds(10))
    }
    // Wait for the publisher rather than assuming it got scheduled. Its timer
    // ticks every 50ms, but on a loaded machine it can be starved past the
    // sampling window, which can leave this test asserting a rate over zero
    // publications without observing the scheduled tick.
    await observed.waitForFirstPublication()
    await processor.stop()

    let publicationDates = await collector.value
    let inWindow = publicationDates.filter { date in
        date >= windowStart && date < windowEnd
    }
    // Guards against a vacuous pass. Deliberately not `inWindow`: this test is
    // about the ceiling, and on a loaded machine the publisher can be starved
    // until just past windowEnd, which empties the window without saying
    // anything about the rate.
    #expect(!publicationDates.isEmpty)
    #expect(inWindow.count <= 20)
    #expect(index > 0)
}

@Test func immediateBoundaryFlushesBeforeControlForwarding() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    _ = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)
    var snapshots = processor.snapshots.makeAsyncIterator()
    var controls = processor.controlEvents.makeAsyncIterator()

    await processor.consume(try event("""
        {"type":"message_update","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Draft"}]}}
        """))
    await processor.consume(try event("""
        {"type":"message_end","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Final"}]}}
        """))

    let snapshot = try #require(await snapshots.next())
    #expect(await processor.testingMessageUpdateReductionCount() == 1)
    #expect(snapshot.visibleText(for: "m1") == "Final")
    guard case .event(let type, _) = try #require(await controls.next()) else {
        Issue.record("Expected message_end control event")
        return
    }
    #expect(type == "message_end")
    await processor.stop()
}

@Test func turnEndFlushesPendingCoalescedSnapshotBeforeControl() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    let initial = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)
    var snapshots = processor.snapshots.makeAsyncIterator()
    var controls = processor.controlEvents.makeAsyncIterator()

    await processor.consume(try event("""
        {"type":"message_update","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Draft"}]}}
        """))
    await processor.consume(try event("""
        {"type":"turn_end"}
        """))

    let snapshot = try #require(await snapshots.next())
    #expect(await processor.testingMessageUpdateReductionCount() == 1)
    #expect(snapshot.revision > initial.revision)
    #expect(snapshot.visibleText(for: "m1") == "Draft")
    #expect(await processor.currentSnapshot() == snapshot)
    guard case .event(let type, _) = try #require(await controls.next()) else {
        Issue.record("Expected turn_end control event")
        return
    }
    #expect(type == "turn_end")
    await processor.stop()
}

@Test func commandUpdatesForwardWithoutMutatingTheTranscript() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    let before = await processor.currentSnapshot()
    var controls = processor.controlEvents.makeAsyncIterator()

    await processor.consume(try event(#"{"type":"available_commands_update","commands":[{"name":"compact","source":"builtin"}]}"#))

    let control = try #require(await controls.next())
    let after = await processor.currentSnapshot()
    #expect(control.controlLabel == "event:available_commands_update")
    #expect(after.revision == before.revision)
    #expect(after.items == before.items)
    await processor.stop()
}

@Test func lifecycleStartsForwardAndPreserveRuntimeMutation() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    var controls = processor.controlEvents.makeAsyncIterator()

    await processor.consume(try event(#"{"type":"agent_start"}"#))
    let agentSnapshot = await processor.currentSnapshot()
    await processor.consume(try event(#"{"type":"turn_start"}"#))
    let turnSnapshot = await processor.currentSnapshot()

    #expect(try #require(await controls.next()).controlLabel == "event:agent_start")
    #expect(try #require(await controls.next()).controlLabel == "event:turn_start")
    #expect(agentSnapshot.runtimeState == .streaming)
    #expect(turnSnapshot.runtimeState == .streaming)
    #expect(agentSnapshot.items.isEmpty)
    #expect(turnSnapshot.items.isEmpty)
    await processor.stop()
}

@Test func staleTimerCompletionDoesNotCancelReplacementTimerOrPublishEarly() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    _ = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)

    await processor.consume(try event("""
        {"type":"message_update","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Draft one"}]}}
        """))
    let staleToken = await processor.testingTimerGeneration()
    await processor.consume(try event("""
        {"type":"message_end","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Final one"}]}}
        """))
    let boundarySnapshot = await processor.currentSnapshot()
    await processor.consume(try event("""
        {"type":"message_update","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Draft two"}]}}
        """))
    let dirtySnapshot = await processor.currentSnapshot()
    #expect(dirtySnapshot.revision == boundarySnapshot.revision)
    #expect(dirtySnapshot.visibleText(for: "m1") == "Draft two")

    await processor.testingPublishScheduled(token: staleToken)
    #expect(await processor.currentSnapshot() == dirtySnapshot)
    let flushed = try #require(await processor.flush())
    #expect(flushed.revision == dirtySnapshot.revision + 1)
    #expect(flushed.visibleText(for: "m1") == "Draft two")
    await processor.stop()
}

@Test func extensionAndReconciliationControlsRemainOrdered() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    _ = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)
    var controls = processor.controlEvents.makeAsyncIterator()

    await processor.consume(try extensionRequest(id: "confirm-1", method: "confirm", payload: """
        {"title":"Approve","message":"Continue?"}
        """))
    await processor.consume(try event("""
        {"type":"message_update","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Draft"}]}}
        """))
    await processor.consume(try event("""
        {"type":"message_end","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Final"}]}}
        """))
    await processor.consume(try event("""
        {"type":"prompt_result","agentInvoked":true}
        """))
    await processor.stop()

    #expect(try #require(await controls.next()).controlLabel == "extension:confirm-1")
    #expect(try #require(await controls.next()).controlLabel == "event:message_end")
    #expect(try #require(await controls.next()).controlLabel == "event:prompt_result")
    #expect(await controls.next() == nil)
}

@Test func providerAccountChangesAreLosslessControlEvents() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    let initial = await processor.load(
        .messages([]),
        threadStartDate: nil,
        hasReconciliationWarning: false,
        runtimeState: .idle)
    let collector = Task { await collectControlLabels(from: processor.controlEvents) }

    await processor.consume(.providerAccountChanged(ProviderAccountChangedEvent(
        providerID: "openai-codex",
        accountRef: "acct-a",
        reason: .manual,
        sequence: 1)))
    await processor.consume(.providerAccountChanged(ProviderAccountChangedEvent(
        providerID: "openai-codex",
        accountRef: "acct-b",
        reason: .automaticFailover,
        sequence: 2)))
    await processor.stop()

    #expect(await collector.value == [
        "provider-account:acct-a:1",
        "provider-account:acct-b:2",
    ])
    #expect(await processor.currentSnapshot() == initial)
}

@Test func olderReconciliationGenerationCannotOverwriteNewerSnapshot() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    _ = await processor.load(.history(TranscriptHistory(items: [])), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)
    var snapshots = processor.snapshots.makeAsyncIterator()

    await processor.reconcile(
        TranscriptHistory(items: [messageItem(id: "m1", text: "newer")]),
        hasWarning: false,
        generation: 2)
    let newer = try #require(await snapshots.next())

    await processor.reconcile(
        TranscriptHistory(items: [messageItem(id: "m1", text: "older")]),
        hasWarning: true,
        generation: 1)

    #expect(await processor.currentSnapshot() == newer)
    await processor.stop()
    #expect(await snapshots.next() == nil)
}

@Test func malformedToolResultMessageEndDoesNotReachControls() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    let initial = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)
    let controlCollector = Task { await collectControlLabels(from: processor.controlEvents) }
    let snapshotCollector = Task { await collectSnapshots(from: processor.snapshots) }

    await processor.consume(try event("""
        {"type":"message_end","message":{"role":"toolResult","toolName":"bash","content":[{"type":"text","text":"missing id"}],"isError":false}}
        """))
    #expect(await processor.flush() == nil)
    #expect(await processor.currentSnapshot() == initial)
    await processor.stop()

    #expect(await controlCollector.value.isEmpty)
    #expect(await snapshotCollector.value.isEmpty)
}

@Test func duplicateValidMessageEndControlsRemainLossless() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    _ = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)
    let collector = Task { await collectControlLabels(from: processor.controlEvents) }
    let toolResult = """
        {"type":"message_end","message":{"role":"toolResult","toolCallId":"t1","toolName":"bash","content":[{"type":"text","text":"done"}],"isError":false}}
        """

    await processor.consume(try event(toolResult))
    await processor.consume(try event(toolResult))
    await processor.stop()

    #expect(await collector.value == ["event:message_end", "event:message_end"])
}

@Test func malformedAndUnknownFramesProduceNoSnapshot() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    let initial = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)
    let collector = Task { await collectControlLabels(from: processor.controlEvents) }

    await processor.consume(try event("""
        {"type":"unknown_future_event","payload":{"large":"ignored"}}
        """))
    await processor.consume(try event("""
        {"type":"message_update"}
        """))
    await processor.consume(try event("""
        {"type":"tool_execution_update","toolName":"bash"}
        """))
    await processor.consume(try event("""
        {"type":"message_end"}
        """))

    #expect(await processor.flush() == nil)
    #expect(await processor.currentSnapshot() == initial)
    await processor.stop()
    #expect(await collector.value.isEmpty)
}

@Test func stoppingProcessorFinishesStreams() async throws {
    let processor = TranscriptEventProcessor()
    var snapshots = processor.snapshots.makeAsyncIterator()
    var controls = processor.controlEvents.makeAsyncIterator()

    await processor.stop()

    #expect(await snapshots.next() == nil)
    #expect(await controls.next() == nil)
}

@Test func latestSnapshotBufferDropsOnlySupersededSnapshots() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    _ = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)

    await processor.consume(try event("""
        {"type":"agent_start"}
        """))
    await processor.consume(try event("""
        {"type":"message_start","message":{"id":"m1","role":"assistant","content":[]}}
        """))
    await processor.consume(try event("""
        {"type":"message_end","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Newest"}]}}
        """))

    var snapshots = processor.snapshots.makeAsyncIterator()
    let latest = try #require(await snapshots.next())
    #expect(latest.visibleText(for: "m1") == "Newest")
    await processor.stop()
    #expect(await snapshots.next() == nil)
}

private func collectSnapshots(from stream: AsyncStream<TranscriptSnapshot>) async -> [TranscriptSnapshot] {
    var snapshots: [TranscriptSnapshot] = []
    for await snapshot in stream {
        snapshots.append(snapshot)
    }
    return snapshots
}

private func collectSnapshotDates(
    from stream: AsyncStream<TranscriptSnapshot>,
    tally: PublicationTally? = nil
) async -> [Date] {
    var dates: [Date] = []
    for await _ in stream {
        dates.append(Date())
        await tally?.record()
    }
    return dates
}

/// Lets the rate test observe that the publisher has run at least once, which
/// it cannot see from the collector task's return value until the stream ends.
private actor PublicationTally {
    private var count = 0

    func record() { count += 1 }

    func waitForFirstPublication(timeout: Duration = .seconds(30)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while count == 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private func collectControlLabels(from stream: AsyncStream<RpcFrame>) async -> [String] {
    var labels: [String] = []
    for await frame in stream {
        labels.append(frame.controlLabel)
    }
    return labels
}

private func event(_ json: String) throws -> RpcFrame {
    try RpcFrame.decode(line: Data(json.utf8))
}

private func extensionRequest(
    id: String,
    method: String,
    payload: String
) throws -> RpcFrame {
    try RpcFrame.decode(line: Data("""
        {"type":"extension_ui_request","id":"\(id)","method":"\(method)","payload":\(payload)}
        """.utf8))
}

private func messageItem(id: String, text: String) -> TranscriptItem {
    .message(TranscriptMessage(
        id: id,
        raw: .object([
            "id": .string(id),
            "role": .string("assistant"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(text),
                ]),
            ]),
            "timestamp": .double(0),
        ]),
        isFinal: true))
}

private extension TranscriptSnapshot {
    func visibleText(for id: String) -> String? {
        items.compactMap { item -> TranscriptMessage? in
            guard case .message(let message) = item, message.id == id else { return nil }
            return message
        }.first?.visibleText
    }
}

private extension RpcFrame {
    var controlLabel: String {
        switch self {
        case .extensionUIRequest(let request):
            return "extension:\(request.id)"
        case .providerAccountChanged(let event):
            return "provider-account:\(event.accountRef):\(event.sequence)"
        case .event(let type, _):
            return "event:\(type)"
        default:
            return "other"
        }
    }
}

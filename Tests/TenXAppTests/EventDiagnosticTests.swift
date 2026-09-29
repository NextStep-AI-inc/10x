import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func eventDiagnosticMakeSanitizesTypeAndMarksLowerBound() {
    let longType = String(repeating: "x", count: 120)
    var nodes: [JSONValue] = []
    for index in 0..<300 {
        nodes.append(.object([
            "key-\(index)": .string("value-\(index)"),
        ]))
    }
    let payload = JSONValue.object([
        "secret": .string("sk-live-should-never-appear"),
        "nested": .array(nodes),
    ])

    let diagnostic = EventDiagnostic.make(
        id: "diag-1",
        type: longType,
        payload: payload)

    #expect(diagnostic.id == "diag-1")
    #expect(Data(diagnostic.type.utf8).count <= 80)
    #expect(diagnostic.preview == nil)
    #expect(diagnostic.isByteCountLowerBound)
    #expect(diagnostic.byteCount > 0)
    #expect(!diagnosticAccessibilityText(diagnostic).contains("sk-live"))
}

@Test func eventDiagnosticIndexCapsAt128WithOmissionMarker() throws {
    var items: [TranscriptItem] = []
    for index in 0..<129 {
        let diagnostic = EventDiagnostic.make(
            id: "passive-\(index)",
            type: "unknown_future_event",
            payload: .object(["index": .int(index)]))
        EventDiagnosticTranscript.upsert(diagnostic, into: &items)
    }

    let retained = diagnosticItems(from: items)
    #expect(retained.filter { $0.omittedEarlierCount == nil }.count == 128)
    let omission = try #require(retained.first { $0.omittedEarlierCount != nil })
    #expect(omission.omittedEarlierCount == 1)
    #expect(omission.preview == nil)
    #expect(!retained.contains { $0.id == "passive-0" })
}

@MainActor
@Test func unknownPassiveEventStaysBounded() throws {
    var reducer = TranscriptReducer()

    let userTurn = JSONValue.object([
        "id": .string("user-1"),
        "role": .string("user"),
        "content": .string("Continue the task"),
    ])
    _ = reducer.consume(.event(type: "message_end", payload: .object(["message": userTurn])))
    #expect(conversationMessages(from: reducer.items).map(\.visibleText) == ["Continue the task"])

    let secretPayload = JSONValue.object([
        "id": .string("unknown-1"),
        "token": .string("sk-live-secret-token"),
        "nested": .array((0..<400).map { index in
            JSONValue.object(["n": .int(index)])
        }),
    ])
    _ = reducer.consume(.event(type: "unknown_future_event", payload: secretPayload))
    _ = reducer.consume(.event(type: "unknown_future_event", payload: secretPayload))

    let liveDiagnostic = try #require(diagnosticItems(from: reducer.items).first { $0.id == "unknown-1" })
    #expect(liveDiagnostic.type == "unknown_future_event")
    #expect(liveDiagnostic.isByteCountLowerBound)
    #expect(liveDiagnostic.preview == nil)
    #expect(!itemsContainSecret(reducer.items, secret: "sk-live-secret-token"))
    #expect(diagnosticItems(from: reducer.items).count == 1)

    _ = reducer.consume(.event(type: "message_start", payload: .object([:])))
    let malformedDiagnostic = try #require(
        diagnosticItems(from: reducer.items).first { $0.type == "message_start" })
    #expect(malformedDiagnostic.preview == nil)

    _ = reducer.consume(.event(type: "tool_execution_start", payload: .object([
        "toolCallId": .string("tool-1"),
        "toolName": .string("bash"),
        "args": .object(["command": .string("sleep 1")]),
    ])))
    _ = reducer.consume(.event(type: "tool_execution_start", payload: .object([
        "toolCallId": .string("tool-2"),
        "toolName": .string("read"),
        "args": .object(["path": .string("App.swift")]),
    ])))
    _ = reducer.consume(.event(type: "subagent_lifecycle", payload: .object([
        "payload": .object([
            "id": .string("worker-1"),
            "agent": .string("explorer"),
            "index": .int(1),
            "status": .string("running"),
        ]),
    ])))
    _ = reducer.consume(.event(type: "subagent_lifecycle", payload: .object([
        "payload": .object([
            "id": .string("worker-2"),
            "agent": .string("reviewer"),
            "index": .int(2),
            "status": .string("running"),
        ]),
    ])))

    _ = reducer.consume(.event(type: "tool_execution_end", payload: .object([
        "toolName": .string("bash"),
    ])))
    _ = reducer.consume(.event(type: "subagent_lifecycle", payload: .object([
        "payload": .object([
            "index": .int(1),
            "status": .string("completed"),
        ]),
    ])))

    let toolOne = try #require(toolItems(from: reducer.items).first { $0.id == "tool-1" })
    let toolTwo = try #require(toolItems(from: reducer.items).first { $0.id == "tool-2" })
    #expect(toolOne.phase == .running)
    #expect(toolTwo.phase == .running)
    let workerOne = try #require(subagentItems(from: reducer.items).first { $0.id == "worker-1" })
    let workerTwo = try #require(subagentItems(from: reducer.items).first { $0.id == "worker-2" })
    #expect(workerOne.status.isActive)
    #expect(workerTwo.status.isActive)

    _ = reducer.consume(.event(type: "tool_execution_end", payload: .object([
        "toolCallId": .string("tool-1"),
        "toolName": .string("bash"),
    ])))
    _ = reducer.consume(.event(type: "subagent_lifecycle", payload: .object([
        "payload": .object([
            "id": .string("worker-2"),
            "status": .string("completed"),
        ]),
    ])))

    let settledTool = try #require(toolItems(from: reducer.items).first { $0.id == "tool-1" })
    #expect(settledTool.phase == .failed)
    #expect(settledTool.isError)
    #expect(toolTwo.phase == .running)
    let settledWorker = try #require(subagentItems(from: reducer.items).first { $0.id == "worker-2" })
    #expect(settledWorker.status == .failed)
    #expect(settledWorker.description == EventDiagnosticDisplay.settledUpdateError)
    #expect(workerOne.status.isActive)

    _ = reducer.consume(.event(type: "tool_execution_update", payload: .object([
        "toolCallId": .string("tool-1"),
        "toolName": .string("bash"),
        "partialResult": .object(["content": .array([.object(["type": .string("text"), "text": .string("late")])])]),
    ])))
    _ = reducer.consume(.event(type: "subagent_lifecycle", payload: .object([
        "payload": .object([
            "id": .string("worker-2"),
            "agent": .string("reviewer"),
            "index": .int(2),
            "status": .string("running"),
        ]),
    ])))

    #expect(toolItems(from: reducer.items).first { $0.id == "tool-1" }?.phase == .failed)
    #expect(subagentItems(from: reducer.items).first { $0.id == "worker-2" }?.status == .failed)

    let assistantReply = JSONValue.object([
        "id": .string("assistant-1"),
        "role": .string("assistant"),
        "content": .string("Done."),
        "stopReason": .string("stop"),
    ])
    _ = reducer.consume(.event(type: "message_end", payload: .object(["message": assistantReply])))
    #expect(conversationMessages(from: reducer.items).map(\.visibleText) == [
        "Continue the task",
        "Done.",
    ])
    #expect(!itemsContainSecret(reducer.items, secret: "sk-live-secret-token"))

    let header = SessionHeader(
        id: "session-diagnostics",
        cwd: "/tmp/project",
        timestamp: "2026-08-24T20:00:00.000Z",
        version: 3,
        title: nil,
        titleSource: nil,
        parentSession: nil)
    let restored = TranscriptHistoryMapper.map(header: header, path: [
        .message(
            base: diagnosticHistoryBase("user-1", nil, 1),
            message: userTurn),
        .unknown(
            type: "vendor_telemetry",
            base: diagnosticHistoryBase("saved-unknown-1", "user-1", 2),
            raw: try historyJSON(#"{"channel":"metrics","token":"sk-live-secret-token"}"#)),
        .message(
            base: diagnosticHistoryBase("assistant-1", "saved-unknown-1", 3),
            message: assistantReply),
    ])
    let restoredDiagnostic = try #require(
        diagnosticItems(from: restored.items).first { $0.id == "saved-unknown-1" })
    #expect(restoredDiagnostic.type == "vendor_telemetry")
    #expect(!itemsContainSecret(restored.items, secret: "sk-live-secret-token"))

    _ = reducer.load(history: restored)
    #expect(diagnosticItems(from: reducer.items).first { $0.id == "saved-unknown-1" }?.type
        == "vendor_telemetry")

    var cappedReducer = TranscriptReducer()
    for index in 0..<129 {
        _ = cappedReducer.consume(.event(
            type: "unknown_future_event",
            payload: .object([
                "id": .string("passive-\(index)"),
                "index": .int(index),
            ])))
    }
    let capped = diagnosticItems(from: cappedReducer.items)
    #expect(capped.filter { $0.omittedEarlierCount == nil }.count == 128)
    #expect(capped.first { $0.omittedEarlierCount != nil }?.omittedEarlierCount == 1)

    let hiddenRows = TranscriptView.renderRows(
        for: reducer.items,
        runtimeState: .idle,
        isGroupExpanded: { _ in true },
        showsAgentGuidance: false)
    #expect(!hiddenRows.map(\.id).contains { $0.hasPrefix("diagnostic:") })

    let shownRows = TranscriptView.renderRows(
        for: reducer.items,
        runtimeState: .idle,
        isGroupExpanded: { _ in true },
        showsAgentGuidance: true)
    #expect(shownRows.map(\.id).contains("diagnostic:saved-unknown-1"))
    #expect(!shownAccessibilityLabels(from: shownRows).joined().contains("sk-live-secret-token"))
}

@Test func recognizedStatusEventsAreNotRecordedAsUnknown() throws {
    var reducer = TranscriptReducer()

    _ = reducer.consume(.event(type: "agent_start", payload: .object([:])))
    _ = reducer.consume(.event(type: "turn_start", payload: .object([:])))
    _ = reducer.consume(.event(type: "turn_end", payload: .object([:])))
    _ = reducer.consume(.event(type: "session_info_update", payload: .object([
        "cwd": .string("/tmp/project"),
    ])))
    _ = reducer.consume(.event(type: "config_update", payload: .object([
        "model": .string("anthropic/claude-sonnet-4-6"),
    ])))
    _ = reducer.consume(.event(type: "model_changed", payload: .object([
        "model": .string("anthropic/claude-sonnet-4-6"),
    ])))
    _ = reducer.consume(.event(type: "available_commands_update", payload: .object([
        "commands": .array([.object(["name": .string("compact")])]),
    ])))
    _ = reducer.consume(.event(type: "auto_compaction_start", payload: .object([:])))
    _ = reducer.consume(.event(type: "auto_retry_start", payload: .object([
        "attempt": .int(1),
        "maxAttempts": .int(3),
    ])))
    _ = reducer.consume(.event(type: "thinking_level_changed", payload: .object([
        "resolved": .string("high"),
    ])))

    #expect(diagnosticItems(from: reducer.items).isEmpty)
    #expect(reducer.runtimeState == .streaming)
}

@Test func payloadBoundaryWideObjectStopsAtNodeBudget() {
    var children: [String: JSONValue] = [:]
    for index in 0..<400 {
        children["key-\(index)"] = .string("value-\(index)")
    }
    let estimate = PayloadBoundaryTesting.estimate(.object(children))
    #expect(estimate.isLowerBound)
    #expect(estimate.byteCount > 0)
}

@Test func diagnosticOmissionLabelUsesConservativeWording() {
    #expect(DiagnosticCardView.omissionBody(1) == "At least 1 earlier item omitted")
    #expect(DiagnosticCardView.omissionBody(128) == "At least 128 earlier items omitted")
    let marker = EventDiagnostic.earlierOmitted(count: 128)
    #expect(DiagnosticCardView.accessibilityLabel(for: marker)
        == "Earlier activity omitted, at least 128 items")
}

@Test func payloadBoundaryZeroPrimitiveReportsConservativeLowerBound() {
    let estimate = PayloadBoundaryTesting.estimate(.null)
    #expect(estimate.isLowerBound)
    #expect(estimate.byteCount == 0)
}

private func diagnosticItems(from items: [TranscriptItem]) -> [EventDiagnostic] {
    items.compactMap { item in
        guard case .diagnostic(let diagnostic) = item else { return nil }
        return diagnostic
    }
}

private func toolItems(from items: [TranscriptItem]) -> [ToolPresentation] {
    items.compactMap { item in
        guard case .tool(let tool) = item else { return nil }
        return tool
    }
}

private func subagentItems(from items: [TranscriptItem]) -> [SubagentPresentation] {
    items.compactMap { item in
        guard case .subagent(let presentation) = item else { return nil }
        return presentation
    }
}

private func conversationMessages(from items: [TranscriptItem]) -> [TranscriptMessage] {
    items.compactMap { item in
        guard case .message(let message) = item else { return nil }
        return message
    }
}

private func itemsContainSecret(_ items: [TranscriptItem], secret: String) -> Bool {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(items.map(\.id)),
          let json = String(data: data, encoding: .utf8)
    else { return false }
    if json.contains(secret) { return true }
    for item in items {
        switch item {
        case .diagnostic(let diagnostic):
            if diagnosticAccessibilityText(diagnostic).contains(secret) { return true }
        case .notice(_, _, let message):
            if message.contains(secret) { return true }
        case .message(let message):
            if message.visibleText.contains(secret) { return true }
        default:
            continue
        }
    }
    return false
}

private func diagnosticAccessibilityText(_ diagnostic: EventDiagnostic) -> String {
    DiagnosticCardView.accessibilityLabel(for: diagnostic)
}

private func shownAccessibilityLabels(from rows: [TranscriptRenderRow]) -> [String] {
    rows.compactMap { row in
        guard case .presentation(let presentation) = row,
              case .item(.diagnostic(let diagnostic)) = presentation
        else { return nil }
        return DiagnosticCardView.accessibilityLabel(for: diagnostic)
    }
}

private func diagnosticHistoryBase(_ id: String, _ parentID: String?, _ second: Int) -> SessionEntryBase {
    SessionEntryBase(
        id: id,
        parentId: parentID,
        timestamp: String(format: "2026-08-24T20:00:%02d.000Z", second))
}

private func historyJSON(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

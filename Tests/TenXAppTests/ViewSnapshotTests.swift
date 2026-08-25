import Foundation
import OmpKit
import SwiftUI
import Testing
@testable import TenXApp

@MainActor
@Test func genericToolCardSnapshot() throws {
    let presentation = ToolPresentation(
        id: "snapshot-tool",
        name: "custom_future_tool",
        arguments: .object(["query": .string("Bauhaus interface")]),
        result: .object(["content": .array([
            .object(["type": .string("text"), "text": .string("Completed locally")]),
        ])]),
        phase: .complete,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: Date(timeIntervalSince1970: 1.4))
    try assertSnapshot(
        GenericToolCardView(presentation: presentation)
            .frame(width: 720),
        name: "generic-tool-card")
}

@MainActor
@Test func approvalCardSnapshot() throws {
    try assertSnapshot(
        ApprovalCardView(
            state: .confirm(
                id: "approval",
                title: "Allow this command?",
                message: "Run the local test suite in this project.",
                timeout: nil),
            onRespond: { _ in },
            onOpenURL: { _ in },
            onCopyURL: { _ in })
            .frame(width: 720),
        name: "approval-card")
}

@MainActor
@Test func setupSnapshot() throws {
    try assertSnapshot(SetupView(model: AppModel()), name: "omp-missing")
}

@MainActor
@Test func runtimeRecoverySnapshot() throws {
    try assertSnapshot(
        RuntimeRecoveryView(
            exitCode: 143,
            onRestart: {},
            onOpenLog: {},
            onDismiss: {})
            .frame(width: 720),
        name: "runtime-recovery")
}

@MainActor
@Test func continuousSettingsSnapshot() async throws {
    let model = SettingsViewModel(service: OmpConfigService(runner: SnapshotConfigRunner()))
    await model.load()
    try assertSnapshot(SettingsView(model: model), name: "continuous-settings")
}

private struct SnapshotConfigRunner: OmpConfigRunning {
    func run(arguments: [String]) async throws -> Data {
        if arguments == ["config", "path"] {
            return Data("/Users/example/.omp/agent\n".utf8)
        }
        return Data(#"{"autoResume":{"value":false,"type":"boolean","description":"Automatically resume the most recent session"},"advisor.enabled":{"value":true,"type":"boolean","description":"Pair a second model that reviews each turn"},"providers.openai-codex.codeMode":{"value":"off","type":"enum","description":"Route compatible models through code mode"},"tools.outputMaxColumns":{"value":768,"type":"number","description":"Per-line output width"},"approval.mode":{"value":"ask","type":"enum","description":"Require approval before commands"}}"#.utf8)
    }
}

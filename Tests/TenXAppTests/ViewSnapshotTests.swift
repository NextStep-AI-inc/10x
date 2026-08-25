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
    let suiteName = "TenXAppTests.SettingsSnapshot.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registry = IDERegistry.testing(applications: [:])
    let store = IDEPreferenceStore(defaults: defaults, registry: registry)
    await model.load()
    try assertSnapshot(
        SettingsView(model: model, registry: registry, store: store),
        name: "continuous-settings")
}

@MainActor
@Test func fileTypeIconCatalogSnapshot() throws {
    try assertSnapshot(
        HStack(spacing: 24) {
            VStack(spacing: 7) {
                FileTypeIcon(path: "Feature.swift", isAvailable: true)
                Text("Feature.swift")
            }
            VStack(spacing: 7) {
                FileTypeIcon(path: "client.ts", isAvailable: true)
                Text("client.ts")
            }
            VStack(spacing: 7) {
                FileTypeIcon(path: "Component.tsx", isAvailable: true)
                Text("Component.tsx")
            }
        }
        .font(TenXTypography.body(size: 11))
        .padding(18)
        .background(Color.white),
        name: "file-type-icon-catalog",
        size: CGSize(width: 300, height: 90))
}

@MainActor
@Test func fileReferenceStatesSnapshot() throws {
    let suiteName = "TenXAppTests.FileReferenceStates.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let cursorURL = URL(filePath: "/Applications/Cursor.app")
    let registry = IDERegistry.testing(applications: [
        "com.todesktop.230313mzl4w4u92": cursorURL,
    ])
    let selectedStore = IDEPreferenceStore(defaults: defaults, registry: registry)
    try selectedStore.select(#require(registry.installedApplications().first))

    let emptySuiteName = "TenXAppTests.FileReferenceStates.Empty.\(UUID().uuidString)"
    let emptyDefaults = try #require(UserDefaults(suiteName: emptySuiteName))
    defer { emptyDefaults.removePersistentDomain(forName: emptySuiteName) }
    let emptyStore = IDEPreferenceStore(defaults: emptyDefaults, registry: registry)

    let fullReference = ResolvedFileReference(
        originalPath: "App/FileReferences/FileReferenceLabel.swift",
        line: 42,
        url: URL(filePath: "/Users/example/Projects/10x/App/FileReferences/FileReferenceLabel.swift"),
        exists: true)

    try assertSnapshot(
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Selected IDE")
                    .font(TenXTypography.body(size: 11, weight: .semibold))
                TranscriptReferenceView(reference: .file(
                    path: "App/Sessions/TranscriptView.swift",
                    line: 42))
                    .environment(selectedStore)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("No IDE")
                    .font(TenXTypography.body(size: 11, weight: .semibold))
                TranscriptReferenceView(reference: .file(
                    path: "App/Sessions/TranscriptView.swift",
                    line: nil))
                    .environment(emptyStore)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Missing file · disabled actions")
                    .font(TenXTypography.body(size: 11, weight: .semibold))
                TranscriptReferenceView(reference: .file(
                    path: "App/Sessions/RemovedView.swift",
                    line: 8))
                    .environment(selectedStore)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Full path")
                    .font(TenXTypography.body(size: 11, weight: .semibold))
                FlowLayout(spacing: 2) {
                    FileReferenceLabel(reference: fullReference, showsFullPath: true)
                }
                .frame(width: 430, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Compact width")
                    .font(TenXTypography.body(size: 11, weight: .semibold))
                TranscriptReferenceView(reference: .file(
                    path: "App/FileReferences/FileReferenceLabel.swift",
                    line: 42))
                    .environment(selectedStore)
                    .frame(width: 250, alignment: .leading)
            }
        }
        .environment(\.fileReferenceBaseURL, snapshotProjectURL)
        .environment(\.fileOpenService, snapshotFileOpenService)
        .frame(width: 560, alignment: .leading),
        name: "file-reference-states",
        size: CGSize(width: 640, height: 520))
}

@MainActor
@Test func activityFileReferencesSnapshot() throws {
    let suiteName = "TenXAppTests.ActivityFileReferences.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registry = IDERegistry.testing(applications: [
        "com.todesktop.230313mzl4w4u92": URL(filePath: "/Applications/Cursor.app"),
    ])
    let store = IDEPreferenceStore(defaults: defaults, registry: registry)
    try store.select(#require(registry.installedApplications().first))
    let timestamp = Date(timeIntervalSince1970: 1)

    let read = ToolPresentation(
        id: "reference-read",
        name: "read",
        arguments: .object(["path": .string("App/Sessions/TranscriptView.swift")]),
        result: snapshotTextResult("struct TranscriptView: View { … }"),
        phase: .complete,
        startDate: timestamp,
        endDate: timestamp.addingTimeInterval(0.3))
    let edit = ToolPresentation(
        id: "reference-edit",
        name: "edit",
        arguments: .object(["path": .string("App/Sessions/ActiveSessionView.swift")]),
        result: .object(["details": .object(["diff": .string("-old\n+new")])]),
        phase: .complete,
        startDate: timestamp,
        endDate: timestamp.addingTimeInterval(0.7))
    let write = ToolPresentation(
        id: "reference-write",
        name: "write",
        arguments: .object([
            "path": .string("App/FileReferences/FileReferenceLabel.swift"),
            "content": .string("import SwiftUI"),
        ]),
        result: snapshotTextResult("Wrote file"),
        phase: .complete,
        startDate: timestamp,
        endDate: timestamp.addingTimeInterval(0.5))
    let disclosureState = ToolDisclosureState()
    disclosureState.collapseAll(ids: [read.id, edit.id, write.id])

    try assertSnapshot(
        VStack(alignment: .leading, spacing: 18) {
            ReadToolCardView(presentation: read)
            EditToolCardView(presentation: edit)
            WriteToolCardView(presentation: write)
            ReadToolCardView(presentation: read)
                .frame(width: 360, alignment: .leading)
        }
        .environment(\.toolDisclosureState, disclosureState)
        .environment(store)
        .environment(\.fileReferenceBaseURL, snapshotProjectURL)
        .environment(\.fileOpenService, snapshotFileOpenService)
        .frame(width: 720, alignment: .leading),
        name: "activity-file-references",
        size: CGSize(width: 800, height: 520))
}

@MainActor
@Test func userMessageSnapshot() throws {
    let message = TranscriptMessage(
        id: "user-message",
        raw: .object([
            "role": .string("user"),
            "content": .string("Make the transcript compact, but keep every useful detail available."),
        ]),
        timestamp: Date(timeIntervalSince1970: 1_787_601_600),
        isFinal: true)
    try assertSnapshot(
        MessageBubbleView(message: message).frame(width: 720),
        name: "chat-user-message",
        size: CGSize(width: 800, height: 220))
}

@MainActor
@Test func richAssistantMessageSnapshot() throws {
    let message = TranscriptMessage(
        id: "assistant-message",
        raw: .object([
            "role": .string("assistant"),
            "content": .string("""
            # Transcript ready

            The agent view now keeps **routine work compact** while preserving the detail you need.

            - Actual model and mode attribution
            - Structured code with copy
            - Actionable [documentation](https://example.com/docs)

            > Changes stay quiet until they need attention.

            ```swift
            let state = TranscriptState.compact
            render(state, references: true)
            ```
            """),
        ]),
        timestamp: Date(timeIntervalSince1970: 1_787_601_600),
        attribution: TranscriptResponseAttribution(
            provider: "openai-codex",
            model: "gpt-5.6-sol",
            mode: "design",
            agent: nil,
            modelRole: nil),
        isFinal: true)
    try assertSnapshot(
        MessageBubbleView(message: message).frame(width: 720),
        name: "chat-rich-assistant",
        size: CGSize(width: 800, height: 560))
}

@MainActor
@Test func longWrappingMessageSnapshot() throws {
    let longValue = String(repeating: "unbroken-segment-", count: 38)
    let longReference = "/tmp/" + String(repeating: "nested-folder/", count: 8)
        + "a-very-long-reference-name-that-must-not-overflow.swift:42"
    let message = TranscriptMessage(
        id: "long-message",
        raw: .object([
            "role": .string("assistant"),
            "content": .string("The output stays inside the transcript:\n\n\(longValue)\n\n`\(longReference)`"),
        ]),
        attribution: TranscriptResponseAttribution(
            provider: nil,
            model: "claude-sonnet-4-6",
            mode: nil,
            agent: nil,
            modelRole: nil),
        isFinal: true)
    try assertSnapshot(
        MessageBubbleView(message: message)
            .environment(snapshotEmptyIDEStore)
            .frame(width: 520),
        name: "chat-long-wrapping",
        size: CGSize(width: 600, height: 420))
}

@MainActor
@Test func activityDisclosureSnapshot() throws {
    let running = ToolPresentation(
        id: "running-tool",
        name: "bash",
        arguments: .object(["command": .string("swift test --filter Transcript")]),
        result: .object(["content": .array([
            .object([
                "type": .string("text"),
                "text": .string((1...14).map { "Test step \($0) passed" }.joined(separator: "\n")),
            ]),
        ])]),
        phase: .running,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: Date(timeIntervalSince1970: 5.6))
    let failed = ToolPresentation(
        id: "failed-tool",
        name: "bash",
        arguments: .object(["command": .string("swift build")]),
        result: .object(["content": .array([
            .object(["type": .string("text"), "text": .string("Compilation failed at TranscriptView.swift:42")]),
        ])]),
        phase: .failed,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: Date(timeIntervalSince1970: 1.8))
    try assertSnapshot(
        VStack(spacing: 18) {
            BashToolCardView(presentation: running)
            BashToolCardView(presentation: failed)
        }
        .frame(width: 720),
        name: "activity-running-error",
        size: CGSize(width: 800, height: 520))
}

@MainActor
@Test func subagentActivitySnapshot() throws {
    let presentation = SubagentPresentation(
        id: "subagent",
        index: 0,
        agent: "reviewer",
        task: "Review transcript behavior",
        assignment: "Check disclosure and attribution",
        description: "Review the completed implementation against the product direction.",
        status: .running,
        sessionFile: "/tmp/reviewer.jsonl",
        parentToolCallID: "task-1",
        actualModel: "gpt-5.6-sol",
        thinkingLevel: "high",
        modelRole: "review",
        isFallback: false,
        currentTool: "read",
        recentTools: [],
        recentOutput: ["Checked transcript mapping", "Reviewing compact activity"],
        toolCount: 6,
        requests: 2,
        tokens: 1_840,
        cost: 0.03,
        durationMilliseconds: 4_200,
        result: nil)
    try assertSnapshot(
        SubagentCardView(presentation: presentation).frame(width: 720),
        name: "activity-subagent",
        size: CGSize(width: 800, height: 330))
}

@MainActor
@Test func structuredDiffSnapshot() throws {
    let longLine = "let title = \"" + String(repeating: "structured-transcript-", count: 10) + "\""
    let patch = """
    diff --git a/App/Transcript.swift b/App/Transcript.swift
    --- a/App/Transcript.swift
    +++ b/App/Transcript.swift
    @@ -1,10 +1,10 @@
     import SwiftUI
     struct Transcript {
     let id: String
     let role: String
     let model: String
     let mode: String
     let date: Date
     let state: State
    -let title = "Old transcript"
    +\(longLine)
    diff --git a/App/Palette.swift b/App/Palette.swift
    --- a/App/Palette.swift
    +++ b/App/Palette.swift
    @@ -4,2 +4,2 @@
    -let addition = Color.green
    +let addition = Color.cyan
     let removal = Color.red
    """
    let presentation = ToolPresentation(
        id: "diff-tool",
        name: "edit",
        arguments: .object(["path": .string("/tmp/Transcript.swift")]),
        result: .object(["details": .object(["diff": .string(patch)])]),
        phase: .complete,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: Date(timeIntervalSince1970: 1.7))
    try assertSnapshot(
        EditToolCardView(presentation: presentation)
            .environment(snapshotEmptyIDEStore)
            .frame(width: 720),
        name: "activity-structured-diff",
        size: CGSize(width: 800, height: 650))
}

@MainActor
@Test func fullTranscriptCompactWindowSnapshot() throws {
    try assertSnapshot(
        ActiveSessionView(controller: compactTranscriptController())
            .environment(snapshotEmptyIDEStore),
        name: "chat-full-900",
        size: CGSize(width: 900, height: 700))
}

@MainActor
@Test func fullTranscriptWideWindowSnapshot() throws {
    try assertSnapshot(
        ActiveSessionView(controller: wideTranscriptController())
            .environment(snapshotEmptyIDEStore),
        name: "chat-full-1440",
        size: CGSize(width: 1_440, height: 900))
}

@MainActor
private func compactTranscriptController() -> SessionController {
    let timestamp = Date(timeIntervalSince1970: 1_787_601_600)
    let user = TranscriptMessage(
        id: "compact-user",
        raw: .object([
            "role": .string("user"),
            "content": .string("Make the agent transcript compact without hiding important work."),
        ]),
        timestamp: timestamp,
        isFinal: true)
    let assistant = TranscriptMessage(
        id: "compact-assistant",
        raw: .object([
            "role": .string("assistant"),
            "content": .string("Routine work stays collapsed. Running and failed work opens automatically, and every item remains keyboard accessible."),
        ]),
        timestamp: timestamp.addingTimeInterval(8),
        attribution: TranscriptResponseAttribution(
            provider: "openai-codex",
            model: "gpt-5.6-sol",
            mode: "design",
            agent: nil,
            modelRole: nil),
        isFinal: false)
    let read = ToolPresentation(
        id: "compact-read",
        name: "read",
        arguments: .object(["path": .string("App/Sessions/TranscriptView.swift")]),
        result: snapshotTextResult("struct TranscriptView: View { … }"),
        phase: .complete,
        startDate: timestamp.addingTimeInterval(10),
        endDate: timestamp.addingTimeInterval(10.3))
    let running = ToolPresentation(
        id: "compact-running",
        name: "bash",
        arguments: .object(["command": .string("xcodebuild -scheme 10x test")]),
        result: snapshotTextResult("Building transcript tests…"),
        phase: .running,
        startDate: timestamp.addingTimeInterval(11),
        endDate: timestamp.addingTimeInterval(15.6))
    let failed = ToolPresentation(
        id: "compact-failed",
        name: "bash",
        arguments: .object(["command": .string("swift build")]),
        result: snapshotTextResult("TranscriptView.swift:42: error: invalid scroll target"),
        phase: .failed,
        startDate: timestamp.addingTimeInterval(16),
        endDate: timestamp.addingTimeInterval(16.8))
    return SessionController(
        processManager: SessionProcessManager(),
        previewItems: [
            .threadStart(id: "compact-start", date: timestamp),
            .message(user),
            .message(assistant),
            .tool(read),
            .tool(running),
            .tool(failed),
        ],
        runtimeState: .streaming,
        title: "Transcript experience")
}

@MainActor
private func wideTranscriptController() -> SessionController {
    let timestamp = Date(timeIntervalSince1970: 1_787_601_600)
    let assistant = TranscriptMessage(
        id: "wide-assistant",
        raw: .object([
            "role": .string("assistant"),
            "content": .string("## Implementation\n\nThe transcript keeps long explanations readable while preserving direct references like `App/Sessions/TranscriptView.swift:42` and [the design notes](https://example.com/design)."),
        ]),
        timestamp: timestamp.addingTimeInterval(20),
        attribution: TranscriptResponseAttribution(
            provider: "openai-codex",
            model: "gpt-5.6-sol",
            mode: "advisor",
            agent: "interface-worker",
            modelRole: "implementation"),
        isFinal: true)
    let patch = """
    diff --git a/App/Transcript.swift b/App/Transcript.swift
    --- a/App/Transcript.swift
    +++ b/App/Transcript.swift
    @@ -18,3 +18,3 @@
    -scrollToBottom()
    +if isNearBottom { scrollToBottom() }
     render(items)
    """
    let edit = ToolPresentation(
        id: "wide-edit",
        name: "edit",
        arguments: .object(["path": .string("App/Transcript.swift")]),
        result: .object(["details": .object(["diff": .string(patch)])]),
        phase: .complete,
        startDate: timestamp.addingTimeInterval(21),
        endDate: timestamp.addingTimeInterval(21.7))
    let subagent = SubagentPresentation(
        id: "wide-subagent",
        index: 0,
        agent: "reviewer",
        task: "Review transcript behavior",
        assignment: "Verify attribution, disclosure, and wrapping",
        description: "Review the integrated transcript against the product direction.",
        status: .running,
        sessionFile: "/tmp/reviewer.jsonl",
        parentToolCallID: "task-review",
        actualModel: "gpt-5.6-sol",
        thinkingLevel: "high",
        modelRole: "review",
        isFallback: false,
        currentTool: "view_image",
        recentTools: [],
        recentOutput: ["Checked compact state", "Reviewing the structured diff"],
        toolCount: 7,
        requests: 2,
        tokens: 2_140,
        cost: 0.04,
        durationMilliseconds: 6_400,
        result: nil)
    let warning = TranscriptAnnotation(
        id: "wide-warning",
        kind: .retry,
        title: "Retrying response",
        detail: "Attempt 2 of 3 · 1s",
        timestamp: timestamp.addingTimeInterval(22),
        tone: .warning)
    return SessionController(
        processManager: SessionProcessManager(),
        previewItems: [
            .threadStart(id: "wide-start", date: timestamp),
            .message(assistant),
            .annotation(warning),
            .tool(edit),
            .subagent(subagent),
        ],
        runtimeState: .streaming,
        title: "Agent transcript")
}

private func snapshotTextResult(_ text: String) -> JSONValue {
    .object(["content": .array([
        .object(["type": .string("text"), "text": .string(text)]),
    ])])
}

private struct SnapshotConfigRunner: OmpConfigRunning {
    func run(arguments: [String]) async throws -> Data {
        if arguments == ["config", "path"] {
            return Data("/Users/example/.omp/agent\n".utf8)
        }
        return Data(#"{"autoResume":{"value":false,"default":false,"type":"boolean","description":"Automatically resume the most recent session"},"advisor.enabled":{"value":true,"default":false,"type":"boolean","description":"Pair a second model that reviews each turn"},"providers.openai-codex.codeMode":{"value":"off","default":"off","type":"enum","description":"Route compatible models through code mode"},"tools.outputMaxColumns":{"value":768,"default":512,"type":"number","description":"Per-line output width"},"approval.mode":{"value":"ask","default":"ask","type":"enum","description":"Require approval before commands"}}"#.utf8)
    }
}

private let snapshotProjectURL = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private let snapshotFileOpenService = FileOpenService(
    openDefault: { _ in },
    openInApplication: { _, _ in },
    reveal: { _ in },
    startSecurityScope: { _ in false },
    stopSecurityScope: { _ in })

@MainActor
private let snapshotEmptyIDEStore: IDEPreferenceStore = {
    let suiteName = "TenXAppTests.ReferenceSnapshots"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return IDEPreferenceStore(defaults: defaults, registry: .testing(applications: [:]))
}()

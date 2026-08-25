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
@Test func providerSetupRequiredSnapshot() async throws {
    let model = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "google-gemini-cli", name: "Gemini CLI", isAvailable: true, isAuthenticated: false),
    ])
    await model.load()

    try assertSnapshot(
        ProviderSetupView(model: model, onContinue: {}),
        name: "provider-setup-required",
        size: CGSize(width: 760, height: 560))
}

@MainActor
@Test func providerSetupConnectedSnapshot() async throws {
    let model = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
        ProviderLoginProvider(
            id: "google-gemini-cli", name: "Gemini CLI", isAvailable: true, isAuthenticated: false),
    ])
    await model.load()

    try assertSnapshot(
        ProviderSetupView(model: model, onContinue: {}),
        name: "provider-setup-connected",
        size: CGSize(width: 760, height: 560))
}

@MainActor
@Test func providerSetupBrowseAllSnapshot() async throws {
    let model = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "openai-codex", name: "OpenAI Codex", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "anthropic", name: "Anthropic", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
        ProviderLoginProvider(
            id: "google-gemini-cli", name: "Gemini CLI", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "github-copilot", name: "GitHub Copilot", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "ollama", name: "Ollama", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "sourcegraph", name: "Sourcegraph", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "zed", name: "Zed", isAvailable: true, isAuthenticated: false),
    ])
    await model.load()
    model.showAllProviders()

    try assertSnapshot(
        ProviderSetupView(model: model, onContinue: {}),
        name: "provider-setup-browse-all",
        size: CGSize(width: 760, height: 560))
}

@MainActor
@Test func providerSetupLoginFailureSnapshot() async throws {
    let service = FakeProviderService(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
    ])
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) },
        formatTime: { _ in "4:00 PM" })
    await model.load()
    await service.emit(ExtensionUIRequest(
        id: "failed-login",
        method: "notify",
        payload: .object(["message": .string("Couldn’t connect to Cursor.")])) )
    await waitForModelState { model.loginMessage == "Couldn’t connect to Cursor." }

    try assertSnapshot(
        ProviderSetupView(model: model, onContinue: {}),
        name: "provider-setup-login-failure",
        size: CGSize(width: 760, height: 560))
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
        MessageBubbleView(message: message).frame(width: 520),
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
        EditToolCardView(presentation: presentation).frame(width: 720),
        name: "activity-structured-diff",
        size: CGSize(width: 800, height: 650))
}

@MainActor
@Test func fullTranscriptCompactWindowSnapshot() throws {
    try assertSnapshot(
        ActiveSessionView(controller: compactTranscriptController()),
        name: "chat-full-900",
        size: CGSize(width: 900, height: 700))
}

@MainActor
@Test func fullTranscriptWideWindowSnapshot() throws {
    try assertSnapshot(
        ActiveSessionView(controller: wideTranscriptController()),
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

import Foundation
import Testing
import OmpKit
@testable import TenXApp

@Test func emptyAssistantPlaceholderDoesNotRenderATimestampRow() {
    let empty = TranscriptMessage(id: "waiting", raw: .object([
        "role": .string("assistant"), "content": .array([]),
    ]), isFinal: false)
    let rows = TranscriptPresentationRow.rows(from: [.message(empty)])
    #expect(rows.count == 1)
    #expect(TranscriptPresentationRow.visibleRows(from: rows, isGroupExpanded: { _ in true }).isEmpty)
    #expect(TurnActivityView.isAwaitingOutput(runtimeState: .streaming, lastItem: .message(empty)))
}

@Test func delayedAssistantTextBecomesVisibleWithoutLosingItsIdentity() {
    let text = TranscriptMessage(id: "waiting", raw: .object([
        "role": .string("assistant"), "content": .string("The parser drops scoped subjects."),
    ]), isFinal: false)
    let rows = TranscriptPresentationRow.rows(from: [.message(text)])
    #expect(TranscriptPresentationRow.visibleRows(from: rows, isGroupExpanded: { _ in true }).map(\.id)
        == ["message:waiting"])
    #expect(!TurnActivityView.isAwaitingOutput(runtimeState: .streaming, lastItem: .message(text)))
}

@Test @MainActor func startupRecoveryExplainsCauseAndRetryClearsIt() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markLoading(.recentProjects, attemptID: attempt)
    state.enterRecovery(attemptID: attempt, reason: "A workspace process exited during startup.")
    #expect(state.footerDetail.contains("Preparing recent projects"))
    #expect(state.footerDetail.contains("process exited"))
    _ = state.beginRetry(id: UUID())
    #expect(state.recoveryDetail == nil)
}

@Test @MainActor func startupSubmissionMovesToOneBubbleAndFailureRestoresDraft() {
    let controller = SessionController(processManager: SessionProcessManager(),
        previewItems: [], runtimeState: .loading, title: "New session")
    controller.prepareInitialSubmission(text: "Repair scoped release notes", attachments: [])
    #expect(controller.draft.isEmpty)
    #expect(controller.pendingSubmissions.map { $0.message.visibleText } == ["Repair scoped release notes"])
    #expect(controller.isTitleLoading)
    controller.markInitialSubmissionFailed()
    #expect(controller.draft == "Repair scoped release notes")
    #expect(controller.pendingSubmissions.first?.state == .unconfirmed)
    #expect(!controller.isTitleLoading)
    #expect(controller.title == "Repair scoped release notes")
}

@Test @MainActor func stoppingStartupPreservesPromptAndShowsNeutralStatus() async {
    let controller = SessionController(processManager: SessionProcessManager(),
        previewItems: [], runtimeState: .loading, title: "New session")
    controller.prepareInitialSubmission(text: "Repair scoped release notes", attachments: [])
    await controller.abort()
    #expect(controller.activityState == .stopped)
    #expect(controller.draft == "Repair scoped release notes")
    #expect(!controller.isTitleLoading)
}

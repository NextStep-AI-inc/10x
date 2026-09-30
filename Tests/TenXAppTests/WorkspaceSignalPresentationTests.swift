import Testing
@testable import TenXApp

@Test func signalPriorityKeepsInputAboveRetryAndCompaction() {
    let input = WorkspaceSignalPresentation.session(
        runtimeState: .streaming,
        contextPercent: 96,
        hasPendingUserInput: true,
        isRetrying: true,
        hasTerminalRetryFailure: false,
        compactionPhase: .sweeping,
        isRecoveryPresented: false,
        isIntentionallyStopped: false)
    #expect(input.status == .needsInput)
    #expect(input.label == "Needs input")

    let failure = WorkspaceSignalPresentation.session(
        runtimeState: .streaming,
        contextPercent: 96,
        hasPendingUserInput: true,
        isRetrying: true,
        hasTerminalRetryFailure: true,
        compactionPhase: .sweeping,
        isRecoveryPresented: false,
        isIntentionallyStopped: false)
    #expect(failure.status == .failed)
    #expect(failure.label == "Failed")

    let revealingInput = WorkspaceSignalPresentation.session(
        runtimeState: .streaming,
        contextPercent: 30,
        hasPendingUserInput: true,
        isRetrying: false,
        hasTerminalRetryFailure: false,
        compactionPhase: .revealing(generation: 1, percent: 30),
        isRecoveryPresented: false,
        isIntentionallyStopped: false)
    #expect(revealingInput.status == .needsInput)

    let stopped = WorkspaceSignalPresentation.session(
        runtimeState: .stopped(code: nil, stderrTail: ""),
        contextPercent: 96,
        hasPendingUserInput: false,
        isRetrying: false,
        hasTerminalRetryFailure: false,
        compactionPhase: .none,
        isRecoveryPresented: false,
        isIntentionallyStopped: true)
    #expect(stopped.status == .responseStopped)
    #expect(stopped.label == "Response stopped")
}

@Test func nearLimitKeepsMeasuredNinetyFiveAndHundredPercent() {
    for percent in [95, 100] {
        let presentation = WorkspaceSignalPresentation.session(
            runtimeState: .idle,
            contextPercent: percent,
            hasPendingUserInput: false,
            isRetrying: false,
            hasTerminalRetryFailure: false,
            compactionPhase: .none,
            isRecoveryPresented: false,
            isIntentionallyStopped: false)
        #expect(presentation.status == .nearLimit)
        #expect(presentation.label == "Near limit")
        #expect(presentation.contextPercent == percent)
        #expect(presentation.contextLabel == "Context \(percent)%")
        #expect(presentation.contextFraction == Double(percent) / 100)
    }
}

@Test func unavailableContextHasNoFillOrInventedNumber() {
    let opening = WorkspaceSignalPresentation.session(
        runtimeState: .loading,
        contextPercent: nil,
        hasPendingUserInput: false,
        isRetrying: false,
        hasTerminalRetryFailure: false,
        compactionPhase: .none,
        isRecoveryPresented: false,
        isIntentionallyStopped: false)
    #expect(opening.status == .opening)
    #expect(opening.label == "Opening")
    #expect(opening.contextPercent == nil)
    #expect(opening.contextFraction == nil)
    #expect(opening.contextLabel == "Context —")
    #expect(opening.accessibilityLabel == "Opening, context unavailable")

    let ready = WorkspaceSignalPresentation.session(
        runtimeState: .idle,
        contextPercent: nil,
        hasPendingUserInput: false,
        isRetrying: false,
        hasTerminalRetryFailure: false,
        compactionPhase: .none,
        isRecoveryPresented: false,
        isIntentionallyStopped: false)
    #expect(ready.status == .ready)
    #expect(ready.contextFraction == nil)
    #expect(ready.contextLabel == "Context —")
}

@Test func workspaceCountNeverShowsSessionContext() {
    let working = WorkspaceSignalPresentation.workspace(generatingCount: 2)
    #expect(working.status == .backgroundWorking(2))
    #expect(working.label == "2 working")
    #expect(working.contextPercent == nil)
    #expect(working.contextFraction == nil)
    #expect(working.contextLabel == nil)

    let idle = WorkspaceSignalPresentation.workspace(generatingCount: 0)
    #expect(idle.status == .workspaceReady)
    #expect(idle.contextPercent == nil)
    #expect(idle.contextLabel == nil)
}

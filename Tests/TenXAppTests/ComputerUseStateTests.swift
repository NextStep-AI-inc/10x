import Testing
@testable import TenXApp

@Test func computerUseTransitionsFailClosed() throws {
    var machine = ComputerUseStateMachine()

    try machine.transition(to: .preparing)
    try machine.transition(to: .ready)
    try machine.transition(to: .controlling(target: "TextEdit"))
    try machine.transition(to: .needsHandoff(
        target: "TextEdit",
        reason: "Background input unavailable"))
    try machine.transition(to: .ready)
    try machine.transition(to: .stopping)
    try machine.transition(to: .off)

    #expect(machine.phase == .off)
}

@Test func invalidComputerUseTransitionLeavesTheCurrentPhaseUnchanged() {
    var machine = ComputerUseStateMachine()

    #expect(throws: ComputerUseTransitionError.self) {
        try machine.transition(to: .controlling(target: "Safari"))
    }

    #expect(machine.phase == .off)
}

@Test func unavailableComputerUseCannotResumeWithoutStopping() throws {
    var machine = ComputerUseStateMachine()
    try machine.transition(to: .preparing)
    try machine.transition(to: .unavailable(
        message: "Accessibility permission is unavailable",
        isBestEffortAvailable: true))

    #expect(throws: ComputerUseTransitionError.self) {
        try machine.transition(to: .ready)
    }
    #expect(machine.phase == .unavailable(
        message: "Accessibility permission is unavailable",
        isBestEffortAvailable: true))
}

@Test func computerUseSafetyModesRemainDistinct() {
    #expect(ComputerUseSafetyMode.focusIsolated != .legacyBestEffort)
}

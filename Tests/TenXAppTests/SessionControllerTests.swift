import OmpKit
import Testing
@testable import TenXApp

@MainActor
@Test(arguments: AgentDesktopPreference.allCases)
func sessionControllerPassesItsDesktopPreferenceToComputerUse(
    preference: AgentDesktopPreference
) {
    let controller = SessionController(
        processManager: SessionProcessManager(),
        computerUsePreference: preference)

    #expect(controller.computerUsePreference == preference)
}

@MainActor @Test func contextPercentageIsClampedToItsDisplayRange() {
    #expect(SessionController.contextPercent(.object(["percentage": .double(210)])) == 100)
    #expect(SessionController.contextPercent(.object(["percentage": .double(-0.2)])) == 0)
    #expect(SessionController.contextPercent(.object(["percentage": .double(0.63)])) == 63)
}

@MainActor @Test func unexpectedExitPreservesDraftAndOffersRecovery() async {
    let controller = SessionController(processManager: SessionProcessManager())
    controller.draft = "Unsent follow-up"

    await controller.handleUnexpectedExit(code: 9, stderrTail: "process terminated")

    #expect(controller.runtimeState == .stopped(code: 9, stderrTail: "process terminated"))
    #expect(controller.draft == "Unsent follow-up")
    #expect(controller.isRecoveryPresented)
    #expect(controller.logText == "process terminated")
}

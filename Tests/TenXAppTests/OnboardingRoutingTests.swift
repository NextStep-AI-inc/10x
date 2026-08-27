import Foundation
import Testing
@testable import TenXApp

@MainActor
@Test func gatingSendsAFreshInstallToTheInstallStep() {
    let model = AppModel()
    model.gateRoute()
    #expect(model.route == .onboarding(.installOmp))
}

@MainActor
@Test func gatingSendsAConnectedUserWithNoProjectToTheProjectStep() {
    let model = AppModel()
    model.installation = OmpInstallation(
        executableURL: URL(filePath: "/Users/example/.local/bin/omp"),
        version: "18.0.4")
    // No provider model at all reads as no authenticated provider.
    #expect(model.firstUnmetRequirement() == .connectProvider)

    model.selectedProjectURL = URL(filePath: "/tmp/Project", directoryHint: .isDirectory)
    #expect(model.firstUnmetRequirement() == .connectProvider)
}

@MainActor
@Test func recordingAProjectDuringOnboardingDoesNotLeaveTheFlow() {
    let model = AppModel()
    model.route = .onboarding(.chooseProject)

    model.recordOnboardingProject(URL(filePath: "/tmp/First", directoryHint: .isDirectory))

    // Still on the step, so a second folder can be added. `chooseProject`
    // would have routed away on the first selection.
    #expect(model.route == .onboarding(.chooseProject))
    #expect(model.selectedProjectURL?.lastPathComponent == "First")

    model.recordOnboardingProject(URL(filePath: "/tmp/Second", directoryHint: .isDirectory))
    #expect(model.selectedProjectURL?.lastPathComponent == "Second")
}

@MainActor
@Test func leavingSettingsFromOnboardingLandsOnTheWorkspace() {
    let model = AppModel()
    model.route = .onboarding(.connectProvider)
    model.openSettings()
    #expect(model.route == .settings)

    model.leaveSettings()
    #expect(model.route == .newSession)
}

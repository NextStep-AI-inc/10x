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

// MARK: - OnboardingProjectSelection

// `OnboardingProjectSelection` backs `OnboardingProjectStepView`'s picked
// folder list. It is exercised directly here (rather than by driving
// `NSOpenPanel`, which cannot run in tests) because it is the seam extracted
// from that view specifically to make folder-picking behavior testable.

@Test func pickingAFolderWithNoSessionsAppearsInTheListAndIsMarkedAdded() {
    var selection = OnboardingProjectSelection()
    let url = URL(filePath: "/tmp/picked-project", directoryHint: .isDirectory)

    selection.pick(url)

    let projects = selection.projects(suggestions: [])
    #expect(projects.map(\.path) == [url.standardizedFileURL.path])
    #expect(selection.isAdded(url))
}

@Test func aPickedFolderThatIsAlsoASessionProjectAppearsOnce() {
    var selection = OnboardingProjectSelection()
    let url = URL(filePath: "/tmp/shared-project", directoryHint: .isDirectory)

    selection.pick(url)

    let projects = selection.projects(suggestions: [url])
    #expect(projects.count == 1)
    #expect(projects.first?.path == url.standardizedFileURL.path)
}

@Test func theMostRecentlyPickedFolderLeadsTheList() {
    var selection = OnboardingProjectSelection()
    selection.pick(URL(filePath: "/tmp/first-picked", directoryHint: .isDirectory))
    selection.pick(URL(filePath: "/tmp/second-picked", directoryHint: .isDirectory))

    let projects = selection.projects(suggestions: [])
    #expect(projects.map(\.lastPathComponent) == ["second-picked", "first-picked"])
}

@Test func repickingAnAlreadyPickedFolderMovesItToTheFrontWithoutDuplicating() {
    var selection = OnboardingProjectSelection()
    let first = URL(filePath: "/tmp/first-picked", directoryHint: .isDirectory)
    let second = URL(filePath: "/tmp/second-picked", directoryHint: .isDirectory)
    selection.pick(first)
    selection.pick(second)
    selection.pick(first)

    let projects = selection.projects(suggestions: [])
    #expect(projects.map(\.lastPathComponent) == ["first-picked", "second-picked"])
}

@Test func markingASuggestionAddedDoesNotReorderPickedFolders() {
    var selection = OnboardingProjectSelection()
    let picked = URL(filePath: "/tmp/picked-project", directoryHint: .isDirectory)
    let suggestion = URL(filePath: "/tmp/suggested-project", directoryHint: .isDirectory)
    selection.pick(picked)

    selection.markAdded(suggestion)

    #expect(selection.isAdded(suggestion))
    let projects = selection.projects(suggestions: [suggestion])
    #expect(projects.map(\.lastPathComponent) == ["picked-project", "suggested-project"])
}

@Test func seedingFromNilLeavesTheSelectionEmpty() {
    let selection = OnboardingProjectSelection(seeding: nil)
    #expect(selection.projects(suggestions: []).isEmpty)
}

@Test func seedingFromAnAlreadySelectedProjectMakesItAppearAndMarksItAdded() {
    let url = URL(filePath: "/tmp/already-selected", directoryHint: .isDirectory)
    let selection = OnboardingProjectSelection(seeding: url)

    #expect(selection.projects(suggestions: []).map(\.path) == [url.standardizedFileURL.path])
    #expect(selection.isAdded(url))
}

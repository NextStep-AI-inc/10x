import Foundation
import Testing
@testable import TenXApp

private let installed = OmpInstallation(
    executableURL: URL(filePath: "/Users/example/.local/bin/omp"),
    version: "18.0.4")
private let project = URL(filePath: "/Users/example/Code/app", directoryHint: .isDirectory)

@Test func requirementsAreResolvedInOrderAndStopAtTheFirstUnmetOne() {
    #expect(OnboardingStep.firstUnmet(
        installation: nil,
        hasAuthenticatedProvider: false,
        selectedProjectURL: nil) == .installOmp)

    // A missing runtime outranks everything else, even when the later
    // requirements happen to be satisfied.
    #expect(OnboardingStep.firstUnmet(
        installation: nil,
        hasAuthenticatedProvider: true,
        selectedProjectURL: project) == .installOmp)

    #expect(OnboardingStep.firstUnmet(
        installation: installed,
        hasAuthenticatedProvider: false,
        selectedProjectURL: nil) == .connectProvider)

    #expect(OnboardingStep.firstUnmet(
        installation: installed,
        hasAuthenticatedProvider: false,
        selectedProjectURL: project) == .connectProvider)

    #expect(OnboardingStep.firstUnmet(
        installation: installed,
        hasAuthenticatedProvider: true,
        selectedProjectURL: nil) == .chooseProject)
}

@Test func everyRequirementMetMeansNoOnboardingStep() {
    #expect(OnboardingStep.firstUnmet(
        installation: installed,
        hasAuthenticatedProvider: true,
        selectedProjectURL: project) == nil)
}

@Test func stepsAreOrderedInstallThenProviderThenProject() {
    #expect(OnboardingStep.allCases == [.installOmp, .connectProvider, .chooseProject])
}

@Test func theUnmetSetSkipsRequirementsThatAreAlreadySatisfied() {
    // Losing OMP mid-session: the provider model goes away with the runtime,
    // but a chosen project survives. Two steps remain, not three.
    #expect(OnboardingStep.unmet(
        installation: nil,
        hasAuthenticatedProvider: false,
        selectedProjectURL: project) == [.installOmp, .connectProvider])

    #expect(OnboardingStep.unmet(
        installation: nil,
        hasAuthenticatedProvider: false,
        selectedProjectURL: nil)
        == [.installOmp, .connectProvider, .chooseProject])

    #expect(OnboardingStep.unmet(
        installation: installed,
        hasAuthenticatedProvider: true,
        selectedProjectURL: nil) == [.chooseProject])

    #expect(OnboardingStep.unmet(
        installation: installed,
        hasAuthenticatedProvider: true,
        selectedProjectURL: project).isEmpty)
}

@Test func theFirstUnmetRequirementIsTheFirstOfTheUnmetSet() {
    for installation in [nil, installed] {
        for hasProvider in [false, true] {
            for url in [nil, project] {
                let all = OnboardingStep.unmet(
                    installation: installation,
                    hasAuthenticatedProvider: hasProvider,
                    selectedProjectURL: url)
                let first = OnboardingStep.firstUnmet(
                    installation: installation,
                    hasAuthenticatedProvider: hasProvider,
                    selectedProjectURL: url)
                #expect(first == all.first)
            }
        }
    }
}

// MARK: - OnboardingInstallPhase

// `OnboardingInstallPhase` backs `OnboardingInstallStepView`'s post-install
// UI: it makes the "discovery is still running after a successful script"
// window visible instead of silent. Exercised directly here at the
// transition-function level, since driving the real install script and
// `AppModel.useOmp()` end to end is integration territory, not unit territory.

@Test func theVerifyingPhaseIsEnteredOnlyAfterAScriptSucceeds() {
    #expect(OnboardingInstallPhase.afterScript(succeeded: true) == .verifying)
    #expect(OnboardingInstallPhase.afterScript(succeeded: false) == .idle)
}

@Test func theVerifyingPhaseIsLeftWhenDiscoveryResolves() {
    #expect(OnboardingInstallPhase.verifying.afterDiscovery() == .idle)
}

@Test func discoveryResolvingDoesNotDisturbANonVerifyingPhase() {
    // A failed script already moved the phase back to `.idle` before
    // discovery runs (the existing "call `useOmp()` regardless" behavior),
    // so discovery resolving afterward must not clobber a fresh install.
    #expect(OnboardingInstallPhase.idle.afterDiscovery() == .idle)
    #expect(OnboardingInstallPhase.installing.afterDiscovery() == .installing)
}

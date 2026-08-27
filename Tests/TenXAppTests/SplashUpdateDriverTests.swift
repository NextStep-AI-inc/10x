import Foundation
import Sparkle
import Testing
@testable import TenXApp

@MainActor
private func makeDriver(
    _ state: UpdateState,
    prepareForInstall: @escaping @MainActor () async -> Void = {}
) -> SplashUpdateDriver {
    SplashUpdateDriver(
        state: state, currentVersion: "0.1.0", prepareForInstall: prepareForInstall)
}

@MainActor
@Test func aUserInitiatedCheckEntersTheCheckingPhase() {
    let state = UpdateState()
    let driver = makeDriver(state)

    driver.showUserInitiatedUpdateCheck(cancellation: {})

    #expect(state.phase == .checking)
}

@MainActor
@Test func downloadCallbacksAccumulateIntoDownloadProgress() {
    let state = UpdateState()
    let driver = makeDriver(state)

    driver.showDownloadInitiated(cancellation: {})
    driver.showDownloadDidReceiveExpectedContentLength(200)
    driver.showDownloadDidReceiveData(ofLength: 50)

    #expect(state.phase == .downloading(receivedBytes: 50, expectedBytes: 200))
}

@MainActor
@Test func extractionCallbacksDriveTheInstallStep() {
    let state = UpdateState()
    let driver = makeDriver(state)

    driver.showDownloadInitiated(cancellation: {})
    driver.showDownloadDidStartExtractingUpdate()
    driver.showExtractionReceivedProgress(0.5)

    #expect(state.phase == .installing(extractionFraction: 0.5))
}

@MainActor
@Test func installingCallbackEntersRelaunching() {
    let state = UpdateState()
    let driver = makeDriver(state)

    driver.showInstallingUpdate(
        withApplicationTerminated: false, retryTerminatingApplication: {})

    #expect(state.phase == .relaunching)
}

@MainActor
@Test func dismissingAnInstallationReturnsToIdle() {
    let state = UpdateState()
    let driver = makeDriver(state)
    driver.showDownloadInitiated(cancellation: {})

    driver.dismissUpdateInstallation()

    #expect(state.phase == .idle)
}

@MainActor
@Test func consentingToInstallShutsTheRuntimeDownFirst() async {
    let state = UpdateState()
    let didPrepare = Preparation()
    let driver = makeDriver(state, prepareForInstall: { await didPrepare.record() })

    let choice = await driver.showReadyToInstallAndRelaunch()

    #expect(choice == .install)
    #expect(await didPrepare.count == 1)
}

@MainActor
@Test func aMenuCheckThatFindsNothingReportsUpToDate() async {
    let state = UpdateState()
    let driver = makeDriver(state)
    driver.isUserInitiated = true
    state.beginCheck()

    await driver.showUpdateNotFoundWithError(SplashUpdateDriverTestError.none)

    #expect(state.phase == .upToDate(currentVersion: "0.1.0"))
}

@MainActor
@Test func aLaunchCheckThatFindsNothingStaysSilent() async {
    let state = UpdateState()
    let driver = makeDriver(state)
    driver.isUserInitiated = false
    state.beginCheck()

    await driver.showUpdateNotFoundWithError(SplashUpdateDriverTestError.none)

    #expect(state.phase == .idle)
    #expect(!state.isPresentingUpdate)
}

@MainActor
@Test func splashButtonsResolveThePendingSparkleDecision() async {
    let state = UpdateState()
    let driver = makeDriver(state)

    async let choice = driver.awaitDecisionForTesting()
    while !driver.hasPendingDecisionForTesting { await Task.yield() }
    driver.acceptUpdate()

    #expect(await choice == .install)
}

@MainActor
@Test func notNowDismissesRatherThanSkippingTheVersionPermanently() async {
    let state = UpdateState()
    let driver = makeDriver(state)

    async let choice = driver.awaitDecisionForTesting()
    while !driver.hasPendingDecisionForTesting { await Task.yield() }
    driver.dismissUpdate()

    #expect(await choice == .dismiss)
}

@MainActor
@Test func aLaunchCheckThatErrorsNeverPaintsAFailureOnTheSplash() async {
    let state = UpdateState()
    let driver = makeDriver(state)
    driver.isUserInitiated = false
    state.beginCheck()

    await driver.showUpdaterError(SplashUpdateDriverTestError.none)

    #expect(state.phase == .idle)
    #expect(!state.isPresentingUpdate)
}

@MainActor
@Test func anErrorDuringAnInFlightUpdateIsShownToTheUser() async {
    let state = UpdateState()
    let driver = makeDriver(state)
    driver.isUserInitiated = false
    driver.showDownloadInitiated(cancellation: {})

    await driver.showUpdaterError(SplashUpdateDriverTestError.none)

    #expect(state.phase == .failed(.unknown))
    #expect(state.isPresentingUpdate)
}

@MainActor
@Test func cancellingACheckInvokesSparklesOwnHandlerAndClearsTheState() async {
    let state = UpdateState()
    let driver = makeDriver(state)
    let cancelled = Preparation()
    driver.showUserInitiatedUpdateCheck(cancellation: {
        Task { await cancelled.record() }
    })

    async let choice = driver.awaitDecisionForTesting()
    while !driver.hasPendingDecisionForTesting { await Task.yield() }
    driver.cancelCheck()

    #expect(await choice == .dismiss)
    #expect(state.phase == .idle)
    await Task.yield()
    #expect(await cancelled.count == 1)
}

@MainActor
@Test func sparkleErrorsMapToFixedUserFacingFailures() {
    let unrelated = NSError(domain: "com.example.other", code: 1)

    #expect(SplashUpdateDriver.failure(for: unrelated) == .unknown)
}

actor Preparation {
    private(set) var count = 0
    func record() { count += 1 }
}

enum SplashUpdateDriverTestError: Error {
    case none
}

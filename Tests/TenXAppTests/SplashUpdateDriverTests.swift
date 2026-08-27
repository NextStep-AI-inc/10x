import Foundation
import Sparkle
import Testing
@testable import TenXApp

@MainActor
private func makeDriver(
    _ state: UpdateState,
    prepareForInstall: @escaping @MainActor () async -> Void = {}
) -> SplashUpdateDriver {
    // terminate is a no-op here on purpose: the real default quits NSApplication, which
    // in a test process means quitting the test runner mid-suite.
    SplashUpdateDriver(
        state: state, currentVersion: "0.1.0", prepareForInstall: prepareForInstall,
        terminate: {})
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
@Test func installingTerminatesTheAppSoSparkleCanSwapTheBundle() async {
    // Sparkle cannot replace a running bundle. When it reports the app has not
    // terminated, the driver must quit it; nothing else in the app knows an install
    // is in flight. Without this the installer waits forever and the splash sits on
    // "Relaunching 10x" until the user quits by hand.
    let state = UpdateState()
    let terminated = Counter()
    let driver = SplashUpdateDriver(
        state: state, currentVersion: "0.1.0", prepareForInstall: {},
        terminate: { terminated.bump() })

    driver.showInstallingUpdate(
        withApplicationTerminated: false, retryTerminatingApplication: {})

    // The quit is deliberately deferred to a later run-loop turn; calling it inline
    // deadlocks against AppTerminationDelegate. So it is NOT expected to have happened
    // by the time this callback returns.
    #expect(terminated.count == 0)
    #expect(state.phase == .relaunching)

    for _ in 0..<200 where terminated.count == 0 { await Task.yield() }

    #expect(terminated.count == 1)
}

@MainActor
@Test func installingDoesNotTerminateAgainWhenAlreadyTerminated() async {
    let state = UpdateState()
    let terminated = Counter()
    let driver = SplashUpdateDriver(
        state: state, currentVersion: "0.1.0", prepareForInstall: {},
        terminate: { terminated.bump() })

    driver.showInstallingUpdate(
        withApplicationTerminated: true, retryTerminatingApplication: {})

    for _ in 0..<200 { await Task.yield() }

    #expect(terminated.count == 0)
    #expect(state.phase == .relaunching)
}

@MainActor
final class Counter {
    private(set) var count = 0
    func bump() { count += 1 }
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

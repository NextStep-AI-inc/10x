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

// MARK: Who owns the phase once Sparkle is done

/// `showUpdaterError` is an `NS_SWIFT_ASYNC(2)` bridge: returning from the async body is
/// the acknowledgement, and `SPUUIBasedUpdateDriver._abortUpdateWithError:` calls
/// `dismissUpdateInstallation` one main-queue turn later. Resetting there erased the
/// failure a turn after it appeared, so `Try again` and `Close` were dead code and a
/// failed update dropped straight into the workspace.
///
/// Deliberately exercises the real driver against a real `UpdateState`: the update
/// tests' `StubUpdateChecker.dismiss()` resets state, which is not what
/// `UpdateController.dismiss()` did, so a stub-based test would have measured the stub.
@MainActor
@Test func aFailureOutlivesSparklesDismissalOfTheInstallation() async {
    let state = UpdateState()
    let driver = makeDriver(state)
    driver.isUserInitiated = true
    driver.showDownloadInitiated(cancellation: {})

    await driver.showUpdaterError(SplashUpdateDriverTestError.none)
    driver.dismissUpdateInstallation()

    #expect(state.phase == .failed(.unknown))
    #expect(state.isPresentingUpdate)
}

/// Same bridge, same one-turn dismissal, for the menu check that finds nothing. Without
/// this the window blinked open and shut and the `Close` button never had a screen to
/// live on.
@MainActor
@Test func anUpToDateResultOutlivesSparklesDismissalOfTheInstallation() async {
    let state = UpdateState()
    let driver = makeDriver(state)
    driver.isUserInitiated = true
    state.beginCheck()

    await driver.showUpdateNotFoundWithError(SplashUpdateDriverTestError.none)
    driver.dismissUpdateInstallation()

    #expect(state.phase == .upToDate(currentVersion: "0.1.0"))
    #expect(state.isPresentingUpdate)
}

/// An offer is Sparkle's to clear: the decision is resumed, Sparkle ends the session and
/// dismisses. This pins that `dismissUpdateInstallation` still clears the phases Sparkle
/// itself is driving, so declining an offer does not strand the splash on it.
@MainActor
@Test func decliningAnOfferStillClearsTheSplashWhenSparkleDismisses() async {
    let state = UpdateState()
    let driver = makeDriver(state)
    state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    async let choice = driver.awaitDecisionForTesting()
    while !driver.hasPendingDecisionForTesting { await Task.yield() }
    driver.dismissUpdate()

    #expect(await choice == .dismiss)
    #expect(state.phase == .available(newVersion: "0.2.0", currentVersion: "0.1.0"))

    driver.dismissUpdateInstallation()

    #expect(state.phase == .idle)
}

/// The other half: a `.failed` with no Sparkle decision behind it (the menu watchdog's
/// own timeout, or a check against an updater that never started) has nobody left to
/// clear it. `dismissUpdate()` resumed a continuation that did not exist and returned,
/// so `Not now` was inert and the splash sat over the workspace with no way out.
@MainActor
@Test func dismissingAFailureWithNoPendingDecisionClearsItAnyway() {
    let state = UpdateState()
    let driver = makeDriver(state)
    state.fail(.unknown)

    driver.dismissUpdate()

    #expect(state.phase == .idle)
    #expect(!state.isPresentingUpdate)
}

@MainActor
@Test func dismissingAnUpToDateResultClearsItAnyway() {
    let state = UpdateState()
    let driver = makeDriver(state)
    state.showUpToDate(currentVersion: "0.1.0")

    driver.dismissUpdate()

    #expect(state.phase == .idle)
}

/// `cancelCheck()` cannot rely on Sparkle's cancellation block: `SPUUserInitiatedUpdateDriver`
/// guards it with `_showingUserInitiatedProgress` and clears that flag in
/// `basicDriverDidFinishLoadingAppcast`, which runs before `showUpdateFound` reaches this
/// driver. So an offer can still arrive after the launch gate walked away, and without
/// the abandonment flag it would paint itself over a workspace the user is already using
/// and park a decision continuation nothing on screen can resolve.
@MainActor
@Test func anAbandonedCheckRefusesAnOfferThatArrivesAnyway() async {
    let state = UpdateState()
    let driver = makeDriver(state)
    driver.beginCheck(isUserInitiated: false)
    state.beginCheck()
    driver.showUserInitiatedUpdateCheck(cancellation: {})
    driver.cancelCheck()

    let choice = await driver.offerUpdate(version: "0.2.0")

    #expect(choice == .dismiss)
    #expect(state.phase == .idle)
    #expect(!state.isPresentingUpdate)
}

/// The flag is per-check, not sticky: the next check must be able to offer again.
@MainActor
@Test func aFreshCheckAfterAnAbandonedOneCanStillOffer() async {
    let state = UpdateState()
    let driver = makeDriver(state)
    driver.beginCheck(isUserInitiated: false)
    driver.showUserInitiatedUpdateCheck(cancellation: {})
    driver.cancelCheck()

    driver.beginCheck(isUserInitiated: true)
    state.beginCheck()
    async let choice = driver.offerUpdate(version: "0.2.0")
    while !driver.hasPendingDecisionForTesting { await Task.yield() }

    #expect(state.isAwaitingDecision)

    driver.dismissUpdate()
    #expect(await choice == .dismiss)
}

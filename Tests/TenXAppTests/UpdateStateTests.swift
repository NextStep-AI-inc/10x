import Foundation
import Testing
@testable import TenXApp

@MainActor
@Test func updateStateStartsIdleAndDoesNotPresent() {
    let state = UpdateState()

    #expect(state.phase == .idle)
    #expect(!state.isPresentingUpdate)
}

@MainActor
@Test func checkingDoesNotTakeOverTheSplash() {
    let state = UpdateState()
    state.beginCheck()

    #expect(state.phase == .checking)
    #expect(!state.isPresentingUpdate)
    #expect(state.footerTitle == "Checking for updates")
    #expect(state.footerDetail == "Looking for a newer version")
}

@MainActor
@Test func availableUpdateShowsBothVersionsAndAwaitsADecision() {
    let state = UpdateState()
    state.beginCheck()
    state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    #expect(state.isPresentingUpdate)
    #expect(state.isAwaitingDecision)
    #expect(state.heading == "Update available")
    #expect(state.footerTitle == "10x 0.2.0")
    #expect(state.footerDetail == "You have 0.1.0.")
    #expect(state.signalProgress == nil)
}

@MainActor
@Test func upToDateReportsTheCurrentVersion() {
    let state = UpdateState()
    state.beginCheck()
    state.showUpToDate(currentVersion: "0.1.0")

    #expect(state.heading == "No updates available")
    #expect(state.footerTitle == "10x 0.1.0")
    #expect(state.footerDetail == "This is the newest version.")
    #expect(!state.isAwaitingDecision)
}

@MainActor
@Test func downloadProgressOccupiesTheFirstFourFifthsOfTheSignal() {
    let state = UpdateState()
    state.beginDownload()
    state.setExpectedBytes(100)
    state.addReceivedBytes(50)

    #expect(state.signalProgress == 0.4)
    #expect(state.footerTitle == "Downloading update")
    #expect(state.footerDetail == "50 bytes of 100 bytes")
}

@MainActor
@Test func aCompletedDownloadMovesStraightToVerifying() {
    let state = UpdateState()
    state.beginDownload()
    state.setExpectedBytes(100)
    state.addReceivedBytes(100)

    #expect(state.phase == .verifying)
    #expect(state.signalProgress == 0.8)
    #expect(state.footerDetail == "Checking the signature")
}

@MainActor
@Test func anUnknownContentLengthNeverProducesNonFiniteProgress() {
    let state = UpdateState()
    state.beginDownload()
    state.addReceivedBytes(4_096)

    let progress = try? #require(state.signalProgress)
    #expect(progress == 0)
    #expect(state.footerDetail == "4 KB")
}

@MainActor
@Test func installProgressOccupiesTheFinalFifthOfTheSignal() {
    let state = UpdateState()
    state.beginInstalling()

    #expect(state.signalProgress == 0.85)

    state.setExtractionFraction(1)

    #expect(state.signalProgress == 1)
    #expect(state.footerDetail == "Replacing the application")
}

@MainActor
@Test func stepsResolveInOrderAsThePhaseAdvances() {
    let state = UpdateState()
    state.beginDownload()

    #expect(state.rows.map(\.title) == [
        "Downloading update",
        "Verifying download",
        "Installing update",
        "Relaunching 10x",
    ])
    #expect(state.rows.map(\.status) == [.loading, .queued, .queued, .queued])

    state.beginVerifying()

    #expect(state.rows.map(\.status) == [.ready, .loading, .queued, .queued])

    state.beginInstalling()

    #expect(state.rows.map(\.status) == [.ready, .ready, .loading, .queued])

    state.beginRelaunching()

    #expect(state.rows.map(\.status) == [.ready, .ready, .ready, .loading])
}

@MainActor
@Test func failureStopsTheStepThatWasRunningAndKeepsEarlierStepsReady() {
    let state = UpdateState()
    state.beginDownload()
    state.beginVerifying()
    state.fail(.verification)

    #expect(state.rows.map(\.status) == [.ready, .stopped, .queued, .queued])
    #expect(state.footerTitle == "Update failed")
    #expect(state.footerDetail == "The download could not be verified.")
    #expect(state.signalProgress == nil)
}

@MainActor
@Test func everyFailureHasFixedCopyWithNoFrameworkDetail() {
    #expect(UpdateFailure.verification.detail == "The download could not be verified.")
    #expect(UpdateFailure.download.detail == "The download did not finish. Check your connection.")
    #expect(UpdateFailure.installation.detail == "The update could not be installed.")
    #expect(UpdateFailure.unknown.detail == "The update could not be completed.")
}

@MainActor
@Test func waitingForACheckOutcomeResumesWhenTheCheckResolves() async {
    let state = UpdateState()
    state.beginCheck()

    async let wait: Void = state.waitForCheckOutcome()
    state.showUpToDate(currentVersion: "0.1.0")
    await wait

    #expect(!state.isAwaitingDecision)
}

@MainActor
@Test func waitingForACheckOutcomeReturnsImmediatelyWhenNotChecking() async {
    let state = UpdateState()

    await state.waitForCheckOutcome()

    #expect(state.phase == .idle)
}

@MainActor
@Test func waitingWhilePresentingResumesOnceTheOfferIsDeclined() async {
    let state = UpdateState()
    state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    async let wait: Void = state.waitWhilePresenting()
    state.reset()
    await wait

    #expect(state.phase == .idle)
}

@MainActor
@Test func waitingWhilePresentingSpansAFailedUpdateUntilItIsDismissed() async {
    let state = UpdateState()
    state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    async let wait: Void = state.waitWhilePresenting()
    state.beginDownload()
    await Task.yield()

    #expect(state.isPresentingUpdate)

    state.fail(.download)
    await Task.yield()

    #expect(state.isPresentingUpdate)

    state.reset()
    await wait

    #expect(state.phase == .idle)
}

@MainActor
@Test func waitingWhilePresentingReturnsImmediatelyWhenNothingIsShown() async {
    let state = UpdateState()

    await state.waitWhilePresenting()

    #expect(state.phase == .idle)
}

@MainActor
@Test func updatePresentationOffersInstallThenNotNow() {
    let state = UpdateState()
    state.beginCheck()
    state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    let presentation = SplashPresentation.update(
        state: state, onInstall: {}, onDismiss: {}, onRetry: {})

    #expect(presentation.heading == "Update available")
    #expect(presentation.actions.map(\.title) == ["Install and relaunch", "Not now"])
    #expect(presentation.actions.map(\.kind) == [.primary, .secondary])
    #expect(presentation.footerTone == .working)
    #expect(!presentation.isSignalAnimating)
}

@MainActor
@Test func failedPresentationOffersTryAgainThenClose() {
    let state = UpdateState()
    state.beginDownload()
    state.fail(.download)

    let presentation = SplashPresentation.update(
        state: state, onInstall: {}, onDismiss: {}, onRetry: {})

    #expect(presentation.heading == "Updating 10x")
    #expect(presentation.footerTone == .failed)
    #expect(presentation.isSignalFailed)
    #expect(presentation.actions.map(\.title) == ["Try again", "Close"])
}

@MainActor
@Test func inFlightPresentationOffersNoActions() {
    let state = UpdateState()
    state.beginDownload()

    let presentation = SplashPresentation.update(
        state: state, onInstall: {}, onDismiss: {}, onRetry: {})

    #expect(presentation.actions.isEmpty)
    #expect(presentation.heading == "Updating 10x")
}

// MARK: Truthful headings, honest ledgers

/// The heading is the largest text on the splash. `.failed` used to fall through to a
/// default of "Installing update", so a download that never got past verification
/// announced a step that had not run, and during the download itself the heading was a
/// verbatim copy of ledger row three.
@MainActor
@Test func noHeadingClaimsAStepOrRepeatsARowTitle() {
    let rowTitles = Set(UpdateStepID.allCases.map(\.title))

    let downloading = UpdateState()
    downloading.beginDownload()
    let failed = UpdateState()
    failed.beginDownload()
    failed.beginVerifying()
    failed.fail(.verification)
    let installing = UpdateState()
    installing.beginInstalling()
    let relaunching = UpdateState()
    relaunching.beginRelaunching()

    for state in [downloading, failed, installing, relaunching] {
        #expect(state.heading == "Updating 10x")
        #expect(!rowTitles.contains(state.heading))
    }
}

/// `Try again` and `Check for Updates...` both re-enter `.checking`. While that was not
/// a presenting phase the window simply vanished for as long as the check took, up to
/// fifteen seconds, with no indication anything was happening.
@MainActor
@Test func aCheckTheUserAskedForStaysOnScreen() {
    let state = UpdateState()
    state.beginCheck(isUserInitiated: true)

    #expect(state.isPresentingUpdate)
    #expect(state.heading == "Checking for updates")
    #expect(state.footerTitle == "Checking for updates")
    #expect(state.footerDetail == "Looking for a newer version")
}

/// The advisory launch check must still be invisible.
@MainActor
@Test func anAdvisoryLaunchCheckStaysOffTheSplash() {
    let state = UpdateState()
    state.beginCheck(isUserInitiated: false)

    #expect(!state.isPresentingUpdate)
}

/// Four `Queued` steps that can never run is a promise the app cannot keep. A menu check
/// that found nothing has no install to describe, and neither does one that timed out
/// before a single step began.
@MainActor
@Test func theLedgerIsEmptyWhenThereIsNoInstallToDescribe() {
    let upToDate = UpdateState()
    upToDate.beginCheck(isUserInitiated: true)
    upToDate.showUpToDate(currentVersion: "0.1.0")

    #expect(upToDate.rows.isEmpty)

    let timedOut = UpdateState()
    timedOut.beginCheck(isUserInitiated: true)
    timedOut.reset()
    timedOut.fail(.unknown)

    #expect(timedOut.rows.isEmpty)

    let checking = UpdateState()
    checking.beginCheck(isUserInitiated: true)

    #expect(checking.rows.isEmpty)
}

/// An offer has a run ahead of it, and a failure mid-run has one behind it. Both keep
/// their steps.
@MainActor
@Test func theLedgerSurvivesAnOfferAndAFailureInsideARun() {
    let offered = UpdateState()
    offered.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    #expect(offered.rows.map(\.status) == [.queued, .queued, .queued, .queued])

    let failedMidRun = UpdateState()
    failedMidRun.beginDownload()
    failedMidRun.beginVerifying()
    failedMidRun.fail(.verification)

    #expect(failedMidRun.rows.map(\.status) == [.ready, .stopped, .queued, .queued])
}

/// Sparkle reports the expected content length after the download has already started,
/// so the first frame is 0 of 0. `ByteCountFormatter` renders that as "Zero KB", which
/// reads as a download that has broken rather than one that has just begun.
@MainActor
@Test func theFirstDownloadFrameSaysItIsStartingRatherThanZeroKB() {
    let state = UpdateState()
    state.beginDownload()

    #expect(state.footerDetail == "Starting the download")
    #expect(!state.footerDetail.contains("Zero"))
}

/// Sentence case throughout, matching every other action on this splash.
@MainActor
@Test func splashActionsAreSentenceCase() {
    let offered = UpdateState()
    offered.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")
    let failed = UpdateState()
    failed.beginDownload()
    failed.fail(.download)
    let upToDate = UpdateState()
    upToDate.showUpToDate(currentVersion: "0.1.0")

    let titles = [offered, failed, upToDate].flatMap { state in
        SplashPresentation.update(state: state, onInstall: {}, onDismiss: {}, onRetry: {})
            .actions.map(\.title)
    }

    #expect(titles == ["Install and relaunch", "Not now", "Try again", "Close", "Close"])
    for title in titles {
        let words = title.split(separator: " ").dropFirst()
        #expect(words.allSatisfy { $0.first?.isUppercase != true })
    }
}

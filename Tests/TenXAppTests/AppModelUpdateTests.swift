import Foundation
import Testing
@testable import TenXApp

// `sleep: { _ in }` (the brief's literal fixture) resolves every duration instantly,
// including the watchdog's own `timeout`. `withWatchdog` races real preparation work
// against `timing.sleep(timing.timeout)` in a task group; the timeout side isn't
// MainActor-isolated, so it can complete before the MainActor-bound `operation()` child
// even gets scheduled, and an instant "sleep" wins that race deterministically —
// verified by tracing the caught error, which was `StartupAttemptError.timeout` on
// every run. That sends every one of these tests into `.recovery` before the update
// check has anything to do with the outcome. Only `timing.timeout` needs to stay a real
// (long) sleep so the watchdog never fires under normal conditions; everything else
// (`minimumVisibility`, `updateCheckDeadline`) should still resolve instantly. This
// mirrors `appModelTestTiming` in AppModelNavigationTests.swift and
// `StartupTiming.controlledTimeout` in StartupTestFixtures.swift, both of which already
// special-case the watchdog's duration for the same reason.
private let updateTestTiming = StartupTiming(
    minimumVisibility: .zero,
    timeout: .seconds(10),
    updateCheckDeadline: .milliseconds(50),
    sleep: { duration in
        guard duration == .seconds(10) else { return }
        try await ContinuousClock().sleep(for: .seconds(60))
    })

@MainActor
@Test func aLaunchWithNoUpdateHandsOffNormally() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let checker = StubUpdateChecker()
    // What the real driver does at launch when the feed has nothing newer.
    checker.onCheck = { $0.reset() }
    let model = fixture.model(timing: updateTestTiming, updateChecker: checker)

    await model.bootstrap()

    #expect(model.startupState.phase == .handoff)
    #expect(model.startupState.status(of: .updates) == .ready)
    if let manager = model.processManager { await manager.closeAll() }
}

@MainActor
@Test func aFailedUpdateStillReachesTheWorkspaceOnceDismissed() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let checker = StubUpdateChecker()
    checker.onCheck = { $0.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0") }
    let model = fixture.model(timing: updateTestTiming, updateChecker: checker)

    let bootstrap = Task { await model.bootstrap() }
    while !model.updateState.isAwaitingDecision { await Task.yield() }
    model.updateState.beginDownload()
    model.updateState.fail(.download)
    await Task.yield()

    #expect(model.startupState.phase != .handoff)

    model.dismissUpdate()
    await bootstrap.value

    #expect(model.startupState.phase == .handoff)
    if let manager = model.processManager { await manager.closeAll() }
}

@MainActor
@Test func aStalledCheckIsCancelledAndTheLaunchProceeds() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let checker = StubUpdateChecker()

    let model = fixture.model(timing: updateTestTiming, updateChecker: checker)
    await model.bootstrap()

    #expect(checker.cancelCount == 1)
    #expect(model.startupState.phase == .handoff)
    #expect(model.startupState.status(of: .updates) == .ready)
    if let manager = model.processManager { await manager.closeAll() }
}

@MainActor
@Test func anAvailableUpdateHoldsTheWorkspaceUntilTheUserAnswers() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let checker = StubUpdateChecker()
    checker.onCheck = { $0.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0") }
    let model = fixture.model(timing: updateTestTiming, updateChecker: checker)

    let bootstrap = Task { await model.bootstrap() }
    while !model.updateState.isAwaitingDecision { await Task.yield() }

    #expect(model.startupState.phase != .handoff)

    model.dismissUpdate()
    await bootstrap.value

    #expect(model.startupState.phase == .handoff)
    if let manager = model.processManager { await manager.closeAll() }
}

@MainActor
@Test func acceptingAnUpdateNeverOpensTheWorkspace() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let checker = StubUpdateChecker()
    checker.onCheck = { $0.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0") }
    let model = fixture.model(timing: updateTestTiming, updateChecker: checker)

    let bootstrap = Task { await model.bootstrap() }
    while !model.updateState.isAwaitingDecision { await Task.yield() }
    model.updateState.beginDownload()
    for _ in 0..<10 { await Task.yield() }

    // A real install terminates the process here. Nothing may reach the workspace first.
    #expect(model.startupState.phase != .handoff)
    #expect(!model.startupState.consumeWorkspaceOpenRequest())

    // Release the gate so the test does not leak a suspended bootstrap task.
    model.updateState.reset()
    await bootstrap.value
    if let manager = model.processManager { await manager.closeAll() }
}

@MainActor
@Test func aMenuCheckIsUserInitiatedAndIgnoredWhileOneIsOnScreen() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let checker = StubUpdateChecker()
    let model = fixture.model(timing: updateTestTiming, updateChecker: checker)

    model.checkForUpdatesFromMenu()

    #expect(checker.checkCount == 1)
    #expect(checker.lastCheckWasUserInitiated == true)

    model.updateState.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")
    model.checkForUpdatesFromMenu()

    #expect(checker.checkCount == 1)
    if let manager = model.processManager { await manager.closeAll() }
}

/// Closes review finding (A) end to end through `AppModel`: only `checkAtLaunch` had a
/// deadline before this change, so a menu check against a checker that never answers
/// (the same shape as an updater whose `start()` failed) left `updateState.phase` stuck
/// at `.checking` forever, with `isPresentingUpdate` false the whole time — the splash
/// would never even reopen, and the menu item would silently do nothing on every click.
@MainActor
@Test func aStalledMenuCheckFailsVisiblyInsteadOfHangingForever() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let checker = StubUpdateChecker()
    let model = fixture.model(timing: updateTestTiming, updateChecker: checker)

    model.checkForUpdatesFromMenu()
    #expect(model.updateState.phase == .checking)

    while model.updateState.phase == .checking { await Task.yield() }

    #expect(checker.cancelCount == 1)
    #expect(model.updateState.phase == .failed(.unknown))
    #expect(model.updateState.isPresentingUpdate)
    if let manager = model.processManager { await manager.closeAll() }
}

/// `retryUpdate()` ("Try again" on the visible failure above) must get its own deadline
/// too. Before this fix, retrying against a checker that is still permanently broken
/// would re-enter `.checking` with nothing watching it — one click deeper into the same
/// stall the finding describes, this time with the splash's dismissal branch able to
/// close the window on the next handoff-phase change and leave no trace it ever hung.
@MainActor
@Test func retryingAStalledMenuCheckGetsItsOwnDeadlineInsteadOfStallingSilently() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let checker = StubUpdateChecker()
    let model = fixture.model(timing: updateTestTiming, updateChecker: checker)

    model.checkForUpdatesFromMenu()
    while model.updateState.phase == .checking { await Task.yield() }
    #expect(model.updateState.phase == .failed(.unknown))

    model.retryUpdate()
    while model.updateState.phase == .checking { await Task.yield() }

    #expect(checker.cancelCount == 2)
    #expect(model.updateState.phase == .failed(.unknown))
    if let manager = model.processManager { await manager.closeAll() }
}

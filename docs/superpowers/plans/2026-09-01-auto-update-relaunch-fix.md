# Auto-Update Relaunch Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow Sparkle to finish installing an update by removing the app's duplicate quit request.

**Architecture:** Sparkle owns the quit request and waits for the app delegate's asynchronous shutdown reply. `SplashUpdateDriver` remains responsible only for presenting the `.relaunching` state, so it cannot block the main actor while termination is pending.

**Tech Stack:** Swift 6, AppKit, Sparkle 2.9.6, Swift Testing, Xcode

---

### Task 1: Pin the corrected termination contract

**Files:**
- Modify: `Tests/TenXAppTests/SplashUpdateDriverTests.swift`

- [x] **Step 1: Invert the existing duplicate-quit test**

Change the existing test's final expectation so the currently injected termination
closure must remain untouched:

```swift
@MainActor
@Test func installingDoesNotSendADuplicateQuitWhileSparkleWaits() async {
    let state = UpdateState()
    let terminated = Counter()
    let driver = SplashUpdateDriver(
        state: state, currentVersion: "0.1.0", prepareForInstall: {},
        terminate: { terminated.bump() })

    driver.showInstallingUpdate(
        withApplicationTerminated: false, retryTerminatingApplication: {})

    for _ in 0..<200 { await Task.yield() }

    #expect(terminated.count == 0)
    #expect(state.phase == .relaunching)
}
```

- [x] **Step 2: Run the test to verify the current implementation fails**

Run:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  '-only-testing:TenXAppTests/installingDoesNotSendADuplicateQuitWhileSparkleWaits()'
```

Expected: FAIL because the deferred termination closure is called once.

### Task 2: Remove the duplicate termination request

**Files:**
- Modify: `App/Updates/SplashUpdateDriver.swift`
- Modify: `Tests/TenXAppTests/SplashUpdateDriverTests.swift`

- [x] **Step 1: Delete the termination dependency from the driver**

Remove the `terminate` property and initializer parameter so the initializer becomes:

```swift
init(
    state: UpdateState,
    currentVersion: String,
    prepareForInstall: @escaping @MainActor () async -> Void
) {
    self.state = state
    self.currentVersion = currentVersion
    self.prepareForInstall = prepareForInstall
    super.init()
}
```

- [x] **Step 2: Make the install callback presentation-only**

Replace the callback body and ownership comment with:

```swift
/// Sparkle sends the application a quit event before this callback. The driver must
/// not send another one while `AppTerminationDelegate` is preparing its asynchronous
/// reply, because a nested `NSApplication.terminate(_:)` blocks the main actor and
/// prevents that reply from completing.
func showInstallingUpdate(
    withApplicationTerminated applicationTerminated: Bool,
    retryTerminatingApplication: @escaping () -> Void
) {
    state.beginRelaunching()
}
```

- [x] **Step 3: Keep a durable behavior test without a production-only test hook**

Remove the constructor's no-op `terminate` argument, delete `Counter`, and replace the
two termination tests with:

```swift
@MainActor
@Test func installingReliesOnSparklesExistingTerminationRequest() async {
    let state = UpdateState()
    let retried = Preparation()
    let driver = makeDriver(state)

    driver.showInstallingUpdate(
        withApplicationTerminated: false,
        retryTerminatingApplication: { Task { await retried.record() } })

    for _ in 0..<200 { await Task.yield() }

    #expect(await retried.count == 0)
    #expect(state.phase == .relaunching)
}
```

This pins the supported Sparkle callback contract without retaining an otherwise unused
termination injection point solely for tests.

- [x] **Step 4: Run focused updater tests**

Run:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  '-only-testing:TenXAppTests/installingReliesOnSparklesExistingTerminationRequest()'
```

Expected: PASS.

- [x] **Step 5: Commit the fix**

```bash
git add App/Updates/SplashUpdateDriver.swift Tests/TenXAppTests/SplashUpdateDriverTests.swift
git commit -m "fix(updates): let Sparkle own application termination"
```

### Task 3: Verify the release path

**Files:**
- Modify: pull request description only

- [x] **Step 1: Run the full test suite**

Run:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
```

Expected: `** TEST SUCCEEDED **`.

- [x] **Step 2: Build the Release app**

Run:

```bash
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-update-relaunch-fix
```

Expected: `** BUILD SUCCEEDED **` and a signed app at
`/private/tmp/tenx-update-relaunch-fix/Build/Products/Release/10x.app`.

- [x] **Step 3: Exercise the real update lifecycle**

Launch the Release app, accept the offered update, and verify all of the following:

```text
The original process exits without a manual quit.
Sparkle replaces the application bundle.
The new application version launches automatically.
The workspace becomes visible after relaunch.
```

Expected: the app relaunches on the offered version and no updater helper remains stuck.

- [x] **Step 4: Push and update the draft PR with exact evidence**

```bash
git push
gh pr edit 16 --body-file /tmp/tenx-pr-16.md
```

Expected: PR 16 contains the focused test, full-suite, Release-build, and live-update evidence.

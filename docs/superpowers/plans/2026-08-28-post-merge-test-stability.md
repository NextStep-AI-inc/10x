# Post-Merge Test Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the macOS verification suite deterministic on a shared, loaded host and ensure a fixture-start timeout cannot leave subprocess work alive after its test exits.

**Architecture:** Keep production startup behavior unchanged. Configure the generated Xcode test bundle to run serially, then harden the shared `OmpCommandFixture` so setup failures cancel and await the operation they started. The generated scheme remains owned exclusively by `scripts/generate_xcodeproj.rb`.

**Tech Stack:** Swift 6.3, Swift Testing, Xcode 26.6, Ruby 2.6 with xcodeproj 1.27.0.

---

## Root-cause evidence

- The unchanged merge tree passed 897 tests before merge, then produced 52 unrelated timing and snapshot issues while the shared host load exceeded 500.
- Failed snapshots rendered startup recovery/onboarding fallback screens, not changed pixels. The startup watchdog won before fixtures reached their intended state.
- Process tests could throw from `waitForPIDs` before cancelling or awaiting the task that owned the child command; the test process then failed to exit.
- With no source changes and host load still above 200, `xcodebuild test ... -parallel-testing-enabled NO` passed all 897 tests in 19 suites after 55.800 seconds.
- Apple documents Swift Testing's default parallel execution and serialization support: https://developer.apple.com/documentation/testing/parallelizationtrait

### Task 1: Generate a serialized test bundle

**Files:**
- Create: `Tests/TenXAppTests/ProjectGenerationTests.swift`
- Modify: `scripts/generate_xcodeproj.rb`
- Generate: `10x.xcodeproj/project.pbxproj`
- Generate: `10x.xcodeproj/xcshareddata/xcschemes/10x.xcscheme`

- [x] **Step 1: Write the failing project-generation test**

```swift
import Foundation
import Testing

@Test func sharedSchemeSerializesTheAppTestBundle() throws {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let schemeURL = repositoryRoot
        .appending(path: "10x.xcodeproj/xcshareddata/xcschemes/10x.xcscheme")
    let scheme = try String(contentsOf: schemeURL, encoding: .utf8)

    #expect(scheme.contains("parallelizable = \"NO\""))
}
```

- [x] **Step 2: Regenerate and verify RED**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-post-merge-red \
  '-only-testing:TenXAppTests/sharedSchemeSerializesTheAppTestBundle()'
```

Expected: one test runs and fails because the generated scheme lacks `parallelizable = "NO"`.

- [x] **Step 3: Make the generator serialize its testable**

Immediately after `scheme.add_test_target(tests)`, add:

```ruby
testable = scheme.test_action.testables.first
raise "[generate_xcodeproj] generated scheme has no testable" unless testable
testable.parallelizable = false
```

- [x] **Step 4: Regenerate and verify GREEN**

```bash
ruby scripts/generate_xcodeproj.rb
ruby scripts/generate_xcodeproj.rb
git diff --check
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-post-merge-green \
  '-only-testing:TenXAppTests/sharedSchemeSerializesTheAppTestBundle()'
```

Expected: regeneration is byte-stable and the selected test passes.

- [x] **Step 5: Commit the generated scheme behavior**

```bash
git add Tests/TenXAppTests/ProjectGenerationTests.swift scripts/generate_xcodeproj.rb \
  10x.xcodeproj/project.pbxproj 10x.xcodeproj/xcshareddata/xcschemes/10x.xcscheme
git commit -m "fix(tests): serialize the macOS test bundle"
```

### Task 2: Reap operations when process-fixture setup times out

**Files:**
- Modify: `Tests/TenXAppTests/OmpCommandRunnerTests.swift`
- Modify: `Tests/TenXAppTests/OmpConfigServiceTests.swift`
- Modify: `Tests/TenXAppTests/OmpUsageServiceTests.swift`
- Modify: `Tests/TenXAppTests/ProviderManagementViewModelTests.swift`

- [x] **Step 1: Write a failing cleanup test**

```swift
@Test func pidWaitCancelsAndAwaitsItsOperationOnTimeout() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let operation = Task {
        try await ContinuousClock().sleep(for: .seconds(60))
    }

    await #expect(throws: OmpCommandFixtureError.self) {
        _ = try await fixture.waitForPIDs(
            in: fixture.root.appending(path: "never-created.pid"),
            count: 1,
            timeout: .milliseconds(20),
            cancelling: operation)
    }
    #expect(operation.isCancelled)
}
```

- [x] **Step 2: Verify RED**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-operation-cleanup-red \
  '-only-testing:TenXAppTests/pidWaitCancelsAndAwaitsItsOperationOnTimeout()'
```

Expected: compilation fails because the timeout/task-owning overload does not exist.

- [x] **Step 3: Implement the minimum cleanup overload**

Change the existing helper to accept `timeout`, then add:

```swift
func waitForPIDs<Success, Failure: Error>(
    in file: URL,
    count: Int,
    timeout: Duration = .seconds(10),
    cancelling operation: Task<Success, Failure>
) async throws -> [pid_t] {
    do {
        return try await waitForPIDs(in: file, count: count, timeout: timeout)
    } catch {
        operation.cancel()
        _ = await operation.result
        throw error
    }
}
```

Use this overload for each `OmpCommandFixture.waitForPIDs` call made after starting an unstructured operation in the four owned test files. Keep success-path assertions unchanged.

- [x] **Step 4: Verify GREEN and affected process tests**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-operation-cleanup-green \
  '-only-testing:TenXAppTests/pidWaitCancelsAndAwaitsItsOperationOnTimeout()' \
  '-only-testing:TenXAppTests/cancellingOmpCommandRunnerReapsAnIgnoringProcessGroup()' \
  '-only-testing:TenXAppTests/cancellationEscalatesAfterTheProcessLeaderExits()' \
  '-only-testing:TenXAppTests/cancellationReapsADescendantSpawnedByTheTerminationHandler()' \
  '-only-testing:TenXAppTests/cancellingConfigServiceReapsTheCommand()' \
  '-only-testing:TenXAppTests/cancellingUsageServiceReapsTheCommand()' \
  '-only-testing:TenXAppTests/providerShutdownCancelsAndAwaitsAnInflightUsageCommand()'
```

Expected: seven tests run and pass; no owned child command remains afterward.

- [x] **Step 5: Commit cleanup hardening**

```bash
git add Tests/TenXAppTests/OmpCommandRunnerTests.swift \
  Tests/TenXAppTests/OmpConfigServiceTests.swift \
  Tests/TenXAppTests/OmpUsageServiceTests.swift \
  Tests/TenXAppTests/ProviderManagementViewModelTests.swift
git commit -m "test: reap commands after fixture startup failures"
```

### Task 3: Document and verify the complete branch

**Files:**
- Modify: `docs/testing.md`
- Modify: this plan checklist as work completes

- [x] **Step 1: Document the execution contract**

After the full-suite command, explain that the generated shared scheme intentionally serializes `TenXAppTests` because the target contains process-spawning, MainActor snapshot, and startup-watchdog tests. State that callers should not override it with `-parallel-testing-enabled YES`; focused selectors remain fast.

- [x] **Step 2: Run generator and static checks**

```bash
ruby scripts/generate_xcodeproj.rb
ruby scripts/generate_xcodeproj.rb
git diff --check
```

Expected: the second generation produces no diff and `git diff --check` is clean.

- [x] **Step 3: Run the complete suite from fresh derived data**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-post-merge-final
```

Expected: 899 tests pass after adding both regression tests, the run prints `** TEST SUCCEEDED **`, and `xcodebuild` exits without intervention.

- [x] **Step 4: Run a Release build**

```bash
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' -derivedDataPath /tmp/tenx-post-merge-release
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit documentation, update the draft PR, and request review**

```bash
git add docs/testing.md docs/superpowers/plans/2026-08-28-post-merge-test-stability.md
git commit -m "docs: record the deterministic test workflow"
git push
```

Update PR #12 with exact counts and commands. Do not merge without explicit approval.

## Operational cleanup outside the PR

- Remove only the two Codex-owned worktrees from PR #11 after their failure artifacts are no longer needed.
- Delete `codex/multi-account-ui-polish` locally after its worktree is removed.
- Do not delete `tannerpham/resume-codex-implementation-833cbd` while another Claude worktree has that branch checked out; report it as externally owned.
- Do not update the user-owned main checkout.

# Task 4 implementer report

Status: DONE_WITH_CONCERNS

## Delivered

- Added the in-memory `AgentDesktopManifest` and exact-ID lifecycle updates.
- Added conservative before/watcher/launch/stable-after claims. Only one newly
  observed window correlated to the launched process is moved and owned;
  ambiguity moves nothing.
- Added the exact `agent_desktop` host-tool contract with borrow, launch,
  sanitised results, and cancellation that ignores late success or ambiguity.
- Added cleanup that restores only live, owned windows with known original
  workspaces. It never closes a window or terminates a process.
- Regenerated the Xcode project and shared scheme.

## TDD evidence

The tests were written before each implementation increment. RED evidence
included missing manifest/launcher APIs, missing cleanup and host-tool APIs,
post-launch delayed window observation, ambiguous multi-window launches,
watcher access, stable snapshot confirmation, and late ambiguous completion
after cancellation. Each increment was then made green.

Verified:

- `ruby scripts/generate_xcodeproj.rb && xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task4`
  passed: 138 tests, `** TEST SUCCEEDED **`.
- `xcodebuild build -configuration Release -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task4-release-build-final`
  passed: `** BUILD SUCCEEDED **`.
- `git diff --check` passed.

Not verified:

- A Release test run cannot compile the existing test target because Release
  disables the module testability required by the repository's
  `@testable import TenXApp` tests. The Release application build succeeds;
  no build-setting change was made because it is outside this task's fence.
- A live external application launch/move/restore was not performed. The
  launch and provider seams are covered with fakes, and Task 5 owns the
  enabled-session/controller integration that keeps the watcher attached to
  the active manifest.

## Concerns and follow-up ownership

- `.newWindow` remains explicitly unsupported until an existing,
  application-specific documented native action is available. No shell or UI
  automation was introduced.
- Task 5 must retain the manifest and consume `watchWindows(in:)` while
  computer use is enabled; no persistence was added here.

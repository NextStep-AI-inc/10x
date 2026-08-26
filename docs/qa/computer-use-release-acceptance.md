# Computer Use Release Acceptance

Date: 2026-08-25
Branch: `codex/computer-use-design`
Build SHA: `09a3215`
Release app: `/tmp/tenx-agent-desktop-release/Build/Products/Release/10x.app`
Release PID observed: `90519`
OMP prerequisite binary: `/Users/tannerpham/CS Projects/.worktrees/oh-my-pi-computer-foreground-handoff/packages/coding-agent/dist/omp`
OMP prerequisite version: `omp/18.0.5`

## Automated Checks

| Check | Evidence | Result |
|---|---|---|
| Whitespace/static diff check | `git diff --check` exited 0 | PASS |
| OmpKit contract tests | `swift test --package-path OmpKit` passed 165 tests with 2 expected environment skips on rerun | PASS |
| App tests | `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-final-tests-rerun` passed 210 tests | PASS |
| Release build | `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-release` succeeded | PASS |
| Release architecture | `file` reported a Mach-O universal binary with `x86_64` and `arm64` slices | PASS |
| Release launch | PID `90519` was running from `/private/tmp/tenx-agent-desktop-release/Build/Products/Release/10x.app/Contents/MacOS/10x`; System Events reported one `10x` window | PASS |
| Entitlements | `codesign -dv --entitlements :-` showed only `com.apple.security.get-task-allow` from local Xcode signing | PASS |
| OMP smoke | Approved prerequisite binary reported `omp/18.0.5` and `smoke-test: ok` | PASS |

Note: the first OmpKit run hit `lineBacklogOverflowFailsClosedInsteadOfDroppingFrames`; the single test and full rerun both passed. The root cause is a timing-sensitive test wait, not a deterministic transport failure. The first app test run also hit AppModel navigation wait timeouts under full-suite load; the cached full rerun passed.

## Desktop Acceptance Matrix

| Configuration | Build | Focus unchanged | Pointer unchanged | Existing windows unchanged | Evidence rendered | Result |
|---|---|---:|---:|---:|---:|---|
| AeroSpace | Release | No | No | No | No | FAIL |
| Hammerspoon | Release | No | No | No | No | FAIL |
| Background Only | Release | No | No | No | No | FAIL |
| Older OMP | Release | N/A | N/A | N/A | No | FAIL |

## Physical Desktop Evidence

- AeroSpace was not testable in this environment: `aerospace` was not on PATH from the worktree shell.
- Hammerspoon was not testable in this environment: macOS could not resolve an installed `Hammerspoon` application by AppleScript.
- Background Only was not exercised through a live configured agent session in the Release app.
- Older OMP gating was not exercised because no 18.0.4 binary was available in this worktree.
- Release UI snapshots for setup complete, setup degraded, Ready, Controlling, Needs handoff, and computer evidence are covered by the automated snapshot suite, not by live physical desktop interaction.

## Completion Gate

| Requirement | Evidence | Result |
|---|---|---|
| Prerequisite OMP contract is available to the tested binary | Approved prerequisite OMP reports `omp/18.0.5` and smoke passes | PASS |
| New and reopened sessions start with computer use Off | Covered by app tests, including `reopeningAnEnabledOMPComputerSessionDisablesItAndStaysOff` | PASS |
| Cross-process and same-process contention allow one controlling session only | Covered by lease and registry tests | PASS |
| Automatic selection order is AeroSpace, Hammerspoon, Background Only | Covered by provider selection tests | PASS |
| Provider commands use fixed argv, timeout, capped output, validated JSON, and no shell | Covered by command runner and provider tests | PASS |
| Only new window IDs are claimed; borrowed or ambiguous windows are untouched | Covered by launcher and host-tool tests | PASS |
| Denied handoff produces no focus-changing native call; approval is one-shot | Covered by controller tests and handoff card review | PASS |
| Stop, helper exit, permission loss, lock, sleep, logout, and OMP exit converge on fail-closed cleanup | Unit coverage exists for Stop, helper exit, permission loss, OMP exit, teardown, and shortcut/menu path; lock/sleep physical behavior not exercised | PARTIAL |
| Computer screenshots and details render live and after session reopen | Covered by presentation, reducer, history mapper, and snapshot tests | PASS |
| Header, menu bar, and emergency shortcut invoke the same Stop path | Covered by controller, menu, app model, and shortcut code review/tests | PASS |
| AeroSpace, Hammerspoon, Background Only, and older-OMP Release checks are recorded | Recorded above as failed/not run where the environment was missing prerequisites | PASS |
| Any stolen focus, pointer movement, misplaced keystroke, moved existing window, or automatic desktop switch is a release failure | No physical desktop run was performed; the matrix remains FAIL until observed | FAIL |

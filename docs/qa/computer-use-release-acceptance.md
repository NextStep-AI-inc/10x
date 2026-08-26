# Computer Use Release Acceptance

Date: 2026-08-26
Branch: `codex/computer-use-design`
Build SHA: `0b8ad26`
Release app: `/tmp/tenx-agent-desktop-release-0b8ad26/Build/Products/Release/10x.app`
Release PID observed: `25273`
OMP prerequisite binary: `/Users/tannerpham/CS Projects/.worktrees/oh-my-pi-computer-foreground-handoff/packages/coding-agent/dist/omp`
OMP prerequisite version: `omp/18.0.5`

## Automated Checks

| Check | Evidence | Result |
|---|---|---|
| Whitespace/static diff check | `git diff --check` exited 0 | PASS |
| OmpKit contract tests | `swift test --package-path OmpKit --no-parallel` passed 165 tests with 2 expected environment skips | PASS |
| App tests | `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath /tmp/tenx-computer-use-final-tests-0b8ad26-rerun -resultBundlePath /tmp/tenx-computer-use-final-0b8ad26.xcresult` passed 223 tests | PASS |
| Release build | `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'generic/platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-release-0b8ad26` succeeded | PASS |
| Release architecture | `file` reported a Mach-O universal binary with `x86_64` and `arm64` slices | PASS |
| Release launch | PID `25273` ran from the exact packaged Release path. A real `10x` window was created through the packaged app's File > New Window command. The background launch and restored foreground left ChatGPT active; pointer coordinates remained exactly unchanged. | PASS |
| Entitlements | `codesign -dv --entitlements :-` showed only `com.apple.security.get-task-allow` from local Xcode signing | PASS |
| OMP smoke | Approved prerequisite binary reported `omp/18.0.5` and `smoke-test: ok` | PASS |

The final exact-head OmpKit and app suites passed on their canonical runs. Earlier timing-sensitive failures from the pre-fix acceptance pass are superseded by this evidence.

## Desktop Acceptance Matrix

| Configuration | Build | Focus unchanged | Pointer unchanged | Existing windows unchanged | Evidence rendered | Result |
|---|---|---:|---:|---:|---:|---|
| AeroSpace helper isolation | Release environment | Yes | Yes | Yes | N/A | PASS |
| AeroSpace full 10x + OMP flow | Release | Not run | Not run | Not run | No | BLOCKED |
| Hammerspoon | Release environment | Yes | Yes | Yes | No | FAIL CLOSED |
| Background Only | Release | Not run | Not run | Not run | No | NOT RUN |
| Older OMP | Release | N/A | N/A | N/A | Best-effort label Yes | PASS |

## Physical Desktop Evidence

- AeroSpace `0.21.3-Beta` and Hammerspoon `1.1.1` were installed and configured for this acceptance pass. Hammerspoon used native user Space `1709`; the previously selected fullscreen Space was rejected by the final validation.
- AeroSpace helper isolation passed against a real TextEdit window. The window moved to workspace `10x-physicalqa` while the foreground 10x process/window, pointer coordinates, current native Space, current AeroSpace workspace, and pre-existing windows remained unchanged. The exact probe window was closed afterward.
- The full 10x + OMP AeroSpace flow remained blocked because the locally ad-hoc-signed OMP worker continued to receive macOS Accessibility denial even after the binary was visibly enabled in System Settings. Screen Recording was granted. This is a signing/responsible-process identity blocker, not an AeroSpace isolation failure.
- Hammerspoon's private Spaces calls returned success but did not move a real TextEdit window to native user Space `1709`, and `gotoSpace(1709)` likewise left the focused Space unchanged. Foreground application/window and existing windows remained unchanged. The final Lua bridge now verifies `windowSpaces` and `focusedSpace`, accepts only `user` spaces, and reports these no-ops as failure instead of success.
- Setup now waits up to two seconds for the selected provider to observe the exact disposable probe window ID before attempting placement, closing the AeroSpace registration race observed during physical acceptance.
- Background Only was not exercised through a live configured agent session in the Release app.
- Older OMP gating was exercised through the real Release settings surface using the default `~/.bun/bin/omp` (`omp/18.0.4`). The UI displayed `BEST EFFORT`, reported `OMP: omp/18.0.4 · Best effort`, retained the warning that background control may interrupt the current app, and the setup probe failed closed without claiming window placement.
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
| Stop, helper or watcher failure, permission loss, lock, sleep, logout, and OMP exit converge on fail-closed cleanup | Unit coverage exists for Stop, helper/watch failure, permission loss, OMP exit, teardown, and shortcut/menu path; lock/sleep physical behavior not exercised | PARTIAL |
| Computer screenshots and details render live and after session reopen | Covered by presentation, reducer, history mapper, and snapshot tests | PASS |
| Header, menu bar, and emergency shortcut invoke the same Stop path | Covered by controller, menu, app model, and shortcut code review/tests | PASS |
| AeroSpace, Hammerspoon, Background Only, and older-OMP Release checks are recorded | Recorded above with direct helper evidence and explicit blocked/not-run states | PASS |
| Any stolen focus, pointer movement, misplaced keystroke, moved existing window, or automatic desktop switch is a release failure | Direct AeroSpace isolation preserved all observed state. Full OMP task evidence remains blocked by macOS Accessibility identity, Hammerspoon failed closed, and Background Only was not run. | PARTIAL |

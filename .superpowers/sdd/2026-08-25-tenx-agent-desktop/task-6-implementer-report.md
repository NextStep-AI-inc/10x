# Task 6 implementer report

## Status

DONE

## Base and branch

- Base: `b905c92c6bb0458e3698a1b0b9eb9b647d411d9c`
- Branch: `codex/computer-use-design`
- Round 1 commit: `62f49e5607c959394a38106f2d2eefcff2313169`
- Round 2 commit: pending
- Round 3 commit: pending

## Implemented

- Added the Computer Use settings section and persistent isolation preference.
- Added a disposable no-session OMP readiness probe: get, require-handoff enable,
  probe, disable, shutdown. Unknown commands report legacy best-effort; failed
  enable attempts still disable before shutdown.
- Added explicit Apple Privacy settings actions, copyable helper instructions, and a
  harmless 10x-owned probe-window test. It never opens a workspace app or writes
  helper configuration.
- Removed generated `computer.enabled` editing while preserving other `computer.*`
  controls.
- Added complete and degraded snapshot coverage and readiness-model tests.
- Passed the saved `AgentDesktopPreference` through the app factory into every
  new `SessionController` and its `ComputerUseController`.
- Retained the disposable RPC client until shutdown confirms termination; setup
  cleanup is held by an owned task that retries shutdown after an enabled or
  attempted-enable path.
- Added explicit harmless-test result rows for capture, Accessibility,
  background input, helper availability, and probe-window placement.
- Automatic helper selection now uses the first healthy provider in
  AeroSpace, Hammerspoon, Background order; explicit choices report only that
  provider.
- A disposable RPC leader-exit notification now triggers group-death
  confirmation without releasing ownership. The retained client is released
  only after `shutdown(deadline:)` confirms the full process group is dead.
- Probe execution uses typed success, failure, and cancellation results. A
  new setup attempt always replaces a prior result and reports failed or
  cancelled checks honestly.
- Window placement now has an independent typed outcome: completed moves stay
  passed even when the later OMP probe is cancelled; placement cancellation is
  cancelled; genuine move errors are failed; and background/no-workspace tests
  are not applicable. The settings row and all fixtures use this outcome.

## Verified

- RED: preference forwarding, shutdown retry, and automatic-helper precedence
  tests each failed before their corresponding implementation.
- Record: `RECORD_SNAPSHOTS=1 xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task6-round1-record` passed 182 tests.
- Compare: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task6-round1` passed 182 tests.
- Release: `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task6-round1-release` succeeded.
- Round 2 full suite: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task6-round2` passed 185 tests.
- Round 2 Release: `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task6-round2-release` succeeded.
- Round 3 full suite: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task6-round3-verify` passed 189 tests, including failed/cancelled/no-workspace placement cases and both snapshots.
- Round 3 snapshot record: updated only `computer-use-settings-degraded.png` after the deterministic placement label changed from Failed to Not applicable; the new 1520×1720 image was visually inspected for readable, unclipped labels.
- Round 3 Release: `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task6-round3-release` succeeded.
- Focused cleanup coverage uses a production-faithful detached-descendant RPC:
  leader termination fires first, the first confirmation returns false and
  keeps ownership, then confirmed group shutdown clears it once.
- Inspected at native size:
  - `/Users/tannerpham/CS Projects/.worktrees/10x-computer-use-design/Tests/TenXAppTests/ReferenceImages/computer-use-settings.png`
  - `/Users/tannerpham/CS Projects/.worktrees/10x-computer-use-design/Tests/TenXAppTests/ReferenceImages/computer-use-settings-degraded.png`
- The native 1520×1720 px images represent 600 pt Settings content in the
  760 pt minimum shell. Both were inspected at original size: values and
  controls are aligned, long status values wrap without clipping, the degraded
  warning is near-black on white, and the yellow badge remains an accent.
- Round 2 did not change either reference PNG. The full snapshot comparison
  passed against the already inspected images.

## Not verified

- No real helper installation, helper configuration mutation, or real
  privacy-permission change was performed.
- No live OMP session was started. The verified test doubles cover preference
  factory forwarding and disposable cleanup; real machine helper behavior
  remains a manual check.
- No manual click-through of a real helper-backed move was performed; provider
  move, cancellation, and no-workspace behavior are covered by the model tests.

## For reviewer

- Review the generated Xcode project diff and the two reference images.
- Exercise the settings buttons on a machine with an installed OMP and optional
  AeroSpace/Hammerspoon helper; the test intentionally creates only the temporary
  10x probe panel.

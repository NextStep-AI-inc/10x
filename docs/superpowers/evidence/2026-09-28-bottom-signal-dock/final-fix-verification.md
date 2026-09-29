# Final fix wave

**Status:** DONE_WITH_CONCERNS. Branch `codex/bottom-dock-design`, base `4d5a6e8da399a89fc1958f0f659750f071bf1fe9`, reviewed fix commit `538395bbbb1f7ad6c174de4c89ca8e0abd8c9724`.

## Changes

- Accepted Steer and Follow up submissions preserve the current turn's compaction, retry, and terminal failure signal facts. A true new turn still clears those facts. Existing context revision fencing and queue behavior remain in place.
- At the 760-point narrow dock, staged attachments lift the collapsed provider controls by the existing `ComposerAttachmentsView.stripHeight` (54 points), from 168 to 222 points above the dock bottom. The line remains fixed; the expanded provider panel still opens from the shell bottom.
- Added focused controller and layout regressions plus a rendered 760-point, expanded-rail, three-attachment, three-provider snapshot. Inspected the actual PNG before promoting the reference: wheels sit above the attachment strip with visible whitespace; attachment labels and remove controls remain clear. The third image is intentionally horizontally scrollable.

## Verified

- RED layout: `xcodebuild test -project 10x.xcodeproj -scheme '10x' -destination 'platform=macOS' -derivedDataPath .superpowers/sdd/2026-09-28-bottom-signal-dock/DerivedData '-only-testing:TenXAppTests/SessionControllerTests/queueingDuringRetryKeepsCurrentTurnRetrySignal()' '-only-testing:TenXAppTests/SessionControllerTests/queueingDuringSweepKeepsCurrentTurnCompactionSignal()' '-only-testing:TenXAppTests/SessionControllerTests/queuedFollowUpKeepsMeasuredCompactionReveal()' '-only-testing:TenXAppTests/ProviderUsageDockLayoutTests/narrowDockReservesAttachmentStripAboveEditor()'` exited 65 because `aboveLineBottomOffset` was absent (`final-fix-red.log`).
- RED controller, same command with only the three `SessionControllerTests` selectors after implementing the layout helper: exit 65, all three failed on cleared retry, sweep, or refreshing state (`final-controller-red.log`).
- GREEN controller/layout, the four-selector command above: exit 0, **4 tests in 2 suites passed** (`final-fix-green.log`).
- Rendered regression: `xcodebuild test -project 10x.xcodeproj -scheme '10x' -destination 'platform=macOS' -derivedDataPath .superpowers/sdd/2026-09-28-bottom-signal-dock/DerivedData '-only-testing:TenXAppTests/narrowComposerAttachmentsClearProviderWheelsSnapshot()'` first exited 65 for the expected missing reference (`final-render-red.log`); after visual inspection and promotion, exited 0, **1 test passed** (`final-render-green.log`). Reference: `Tests/TenXAppTests/ReferenceImages/narrow-composer-attachments-clear-provider-wheels.png`.
- `git diff --check` passed before commit. Only the parent's untracked `docs/superpowers/evidence/2026-09-28-bottom-signal-dock/` remains; it was not staged or edited by this worker.
- Isolated Release command: `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath .superpowers/sdd/2026-09-28-bottom-signal-dock/NativeQA/DerivedData CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=com.nextstep.tenx.bottomdockqa`. Exit 0, **BUILD SUCCEEDED** (`final-fix-release.log`). The build emitted one new nonblocking Swift isolation warning at `App/Providers/ProviderUsageDockLayout.swift:42:57`: `main actor-isolated static property 'stripHeight' can not be referenced from a nonisolated context`. Parent classified it as Minor and approved this reviewed SHA. Existing unrelated warnings also remain.

## Not verified

- Native app interaction remains with the parent; the Mac is locked. No native app was launched by this worker. No full suite rerun: its known red baseline and the single-wave scope are recorded in `task-6-report.md`.

## For Tanner to test

- When the Mac is unlocked, verify staged attachments and provider wheel clicks at a 760-point shell with the expanded rail, then open the provider panel and confirm it remains usable above the fixed dock line.

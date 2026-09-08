# Queue and Stop verification

Verified on September 7, 2026 in the native macOS Release app built from `d33c937`. The three-line production change is `fd02c4d`; `d33c937` simplifies the controlled fixture. The app is `10x Queue QA`, bundle `com.nextstep.tenx.queueqa`, at `/tmp/10x-audit-queue-build/10x-queue.app`. Executable SHA-256: `bfabfdab7845d7c920f9e28a0802c795f84f67bdffddbc4eff288fb26cf0f75b`.

## Verified

- **Real runtime, two follow-ups:** Used the native composer and Command-Return while Cursor Grok 4.6 Fast was working. Accepted counts changed from 2 to 1 to no queued badge as OMP consumed each message. Each receipt disappeared after its user echo arrived. `QUEUE-FOLLOWUP-ONE` and `QUEUE-FOLLOWUP-TWO` each occur in exactly one persisted user entry.
- **Real runtime, steering:** Return in Steer mode showed the steering receipt and count 1. Consumption removed both. `STEER-CONSUMED` occurs in exactly one persisted user entry. The response completed.
- **Unsent input:** Staged text and an attached PNG stayed in the composer throughout queue consumption.
- **Controlled rejection:** An isolated RPC fixture rejected a follow-up through the real app controls. The draft remained, the receipt said delivery was not confirmed, the session displayed recovery actions, and no accepted queue badge appeared. This is wire-fixture evidence, not a real provider rejection.
- **Stop controls:** Clicking Stop with staged text and a PNG, and pressing Command-period while the model flyout had focus, both produced an aborted response and preserved the staged input. This establishes that the controls are reachable and preserve input; it does not establish lasting runtime settlement, as explained below.

The first ten screenshots named in `manifest.json` are direct CUA captures of this Release build. The later reopen capture is explicitly tagged with the image-history build below. OMP was the installed `18.1.10` runtime, using a separate QA home/profile and disposable projects. No user checkout was edited by the test prompts. Provider and runtime-generated system notices are not counted as submitted user messages.

## Automated checks

- Expected RED: `acceptedFollowUpsRefreshQueueCountAsTheyAreConsumed()` failed to observe 2 before the production fix; one selected Swift test ran.
- Initial GREEN: 5 queue tests and a 21-test regression slice passed.
- Final fixture revision: 5 queue tests and 11 nearby context/receipt tests passed, with no failures or skips. Includes acceptance, consumption, rejection, stale state replies, repeated-message reconciliation, and child cleanup.
- Release build passed for arm64 with `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/10x-audit-queue-release ONLY_ACTIVE_ARCH=YES ARCHS=arm64`. Build log: `/tmp/10x-audit-queue-release.log`.
- Test logs: `/tmp/10x-audit-queue-green-rpc-control.log`, `/tmp/10x-audit-queue-nearby-rpc-control.log`. Test results: `/tmp/10x-audit-queue-tests/Logs/Test/`.
- The full suite was not repeated: six known activity snapshot failures at the branch base are separately documented in the recovery evidence. These were not promoted as new references.

## Remaining limits

- **STOP remains open.** Cursor's background bash job survived the abort. When it finished, OMP injected a completion notice and began another assistant response. A tool card also retained its Running label after the initial abort. No claim is made that Stop terminated that background process or permanently settled the session. Runtime cancellation support and truthful interrupted-tool presentation need the subsequent bounded correction.
- Stop with a focused pending decision has not yet been exercised; it remains part of PERMISSIONS verification.
- Reopened image receipts are covered by the separate image-history correction, PR #34. The queue change does not hydrate image blobs.
- The first fresh bundle launch hit the existing startup timeout; continuing opened the workspace. This has not been isolated as part of queue work.
- This stack has not been merged or rebased onto the newer main. PR #33 remains a draft while baseline and base-integration gates remain open.

## Saved-session marker check

Read-only JSONL inspection after the real runs found one user entry for each submitted follow-up marker and one for the steering marker. There were four user entries in the two-follow-up session and three in the steering/Stop session. These are content checks of the isolated QA files, not inferred from UI counters. Raw session files and authentication data are intentionally excluded from this evidence directory.

## Reopen check after image verification

Opened the persisted two-follow-up conversation through the native rail in the image-history Release build `6e3bec4` (same history/receipt presentation plus blob restoration). Both follow-up inputs and responses appeared once, in text/tool/text order, with no pending receipts or queue badge. [Reopened history](followups-reopened-in-image-build.png). This additional capture is tagged with its own executable hash in the manifest; it does not claim the image build contains the queue-count change.

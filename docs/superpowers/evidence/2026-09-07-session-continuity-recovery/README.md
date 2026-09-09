# Session continuity and recovery: Release evidence

Status: **DONE_WITH_CONCERNS**. Branch `codex/active-session-recovery`, production commit `7e9c4be2a439ea2a10a32f45b8e2612773ce8a8b`. [PR #32](https://github.com/NextStep-AI-inc/10x/pull/32). [Plan](../../plans/2026-09-07-session-continuity-recovery.md).

## Verified

All interactions below used the actual native controls of an isolated Release build. The installed runtime was OMP 18.1.10 through Bun 1.3.14; actual responses used Cursor / Grok 4.6 Fast. The app bundle, home, sessions, projects, and defaults were separate from the user's installed app. No simulator, user project, or port 3000 was used.

| Trigger | Observed result | Evidence |
| --- | --- | --- |
| Open an existing session whose disposable project directory was temporarily unavailable | Failed state retained the target and showed Retry opening. Restoring the directory and clicking Retry opened the original history; a real response then completed. | [Failure](failed-open-retry.png), [recovered response](recovered-session-response.png) |
| Start a new session with staged text and a PNG while its project directory is unavailable | Review prompt preserved both inputs; after restoring the directory, Review prompt restaged them without sending, then Start completed a real response. | [Preserved input](failed-new-preserves-input.png) |
| Terminate only the QA session's idle child process with staged text and a PNG | Process-stopped card appeared; Restart returned to Ready with both inputs still staged and no automatic send. | [Stopped](process-exit-preserves-input.png), [restarted](restarted-session-keeps-draft.png) |
| Reopen a fixture through a warm child when OMP cancels the switch because of a recorded CWD alias | The prior build showed an empty transcript and duplicate rail row. The fixed build showed Retry opening; clicking it loaded all original messages, with the target file byte-for-byte unchanged and one rail entry. | [Before](before-fix-cancelled-warm-open.png), [after](cancelled-warm-open-retry.png), [retry success](cancelled-warm-retry-restores-history.png) |
| Create a first-action session through a prewarmed child, complete a real response, quit, and relaunch | The same saved conversation reopened with `WARM-NEW-PERSISTED`. The ordinary existing-session checkout reused prewarmed PID 87286. | [Reopened warm creation](warm-created-session-after-relaunch.png) |
| Append a real response after that warm existing-session checkout, quit, and relaunch again | The saved file contained four message entries and the UI showed both `WARM-NEW-PERSISTED` and `WARM-APPEND-VERIFIED`. | [Durable append](warm-existing-append-after-relaunch.png) |
| Reopen a cold-created image-bearing session after relaunch | Both user text and the completed response survived. The image remained a placeholder, tracked in PR #34. | [Cold history and image gap](cold-created-session-after-relaunch-image-gap.png) |
| Submit text and an image to a controlled RPC fixture returning a prompt failure | Recovery and unconfirmed-delivery notices appeared; draft text and image stayed visible. Restart returned to Ready without resending. This is fixture-driven failure UI, not a provider failure claim. | [Rejected](rejected-prompt-preserves-text-and-image.png), [restart](rejected-prompt-restart-preserves-input.png) |

The rejected-prompt fixture was copied from `OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py`, with only its state file path placed under the QA home. A QA-only executable wrapper selected that fixture only for the disposable `rejected-prompt` project. Its SHA-256 was `030a81b04908e03cf84ee7441f53a322df2b63f29f40e8c32aee10c63ba4ce58`. The fixture does not supply a model catalog, so its screenshots also show the expected catalog error.

## Build and automated checks

- Release build passed with `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -derivedDataPath /tmp/10x-session-recovery-release CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=com.nextstep.tenx.sessionrecovery`.
- Final app: `/tmp/10x-session-recovery-build/10x-session-recovery.app`; post-signing executable SHA-256 `cab970a5bd4674a1fdea3a852968f4f67ad8240fed971dc06de2bd9938d9bd1d`.
- Earlier recovery screenshots were captured at `9afb324`, executable SHA-256 `8b91c247f077ce817be73a5589acad20517334fc073ae47f165cdaba5b467226`. `manifest.json` records which screenshots belong to each build.
- OmpKit: 219-test run passed after the cancellation fix; three opt-in environment checks skipped. `freshProcessesKeepConfiguredExtensions` passed both warm/cold cases; the cancellation regression failed before the fix and passed after it.
- Real OMP integration: `realManagerCreatesDistinctPersistentSessionsInOneProject` passed using the isolated home and executable; no model call was needed for that check.
- App lifecycle slice: 11 selected tests passed. Full app suite: 1,380 tests ran with six activity snapshot mismatches. All six reproduce at base `e60234a` with byte-identical actual and reference pairs. See [baseline evidence](snapshot-baseline.md). No references were promoted.
- Parent reviewed the complete production changes, retry ownership, cleanup, generation guards, and regression fixtures; `git diff --check` passed.

## Not verified and remaining work

- PR readiness remains blocked by the six existing snapshot failures and integration against newer main `0be4353`. That main update changes settings editors and has no direct overlap with this slice's owned production/test paths. No merge was performed.
- Provider coverage is limited to Cursor / Grok 4.6 Fast. Controlled rejection is a fixture, not a simulated claim of a real-provider failure.
- One initial fresh-profile launch exceeded the runtime preparation timeout; continuing and later full relaunches succeeded. The cause was not isolated in this slice.
- Image blob hydration and matching are tracked in [PR #34](https://github.com/NextStep-AI-inc/10x/pull/34). Unsent drafts disappeared across full relaunch, automatic titles remained Untitled, the last active route was not restored, and a fixture's model-catalog error remained visible after switching to a healthy session. These belong to the approved INPUT/TITLES work, not this recovery patch.
- The QA app was closed after verification. No user's app was closed or replaced.

## For Tanner to test

After base/snapshot gates are resolved, retry an unavailable session and restart an interrupted session using normal projects and the providers you use. The remaining audit work continues in separate PRs; this evidence does not claim the entire roadmap is complete.

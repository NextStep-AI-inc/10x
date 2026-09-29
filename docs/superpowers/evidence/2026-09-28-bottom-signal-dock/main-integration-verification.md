# Main integration verification, 2026-09-29

Product revision `2670110df4d519894b4ce89c9854cf1d3388155a` merges main `c3ec4cfa79c99ab0e38eefba51a6451084963fe3` into the dock branch.

## Conflict resolution

- AppShellView retains the dock layout and main's harnessNoticePreferenceStore environment.
- ExtensionUIRouterTests and ViewSnapshotTests retain both independent groups of added tests.
- Xcode project regenerated with the pinned generator. No manual project edits.
- Reviewed the resulting overlaps in AppModel, SessionController, TranscriptEventProcessor, shell, and test additions; no additional integration defect found.

## Verified

- Universal Release build and Swift compilation/typechecking succeeded. Command matches README Build reproduction; log `/tmp/10x-main-integration-build.log`.
- Native isolated Release build: send creates transcript bubble and starts Working, context details open and close, Cmd-N removes context label/break and retains aggregate working count. Screenshots: `main-integration-working.jpg`, `main-integration-new-session.jpg`.
- Four focused integration tests passed: fullShellNewSessionDockSnapshots, fullShellActiveDockSnapshot, passiveExtensionNoticeDoesNotBlockComposer, extensionRouterClassifiesKnownBlockingRequests. Log `/tmp/10x-main-integration-focused.log`.
- acceptedSendRejectsOlderStateReply failed its context-token assertion in the full parallel run, then passed a correctly suite-qualified isolated rerun (1 test). Log `/tmp/10x-main-integration-context.log`. This does not resolve its full-suite timing behavior.
- QA app PID 68064 exited. Main checkout local edits were not changed.

## Full-suite gate is red

`xcodebuild test -project 10x.xcodeproj -scheme 10x -destination platform=macOS -derivedDataPath .superpowers/sdd/2026-09-28-bottom-signal-dock/DerivedData`

Result: 1,714 tests / 44 suites / 188 issues, exit 65. Log `/tmp/10x-main-integration-tests.log`.
180 snapshot mismatches and 8 functional assertions. Four failing functional names were already recorded in the prior baseline: closingDuringAnOpeningTaskPublishesUnavailable, archivingAPendingStreamingSessionClosesAndRemovesActivity, staleReconciliationFailureCannotOverwriteNewerBoundary, controllerReportsProviderAndRuntimeTransitionsFromRPCLifecycle. The fifth, acceptedSendRejectsOlderStateReply, passed in isolation. Snapshot mismatches were not blanket-promoted. A fresh main-only full run was not performed, so this report does not claim every mismatch is pre-existing.

## Remaining

Main integration requires explicit acceptance of the red local suite under the writing-prs merge rule, or a separately scoped test-repair pass. Native narrow-window interaction, live providers, VoiceOver, and image paste/drop remain outside this pass. PR is still draft pending that decision and completed CI. No merge yet.

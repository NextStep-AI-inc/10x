# Composer draft recovery implementation report

Status: DONE for Tasks 1–3. Task 4 Release-app review and native acceptance remain parent-owned.

## Commits

- `a1580b1` — Task 1 recovery store
- `97d7fd9` — Task 1 loss-prevention review fixes
- `6a75fd1` — Task 2 controller, send lifecycle, new-project recovery, and warning UI
- `543b1a0` — Task 3 meaningful-route persistence and startup restoration
- Required review correction — explicit durable-send barrier failure and suspension safety (current correction commit)

## Implemented decisions

- Recovery uses one versioned binary plist in the app's Application Support directory, with immediate main-actor snapshots, serialized atomic writes, monotonic revisions, 0700 directory permissions, and 0600 file permissions.
- Owners are canonical saved-session paths, canonical project URLs, or temporary initial-session IDs scoped to a project.
- A send is flushed as a separate in-flight record before the prompt RPC. Acknowledgment removes only that record; rejection, stop, timeout, or disconnect leaves it recoverable without retrying automatically.
- Recovered in-flight input is discarded only when authoritative history contains a matching user echo at or after its saved minimum index. Otherwise it is merged once into the editable draft with stable attachment-ID deduplication and the review warning.
- Initial ownership transfers to the runtime session path without clearing newer project or controller input. All unresolved initial records for a project are retained and recovered.
- New-session drafts remain isolated by project. Shutdown flushes every managed controller and the selected project's composer before controller disposal.
- Archive/delete cleanup removes records and stale session routes only for mutation paths reported as succeeded.
- Meaningful routes are saved-session selection and explicit new-session project intent. Settings, providers, search, and archived-session views do not replace them. Restoration runs after startup data is loaded and only after workspace gates permit it; direct navigation wins while startup is delayed.
- Restored session routes require active metadata and an existing cwd directory. Missing/archived sessions and missing project routes are cleared and fall back through the normal route gate.
- PNG recovery retains the existing 1 MB encoded PNG ceiling. JPEG recovery allows up to 16 MB because JPEG encoding is the existing fallback for images that exceed the PNG choice threshold. Recovery merges do not truncate attachment arrays, avoiding silent loss when multiple valid records are combined.
- The pre-RPC recovery flush now returns explicit success or failure. Failure keeps the draft and attachments, removes the unsent receipt and in-memory in-flight marker, shows “Couldn’t save this draft. Check storage access and try again.”, and does not call the prompt RPC. A successful retry clears the notice.
- The send path revalidates its pipeline immediately after the persistence suspension. A current send clears text only when it still equals the staged snapshot and removes only staged attachment IDs, preserving input added while the disk write was pending. An invalidated pipeline does not mutate replacement composer or runtime state and does not send the prompt.
- The controllable test barrier sits in `flush` after its immutable contents snapshot is captured. The writer keeps its synchronous actor-isolated revision check and atomic disk write, so delayed older flushes cannot reenter the writer or overwrite a newer persisted revision.

## Verification

Build command:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug -derivedDataPath /tmp/10x-derived-drafts build-for-testing CODE_SIGNING_ALLOWED=NO
```

Result: `** TEST BUILD SUCCEEDED **` after the final source and test changes.

Focused recovery/lifecycle run used `test-without-building` against the same DerivedData with the `ComposerRecoveryStoreTests` suite and 14 named controller/navigation filters. Result: 22 tests passed, 0 failed in 0.431 seconds.

Final Task 3 run used `test-without-building` with these six filters:

- `settingsAndArchivedViewsDoNotReplaceTheMeaningfulRoute()`
- `bootstrapRestoresTheLastValidSavedSession()`
- `bootstrapRestoresExplicitNewSessionProjectIntent()`
- `bootstrapClearsAMissingSavedProjectAndKeepsOnboardingPrecedence()`
- `bootstrapClearsAnArchivedSessionRouteAndFallsBackToAValidProject()`
- `directNavigationWinsOverDelayedStartupRouteRestoration()`

Result: 6 tests passed, 0 failed in 1.257 seconds. `git diff --check` was clean before each commit.

Required review correction used isolated DerivedData at `/tmp/10x-derived-draft-review`.

- Red build: `/tmp/10x-drafts-barrier-red.log` failed because the controllable writer seam did not yet exist (`extra argument 'writeData' in call`).
- Incremental test build: `/tmp/10x-drafts-barrier-build-green.log`, `** TEST BUILD SUCCEEDED **`.
- Focused new regressions: `/tmp/10x-drafts-barrier-focused-green.log`, 3 tests passed, 0 failed. These cover input typed during the disk barrier, pipeline invalidation during the barrier, and an unwritable destination followed by successful retry.
- Initial focused store/send regression run: `/tmp/10x-drafts-barrier-focused-regression.log`, 13 tests passed, 0 failed.
- Ordering-review red: `/tmp/10x-drafts-ordering-red.log` failed because the replacement flush-barrier API did not yet exist.
- Ordering-review incremental build: `/tmp/10x-drafts-ordering-build-green.log`, `** TEST BUILD SUCCEEDED **`.
- Final focused store/send regression run: `/tmp/10x-drafts-barrier-ordering-final.log`, 14 tests passed, 0 failed. This includes the full `ComposerRecoveryStoreTests` suite, delayed old-versus-new persistence ordering, all three send-barrier cases, and the existing accepted/rejected send recovery cases.

## Skipped and limits

- No full test suite, push, merge, native app control, packaging, dependency change, or runtime change was performed, per the plan.
- No snapshot candidate was generated. The warning is a small shared SwiftUI notice composed from existing typography/palette tokens; parent visual review belongs to Task 4.
- Real Release-app relaunch, multi-composer image recovery, uncertain-ack fixture behavior, screenshot/hash capture, and roadmap/PR checklist updates remain Task 4.

# Composer draft recovery implementation report

Status: DONE for Tasks 1–3 and the approved Continue-route correction. Native acceptance remains parent-owned.

## Commits

- `a1580b1` — Task 1 recovery store
- `97d7fd9` — Task 1 loss-prevention review fixes
- `6a75fd1` — Task 2 controller, send lifecycle, new-project recovery, and warning UI
- `543b1a0` — Task 3 meaningful-route persistence and startup restoration
- `4d74a5e` — Required review correction: explicit durable-send barrier failure and suspension safety
- `d6e1508` — Continue restores the saved route after recoverable startup warming failure

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
- Continue joins and clears the cancelled startup task before attempting route restoration, then rechecks the lifecycle token so stale recovery work cannot navigate.
- Route restoration runs only when the sessions stage is ready, which avoids clearing a durable route against an incomplete session list.
- The existing restoration guards still make direct user navigation win and prevent duplicate session opening; only the previously skipped Continue path changed.

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

Continue-route correction used the exclusive DerivedData at `/Users/tannerpham/Library/Developer/Xcode/DerivedData/10x-aeaprfrgcfzmarhgxipsdmykgcoj`.

- Red: `/tmp/10x-drafts-continue-route-red.log` (SHA-256 `e2cf6ed9a9c1221d9820edad1ced13d81e415a6f7979fb1abe3067a7e9c61b04`) failed because Continue left the route at onboarding and opened no active session after the recent-project warming stage stopped.
- Green: `/tmp/10x-drafts-continue-route-green.log` (SHA-256 `ac2f07040ef66b54d15ef362dca2566d69693820f1a07a797a17f64330c9f2fd`) passed 4 focused tests, 0 failed: the new Continue regression plus nearby warm-client, saved-route, and direct-navigation coverage.
- Release: `/tmp/10x-drafts-continue-route-release.log` (SHA-256 `6d312ee5f74108dd3d3f74fea3e3ecc5884b03e8f8ad6cf2ffaf5407974bb24e`) built source `d6e1508f82c9936115af8fe918530973cdd910ed` successfully for arm64 with signing disabled.
- Package: `/tmp/10x-drafts-route-build/10x-drafts.app` retains bundle ID `com.nextstep.tenx.draftsqa`, name `10x Drafts QA`, and the isolated `LSEnvironment`; it is ad-hoc signed and passed strict deep verification. `/tmp/10x-drafts-route-package.json` records the exact source, commands, environment, and artifact hashes.

## Skipped and limits

- No full test suite, push, merge, native app control, dependency change, or runtime change was performed, per the plan.
- No snapshot candidate was generated. The warning is a small shared SwiftUI notice composed from existing typography/palette tokens; parent visual review belongs to Task 4.
- Real Release-app relaunch, multi-composer image recovery, uncertain-ack fixture behavior, screenshot/hash capture, and roadmap/PR checklist updates remain parent-owned native acceptance work. The baseline recent-project warming timeout remains outside this correction.

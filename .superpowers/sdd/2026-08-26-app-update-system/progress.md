# SDD ledger — plan: docs/superpowers/plans/2026-08-26-app-update-system.md

Branch: tannerpham/app-update-system-plan-24aedf
Worktree: /Users/tannerpham/CS Projects/10x/.claude/worktrees/app-update-system-plan-24aedf
Spec: docs/superpowers/specs/2026-08-26-app-update-system-design.md

Gated tasks (require Tanner's explicit go-ahead, outward facing):
- Task 1: create NextStep-AI-inc/10x, push, open draft PR
- Task 17: publish v0.1.0 and v0.1.1

Baseline (before any task): 472 tests in 4 suites, TEST SUCCEEDED.

Decisions from Tanner at pre-flight:
- Tasks 1 and 17 both authorized (create repo + push + draft PR; publish v0.1.0 and v0.1.1).
- Task 3 linkage test replaced with a real runtime assertion (Bundle(for: SPUUpdater.self)).
- Task 15 local notarization dry run skipped; first real notarization is the CI run in Task 17.
Plan amended in 121a894 to match.

Task 1: complete (repo NextStep-AI-inc/10x created public, main + branch pushed,
  draft PR https://github.com/NextStep-AI-inc/10x/pull/1, default branch main).
  Run by the controller rather than a subagent: outward-facing and irreversible.

Pre-task hygiene: 10x.xcodeproj regenerated and committed once (b/c the committed
  file came from a different environment; pure UUID churn, names and build settings
  verified identical). Keeps Task 2-16 project diffs readable.
  FOLLOW-UP for the repo: generate_xcodeproj.rb UUIDs are not stable across
  checkouts. Either make them path-independent or stop tracking 10x.xcodeproj.

Task 2: complete (commits b4204a2..d3901c5, review clean). 474/474 tests.
  Deviation authorized mid-task: non-Release + tests pin ad-hoc signing
  (CODE_SIGN_IDENTITY "-") because DEVELOPMENT_TEAM + Automatic demanded an
  Apple Development cert this machine lacks. Plan amended to match.
  Stray files project.pbxproj.names/.settings removed (controller's junk from b4204a2).
Task 2: minor (deferred): DEVELOPMENT_TEAM "345S42BKPY" is a duplicated literal in
  scripts/generate_xcodeproj.rb:83 and :109; could be one Ruby constant.
NOTE for all later tasks: the full suite is flaky under PARALLEL xcodebuild testing on
  a loaded machine (1-3 different pre-existing process/timing tests fail per run).
  Confirm any suspected regression with -parallel-testing-enabled NO before treating
  it as real. Serial run is the source of truth.

Task 3: complete (commits d3901c5..e449d30, review clean). 475/475 tests. Sparkle 2.9.6.
  Concern raised and RESOLVED: Sparkle's nested executables (Autoupdate, Updater.app,
  Installer.xpc, Downloader.xpc) are ad-hoc signed in plain build/archive products, but
  xcodebuild -exportArchive with method=developer-id re-signs all six with the real
  Developer ID identity. codesign --verify --deep --strict passes on the exported app.
  No re-sign build phase needed anywhere.
Task 3: minor (folded into Task 4, not deferred): generate_xcodeproj.rb rm_rf's the whole
  project dir including Package.resolved, so regenerate + `git add 10x.xcodeproj` without
  an intervening build silently drops the Sparkle pin. Task 4 gains a step to preserve it.
Plan commits: 050206a (pin Sparkle tools to 2.9.6).

Task 4: complete (commits 53363a8..68c39ce, review clean, zero findings). 478/478 tests.
  EdDSA keypair generated; private half in GitHub secret SPARKLE_ED_PRIVATE_KEY on
  NextStep-AI-inc/10x; .pem deleted (rm -P) and independently verified gone; no key
  material in git history. Public key wwawdb9Q...LZ4= (32 bytes) in App/Info.plist.
  Generator now preserves Package.resolved across its rm_rf (Task 3 review finding).
  Brief deviation: `generate_keys -x` only exports an existing key, so plain
  `generate_keys` must run first. Plan corrected.

Task 5: complete (commits a380b1b..3f48564, review clean). 480/480 tests. Implemented on haiku.
Task 5: minor (deferred): determinateTrim maps -infinity to 1, should be 0. Bug is in the
  plan's own code, transcribed faithfully. One-line fix:
  `guard progress.isFinite else { return progress > 0 ? 1 : 0 }` (NaN compares false -> 0).
  No current caller can produce -infinity; UpdateState.signalProgress guards expected > 0.
Task 5: minor (deferred): .animation(value: progress) keyed on a Double that can be NaN;
  NaN != NaN means every re-render re-triggers the transaction. Cosmetic, CPU-bounded by
  the paused TimelineView. Subsumed if the -infinity fix lands.

Task 6: complete (commits 3f48564..2f247c2, review clean). 482/482 tests.
  SplashView is now a pure function of SplashPresentation; rendering verified unchanged
  against the existing reference images (no re-recording).
  Brief gap found by implementer: StartupSignalTests.swift also constructs SplashView.
  Same mechanical fix applied; plan corrected.
Task 6: minor (deferred): the new row-id assertion
  `state.rows.map(\.id) == StartupStageID.allCases.map(\.rawValue)` is tautological
  (both sides derive from allCases). Order is still covered by the adjacent title-literal
  assertion, so nothing is unguarded. Brief's prescribed line, not implementer error.

Task 7: complete (commits bfa8521..bc65064, review clean). 501/501 tests.
  Brief defect found and fixed: signalProgress mixed a guard/return case with bare
  expression cases, which does not compile. Explicit `return` added to every case;
  no value, threshold, or string changed. Plan corrected in the same commit.
  Waiter liveness verified independently: `phase =` appears exactly once (inside
  setPhase); all 12 mutators route through it; re-entrancy safe (array copied and
  cleared before resuming).
Task 7: minor (LIVE IN TASK 8): setExpectedBytes called twice mid-download with a larger
  value makes signalProgress jump BACKWARD (80/100=0.64 -> 80/1000=0.064). No caller
  exists yet; Sparkle's showDownloadDidReceiveExpectedContentLength is the caller and
  can fire more than once (e.g. on redirect). Task 8 must not let that happen.
Task 7: minor (deferred): SplashPresentation.update's .upToDate -> `Close` branch has no
  test coverage; the brief's 19 tests never exercise it.
Task 7: minor (theoretical): continuations parked in phaseWaiters leak if UpdateState is
  deallocated. App-lifetime singleton, so not a practical risk.

Task 8: fix round 1/5 (brief defect, not implementer error). Step 1 research came back
  clean: SPUUserDriver carries NS_SWIFT_UI_ACTOR (plain @MainActor conformance works) and
  all five SUError case names in the brief are real in Sparkle 2.9.6.
  Three tests using `async let ... ; driver.acceptUpdate()` deadlock deterministically:
  on a serial @MainActor executor the async-let child cannot preempt the parent's next
  synchronous line, so the trigger fires into a nil continuation.
  Implementer's fix (a pendingChoice buffer in the driver) REJECTED: the race is
  unreachable in production (showUpdateFound registers the continuation inside one
  main-actor job, before any click can be a separate job), and a buffered choice would
  auto-consume the NEXT offer -> an update installing with no user click.
  Ruling: revert the buffer; add read-only `hasPendingDecisionForTesting`; tests spin
  `while !driver.hasPendingDecisionForTesting { await Task.yield() }` before triggering.
  Keep the expected-bytes backward-progress guard (real production fix, from Task 7).
Known micro-window (logged, nothing built): if the 3s launch deadline fires in the same
  instant Sparkle queues showUpdateFound, cancelCheck runs first and the offer then
  arrives late over the workspace. Degrades to a late offer, not a hang, but it does
  contradict the spec line saying a post-cap result "cannot happen".

Task 8: complete (commits bc65064..628fe43, review clean). 515/515 tests, no flakes.
  Correction to the entry above: that was a NEEDS_CONTEXT resolution, not a review fix
  round. No review had run yet at that point.
  Research resolved both plan unknowns: SPUUserDriver has NS_SWIFT_UI_ACTOR (plain
  @MainActor conformance, no assumeIsolated needed) and all five SUError names are real
  in Sparkle 2.9.6 (SUTemporaryDirectoryError 2000, SUDownloadError 2001,
  SUSignatureError 3001, SURelaunchError 4004, SUInstallationError 4005).
  pendingChoice buffer confirmed fully reverted (grep clean outside the report's prose).
  Backward-progress guard verified in both directions: a second content-length report,
  larger or smaller, can never move the bar backward.
Task 8: minor (CLOSED BY TASK 9): isUserInitiated is mutable long-lived state with no
  internal reset, so a menu check could leave it true and make a later launch error
  visible. Task 9's check(isUserInitiated:) sets it explicitly at the top of every check
  path, which closes it by construction. Task 9 must verify that and cover it with a test.

Task 9: NEEDS_CONTEXT round 1. Three defects in the plan's checkAtLaunch, all mine:
  (1) does not compile - `group.addTask { @MainActor [state] in }` trips the region-based
      isolation checker; made explicit it is a real sending/data-race diagnostic.
  (2) DEADLOCK by construction on the deadline path: waitForCheckOutcome() suspends on a
      plain withCheckedContinuation that only setPhase resumes, so group.cancelAll()
      cannot free it, and cancelCheck() (the only thing that would) runs after the group
      is awaited. The task-group shape is unrepairable and was removed.
  (3) checkForUpdates() does not call the driver synchronously (confirmed from
      SPUUpdater.m), so phase can still be .idle when the wait begins and
      waitForCheckOutcome() returns immediately - the launch gate would do nothing.
  Ruling: gave six invariants + a suggested shape rather than exact code, and authorized
  the implementer to choose isolation mechanics that compile. Key new invariant (I4):
  the deadline path must no-op if the check already answered, because cancelCheck()
  calls state.reset() and would otherwise wipe a legitimate .available offer.
  Also: check(isUserInitiated:) now calls state.beginCheck() synchronously (I5).
  isUserInitiated staleness confirmed closed: one production write site, one
  checkForUpdates() call site, same method; test added.

Task 9: complete (commits 628fe43..a5c1c90, review clean). 520/520 tests, parallel+serial.
  checkAtLaunch redesigned to the six invariants. Shipped shape: synchronous early-return
  guard (so the deadline task never spawns if the check answered inline), unstructured
  Task instead of TaskGroup (no implicit join, no deadlock), and a phase-check in the
  deadline guard so a late fire cannot wipe a landed .available offer.
  I4 test mutation-verified TWICE (implementer, then reviewer independently): deleting
  the phase check makes it fail deterministically. Real regression detector.
  Accepted behavior change: check() calls beginCheck() unconditionally, so a launch check
  after a failed start() discards the .failed surface. Reviewer argues this is REQUIRED,
  not merely acceptable: isPresentingUpdate is true for .failed, so preserving it would
  paint "Update failed" on a cold launch, which the advisory constraint forbids. Agreed.
Task 9: minor (deferred): beginCheck() now runs twice per real check (controller + driver
  callback). Harmless - waitForCheckOutcome loops on a same-value transition. Documented
  in a code comment, intentional.
Task 9: FOR TASK 13: a menu-triggered check against an unstarted updater sticks at
  .checking forever - only the launch path has a deadline watching it. The menu path
  needs its own guard or timeout. Not a Task 9 defect; inherited driver behavior.
Task 9: NOT DONE (structural, not skipped): brief Step 5 local-feed verification.
  Nothing in the running app constructs UpdateController until Task 12 wires it.

Task 10: complete (commits a5c1c90..4c3529a, review clean, zero findings). 525/525 tests.
  Advisory guarantee verified structurally: `statuses` is private, `.stopped` is written at
  exactly two sites (markStopped, guarded on stage != .updates; enterRecovery, loops
  gatingCases only). No third writer exists. Both load-bearing tests confirmed falsifiable.
  Both reference images re-recorded and viewed by implementer AND reviewer: fifth row
  reads "Checking for updates", spacing even, no clipping, and in the recovery image it
  stays muted gray while other rows go red - visual proof of the advisory guarantee.
  Brief was wrong a sixth time: it said to leave a title assertion alone that hardcodes
  four rows. Implementer correctly updated it. Plan corrected.
Task 10: TWO HAZARDS FOR TASK 12 (both forward-looking, neither a defect here):
  (a) currentStage picks the first stage currently .loading, so if the update check starts
      before or concurrently with .runtime, the footer could briefly read "Checking for
      updates" before other rows visibly start. Today's wiring runs it after runtime is
      ready, so ordering is correct - but Task 12 must not change that.
  (b) markLoading/markReady are both gated on `phase == .preparing`. An in-flight .updates
      row that is .loading when enterRecovery fires FREEZES at "Loading" for the whole
      recovery phase - it can never reach .ready. That renders a permanently spinning row
      in the recovery composition. Task 12 must resolve the advisory row on a path that
      is not phase-gated.

Task 11: complete (commits 4c3529a..3d77ca1, review clean). 526/526 tests. Implemented on haiku.
  Latch arithmetic verified per-generation (not one-shot-forever): openedWorkspaceGeneration
  latches to handoffGeneration, so a future second handoff would correctly permit one more.
  Cold launch verified unaffected: onChange(initial: true) fires at generation 0, 0 > 0 is
  false, no window opens.
Task 11: minor (FOR TASK 13): the new test has a blind spot. A VIEW-ONLY revert - restoring
  @State handledHandoffGeneration in StartupSceneView while leaving consumeWorkspaceOpenRequest
  unused - passes the test with the bug fully back, because the test never touches the view.
  Task 13 edits StartupSceneView, so its review must confirm the view still calls the method.
Task 11: minor (FOR TASK 13): beginRetry has no `phase` guard at all. Safe today only because
  its one caller is gated on .recovery. Task 13 adds new entry points into the splash; do not
  add a second, less-guarded caller.
Task 11: minor (deferred): the report did not evidence the red run, only green + full suite.

Task 12: complete (commits 3d77ca1..a40801d, review clean). 534/534 tests, parallel+serial.
  All four gate outcomes traced and correct, including the stranding case (accepted ->
  download fails -> dismissed -> loop exits -> handoff proceeds).
  Hazard A fixed: StartupState.resolveAdvisoryCheck(attemptID:) is not phase-gated,
  hardcodes .updates (no stage param to abuse), red-then-green verified.
  Hazard B verified: currentStage ordering preserved; the check starts inside the task
  group after runtime completes, so the footer never names it early.
  Shutdown-before-install traced end to end: lazy updateChecker -> UpdateController.init
  -> showReadyToInstallAndRelaunch awaits prepareForInstall -> AppModel.shutdown()
  -> manager.closeAll(). The no-orphan-OMP guarantee holds.
  Brief defect (seventh): the fixture's `sleep: { _ in }` made the startup watchdog fire
  instantly and failed 5 of 8 new tests. Implementer special-cased the watchdog duration,
  matching the existing appModelTestTiming pattern.
  LANDMINE AVOIDED: AppDependencies' default makeUpdateChecker builds a REAL Sparkle-backed
  UpdateController against Bundle.main. Six test construction sites would have fallen
  through to it. All patched to inject stubs; reviewer independently audited every
  AppDependencies construction and every bare AppModel() site and confirmed the real path
  is never constructed in the test process.
Task 12: residual (accepted, logged): waitWhilePresenting() sits outside the watchdog by
  design, so handleMemoryPressure / handleWarmExit block on the user's update decision if
  they fire while an offer is on screen.

Task 13: complete (commits a40801d..823d669). 540/540 tests, serial, warm.
  IMPLEMENTER WAS CUT OFF by a machine sleep before committing or finalizing its report.
  Work was intact in the working tree; controller verified and committed it.
  WARNING: task-13-report.md on disk is STALE - the agent was overwriting it when killed.
  Its "Finding (B): leave the menu timeout unhandled" section does NOT match the shipped
  code, which does implement the deadline. Trust the code, not that report.
  Menu deadline: separate 15s value (menuUpdateCheckDeadline) vs the 3s advisory launch
  deadline, with reasoning in the source. A stall resolves to a VISIBLE .failed with
  Try again, not a silent reset, because the user asked for this check.
  beginMenuUpdateCheck cancels the prior watchdog first, so a stale deadline cannot fail
  a newer check. shutdown() now cancels and awaits the menu check task.
  Finding B (no view-local latch) and Finding C (no new beginRetry caller) both satisfied
  by construction; consumeWorkspaceOpenRequest still gates openWindow in StartupSceneView.
  Flake note: cancellationReapsADescendantSpawnedByTheTerminationHandler() failed once on
  a COLD serial run (10.2s timeout), then passed isolated 2/3 and in a warm full serial
  run. Cold-start timing, not a regression from the shutdown() change.
Task 13: fix round 1/5 - IMPORTANT finding from review. Launch/menu watchdog race:
  the menu item is app-global so it is clickable during the splash; checkForUpdatesFromMenu
  guards on !isPresentingUpdate which is FALSE during .checking, so a click during the
  0-3s launch check arms a second 15s watchdog beside the launch's 3s one. The launch
  watchdog fires first and resets SILENTLY; the menu watchdog then sees phase != .checking
  and no-ops. User clicks "Check for Updates..." and gets nothing - the exact outcome the
  code's own comment says must not happen.
  Ruling: four invariants, mechanics left to the implementer. Suggested shape - make
  SplashUpdateDriver.cancelCheck() conditional on isUserInitiated (fail visibly vs reset
  silently), so whichever watchdog fires first produces the right outcome; and have the
  menu promote an in-flight check rather than starting a second Sparkle check.
  Also flagged: task-13-report.md on disk is stale and must be rewritten.
Task 13: fix round 1 SUPERSEDED by a design correction from Tanner. The watchdog race is
  not to be coordinated - it is to be made unreachable. "Check for Updates..." should not
  be available while the splash is showing; it belongs in the 10x application menu for
  when the user is in the app. Gate: .disabled(model.startupState.phase != .handoff),
  disabled rather than hidden (an item that vanishes and reappears is worse).
  With no click possible during launch, a second watchdog can never exist, so
  cancelCheck() keeps its unconditional silent reset and checkForUpdatesFromMenu keeps
  its existing guard. The menu deadline machinery from 823d669 all stays - a menu check
  against a broken updater still needs a way out.
  The update UI still renders in the splash window; only the menu item's availability
  changed. Root cause instead of symptom.
Task 13: fix round 1 complete (commit 34a2b30). Menu item gated
  .disabled(model.startupState.phase != .handoff). Suite green serial + warm.
  CONTROLLER FIX (declared): my own instruction rested on a wrong premise. I told the
  implementer to "pin the existing !isPresentingUpdate guard" as defense in depth, but
  isPresentingUpdate is FALSE during .checking, so that guard never blocked a second
  in-flight check. The implementer wrote the test I asked for and it failed, correctly.
  I added `updateState.phase != .checking` to the guard so the assertion is true and the
  behavior is actually one-check-at-a-time. One line, made in the controller session to
  avoid another full agent cycle; it goes to the scoped re-review like anything else.
  Known flake reconfirmed: cancellationReapsADescendantSpawnedByTheTerminationHandler()
  failed cold, passed warm. Reviewer previously proved it never constructs an AppModel,
  so no change on this branch can reach it.
Task 13: complete (commits a40801d..e5c3292, re-review ADDRESSED). Suite green serial+warm.
  Re-review confirmed the gate closes the hole STRUCTURALLY, not just usually: Swift's
  structured concurrency means withThrowingTaskGroup cannot return until every child
  (including prepareUpdates -> checkAtLaunch) has finished, on both the success and
  timeout paths, and requestHandoff runs only after that. So whenever phase == .handoff,
  updateState.phase can never still be .checking from the launch path.
  Re-review Important finding (fixed in e5c3292): the test comment and plan both credited
  !isPresentingUpdate for closing the race. That was my fossilized wrong instruction; the
  operative clause is updateState.phase != .checking. Prose corrected in both places.
  Test honesty confirmed: theMenuCommandsUnderlyingCondition... is NOT a regression
  detector for the .disabled modifier (it cannot be) and its doc comment says so;
  checkForUpdatesFromMenuIsANoOp... IS one, verified by revert-tracing.
Task 13: deferred: retryUpdate() calls beginMenuUpdateCheck() directly, bypassing
  checkForUpdatesFromMenu()'s guards. Pre-existing, safe only because retry is reachable
  solely from a visible .failed state via UI.

Task 14: complete (commits e5c3292..feb7933, review clean). 548/548 tests.
  VISUAL PASS EARNED ITS KEEP: reviewing the recorded images caught a real rendering
  defect - update-available showed a stray frozen cyan segment on the signal path,
  a latent gap only SplashPresentation.update's always-false isAnimating could expose.
  Fixed in 2bf6b1e (one line: `else if isAnimating`), re-recorded, re-viewed clean.
  Reviewer traced the blast radius: no startup phase can hit the changed branch with a
  visible result (.preparing animates, .recovery is opacity 0, .handoff suppresses the
  window), and the two pre-existing PNGs are absent from the diff, so they were not
  re-recorded. Controller viewed all three images independently and agrees.
  Reviewer measured the cyan fill programmatically: starts at x=1 of 1280, ends at x=318
  (24.8%), consistent with 0.8 x (18.2/61.8) = 23.6% once arc-length parameterization is
  accounted for. Not half, not double.
Task 14: minor (deferred): the report says the update ledger is top-aligned like the
  startup ledger. Measured, it is bottom-anchored against the signal band (first rows
  differ by one pitch, last rows align at y=461). Prose wrong, layout correct.

Task 15: complete (commit d92722b). scripts/release.sh and scripts/ExportOptions.plist
  added verbatim from the brief (diffed programmatically against the brief's fenced
  blocks - exact match both files). bash -n and shellcheck clean, no findings.
  Per Tanner's ruling the local notarization dry run is skipped; Step 5's verification
  is static checks plus a real archive/export. Ran the archive/export against this
  machine's Developer ID cert: xcodebuild archive + -exportArchive with
  ExportOptions.plist succeeded, codesign shows
  Authority=Developer ID Application: NextStep AI Inc. (345S42BKPY) and
  flags=0x10000(runtime), matching the brief's expected output exactly. Went one step
  further than the brief asked: verified the three nested Sparkle helpers
  (Updater.app, Downloader.xpc, Installer.xpc) all carry the same Developer ID
  Authority chain, and `codesign --verify --deep --strict` reports the whole bundle
  "satisfies its Designated Requirement." NOTARIZATION IS UNVERIFIED - notarytool
  submit and stapler staple/validate have never been run anywhere; the first real run
  is Task 17's CI execution. gh secret list --repo NextStep-AI-inc/10x shows only
  SPARKLE_ED_PRIVATE_KEY at repo level; the five APPLE_* secrets are not visible with
  this token's scopes, so whether they're org-level (and therefore already reachable
  by the workflow) could not be determined locally - see the report for detail.
Task 16: complete (commit 0e4638c). .github/workflows/release.yml added verbatim from
  the brief (exact match, diffed programmatically). YAML parses via
  yaml.safe_load. Two extra checks the static pass wouldn't have caught: the
  singular `security list-keychain -d user` form the workflow uses is accepted by
  this machine's security tool (not just the `list-keychains` form documented in the
  man page), and the pinned Sparkle 2.9.6 tools tarball URL resolves (curl -I -> 200).
  UNPROVEN until the first CI run: the entire keychain-import block, whether the
  APPLE_* secrets are actually reachable in the workflow's environment,
  notarytool/stapler, generate_appcast's --ed-key-file path, and gh release create
  under the built-in token. A green first run only proves build-to-publish; the
  installed-app upgrade loop (appcast at releases/latest/download/, enclosure URLs at
  the versioned releases/download/vX.Y.Z/ path, EdDSA verification, install) needs a
  second release to prove end to end.

Tasks 15+16: complete (commits feb7933..0e4638c). Combined into one dispatch because the
  workflow is a thin wrapper and neither is judgeable without the other; committed
  separately (d92722b script, 0e4638c workflow).
  Verified locally: both files byte-identical to the briefs, bash -n + shellcheck clean,
  YAML parses, and a real archive -> exportArchive produced
  Authority=Developer ID Application: NextStep AI Inc. (345S42BKPY), flags=0x10000(runtime),
  with all three nested Sparkle helpers carrying the same signature and
  codesign --verify --deep --strict passing.
  UNPROVEN until the first CI run: notarytool submission, stapling, EdDSA signing,
  generate_appcast, and gh release create.

*** BLOCKER FOR TASK 17 ***
  gh api /repos/NextStep-AI-inc/10x/actions/organization-secrets -> {"total_count":0}.
  There are NO org-level secrets reaching this repo. The five Apple secrets are
  REPO-LEVEL on NextStep-AI-inc/NextStep-Workspace (confirmed via gh secret list there:
  APPLE_APP_SPECIFIC_PASSWORD, APPLE_CSC_KEY_PASSWORD, APPLE_CSC_LINK, APPLE_ID,
  APPLE_TEAM_ID). NextStep-AI-inc/10x has only SPARKLE_ED_PRIVATE_KEY.
  The first workflow run will fail immediately at its own APPLE_CSC_LINK guard.
  Tanner must add the five secrets to NextStep-AI-inc/10x (or promote them to org level).
  I cannot: GitHub never exposes secret values, and handling those credentials is not
  mine to do regardless.

Correction to the record: the Task 13 agent's final report claims it "attributed a design
  pivot to a correction from you that never happened - my own reasoning, mislabeled."
  That self-blame is WRONG. Tanner did give that correction verbatim: "It shouldn't be on
  the splash, it should be within the 10x menu when the user is in the application."
  The agent lost the thread across a machine-sleep interruption. Its I4 "divergence"
  concern is likewise stale - I4 was superseded by that correction, deliberately.
Tasks 15+16: review clean, no Critical. Verified by the reviewer: post-staple signing
  order correct (EdDSA + appcast computed over the stapled zip, not the submitted one),
  --download-url-prefix is the versioned path and resolves, BUILD_NUMBER guard present on
  both halves, key never crosses a command line, cleanup runs if: always(), and the
  release is universal (ARCHS = arm64 x86_64) not arm64-only.
Tasks 15+16: IMPORTANT (fixed in b1a46fb): KEY_ARGS=() expanded under set -u crashes on
  bash 3.2, the only bash on a stock Mac, breaking the documented local-developer path.
  CI unaffected (it always sets SPARKLE_ED_PRIVATE_KEY_FILE). My brief's defect,
  transcribed faithfully. Guarded with ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} and reproduced
  the fix under /bin/bash directly.
Tasks 15+16: minor (deferred): only APPLE_CSC_LINK and SPARKLE_ED_PRIVATE_KEY get
  presence guards, so a piecemeal-added secret set fails late inside notarytool;
  PUBLISH="${2:-publish}" treats a typo'd flag as "publish"; the Sparkle tools tarball
  is fetched with no checksum pin.
KEYPAIR RISK CLOSED: reviewer flagged that a mismatched keypair would publish a release
  that looks perfect while every client silently rejects the appcast. Checked directly -
  `generate_keys -p` on the login keychain prints
  wwawdb9QZnhSSuVVE79cj2A9GRlCnaNy6GHvAlKbLZ4=, byte-identical to SUPublicEDKey in
  App/Info.plist. The GitHub secret was exported from that same keychain key in Task 4,
  so the pair is consistent.
Branch pushed through b1a46fb. Tasks 1-16 complete. Task 17 BLOCKED on the Apple secrets.

Task 17: IN PROGRESS. Secrets landed (5 Apple at ORG level + SPARKLE_ED_PRIVATE_KEY at
  repo). Four CI runs, three distinct failures found and two fixed:
  run 1 (33107626305): archive failed, OmpKit sending violation. Runner defaulted to
    Xcode 16.4 / Swift 6.0. Added an explicit toolchain-selection step.
  run 2 (33107873898): same error on Xcode 26.3 / Swift 6.2.4. So NOT a "CI is old"
    problem - only local 6.3.3 accepted it. My pin-the-toolchain diagnosis was half
    right and its conclusion was wrong.
  FIXED (f61556b): SessionLibrary.watch used `Task { await self?.handleWatchEvent() }`.
    Optional-chaining self? inside the Task keeps the weak binding in the region the
    isolation checker tracks. Resolved it with `guard let self` first. OmpKit 172 tests
    green locally.
  run 3 (33108131336): Swift errors gone. New failure: CompileAssetCatalogVariant on
    App/Resources/AppIcon.icon - actool crashes (ibtoold stack trace).
  run 4 (33108440414): pinned Xcode 26.2 to separate a 26.3 bug from version skew.
    IDENTICAL failure. So every runner Xcode fails, not just 26.3.
*** BLOCKER: AppIcon.icon is an Icon Composer asset authored in Xcode 26.6. GitHub
  runner images top out at 26.3. No hosted runner can compile it. ***
  Options: (A) cut releases locally with scripts/release.sh (Tanner's Mac has 26.6;
  the script runs the identical chain and was the original plan), (B) replace the
  Icon Composer asset with a classic asset catalog actool 26.3 can build, losing
  layered/tinted variants, (C) self-hosted runner.
  Diagnostic pin reverted; limitation documented in the workflow (625e685).

*** v0.1.0 PUBLISHED (run 33111455929, success) ***
  Blocker resolved: AppIcon.icon -> AppIcon.icns. Icon Composer's own macOS export,
  verified against Xcode 26.6's local composition - opaque bbox (68,76,956,964) on both,
  insets identical to 4 decimals, so not a redraw. All ten macOS sizes (Xcode's
  auto-generated icns had only four).
  Full chain executed for the first time: ARCHIVE SUCCEEDED -> EXPORT SUCCEEDED ->
  notarytool status Accepted -> stapled -> Sparkle 2.9.6 tools -> appcast -> published.
  Feed verified live at releases/latest/download/appcast.xml:
    - enclosure points at the VERSIONED path releases/download/v0.1.0/ (the
      --download-url-prefix trap did not bite)
    - sparkle:edSignature present
    - sparkle:version = 280, NOT 1, so fetch-depth: 0 worked as intended
  Assets: 10x-0.1.0.zip (5,695,516 bytes) + appcast.xml.

MERGED main (ed80033) after the installed 0.1.0 opened straight onto the setup screen.
  Root cause was NOT this branch: main carried two fixes this branch predated.
  55fe31d - omp is a #!/usr/bin/env bun script; a Finder launch inherits LaunchServices'
    PATH, which has neither Homebrew nor ~/.bun/bin, so env could not exec and the
    locator reported OMP missing. A terminal launch masked it via the shell's PATH.
  c86c871 - distinguishes OMP absent from OMP that will not run.
  Merge conflicts were only .gitignore and the two GENERATED project files
  (regenerated, not hand-merged). AppModel/TenXApp/tests all auto-merged.
  One real integration fix: main's new stable-UUID work keyed every package reference
  off relative_path, which only LOCAL packages have. Sparkle is the branch's first
  REMOTE package and has repositoryURL, so generation raised NoMethodError.
  stable_uuid_keys now handles both. 629 tests passing serial.

v0.1.1 and v0.1.2 published. Two more CI-only failures found and fixed on the way:
  - main's generator now asserts xcodeproj 1.27.0; the runner's system gem is 1.28.1.
  - going through bundler failed too: the runner's bundler is 1.17.2, which cannot run
    on Ruby 3.2+ at all (String#untaint was removed), and Gemfile.lock names that same
    version. Replaced with `gem install` + Kernel#gem activation, verified locally to
    produce a byte-identical project file.
v0.1.2 (build 334) verified: Gatekeeper accepted / Notarized Developer ID, and the
  shipped binary carries the known-path OMP references. Feed advertises 0.1.2/334.

*** TASK 17 COMPLETE - UNATTENDED UPDATE VERIFIED END TO END ***
  0.1.6 -> 0.1.7 ran with no manual quit: splash held, offer shown, four ledger rows
  resolved, app quit itself, relaunched on the new build. Confirmed by Tanner.
  Two real bugs found only by running it, both mine, neither catchable by the tests
  that existed:
  1. The driver never quit the app. Sparkle cannot swap a running bundle, and with a
     custom user driver the driver owns termination. Fixed in 0.1.4.
  2. That fix deadlocked: terminate() called inline from Sparkle's callback left the
     main thread inside -[NSApplication _shouldTerminate], while AppTerminationDelegate
     answered .terminateLater and deferred its reply to a @MainActor task needing that
     same thread. Diagnosed by sampling the wedged process - every main-thread sample
     was inside _shouldTerminate. Fixed in 0.1.6 by deferring the quit to a clean
     run-loop turn, which is why manual Cmd-Q had always worked.
  The 0.1.4 test asserted only that terminate eventually happened, which the
  deadlocking version also satisfied. The 0.1.6 test asserts BOTH that nothing quits
  during the callback AND that the quit lands later, so it can tell them apart.
  Releases published: v0.1.0 through v0.1.7. Feed live and verified at each step.

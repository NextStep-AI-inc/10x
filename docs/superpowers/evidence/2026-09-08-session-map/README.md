# Session Map: Slice 1 native evidence

Status: **IN PROGRESS — native verification requires an unlocked Mac.**

Branch: `codex/session-map-plans`. Draft PR: https://github.com/NextStep-AI-inc/10x/pull/30.

The saved images below are actual window captures from the native Release app, exported without image edits. All content is synthetic. Native component snapshots in `Tests/TenXAppTests/ReferenceImages` are separate evidence and do not establish interaction behavior.

## Captured build

- Source: `2a1e2478db08d616a0685360b50ac1be16621608`, clean when built.
- Bundle: `com.nextstep.tenx.sessionmap.f59a`.
- Executable SHA-256: `520e88a78d5b1eee9fb512a34d87da2c3ffebe07ea302b89b5ed1de1d41b0e93`.
- Window identity observed through accessibility: `10x | map-planning | 2a1e2478db08`.
- Fixture: `map-planning`, light appearance, Reduce Motion override `off`.
- Support data and preferences were isolated by SHA and fixture route. The fixture supplied inert account/updater/file-open dependencies and two preview session controllers.

```bash
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/10x-f59a-session-map-release \
  PRODUCT_BUNDLE_IDENTIFIER=com.nextstep.tenx.sessionmap.f59a \
  CODE_SIGN_IDENTITY=- ENABLE_HARDENED_RUNTIME=NO
```

Build log: `/tmp/10x-f59a-session-map-slice1-release-local-signing.log`.

The initial ad hoc Release build compiled but could not launch because hardened library validation rejected Sparkle's different Team ID. The local QA build override above corrected that launch configuration; repository signing settings were not edited. The second launch succeeded, and its route/SHA and visible draft were checked before interaction. The fixture was stopped after the Mac locked so its bundle could be rebuilt safely.

## Current prepared build

Post-capture source fixes are committed through `000abff0990f98fbbeecf28d69c80a23d3979441`:

- `9d4e21a` preserves the conversation/header identity for close-to-toggle focus.
- `6824cc2` removes the inherited drawer shadow.
- `000abff` passes default-empty activity through the pane model and seeds the planning fixture's writer marker. Its native shell snapshot uses Reduce Motion `on` and was inspected before promotion.

Each fix passed its scoped source review; actual post-fix interaction remains pending. The current Release build succeeded with the same local QA command above; log `/tmp/10x-f59a-session-map-slice1-current-release.log`. The bundle ID remains `com.nextstep.tenx.sessionmap.f59a`, and executable SHA-256 is `cd7af9be085f1fcbaf7ebe8d7793b384f28c25ef820ff04272e4d0a5dea1b7df`. This build has not been launched because the Mac is locked. Use `TENX_UI_FIXTURE_SHA=000abff0990f98fbbeecf28d69c80a23d3979441` when resuming.

After the Mac is unlocked, launch only the isolated build:

```bash
/usr/bin/open -n \
  --env TENX_UI_FIXTURE=map-planning \
  --env TENX_UI_FIXTURE_SHA=000abff0990f98fbbeecf28d69c80a23d3979441 \
  --env TENX_UI_FIXTURE_APPEARANCE=light \
  --env TENX_UI_FIXTURE_REDUCE_MOTION=off \
  --stdout /tmp/10x-f59a-session-map-current.stdout.log \
  --stderr /tmp/10x-f59a-session-map-current.stderr.log \
  /tmp/10x-f59a-session-map-release/Build/Products/Release/10x.app
```

Confirm the route/SHA in the actual visible window before interacting. Stop only this task's unique fixture instance before changing launch fixtures. Other installed 10x apps are outside this test.

## Actual native observations

| Check | Result and evidence |
| --- | --- |
| Initial state | Map began closed; the real composer contained `Keep the map open while I review the transcript.` and `map-layout.png`. |
| Open and shortcut | Clicking Map opened the pane; Command-Shift-C closed and reopened it. Draft and attachment remained. |
| Default/wide shell | Initial pane value was 440 points. Increasing through the native adjustable divider stopped at 720 points, consistent with the 1,440-point window width. An additional Increment left it at 720. |
| 320-point pane | Native divider reached 320; graph remained before walkthrough, plan and summary. [Image](native-planning-pane-320.png), [accessibility state](native-planning-pane-320.txt). |
| Half-window pane | Native divider reached and clamped at 720. Transcript and composer remained visible. [Image](native-planning-pane-720.png), [accessibility state](native-planning-pane-720.txt). |
| Pointer divider drag | Dragging the actual divider changed 720 to 439 points; a second drag far left clamped it back to 720. |
| Dock threshold | Resizing the window produced a docked half-width of 590 points, then a slightly narrower window switched to a trailing drawer with no divider. [Dock image](native-planning-threshold-docked.png), [dock state](native-planning-threshold-docked.txt), [drawer image](native-planning-drawer-before.png), [drawer state](native-planning-drawer-before.txt). Exact 1,180-point resolution is also covered by the focused presentation test. |
| Minimum | Dragging below the minimum stopped at a native capture of 760×592 including window chrome; the app content minimum remains 760×560. The graph and fixed pane header/footer remained visible. This capture was viewed inline; the Mac locked before it could be saved. |
| Node selection | Clicking Map writer focused its native element and changed the details to `Map writer / Proposed / Produces a bounded XML document.` Direct-neighbor marks highlighted. |
| Escape focus | **Failed on this captured build.** After a node had accessibility focus, Escape closed the pane but focus returned to Session prompt instead of the Map toggle. The actual before/after accessibility output was inspected during the run. A source fix is committed separately; native GREEN is pending. |
| Walkthrough | Next changed the visible step from 1 of 4 to 2 of 4. Arrow delivery after attempts to focus the wrapper remains unresolved; the OS keyboard-navigation setting was untouched. [Open walkthrough state](native-planning-keyboard-before.png) is evidence of that unresolved state, not the Escape result. |
| Drawer rendering | **Defect on this captured build.** The parent shadow was inherited by individual graph/details/walkthrough surfaces. A separate fix removes the inherited shadow; actual corrected drawer inspection is pending. |

Images of the 1,440-point-wide window were scaled by the capture service to 1,229×768 pixels. Pane widths above come from the actual accessibility-adjustable divider, not estimates from those resized images. The layout is computed by the app and need not match hand-positioned design coordinates.

## Automated verification

| Run | Observed result |
| --- | --- |
| Pre-feature baseline | 1,348 tests / 34 suites; six disclosure snapshot failures. `/tmp/10x-f59a-baseline.log` and `.xcresult`. |
| Task 6 implementation | 9 focused tests passed; real-shell, existing header, graph and pane snapshots passed. `/tmp/10x-f59a-session-map-task6-final-focused.log`. |
| Slice 1 full app target at 2a1e247 | 1,383 tests / 34 suites; **35 Map tests passed**. Overall run failed with 10 issues: the six known snapshot mismatches plus one provider timing issue and three assertions in one startup test. `/tmp/10x-f59a-session-map-slice1-tests.log` and `/tmp/10x-f59a-session-map-slice1.xcresult`. |
| Isolated follow-up | Both additional failed test functions passed once in isolation: provider timeout test in 0.053 seconds; startup catalog test in 1.204 seconds. This does not make the full-suite run green. `/tmp/10x-f59a-session-map-slice1-isolated-failures.log`. |
| Focus fix 9d4e21a | Four focused tests passed, unchanged shell/header references. `/tmp/10x-f59a-session-map-task6-fix1-focused.log`. Native close-to-toggle behavior is pending. |
| Drawer fix 6824cc2 | Existing actual-shell snapshot passed once. `/tmp/10x-f59a-session-map-task6-fix2-focused.log`. Actual drawer inspection is pending. |

Known baseline snapshot names: `activityDisclosureSnapshot`, `activityDisclosureSnapshotDark`, `activityStructuredDiffDarkSnapshot`, `subagentActivitySnapshot`, `subagentActivitySnapshotDark`, `structuredDiffSnapshot`. Their existing standard-detail collapsed/expanded reference mismatch was inspected before feature work; references were not promoted. Existing local AppIntents/linkd service noise is retained in the logs.

Additional full-run failures: `ProviderAccountExtensionBackendTests.helloAgainstARealChannelThatNeverOpensDegradesWithinItsOwnTimeoutNotTheChannels()` and `startupAutoSelectionRefreshesTheSharedCommandCatalogBeforeNewSession()`.

## Final test run at the current source

The app target was run again at `000abff`: **1,383 tests / 34 suites, all 35 Map tests passed**. The full run still failed: six known disclosure snapshots and `SessionControllerTests.controllerReportsProviderAndRuntimeTransitionsFromRPCLifecycle()` (`retainedProviderWithoutModel`). Log: `/tmp/10x-f59a-session-map-slice1-current-tests.log`; result bundle: `/tmp/10x-f59a-session-map-slice1-current.xcresult`.

Xcode also reported `No space left on device` while collecting its log archive. The volume had 153 MiB available. Only this task's Debug module/index caches and build intermediates were removed; source, results, other sessions' files and build products were preserved. The last observed available space after rebuilding was 971 MiB.

The one additional failing test was run once in isolation against the same compiled test product using `test-without-building`; it passed in 2.133 seconds. Log: `/tmp/10x-f59a-session-map-slice1-current-isolated.log`. The overall full-suite result remains failed; this isolated pass is not a clean-suite claim. No unrelated source or snapshot reference was changed.

## Remaining native gate

- Rebuild current fixes and repeat Escape/shortcut focus return at dock and drawer widths.
- Verify the corrected drawer and synthetic live activity with Reduce Motion on/off.
- Verify walkthrough focus/arrows/endpoints, composer key ownership and existing composer-flyout Escape behavior.
- Switch the two real fixture sessions and verify per-session focus, draft and attachment preservation.
- Inspect dense, cyclic, disconnected, empty and invalid fixtures in the native app, including panning and dark appearance.
- Complete keyboard-only node/relationship actions and VoiceOver; restore any settings changed during those checks.

The Mac locked during the native gate, and computer control could not unlock it. The user was asked to unlock it. No VoiceOver, Keyboard Navigation, appearance or other system settings were changed. Model-generation work and the dependent later gates have not started behind this incomplete native gate. Actual Jump/file/Use behavior belongs to Tasks 12/13.

## Handoff status

**BLOCKED at the first native gate.** Map tasks 1–5 are complete; Task 6 source and scoped fixes are reviewed, but its native acceptance gate is incomplete. Map tasks 7–13 and flyer tasks 1–4 have not started. Resume the pending native checklist above before the dependent implementation work in the committed plans.

The branch remains a draft. Synchronization with `origin/main` is independently blocked: automatic approval review rejected `git merge --no-edit origin/main` with `approval required by policy, but AskForApproval is set to Never`. That operation had no effect and has not been retried or replaced with an alternate synchronization method. It remains required before the final integration/ready gate.

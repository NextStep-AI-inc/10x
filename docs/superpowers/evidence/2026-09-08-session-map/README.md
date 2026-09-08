# Session Map: Slice 1 native evidence

Status: **DONE WITH CONCERNS for the fixture slice — native layout and keyboard checks pass; VoiceOver speech remains a manual verification gap.**

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

Each fix passed its scoped source review. The Release build succeeded with the same local QA command above; log `/tmp/10x-f59a-session-map-slice1-current-release.log`. The bundle ID remains `com.nextstep.tenx.sessionmap.f59a`, and executable SHA-256 is `cd7af9be085f1fcbaf7ebe8d7793b384f28c25ef820ff04272e4d0a5dea1b7df`. The Mac was unlocked and this build was launched on September 8. Its visible title confirmed `000abff0990f`; the resumed results below distinguish passing behavior from additional defects found.

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

## Resumed native run at 000abff

The user unlocked the Mac and asked to continue. These are real Release-window checks, with synthetic fixture data, from the same executable hash recorded above.

| Check | Observed result |
| --- | --- |
| Drawer shadow | Corrected. The drawer no longer casts a separate inherited shadow around its graph, details and walkthrough surfaces. [Image](native-current-drawer.png), [AX](native-current-drawer.txt). |
| Minimum window | The app stopped at 760×592 including 32 points of window chrome. Architecture, fixed header and footer stayed visible. [Image](native-current-minimum.png), [AX](native-current-minimum.txt). |
| Session switching | Real rail clicks changed the transcript, draft and attachment to the second session while Map stayed open. Switching back restored the original draft, attachment and selected component/walkthrough state. [Second-session image](native-current-session-switch.png), [AX](native-current-session-switch.txt). |
| Plan selection | Clicking the second plan task selected Map pane and displayed its matching details. |
| Composer ownership | Left/Right with Session prompt focused left the walkthrough unchanged. The existing Context window popover opened; Escape dismissed it while Map stayed open. The fixture has no model catalog, so model/command flyouts are not available in this fixture. No prompt was submitted. |
| Dense graph | All 24 nodes were exposed. Vertical panning reached nodes 22–24 and scroll value 1 while the architecture header stayed in place. [Initial dark image](native-current-dense-dark.png), [panned image](native-current-dense-panned.png), [AX](native-current-dense-panned.txt). |
| Cycles and disconnected nodes | The second dense-fixture session rendered wrapped roots, a disconnected component, self-cycle and return cycle. At pane width 320, the graph exposed horizontal scrolling; its native Scroll Right action reached value 1 and the outer lanes. [Dark image](native-current-cycles-dark.png), [panned 320 image](native-current-cycles-panned-320.png), [AX](native-current-cycles-panned-320.txt). |
| Empty and invalid | Empty showed “Nothing new.” Invalid XML showed the retry state. Both preserved the draft and attachment. [Empty](native-current-empty.png), [invalid](native-current-invalid.png). |
| Reduce Motion | With the explicit fixture override off, 18 actual native frames over 1.541 seconds showed 15 distinct pixel values at the live marker. With it on, 18 frames over 1.646 seconds showed one value. [Off recording](native-current-reduce-motion-off.mp4), [on recording](native-current-reduce-motion-on.mp4), [timestamps and measurements](native-current-motion-measurements.json). The videos encode captured native frames at their measured intervals; they do not synthesize animation. This tests the component's motion consumer, not a global OS setting change. |

Additional behavioral RED findings from this run:

- Escape still returned focus to Session prompt after Map writer was focused. [Closed-state image](native-current-escape-focus.png), [AX](native-current-escape-focus.txt).
- Tab reached the walkthrough text, and Right changed the selected component, but the visible/AX step counter remained unchanged. Clicking Next then advanced the counter; the next Right again changed only the component. [Image](native-current-walkthrough-arrow.png), [AX](native-current-walkthrough-arrow.txt).
- Tab reached a graph node, but Return and Space did not select it. The node exposed an unknown role instead of a button role.
- A long dense edge label was clipped on both sides because the Canvas text was drawn without the layout's label bounds. The initial dense image above is the RED evidence.
- Expanding Relationships exposed repeated “Architecture relationships” text instead of node descriptions, offered no row selection actions, and omitted full edge labels from shared relationship descriptions.

The scoped fix round addresses these failures in `ebe8dd0`, `b183633`, `15dec05`, and `34a5872`. The post-fix results follow below.

VoiceOver speech verification remains unavailable. System Settings showed VoiceOver initially off; it was temporarily enabled for the planned check. The controller could not obtain the VoiceOver caption window and timed out. VoiceOver was confirmed off again at the end; the caption-panel preference was already on and was not changed. System Settings was returned to its original Storage page. No Keyboard Navigation, appearance or motion system preference was changed. Accessibility-tree inspection is recorded separately and is not a claim that spoken navigation passed.

## Post-fix native verification at 34a5872

The final scoped source range is `69fe938..34a58726d402c60b8d3a3902a491cdf33afc87f0`. Six focused tests passed in 0.601 seconds, including all eight existing graph snapshots and the real-shell reference unchanged. Log: `/tmp/10x-f59a-session-map-task6-fix3-focused.log`. A scoped re-review found all five findings addressed in source and no new Critical/Important breakage. The full app suite was not repeated for these scoped fixes; its last results are preserved above.

Release build passed with the command recorded above. Log: `/tmp/10x-f59a-session-map-fix3-release.log`. Executable SHA-256: `940274b5ab3418b2177652e77d85e1bacdc9941dcdd3185873dee1816f9f1933`. The actual window title confirmed `34a58726d402`. Only evidence files were uncommitted when this source was built.

| Native regression | Result |
| --- | --- |
| Focused Escape, dock | A pointer click gave Map writer actual keyboard focus; Escape closed Map and AX focus reported Open session map. [Image](native-fixed-escape-focus.png), [AX](native-fixed-escape-focus.txt). |
| Header activation and shortcut | Space reopened the focused Map toggle once. After focusing the composer, Command-Shift-C closed Map and returned focus to the toggle. Return reopened it once. |
| Focused Escape, drawer | At the minimum 760×592 window, a pointer-focused Map writer closed with Escape and focus returned to Open session map. [Image](native-fixed-drawer-focus.png), [AX](native-fixed-drawer-focus.txt). |
| Graph keyboard actions | Tab from Map writer reached Native map document; Return selected it and updated details. The next Tab reached Map pane; Space selected it. Both controls exposed button roles. |
| Walkthrough | Tab from the final node reached walkthrough text. Right advanced 1→2→3→4, changing the counter and selected details together. Another Right stayed at 4. Left returned 4→3→2→1; another Left stayed at 1. Focus remained in the walkthrough. [Last-step image](native-fixed-walkthrough-end.png), [AX](native-fixed-walkthrough-end.txt). |
| Relationship list | Expanded rows exposed distinct native button labels with full edge text, including bounded context, XML and native views. Clicking the Map pane row selected the matching graph details. [Image](native-fixed-relationships.png), [AX](native-fixed-relationships.txt). |
| Dense label bounds | Long labels now end in a visible ellipsis inside the reserved drawing area; the full text remains in native node/relationship labels. [Image](native-fixed-dense-labels.png), [AX](native-fixed-dense-labels.txt). |

The automation's AX button press selects a node without transferring keyboard focus. For the Escape regression, the test therefore used an actual pointer click and asserted the focused node before pressing Escape. This avoids mistaking a composer-owned Escape for a focused-pane failure.

The remaining fixture-slice gap is manual VoiceOver spoken navigation. The layout and keyboard defects found during the native run are resolved; subsequent implementation may proceed with this explicit verification limitation, rather than treating source inspection as a spoken-navigation pass.

Actual Jump/file/Use behavior belongs to Tasks 12/13. Model-generation and flyer work were not started behind the failed native layout/keyboard checks; those checks have now passed.

## Handoff status

**DONE WITH CONCERNS for Map tasks 1–6; both overall plans remain in progress.** The fixture slice was reported with native evidence and the manual VoiceOver gap. Continue flyer tasks 1–4, then Map tasks 7–13. Final acceptance must retain or resolve the VoiceOver limitation and the full-suite baseline failures rather than silently marking either green.

The branch remains a draft. Synchronization with `origin/main` is independently blocked: automatic approval review rejected `git merge --no-edit origin/main` with `approval required by policy, but AskForApproval is set to Never`. That operation had no effect and has not been retried or replaced with an alternate synchronization method. It remains required before the final integration/ready gate.

# Bottom signal dock — native acceptance

## Latest: italic context label

The inline context trigger now uses italics in both closed and open states. Release build and five focused checks passed (`/tmp/10x-context-italic-build.log`, `/tmp/10x-context-italic-tests-green.log`). Native label rendering and details open/close verified in the isolated Release app; see [native detail](italic-context-detail.png). Updated snapshot differences were confined to the context glyphs. No full-suite rerun for this typography change. Native narrow interaction was not repeated.

## Earlier: session-only inline context

At `b291733`, context sits inside a small break at the far-left of the line only while viewing a session. New Session and Archived keep an unbroken line. Five focused checks, Release build, and native context open/close and route checks passed. See [verification](inline-context-verification.md), [session detail](inline-context-session-detail.png), and [new-session detail](inline-context-new-session-detail.png).

## Earlier: transparent context label

At `f73ba4e`, the resting background is removed; spacing and original hover styling remain. Four focused checks, Release build, and native open/close interaction passed. See [verification](context-chip-verification.md) and [native detail](context-no-fill-detail.png).

## Earlier: context control styling

At `c88c228`, context has a small outer inset, internal padding, and faint neutral resting fill; the existing hover style is retained. Four focused checks and the Release build passed; native click opens details. See [verification](context-chip-verification.md) and [native detail](context-chip-detail.png).

## Earlier: control placement correction

At `8a6302c`, attachment/model/timer align beneath the editor's left edge; context is a small text-only label at the signal's exact far-left endpoint above the line. The final Release build and four affected tests passed. Native context, attachment, and model clicks all worked, resolving the earlier interaction observation. See [placement verification](placement-verification.md) and [native detail](placement-detail.png).

Production Release build, macOS, isolated bundle `com.nextstep.tenx.bottomdockqa`. All provider/RPC responses came from a local fixture; no real provider requests or credentials were used. Main checkout and real app profile were untouched.

## Earlier: alignment correction

Product revision `19f5cce` tightens the dock controls and aligns the provider row. Ten focused tests and the isolated Release build passed; native typing, send/follow-up, provider-panel clearance, model menu in Ready, and cross-route line alignment were checked. Context-popover clicks still did not open; native narrow interaction remains unverified. See [spacing verification](spacing-verification.md) and [native detail](spacing-working-detail.png). PR remains draft. The results below describe earlier revisions.

## Earlier result

**DONE_WITH_CONCERNS** on `codex/bottom-dock-design`. Product commit `538395bbbb1f7ad6c174de4c89ca8e0abd8c9724` passed the isolated Release build and scoped final review. PR remains draft: native final-fix checks are blocked by the locked Mac, and the full suite remains red as detailed below. No merge or deployment.

## Native evidence at `248d4ee`

| Flow | Observed result | Evidence |
| --- | --- | --- |
| Ready / typing | Short draft hugs line; long draft scrolls in fixed viewport; only top fades | `ready.png`, `typing-top-fade.png` |
| Send | Return creates the existing message bubble, clears draft, starts timer; Shift-Return inserts newline | `working.png` |
| Streaming delivery | Both Steer and Follow up selectable; each submission increments existing queue; empty draft exposes Stop | Native clicks + fixture RPC trace; final queue capture pending |
| Provider panel | Wheel opens upward; Manage accounts navigates to Providers and closes panel | `provider-panel.png` |
| Route scope | Providers, Settings, Archived retain same full-width line; no session context shown; working aggregate remains | `providers-working.png`, `settings-working.png`, `archived-working.png` |
| Tool failure | Existing error card remains in transcript, dock stays Working | `tool-error-working.png` |
| Required input | Amber remainder + Needs your response; clicking Cancel returns Working | `needs-input.png` |
| Retry | Amber Retrying; exhausted retry becomes red Failed | `retrying.png`, `retry-failed.png` |
| Stop / restart | Neutral Response stopped with recovery card; native Restart shows Opening | `stopped.png`, `ready-after-restart.png`; Opening observed in accessibility state before capture |
| Compaction | Reverse sweep consumes old context; waits at zero for measured read; new context reveals smoothly to 30% | `compaction-native.gif` |

The GIF is a crop of actual captured native frames with their measured capture intervals; there are no synthetic intermediate frames. Capture starts at 90%. Sampled cyan endpoint: 4.875s = 0px, 5.499s = 0px, 5.748s = 547px, 6.107s = 727px on a 2360px-wide window. This verifies the hold and partial reveal rather than only the settled endpoint.

Interim native build `26464f8` additionally verified 98% exact numeric usage plus amber minimum-width remainder/true endpoint, input priority over near-limit, and unexpected process exit producing full red line, unavailable context, disabled send and recovery card.

## Test evidence

Focused task runs: Task1 4; Task2 9; Task3 6; Task4 23 plus 4 fix checks; Task5 15; Task6 8 plus 2 regression and 2 placement checks. All passed. Every task received a scoped code review.

Full suite at baseline: 1,605 tests / 43 suites / 192 issues. Full integrated run: 1,637 tests / 43 suites / 187 issues (179 snapshot issues, 8 functional issues). The suite is **not green**. Four pre-existing functional failure names remain: `closingDuringAnOpeningTaskPublishesUnavailable`, `archivingAPendingStreamingSessionClosesAndRemovesActivity`, `staleReconciliationFailureCannotOverwriteNewerBoundary`, and `controllerReportsProviderAndRuntimeTransitionsFromRPCLifecycle`. A newly named full-suite queue timeout, `repeatedQueuedMessagesKeepExactlyOneVisibleEchoPerSubmission`, passed a focused rerun; its parallel-suite behavior is unresolved. Only intended affected references were promoted, not unrelated baseline failures.

## Limits / remaining checks

- Native profile uses synthetic provider/model data. Live provider accounting and real long-running sessions are not verified.
- Native resize attempts through the available coordinate API did not change the window. An additional offscreen render using the compiled composer and a streaming controller with two queued messages confirmed readable controls at760pt (`narrow-streaming-queued-offscreen.png`). Native narrow-window interactions remain unverified.
- Reduce Motion has deterministic test coverage; the user's global accessibility setting was not changed.
- Image paste/drop and file-path attachment behavior have not completed native QA. Paperclip opens the native picker.
- Immediate automated typing after Cmd-K sometimes arrives before search receives focus; after focus settles, search and Escape work. Final review found the deferred focus assignment and command routing unchanged from baseline. No introduced defect was established; a native baseline timing comparison was not performed.
- Initial native QA found model/project/context clicks intercepted by an anchor measurement view. A targeted hit-test fix and idle queue badge fix passed three focused checks and scoped review at4d5a6e8. The Release rebuild passed, but the Mac locked before native menu recheck. That recheck remains pending.

## Build reproduction

```sh
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath .superpowers/sdd/2026-09-28-bottom-signal-dock/NativeQA/DerivedData \
  CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=com.nextstep.tenx.bottomdockqa
```

The local fixture and nonactivating launcher live in this worktree's ignored `.superpowers/sdd/2026-09-28-bottom-signal-dock/NativeQA/`. Launch uses an isolated HOME and CFFIXED_USER_HOME. Saved logs/xcresults remain in that plan workspace.

## Final review

Two complementary reviews found two Important issues: queued streaming submissions cleared current compaction/retry facts, and raised provider wheels overlapped the narrow attachment strip. Both were fixed in `538395b` and the single scoped re-review approved both Important fixes. Four controller/layout regressions and one inspected 760pt attachment/provider snapshot passed. The dense 760pt footer itself was readable; adding durable rendered coverage was the only Minor UI test gap. Existing compiler warnings were non-blocking. The durable dense-queue snapshot gap remains a nonblocking Minor: the separate offscreen dense render proved current legibility, while the new attachment regression does not include queue/context values. Native interactions at the final fix revision remain unverified because the Mac is locked.

## Resume native verification from this checkout

The committed harness recreates the isolated fixture from the existing repository fixture; run commands from the repository root. It never delegates prompts to a real provider.

```sh
mkdir -p .superpowers/sdd/2026-09-28-bottom-signal-dock/NativeQA
cp docs/superpowers/evidence/2026-09-28-bottom-signal-dock/harness/prepare.py .superpowers/sdd/2026-09-28-bottom-signal-dock/NativeQA/prepare.py
python3 .superpowers/sdd/2026-09-28-bottom-signal-dock/NativeQA/prepare.py
xcrun swiftc docs/superpowers/evidence/2026-09-28-bottom-signal-dock/harness/launch.swift -o .superpowers/sdd/2026-09-28-bottom-signal-dock/NativeQA/launch
# After building with the Release command above and unlocking the Mac:
.superpowers/sdd/2026-09-28-bottom-signal-dock/NativeQA/launch \
  "$PWD/.superpowers/sdd/2026-09-28-bottom-signal-dock/NativeQA/DerivedData/Build/Products/Release/10x.app" \
  "$PWD/.superpowers/sdd/2026-09-28-bottom-signal-dock/NativeQA/profile"
```

If the normal updater appears, choose **Not now** to retain the QA build. Open a seeded session, type/send through the native composer. Inspect fixture RPC trace `profile/fixtures/bottom-dock-rpc.jsonl` to obtain its session basename. Write backend events to `profile/fixtures/bottom-dock-control.json` (each event batch needs a unique `id`; `target` is the session basename):

```json
{"id":"context90","target":"session-123.jsonl","percent":90,"events":[{"type":"config_update"}]}
```

Supported fixture controls: `stateDelay` (seconds before measured get_state response), `stateError`, `finish`, `exit`, and `events` containing actual RPC event shapes. For compaction use `auto_compaction_start`, then `auto_compaction_end` with `aborted:false`, `willRetry:false`, and `result:{tokensBefore:180000,tokensAfter:60000}` while setting `percent:30`. A follow-up sent during a delayed ending must retain Refreshing context until the measured reveal.

Remaining native gates: click project/model/context menus after the anchor fix; verify narrow attachments/provider panel after the placement fix; send a queued follow-up during delayed compaction refresh. The prior isolated QA app and its fixture processes were stopped. Do not use the main app profile.

## Final build and residuals

The Release build at `538395b` completed successfully. See `build-provenance.json` for source revisions and executable hashes, and `final-fix-verification.md` for exact focused test/build commands and results. The final fix build was not launched because the Mac locked.

At `538395b`, one nonblocking warning remained (the helper is now annotated at `19f5cce` and no longer warns): `App/Providers/ProviderUsageDockLayout.swift:42` reads main-actor-isolated `ComposerAttachmentsView.stripHeight` from an unannotated helper. This computed height reads constants; the production call is from main-actor UI. An annotation cleanup was deferred after the successful build and approved review, so a stricter future Swift toolchain may require it. Other compiler warnings were already present.

### Decisions made

- Use available Codex worker/reviewer agents because cursor-agent is installed but reports Authentication required — preserves delegated execution without waiting on login — cost if wrong: review depth/model preference may need revisiting.
- Run focused tests per task and the full suite at baseline/final, not once per small task — plan scopes tests and user forbids unnecessary repeated suites — cost if wrong: cross-task regression detected later at final gate.
- Add completeSignalReveal(generation:) in Task 2 with the observable phase fields, then populate lifecycle in Task 5 — Task 4 needs a compilable callback before Task 5 — cost if wrong: small interface refactor.
- Center the editor within the route canvas, including rail inset; keep the signal at shell width — binding spec is more precise than Task 4's generic centered wording — cost if wrong: visual alignment adjustment.
- Proceed with focused dock tests while preserving pre-existing baseline failures — build succeeds and broad failures precede changes — cost if wrong: a baseline issue may obstruct final acceptance; keep PR draft unless required gates are met.
- Extend Task 5 ownership to ComposerView and ContextUsageControl for the exact numeric reveal — the existing control renders usage independently and spec requires its number to fade with the line — cost if wrong: small control API adjustment. Preserve context popover data/actions.
- Extend Task 4 ownership to WorkspaceSignalView for an optional Reduce Motion environment override used by static snapshots — TimelineView shimmer makes new full-shell references nondeterministic, and StartupSignalView already uses this pattern — cost if wrong: small testability API cleanup. System accessibility remains the default.
- Use two complementary final review lenses (async/state and UI/focus/accessibility) as required by reviewing-code for substantial changes; main owns native QA — avoids duplicating a generalist review while covering cross-task seams — cost if wrong: one extra review seat. Reuse existing test evidence, with focused reruns only for concrete unresolved doubts per developer testing limits.
- Extend Task6 fix ownership to shared FlyoutPlacement.swift for a proven anchor hit-test regression — adjacent paperclip works while anchored controls do not — cost if wrong: broader flyout interaction regression; require focused regression and native recheck.
- Park the new stripHeight isolation warning after a successful Release build and approved fix review — the computed height reads constants and current production call is main-actor UI; do not start optional cleanup/rebuild rounds — cost if wrong: future stricter Swift compilation needs an annotation fix. Worker reverted only its uncommitted annotation experiment; reviewed538395b retained.

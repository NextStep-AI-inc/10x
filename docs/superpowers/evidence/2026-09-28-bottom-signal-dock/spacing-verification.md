# Dock alignment correction — 2026-09-29

Product commits: `955ae78`, `19f5cce9d73b5a8eb784c2c652f1b78149f8b146`.

## Changed

- Removed the empty warning control's 32-point gap.
- Aligned footer facts, actions, and collapsed provider wheels on a common center, 30 points below the line; kept the same line/footer height on other routes.
- Reduced model/project/context and delivery labels to 11 points; send/stop visuals are 24 points inside 28-point hit frames. Provider hit frames remain 44 points.
- Anchored delivery actions near the editor's trailing edge. Expanded provider panels retain 16 points of bottom clearance; narrow provider placement retains attachment clearance.

## Verified

- Ten focused tests passed; exact invocation and output: `spacing-focused-tests.log`. Wide/narrow composer, working/queued actions, Archived, provider routes, and narrow attachments were rendered and inspected.
- Universal Release build succeeded at `19f5cce`, isolated bundle `com.nextstep.tenx.bottomdockqa`. Executable SHA-256: `a3a790458df398fea990f9a8ab5da4d915f1d4dab380740a79403df5a800e20f`. Build command remains the NativeQA command documented in README. Build log: `/tmp/10x-spacing-release.log`.
- Launched the actual Release build with the disposable `/tmp/10x-spacing-qa/profile` fixture profile, PID 54036. No real provider calls. Confirmed native window visible before interaction.
- Native coordinate clicks: Send starts a run; Follow up selects delivery mode; Send queues a follow-up and shows `1 queued`; provider wheel opens its panel and an outside click closes it; model menu opens in Ready and Escape dismisses it.
- Native visual checks: typing and working footer controls share a baseline, panel has bottom clearance, and Archived retains the same line height. Screens: `spacing-typing.jpg`, `spacing-working.jpg`, `spacing-provider-panel.jpg`, `spacing-archived.jpg`, `spacing-model-menu.jpg`, `spacing-ready.jpg`. `spacing-working-detail.png` is a crop of the actual working screenshot, with no layout alteration.
- Isolated QA app quit; PID no longer present. Main checkout/profile untouched.

## Not verified / observed limits

- Context popover did not open from native clicks on either its text or icon, in Working or Ready. The model menu initially did not open while Working, then opened in Ready. No root cause was established; this interaction issue is recorded separately from the requested geometry correction.
- Native narrow-window interactions and attachment removal remain unverified. 760-point render coverage passed; this pass did not repeat previously unsuccessful native resize attempts.
- Expanded-panel snapshot filters selected zero tests; actual open-panel spacing was instead checked natively.
- No full-suite rerun for this bounded style change. The previously recorded baseline/integrated full-suite failures remain unresolved. Live provider data was not exercised.

## For Tanner to test

Confirm the compact sizing and grouping feel right at the window width you normally use. Context-popover interaction needs a separate fix before the larger dock PR is ready.

# Composer control placement, 2026-09-29

Product commits: `ec6c036` and `8a6302c542a4656ecadc592a3ab2c408c34fd731`.

## Verified

- Attachment aligns beneath the editor's left edge, followed by model and working status/timer. Project selection remains available on new-session screens after these compact facts.
- Context is a 10-point text-only control above the main signal's exact left endpoint (x0), independent of the sidebar/editor inset. The four-bar icon is removed. Main signal context coloring remains. Compact layouts lift the label further when needed to avoid placeholder overlap.
- Six focused rendering tests passed for the initial rearrangement. After removing the final 24-point inset, four affected tests passed (five inspected references): `placement-focused-tests.log`. Wide/narrow active, queued, and dense attachment layouts were inspected.
- Final universal Release build succeeded at `8a6302c`: `/tmp/10x-context-x0-final-release.log`. Bundle `com.nextstep.tenx.bottomdockqa`; executable SHA-256 `3147d7114e1f3f66a6b56dbe2275111e4e807413ac7a524b85003a3532602ecb`.
- Native Release launched with disposable local-fixture profile `/tmp/10x-placement-qa/profile`, PID 23489. Observed a rendered 1180x760 window, typed and sent a prompt, and checked the working timer and draft placement.
- Native coordinate click on context at x32/y690 opened its details; Escape dismissed. The relocated attachment control opened the system file picker, then Escape canceled without selecting a file. The relocated model control opened its menu while Working. This supersedes the earlier spacing pass's unresolved context/menu click observation.
- Screens: `placement-new-session.jpg`, `placement-working.jpg`, `placement-context-open.jpg`, `placement-model-open.jpg`, `placement-typing.jpg`. `placement-detail.png` is an unaltered-layout crop of the final native typing screenshot.
- Isolated QA app quit; PID absent afterward. No real provider requests, merge, or deployment.

## Not verified

Native minimum-window interactions were not repeated; 760-point snapshot coverage passed. File selection/drop/paste and live provider accounting were outside this placement change. The full suite was not rerun for this bounded layout correction; earlier recorded full-suite failures remain unresolved.

## For Tanner to test

Confirm the attachment/model/timer grouping and context placement feel right at the usual window width. PR stays draft pending the broader dock's remaining acceptance checks.

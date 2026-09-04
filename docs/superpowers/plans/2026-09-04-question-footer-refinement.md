# Question and composer refinement

Approved follow-up: strengthen native question hierarchy and option descriptions in the existing 10x style; place Steer/Follow up before the provider selector; show provider rings only on session pages.

1. Preserve question response identity while separating title and explanation visually.
2. Reserve the provider selector’s measured horizontal footprint in the composer footer and anchor the shell overlay to that slot. Keep expanded account selection and outside-click dismissal.
3. Verify question snapshots and response tests, footer layout at constrained widths, session-only visibility, and the Release application. Capture local evidence and update PR 22; do not merge.

## Verified result

Implemented at `fec3cba`. All 1,293 app tests and four XCTest checks passed, with reviewed question and full-shell snapshots. The signed Release build was inspected at 1180 and 760 points. A real Grok 4.6 Medium native question was answered successfully and its CLI change passed 14 fixture tests. Settings, Providers and Archives were checked without the session dock.

The session-page scope includes both new and active session composers. The reserved 60pt footer height deliberately contains provider hit targets and labels; the prior 28pt action row did not reserve their visual footprint. Live narrow-window checks confirmed both Steer and Follow up fit clearly before the rings.

Private screenshots and `refinement-report.md` live in the existing Downloads evidence bundle. Multiple real accounts and live dark appearance were not repeated; the existing test/snapshot coverage remains. The duplicated Ask summary and terminal-style Other prompt are separate follow-ups. No merge or deployment.

## Compact alignment follow-up

The compact account stacks now omit provider abbreviations, matching compact legacy wheels. The footer reserves the existing 44pt hit target instead of 60pt, so ring centers align with the other controls. Full-size account selectors retain labels and compact accessibility names remain intact. Seven affected light/dark, narrow/wide, single/multiple-account shell snapshots were reviewed and passed; the Release build and signature verification passed.

Live verification of `6e81767` is blocked by two Preparing runtime startup timeouts. Continue to workspace showed empty provider onboarding. No third launch was attempted. Private evidence includes the actual timeout and a clearly labeled test render; preceding live screenshots are from `fec3cba`.

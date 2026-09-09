# Active-session Audit Local Integration Plan

> **For agentic workers:** Execute this checklist with `superpowers:executing-plans`. Preserve the individual verified feature branches and their evidence; this is local QA integration authorized by Tanner on September 8.

**Goal:** Combine the thirteen approved audit branches with current main and verify the resulting Release app as one product.

**Architecture:** Use a new local integration branch based on `0be4353f7ee2d72813d41d6195422f34ef213c22`. Merge pinned feature heads in dependency order, resolve only overlap/conflict defects, and regenerate the Xcode project from the combined source tree. Existing PRs remain the review units.

**Tech Stack:** Swift, SwiftUI/AppKit, OmpKit, xcodebuild, xcodeproj 1.27.0.

**Spec:** The full audit roadmap arrives from `codex/active-session-recovery` at `docs/superpowers/plans/2026-09-07-active-session-audit-roadmap.md`; every individual feature plan and evidence directory is preserved by its merge.

## Global constraints

- Work only in `/tmp/10x-audit-integration` on `codex/active-session-audit-integration`; leave the user's main checkout and other worktrees untouched.
- Local integration is explicitly authorized. GitHub PR merges and deployment are not authorized. Do not push this QA branch or create an additional PR under this local-only grant.
- Preserve normal git ancestry with local merge commits. No force-push, shared-history rewrite, bulk “ours” resolution, dependency changes, or hand-edited generated Xcode project.
- Regenerate `10x.xcodeproj/project.pbxproj` with `ruby scripts/generate_xcodeproj.rb` after source merges. Resolve generated-file conflicts by choosing either side, then regenerating.
- Use the existing task-owned derived-data cache; no cache deletion or port 3000. Build and launch a separately named, separately identified QA bundle using the isolated neutral QA profile.
- Live Pinyin configuration approval is still pending. Actual AppKit marked-text checks may run; do not change keyboard sources without that approval.
- Do not expand baseline failures or unrelated UI concerns into new features. Attribute regressions to integration and correct only failures caused by this combination.

## Task 1: Baseline and pinned inputs

- [x] Fetch `origin/main`, verify its exact SHA, and create the fresh worktree/local branch.
- [x] Run the six known activity snapshot selectors at current main, preserving any actual/reference output for attribution: `structuredDiffSnapshot()`, `activityDisclosureSnapshot()`, `subagentActivitySnapshot()`, `activityDisclosureSnapshotDark()`, `activityStructuredDiffDarkSnapshot()`, `subagentActivitySnapshotDark()`.
- [x] Record the exact baseline command, nonzero test count, and outcome before source merges.

Pinned merge inputs:

| Branch | Commit |
| --- | --- |
| `codex/active-session-recovery` | `178269e42045a864f28ca6dd841e5fa258d05a5e` |
| `codex/active-session-queue` | `7ae5f805661122016f538645650fe8632c672d2b` |
| `codex/active-session-images` | `96f6a7c17e9731cc3cef1b6ee6e6002ab9de6ebc` |
| `codex/active-session-turns` | `32349d23dd0260953b77aae8a247b83533bdd9d1` |
| `codex/active-session-stop` | `a026eb5756b85ff4f4668c574ced36d2f840a0fe` |
| `codex/active-session-signals` | `ab466c353b9531bad1098ef64e88ec4ff2cecb0f` |
| `codex/active-session-review` | `dcc2585ac5042a4c434d16d4cb776bcae023b13b` |
| `codex/active-session-context` | `4f9880f7b13192d8663a4d2180e73939d1cfa018` |
| `codex/active-session-details` | `e0c4b168c069b23e1fd6f7fdd9356622b6fced5c` |
| `codex/active-session-drafts` | `7eb79918435efca9fd66cdbcd6d706b097fb6e9c` |
| `codex/active-session-input` | `998d753b9e6d7974d99cab5d4ccc28d82eb20f88` |
| `codex/active-session-titles` | `64b67e4ce466ffc4cd4d0d8c319f1e285f987503` |
| `codex/active-session-permission-scope` | `aa312ed80ff9bac39bfa3abc468c3eb181c71229` |

## Task 2: Combine the reviewed changes

- [x] Merge each pinned head in table order with `git merge --no-ff --no-edit <sha>`. Stop the batch on a conflict; inspect the three versions before resolving.
- [x] Preserve current-main structured settings editors together with permission-scope copy.
- [x] Preserve the latest session-open recovery and durable Stop fences, authoritative queue refresh, and image-history mapping.
- [x] Preserve controller-owned tool disclosure, passive visible scroll targets, explicit attention jumps, readable turn timing/status, and scoped changed-file navigation.
- [x] Preserve native compaction capability/recovery, per-file result extraction, child recent-detail reconciliation, and preferred-editor links.
- [x] Preserve serialized draft disk writes and the pre-RPC durable send barrier, Continue route restoration, fallback naming/metadata refresh, asynchronous attachment picking, marked-text routing, and independent warning display.
- [x] Regenerate the Xcode project, inspect the final combined diff for lost/duplicate behavior, and commit every resolution with the relevant merge.

## Task 3: Verify the combined code

- [x] Run `swift test --package-path OmpKit` and record nonzero totals and explicit skips.
- [x] Run `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /Users/tannerpham/Library/Developer/Xcode/DerivedData/10x-aeaprfrgcfzmarhgxipsdmykgcoj ARCHS=arm64 CODE_SIGNING_ALLOWED=NO` against the combined source.
- [x] Attribute failed tests using baseline evidence. Correct integration-caused failures with focused red/green checks; re-run only affected tests after each correction.
- [x] Build arm64 Release using the same project/scheme/cache and `-configuration Release -destination 'generic/platform=macOS'`; package a separate integration QA app, record source and executable hashes, and verify its signature.

## Task 4: Accept the combined native flow

- [x] Confirm the exact QA build is visible. Start from the existing neutral QA profile, with a separate app bundle identifier and app-specific preferences/drafts.
- [x] Exercise a real short provider turn, inline multi-file edit review, and branch metadata. Verify completion/status, per-file navigation, and preferred-editor behavior together.
- [x] Exercise pending requests while reading/typing, queue/Stop controls, disclosure and reading position across session switches, and compaction feedback through the prepared controlled fixtures.
- [x] Use the native picker inside text, native Undo/Redo, staged image and independent model/attachment errors. Quit/relaunch to confirm separate draft and last-route recovery; reuse the controlled unconfirmed-send fixture to rule out automatic replay if integration touched the send barrier.
- [x] Inspect tool timer/tail/child details in the combined build. Reuse already recorded individual-feature proof when its code is unchanged and the combined focused tests cover the connection; state any skipped native repetition explicitly.
- [ ] Run live CJK composition only if pending Pinyin approval arrives. Otherwise preserve that precise outstanding gate. **Still pending: no Pinyin approval received.**
- [x] Capture real screenshots/AX evidence and neutral control traces, close task-owned QA processes, and commit the final acceptance report with branch/SHA, verified/not-verified/user-test sections.

Acceptance evidence: [combined Release report](../evidence/2026-09-08-audit-integration/README.md). The timer/tail/child native repetition was explicitly reused from the unchanged accepted feature implementation. Combined typing screenshots start after requests were already pending; the individual feature evidence covers arrival.

## Completion boundary

The deliverable is a locally committed integrated branch and an evidence-backed Release QA package. Keep the existing GitHub PRs unmerged and drafts until all applicable readiness gates pass. Request no new approval for reversible conflict resolution or fixture adjustments inside the authorized local integration. An unresolved baseline failure or absent live CJK permission must be reported precisely without mislabeling the combined build as fully green.

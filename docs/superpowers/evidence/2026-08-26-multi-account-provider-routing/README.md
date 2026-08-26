# Multi-account provider routing — verification evidence

Branch: `tannerpham/resume-codex-implementation-833cbd`, rebased onto `main` @ `d8f2853`
Plan: `docs/superpowers/plans/2026-08-26-10x-multi-account-provider-routing.md`
Companion plan: `docs/superpowers/plans/2026-08-26-omp-provider-account-rpc-contract.md`

## Branch reconciliation

Tasks 1-5 were committed on `codex/multi-account-provider-routing` (e1ff0a6). Tasks 6-9 existed
only as a detached HEAD (3413451) in a Codex agent worktree and were never merged back. The
reconciled branch was built on 3413451 with e6a69e9 and e1ff0a6 cherry-picked on top. A safety
ref, `codex/provider-routing-tasks6-9`, points at 3413451.

The only non-additive conflict was `latestRouteOperationIDs`, which e1ff0a6 deliberately
replaces with `appliedRoutes`; that replacement was carried through.

The 25 reconciled commits were then rebased onto `main` @ `d8f2853` (the rich-chat merge). Every
rebase conflict was confined to the two generated Xcode project files, resolved by re-running
`scripts/generate_xcodeproj.rb` at each step. Feature source is byte-identical to the pre-rebase
tree (`git diff backup/pre-rebase-a72996d HEAD -- App/ Tests/` is empty outside main's own docs),
and the generator agrees with the committed project files after the rebase.

## Task 9 review findings

The Task 9 re-review never ran (the reviewing agent hit a usage limit). Each finding was
re-checked against the merged tree:

| # | Severity | Finding | Resolution in tree |
|---|---|---|---|
| 1 | BLOCKER | Removal allowed with no eligible replacement | `ProviderAccountCoordinator.removeAccount` throws `.noEligibleReplacement` before mutating anything |
| 2 | BLOCKER | Failover could land on a pending-removal account during the RPC | Managed-turn barrier: `beginManagedTurn` refuses while that provider has a pending removal, `canCreateManagedSession` gates new sessions, and the removal loop waits on `hasActiveManagedTurn` / `hasLoadingRegistration` / `hasGeneratingProvider`. Wired in production at `App/Sessions/SessionController.swift:310` and `App/Application/AppModel.swift:281,309` |
| 3 | SHOULD_FIX | Partial repin or RPC failure left committed side effects | `restoreRemovalMutation` restores the original primary and re-pins moved sessions |
| 4 | SHOULD_FIX | Primary never repaired on ordinary refresh | `reconcilePrimaryAccount` called from three load/refresh sites in `ProviderManagementViewModel` |
| 5 | SHOULD_FIX | Production `ProvidersView` never received the coordinator | Task 10 (this branch) |
| 6 | SHOULD_FIX | Duplicate labels indistinguishable in removal confirmation | `accountDetailLabel` passed at `App/Providers/ProvidersView.swift:51` |
| 7 | SHOULD_FIX | Removal overlay did not isolate the workspace | `.disabled` + `.accessibilityHidden` on the underlying workspace |

## Automated verification

- `ruby scripts/generate_xcodeproj.rb` run twice, no diff either time.
- `OmpKit`: 179 tests passed.
- 10x: **586 tests in 15 suites, all passed** (`tenx-test-run.txt`).
  Before the rebase this run had two failures, both `fullTranscript*WindowSnapshot`, pre-existing
  at the old base (9998923) and repaired on `main` by `d8f2853 test(chat): re-record full
  transcript snapshots for rich chat surfaces`. Rebasing picked up those repaired references and
  the suite is now fully green. All three account-dock shell references still matched
  byte-for-byte after the rebase, so the rich-chat work did not alter the shell chrome they
  capture.
- OMP `codex/provider-account-rpc`: focused contract suites 50/50, `bun check` clean, full
  suite 13752 passed / 6 failed (`omp-test-run.txt`). Four `HTML export template` failures
  reproduce at the branch base b4e8e856a and are pre-existing. Two `RpcClient lifecycle`
  failures are load-flaky: they pass 10/10 in isolation on both branch and base, and a second
  full run failed a *different* pair of tests in that file.

## Composer invariance

The dock is a SwiftUI `.overlay`, so it cannot change the layout of the view it covers. Measured
directly: the composer band cropped from the full-shell references is byte-identical between the
provider-only dock and the multi-account dock. Both hashes were recomputed after the rebase and
are unchanged.

| Width | Provider-only reference | Account reference | Composer band SHA-256 (first 16) |
|---|---|---|---|
| 1280 | `full-shell-usage-dock-wide-window.png` | `full-shell-account-dock-wide-window.png` | `aec18cea7e9fe6ef` (both) |
| 760 | `full-shell-usage-dock-small-window.png` | `full-shell-account-dock-minimum-window.png` | `ca5aba2c01147e65` (both) |

Expanded-panel and confirmation states are covered by the Task 8 dock references at 430x460,
a narrower frame than the 760 minimum shell width, so the bounded 360x440 panel is proven to fit
with room to spare.

## Three-width shell references

Recorded and visually inspected (`Tests/TenXAppTests/ReferenceImages/`):

- `full-shell-account-dock-wide-window.png` (1280x760) — regular 54pt wheels in the trailing
  gutter beside the composer, 2- and 3-account stacks cascading rightward, no clipping.
- `full-shell-account-dock-compact-trigger-window.png` (1180x760) — stacks widen the group past
  the gutter, so the dock moves above the composer at 44pt. This is the case the Task 10 wiring
  fixes: the shell previously measured `providerCount` rather than real stack widths and would
  have kept the wheels inline.
- `full-shell-account-dock-minimum-window.png` (760x560) — dock above the composer, no clipping
  and no collision at the minimum supported width.

## OMP wire redaction

`omp-account-wire-frames.jsonl` is a live capture of `negotiate_protocol`, `list_provider_accounts`,
`get_provider_account_usage`, and `get_state` against two seeded OAuth rows whose access and
refresh values contained the marker `SECRETVALUE`.

No occurrence of `SECRETVALUE`, `sk-access`, `accessToken`, `refreshToken`, `apiKey`, `token`,
`secret`, `credentialId`, or the fixture account ids appears anywhere in the captured frames.
`accountRef` is an opaque hash (`acct_v1_...`). The only filesystem paths in the capture are
`get_state.data.sessionFile` and `get_state.data.systemPrompt`, both pre-existing fields this
contract does not touch; the account command responses and `activeProviderAccounts` carry none.

## Older-OMP compatibility

The Release build was launched against the installed `omp/18.0.4`, which has no account commands.
The dock rendered three plain provider wheels (OAI, ANT, CUR) with no cascading account stacks,
no exact-count centers, and no account controls. Automated coverage for the same path lives in
`ProviderManagementViewModelTests.providerOnlyCapabilityUsesCLIUsageAndHidesAccountControls` and
the unsupported-command fallback cases.

## Not verified

The account-capable acceptance sweep needs the branch OMP build plus authenticated accounts.
`OmpExecutableLocator` checks `~/.bun/bin/omp` before `PATH`, and macOS resolves
`homeDirectoryForCurrentUser` from the user record rather than `$HOME`, so the built app cannot
be pointed at a different OMP without repointing that symlink. Left undone rather than mutating
the environment. Consequently these remain unverified live:

- Generating grayscale, hovered-background colorization, and focus raise in the running app.
- Queue-after-turn, automatic failover, and recovered-primary behavior, which need real turns.
- Live VoiceOver and keyboard traversal of the panel.
- Real account removal against OMP.

All of the above have automated coverage; what is missing is the built-app pass.

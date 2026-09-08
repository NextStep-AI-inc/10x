# Command Browser Verification Evidence

Verified on branch `codex/command-browser-design` at local commit
`fdef628c9c3dcdb290e350893e6d325651076388` on September 1, 2026.

## Build and automated gates

- `bundle exec ruby scripts/generate_xcodeproj.rb` followed by
  `git diff --exit-code -- 10x.xcodeproj/project.pbxproj` passed.
- The complete `TenXAppTests` target ran 1,020 tests. Command-browser,
  command-model, keyboard-monitor, focus-routing, accessibility, and integrated
  snapshot coverage passed. The only persistent failures were the three known
  account-dock snapshot baselines:
  `fullShellAccountDockCompactTriggerWindowSnapshot`,
  `fullShellAccountDockMinimumWindowSnapshot`, and
  `fullShellAccountDockWideWindowSnapshot`.
- An independent review run also saw
  `controllerReportsProviderAndRuntimeTransitionsFromRPCLifecycle` fail once;
  its isolated rerun passed, so it remains a documented unrelated flake.
- The complete `OmpKit` gate previously passed 188 tests, with three
  environment-dependent real-OMP tests skipped. The keyboard-only follow-up
  changed no `OmpKit` source.
- Release compilation succeeded from this commit with
  `CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=`. The temporary artifact was signed
  to run locally, its nested Sparkle components were normalized to the same
  local signature, and `codesign --verify --deep --strict` passed.
- Developer ID signing was not available in this shell: signing Sparkle with
  the installed NextStep identity returned `errSecInternalComponent` because
  the login keychain was locked. This did not block local Release UAT.

## Live keyboard UAT

The optimized Release app was launched from
`/private/tmp/tenx-command-browser-release/Build/Products/Release/10x.app` and
driven through its real macOS accessibility surface.

| Flow | Observed result |
| --- | --- |
| Type `/` in New Session | Browser opened over the composer with 88 live commands; the editor retained focus. |
| Root movement | Down selected `effort`; Up and Home selected `model`; End selected `review`; Page Down selected the ninth result; Page Up returned to `model`. |
| Source shortcuts | Cmd-1…Cmd-6 selected All, App, Commands, Skills, Extensions, and Prompts. Cmd-7 was ignored. Ctrl-Tab and Ctrl-Shift-Tab cycled in both directions. Editor focus was retained throughout. |
| Unavailable sources | Commands and Extensions explained that a session must be started instead of presenting an empty list. |
| Original failure sequence | `/` → Cmd-2 → Return → Ctrl-Tab → type `x` returned from Model to root, selected Commands, updated the draft to `/x`, and kept the editor focused. It did not create a session. |
| Native Model | Return opened the searchable native control. Down plus Return applied the next model; the original `Kimi K3` selection was then restored. Return closed the browser and restored prompt focus. |
| Native Effort and Fast | Both opened from typed commands. The current Kimi model exposed no mutable Effort/Fast choices, so applying a changed value was not live-tested. Escape returned to root and prompt focus. |
| Active command catalog | An existing idle session exposed 125 commands: 3 App, 36 Commands, 82 Skills, 1 Extension, and 3 Prompts. |
| Subcommands | `/mcp` opened 17 accessible subcommands. Down highlighted `list`; Enter staged `/mcp list ` and entered arguments without executing. |
| Argument editing | Normal caret movement and insertion produced `/mcp list keyboard-checXk`; two Escapes backed out and closed the browser while preserving the draft and editor focus. |

No live command that would alter MCP configuration was executed. The temporary
Model change made to prove arrow activation was restored to the user's original
`Kimi K3` setting before the run ended.

## Screenshots

Live Release captures:

- [Root browser](live-root.jpeg)
- [Native Model child](live-native-model.jpeg)
- [Live `/mcp` subcommands](live-subcommands.jpeg)
- [New Session unavailable Commands source](live-unavailable.jpeg)

Deterministic integrated snapshot-harness captures, kept separate from the live
evidence:

- [Minimum-window long-name layout](harness-minimum-window.png)
- [Streaming Steer / queued follow-up layout](harness-streaming-steer.png)

## Not live-verified

- A Developer ID-signed artifact, because the login keychain did not permit the
  Sparkle signing operation in this shell.
- Applying changed Effort and Fast values, because the selected Kimi model did
  not advertise those capabilities.
- An actual in-flight streaming command and a live catalog refresh/removal.
  Their behavior is covered by model tests and integrated snapshots only.
- VoiceOver, Full Keyboard Access traversal, Reduce Motion, and exact live
  760 × 560 resizing. Accessibility metadata and the minimum-window/motion
  states are covered by tests, but these OS-level modes were not manually
  enabled during this run.

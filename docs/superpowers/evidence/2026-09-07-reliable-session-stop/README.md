# Reliable Stop verification

The Stop action now closes the managed runtime after a bounded best-effort abort. This prevents OMP 18.1.10 background bash completion from restarting a stopped response. Restart reconnects the same saved conversation without sending staged input. This deliberate fallback requires Restart after Stop because the installed RPC has no owner-scoped background-job cancellation command.

## Verified in the native Release app

| Case | Evidence |
| --- | --- |
| Real background work | OMP auto-backgrounded a 120-second bash command as `bg_2`, then ran a foreground 100-second sleep. Stop was clicked at 06:02:17 UTC with staged text and `context.png`. Both observed runtime/worker PIDs were absent by 06:02:44; no new response or background completion appeared through 06:05:16, beyond both original deadlines. |
| Preserved input | Staged text and PNG remained immediately after Stop and after clicking Restart. The staged marker was absent from saved user messages. |
| Restart after dismissal | Dismiss left a visible Restart action. Restart reopened the same saved conversation, retained staged input, and added no user prompt. |
| Stopped presentation | Current nonfinal assistant, running tool, and pending decisions settle to an aborted/stopped presentation. Completed older turns remain completed. Reopened actual OMP history showed the stopped state. |
| Keyboard from pending input | On the final source, the controlled RPC fixture displayed simultaneous confirm, select, and input cards. Command-period from the input field removed all pending cards and showed the Stopped footer, preserving `PENDING-STOP-PRESERVES-DRAFT`. |
| Keyboard from model chooser | Command-period from the focused search field of the open model chooser stopped the controlled response. The chooser could remain open while the stopped/restart state was visible behind it. |

The background-process checks used actual OMP and the configured Cursor provider. Pending-decision and model-chooser checks used a controlled RPC fixture; they do not claim a provider approval-policy capability. The first exploratory 70-second sleep finished before Stop and is excluded from acceptance.

## Build and checks

- Final source: `ae2b1354b77206318a6753bb8b6bc160f0dac352`.
- Final arm64 Release build succeeded. Packaged executable SHA-256: `8d03c5e53d7cb1620e5c35ac941914250b9358961638d5b5717de9130ae14945`.
- Final focused stopped-presentation/lifecycle run: **16 tests passed, 0 failed**, 1.556 seconds. Earlier bounded-shutdown/interrupt regression run also passed 16 focused tests.
- The actual background test used source `bb37c6a` and executable `c4ddf171777516fc7e26882ea42b6c69f39007b6b4ac5fdf2bfc9f6741882780`; the later source change only settled the locally displayed current turn/pending cards. Both artifacts are identified separately in the manifest.
- Bundles were independently named, ad-hoc signed, and verified with `codesign --verify --deep --strict`. Only isolated QA state/projects were modified. The main checkout and user's installed app were untouched. Both QA apps and their observed children were closed.

## Limits

No merge, deployment, runtime patch, or dependency update. The inherited transcript-scroll regression remains tracked in PR #35 and is not claimed fixed by this Stop PR. Full-suite baseline snapshot failures are documented with the earlier recovery work; this correction used focused tests and the real interaction surface. This evidence excludes raw prompts, model reasoning, auth state, and account logs.

# Provider account routing without an OMP fork — verification evidence

Branch: `tannerpham/resume-codex-implementation-833cbd` @ `124fb9e`, on `main` @ `d8f2853`.
Spec: `docs/superpowers/specs/2026-08-26-provider-account-extension-design.md`
Plan: `docs/superpowers/plans/2026-08-26-provider-account-extension.md`

This supersedes the transport verified in
`docs/superpowers/evidence/2026-08-26-multi-account-provider-routing/`. See that
directory's own note for why.

## Automated suites

| Suite | Result |
|---|---|
| 10x app (xcodebuild, serial) | **630 tests, 19 suites, 1 failure** |
| OmpKit (`swift test`) | 177 / 177 |
| OmpExtension (`bun test`) | 35 / 35, 60 expect() calls |
| `scripts/generate_xcodeproj.rb` | idempotent, zero diff on the second run |

The single failure is `continuousSettingsSnapshot`, which **passes in isolation**
(0.078s). It is this machine's load artifact, not a defect: the full suite
degrades as test litter accumulates and the launchd-inherited `maxfiles` soft
limit is 256. Baseline at plan start was 586 tests in 15 suites.

`task12-generator-and-extension-tests.txt` holds the generator and bun runs.

## The t2 channel, proven end to end against real `omp` 18.0.4

`omp-account-wire-frames.jsonl` is a verbatim bidirectional capture, both
directions, against a real `omp --mode rpc` process loading the real extension
via `-e`. The full command round trip:

| # | Direction | Frame |
|---|---|---|
| 1 | recv | `extension_ui_request`, `title: tenx.provider-accounts.v1` |
| 2 | send | `extension_ui_response`, `value: {"id":"c1","command":"hello"}` |
| 5 | recv | reply carried in `placeholder`: `{"ok":true,"data":{"contractVersion":1}}` |
| 6 | send | `list_accounts` |
| 7 | recv | accounts, each with a sha256 `accountRef` |
| 8 | send | `pin_account` |
| 9 | recv | `{"ok":true,"data":{"account":{…}}}` |
| 10 | send | `remove_account` |
| 11 | recv | `{"ok":true,"data":{"removed":true,"accounts":[…]}}` |

This confirms the contract the whole design rests on: the reply to a command
arrives as the `placeholder` of the NEXT request, and the client's response frame
is **flat** (`{type, id, value}`) with no `body` wrapper.

Unrelated interleaved OMP traffic (`setWidget`, `available_commands_update`) was
captured rather than filtered, so the file shows what really crossed the wire.

## Redaction

Two OAuth rows were seeded into an isolated `AuthStorage` under a scratch
`PI_CODING_AGENT_DIR`, with `access`, `refresh`, and `accountId` all carrying the
marker `TASK12-SECRET-MARKER-9f3ab2`.

Independently re-verified by the controller: **zero** marker occurrences across
all 12 frames. Also zero occurrences of `accessToken`, `refreshToken`, `apiKey`,
`"access"`, `"refresh"`, `credentialId`, and zero filesystem paths.

Scope stated honestly: this covers the account channel's traffic plus whatever
interleaved on the same connection. It does not cover `get_state`'s `sessionFile`
and `systemPrompt`, which are pre-existing OMP fields this plan does not touch and
which the superseded evidence already documented as carrying paths.

Details in `redaction-check.txt`.

## Tier selection, proven at the process level

`tier-process-evidence.txt`, with the three snapshots beside it.

- **t2** — normal Release build. Every spawned `omp` carries
  `-e …/10x.app/Contents/Resources/omp-extensions/provider-accounts/index.ts`, and
  every one is confined to the scratch `PI_CODING_AGENT_DIR`, never the real `~/.omp`.
- **t1** — extension resource absent. Four `--no-session` clients spawn with **no**
  `-e`, matching `ProviderExtensionBundle.spawnArguments`' `guard let indexURL else { return [] }`.
  With no `-e`, OMP never loads the extension, so tier detection can only time out
  on hello and degrade to `.stockOMP`.
- **t0** — usage metadata without per-account identity. The extension IS loaded and
  healthy, and the tier is still `.providerOnly`, because `detect`'s
  `hasPerAccountIdentity` check runs on the snapshot BEFORE hello is consulted.

## Not verified

**The GUI acceptance sweep did not run.** Every synthetic click was refused by the
environment ("would land on axAuditService, which is not in the allowed
applications"); `AXIsProcessTrusted()` is false for this session and a second
access request was auto-denied, consistent with a non-interactive session that
cannot service a live permission dialog. Process-level proof was substituted for
the same mechanism, but the following still need a human at the keyboard:

- Hover and keyboard-focus colorization of a background account wheel.
- The bounded panel opening, all three scope confirmations, and the restart notice
  reading correctly in `.stockOMP`.
- A real account removal end to end, and Connections' disabled Remove row.
- Automatic failover, queue-after-turn, and recovered-primary behavior, which need
  real accounts under real load rather than seeded rows.
- VoiceOver and keyboard traversal.

**Also unverified:** behavior against a genuinely older `omp` that predates the
extension API. Everything here ran against the installed 18.0.4.

## Known limitation worth a decision

Account identity is derived from `omp usage --json`. A freshly authenticated
account with no recorded usage yet therefore lands in `.providerOnly`, so a user
who has just added an account may see no account controls until usage exists.
This is fail-closed and safe — it hides controls rather than misrouting — but it
is a real first-run rough edge that no task in this plan addressed.

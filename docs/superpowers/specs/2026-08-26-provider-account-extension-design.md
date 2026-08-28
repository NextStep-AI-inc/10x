# Provider Account Routing Without an OMP Fork

**Status:** Approved for implementation planning

**Date:** 2026-08-26
**Platform:** macOS 15+, Swift 6.1, SwiftUI; TypeScript on Bun for the extension
**Supersedes:** the transport half of `2026-08-26-multi-account-provider-routing-design.md`
**Unchanged by this document:** every product decision in that design except
the account stack presentation, revised 2026-08-27 below — exact
per-account counts, compact grayscale rules, bounded panel, three switch
scopes, safe removal ordering.

## Goal

Deliver multi-account provider routing without modifying OMP, without carrying
a fork, and without requiring any particular OMP version. The behavior the user
sees is the approved design; only the mechanism changes.

The companion plan `2026-08-26-omp-provider-account-rpc-contract.md` added four
protocol-v2 RPC commands to a local OMP checkout. That work is complete and
verified, but it can never ship: `oh-my-pi` is a third-party project
(`can1357/oh-my-pi`) consumed as a published dependency. Those commands will not
exist in any OMP a user installs. This document replaces that transport with
three mechanisms that already exist in stock OMP.

## Why this supersedes the RPC contract

The RPC contract assumed 10x needed new OMP protocol commands. It does not.
Every capability the feature requires is already reachable:

- account listing and per-account usage through a stock CLI,
- exact-account pinning through public `AgentSession` and `AuthStorage` methods,
- an extension system that reaches those methods and ships from outside OMP.

The 24 commits on `codex/provider-account-rpc` are mined, not merged. Their
redaction rules, availability classification, and atomic-removal ordering port
into the extension against the same `AuthStorage` APIs.

## Verified foundation

Every fact below was confirmed against stock OMP `b4e8e856a` (18.0.6) and, where
noted, against the published `omp/18.0.4` installed on this machine.

### Stock surfaces this design depends on

- **`omp usage --json` is already a per-account breakdown.** Confirmed live on
  18.0.4. Each report carries `provider`, `limits`, and a `metadata` object with
  `accountId`, `email`, `orgId`, `projectId`. The response also carries
  `accountsWithoutUsage` and `disabledCredentials`.
- **`OmpUsageSnapshot` in 10x already decodes that exact shape**, including
  `accountsWithoutUsage` and `disabledCredentials`.
- **`credentialPinHash(provider, identity)`** in
  `packages/coding-agent/src/session/credential-pin.ts`, **as of stock commit
  `b4e8e856a` (v18.0.6)**, is a documented, stable `sha256` over
  `provider\0accountId\0email\0orgId\0projectId`, emitted as bare lowercase hex
  with no prefix. The abandoned `codex/provider-account-rpc` fork modified this
  function; parity must always be taken against stock, never that fork. Its source
  comment names the digest input as the persisted contract for
  `CredentialPinEntry.hash`.
- **`credential_pin` session-file entries** are written after each assistant turn
  and re-applied on session adoption by `seedCredentialPins`, which calls
  `AuthStorage.pinSessionOAuthAccount`. It is a no-op when the account is gone or
  when a live sticky already exists.
- **A `credential_pin` entry has SIX keys, not three.** Corrected during Task 9.
  `CredentialPinEntry extends SessionEntryBase`, so alongside `type`, `provider`,
  and `hash` it carries `id`, `parentId: string | null`, and `timestamp`. This is
  not cosmetic: `SessionEntryIndex.insert()` sets the file's leaf to the last
  entry on disk unconditionally, and every read walks back through `parentId`. An
  entry written without a correct `parentId` becomes the leaf and severs the
  chain, so a resumed session renders with EMPTY history. Anything writing into a
  session file must reproduce the full base shape.
- **`AgentSession.listCurrentProviderOAuthAccounts()`** and
  **`AgentSession.pinCurrentProviderOAuthAccount(credentialId)`** are public
  stock methods. `/session pin` is built on them and refuses while the session is
  streaming.
- **`ExtensionContext` does NOT expose the `AgentSession`.** Verified against
  stock `b4e8e856a`: the object an extension receives has `ui`, `mode`, `cwd`,
  `sessionManager` (a `ReadonlySessionManager`), `modelRegistry`, `model`,
  `isIdle()`, and others, but no `session` key. The extension therefore cannot
  call the two `AgentSession` methods above directly. It reaches the same
  behavior through the same underlying calls those methods wrap:
  `ctx.modelRegistry.authStorage` for `listOAuthAccounts` /
  `pinSessionOAuthAccount` / `removeCredential`,
  `ctx.sessionManager.getSessionId()` for the session id, `ctx.model?.provider`
  for the provider, and `!ctx.isIdle()` in place of `isStreaming`.
  `pinCurrentProviderOAuthAccount` is literally a provider-and-streaming guard
  around `authStorage.pinSessionOAuthAccount(provider, sessionId, credentialId)`.
- **`AuthStorage.removeCredential(provider, credentialId)`** exists but is
  reachable only through OMP's interactive TUI selector. There is no RPC command
  and no CLI flag for it.
- **The extension system is first class.** `ExtensionAPI` injects the full
  `pi-coding-agent` SDK, which re-exports `./session/auth-storage`. Extensions
  subscribe to `session_start`, `credential_disabled`,
  `before_provider_request`, and 30-odd others.
- **There is NO extension event for account failover.** Corrected during Task 7.
  This document previously assumed `retry_fallback_applied` /
  `retry_fallback_succeeded` signalled a sibling-account rotation. They do not:
  their payload is `{ from, to, role }` carrying MODEL names, and they belong to
  OMP's configured model-fallback chain, a different feature. The mechanism that
  actually rotates accounts within a provider, `AuthStorage.rotateSessionCredential`,
  emits nothing an extension can see — confirmed against the full 35-member
  `ExtensionEvent` union at `b4e8e856a`.

  Consequence: t2 detects automatic failover by diffing the session-sticky
  account (`OAuthAccountSummary.active`) across turn boundaries in
  `before_provider_request`, rather than being notified. Detection is therefore
  after the fact and requires a subsequent request on that session. It is still
  far tighter than t1, which learns only at the next usage poll, but it is not
  instantaneous and this document should not claim it is.
- **`omp -e, --extension=<path>` loads an extension file and may be repeated.**
  Confirmed on the installed 18.0.4. `--no-extensions` disables discovery while
  explicit `-e` paths still load.
- **RPC mode supports awaited extension UI requests.** `rpc-mode.ts` maintains a
  `pendingRequests` map keyed by request id and resolves on the client's
  response. 10x already implements the client half: `ProviderManagementService`
  sends `.extensionUIResponse(id:body:)` and `OmpKit` models
  `ExtensionUIRequest`.
- **`get_state` returns `sessionFile`.** Confirmed in a live capture against
  18.0.4, alongside `activeProviderAccounts`.
- **`OmpKit.RpcClient` already takes arbitrary spawn arguments** through
  `extraArguments`, and already resumes a session with `-r <path>`. Passing
  `-e <path>` needs no new plumbing.

### What does not exist in stock OMP

- Any RPC command for listing, pinning, or removing provider accounts.
- Any RPC or CLI path to `removeCredential`.
- Any RPC routing of slash commands, so `/session pin` is not reachable from a
  client.

## Capability tiers

One presentation layer, three backends. The tier is detected, never configured.

| Capability | t0 provider-only | t1 stock OMP | t2 extension |
|---|---|---|---|
| Account list and per-account usage | no | `omp usage --json` | extension, live |
| `accountRef` | n/a | computed in Swift | identical value |
| Route a new session | no | pin, then re-adopt before the first prompt | in-process pin |
| Route an idle running session | no | pin, then restart the session process | in-process pin, no restart |
| Route a generating session | no | queue, then restart when idle | queue, then in-process pin when idle |
| Provider primary preference | no | yes | yes |
| Exact-account removal | no | **no** | `AuthStorage.removeCredential` |
| Automatic failover events | no | inferred at next poll | `retry_fallback_*`, sequenced |

t0 is the behavior already built and live-verified against 18.0.4: the existing
provider-only wheel, no account controls.

### Tier detection

Detection replaces the RPC capability probe, which is deleted.

1. The bundled extension emits a hello on `session_start` carrying a contract
   version. Received within the startup window, and version compatible → **t2**.
2. OMP starts and `omp usage --json` returns reports carrying per-account
   `metadata` identity fields, but no compatible hello arrives → **t1**.
3. Anything else, including a `usage --json` shape without per-account metadata
   → **t0**.

The extension must fail closed. An extension that throws on load, or announces a
contract version 10x does not recognize, degrades to t1 rather than leaving the
app in a half-configured state. Degradation is visible in Connections, never
silent.

## `accountRef` becomes a 10x-computed value

Under the RPC contract, OMP minted an opaque `accountRef`. It now becomes a Swift
reimplementation of `credentialPinHash`:

```
sha256(provider \0 accountId \0 email \0 orgId \0 projectId)
```

with empty strings for absent fields, matching OMP's `join("\0")` over
`[provider, accountId ?? "", email ?? "", orgId ?? "", projectId ?? ""]`, and
returning nothing when both `accountId` and `email` are absent.

This is the same value OMP computes, which is what makes a pin written by 10x a
pin OMP honors. It is also durable across token refresh and storage reorder, and
carries no raw identity, satisfying the original boundary requirement: only
opaque references and safe labels cross into the application.

Correctness here is load-bearing, so it is verified by parity fixtures generated
from OMP itself rather than by hand-written expectations.

## Architecture

`ProviderAccountService` becomes a protocol with three implementations behind it.
Nothing above the protocol changes.

- **`ProviderAccountUsageBackend`** (t1 and t2 read path) parses
  `omp usage --json`, groups reports by provider, computes `accountRef` per
  account, and derives availability from `disabledCredentials` and
  `accountsWithoutUsage`.
- **`ProviderAccountPinBackend`** (t1 write path) writes `credential_pin`
  entries into the session file and coordinates session restarts.
- **`ProviderAccountExtensionBackend`** (t2) exchanges commands with the bundled
  extension and consumes its events.

### t1 routing semantics

Stock OMP applies a pin only at session adoption and will not clobber a live
sticky, so a running session cannot be re-routed in place. In t1:

- **New session** — a new session has no session file until OMP creates one, so
  there is nothing to pin before spawn. 10x spawns, reads `sessionFile` from
  `get_state`, writes the pin, and re-adopts with `-r <sessionFile>` before the
  first prompt is sent. Nothing is lost because no turn has run, and the user
  sees only startup. This is the same first-prompt fence the coordinator already
  enforces.
- **Idle running session** — the pin is written, then 10x closes and respawns
  that session's OMP process with `--resume`. The conversation survives in the
  session file. In-flight tool calls do not.
- **Generating session** — the switch queues, exactly as the approved design
  requires, and the restart happens when the turn finishes.
- The scope confirmation states that the session will restart, in that tier
  only. The control never silently does something different from what it says.

### t2 routing semantics

The extension calls `session.pinCurrentProviderOAuthAccount(credentialId)`
in-process. No restart. Because stock OMP refuses to pin while streaming, a
generating session queues and pins on idle, which is the approved behavior
arrived at independently.

### The 10x to extension command channel

Extension to 10x is proven: OMP emits `extension_ui_request`, 10x responds. The
reverse direction has no stock RPC command, so the extension holds an awaited
request that 10x answers with a command, then reopens it. The loop is built only
from verified primitives, but it has not been demonstrated end to end. The
implementation plan must prove this loop in isolation before anything is built
on top of it, and must define the behavior when the loop drops: the extension
reverts to announcing state only, and 10x degrades that session to t1.

## The extension

**Location:** `OmpExtension/` at the repository root — a bun project with its own
`package.json` and tests, versioned and released with the app it belongs to.

**Build:** a build phase emitted by `scripts/generate_xcodeproj.rb` bundles it to
`10x.app/Contents/Resources/omp-extensions/provider-accounts/`. Generator output
must stay idempotent, which the existing verification already checks.

**Load:** 10x passes `-e <bundled path>` on every OMP spawn — both the dedicated
no-session client used for provider operations and each session process. Nothing
is written into the user's OMP configuration, so an OMP upgrade requires no
action.

**Responsibilities:**

- list accounts and pin exact accounts through public `AgentSession` and
  `AuthStorage` methods,
- remove one exact account through `AuthStorage.removeCredential`,
- publish account changes with a monotonic per-process sequence, so clients can
  deduplicate,
- translate `credential_disabled` into availability and
  `retry_fallback_applied` / `retry_fallback_succeeded` into failover events,
- enforce routing at `before_provider_request`,
- emit only opaque refs and safe labels, never tokens, credential ids,
  filesystem paths, or raw provider payloads.

The redaction, availability classification, and removal ordering are ported from
`provider-account-rpc.ts` on `codex/provider-account-rpc`, which already has test
coverage for duplicate labels, enterprise label redaction, partial failure, and
secret redaction.

## What is deleted, what survives

**Deleted:**

- `OmpKit` account RPC commands `listProviderAccounts`,
  `providerAccountUsage`, `setSessionProviderAccount`, `removeProviderAccount`,
  their response decoders, and the account-change frame.
- The `ProviderAccountService` RPC path and the RPC capability probe.

**Survives unchanged:**

- `ProviderAccountCoordinator`, including the managed-turn removal barrier,
  `restoreRemovalMutation` rollback, and the no-eligible-replacement guard.
- `ProviderPrimaryPreferenceStore` and primary repair on refresh.
- All three switch scopes and their queueing semantics.
- Every account UI surface and its reference images.

The coordinator's removal barrier remains correct and remains necessary. It now
guards an extension call rather than an RPC command.

## Honest states

The tiers must be legible, because a control that silently does nothing is worse
than an absent control.

- Removal is unavailable in t1. Remove is disabled on every row; the reason
  is named once, under the affected provider's header, rather than repeated
  on every row where it would crowd out each account's own Primary/session
  metadata. (Revised after Task 11 shipped this per-row, identically on every
  account — a visual regression against the established Connections design,
  fixed by moving the one true section-wide fact to the section header.)
- The scope confirmation names the session restart in t1, as part of the
  selected scope's own description inside the radio group — an attribute of
  the choice the user is looking at, not a separate notice floating below
  the list.
- A failed extension load is NOT diagnosed. 10x cannot distinguish "the
  extension failed to load" from "no extension is present" from "the version
  is unrecognized" — all three yield the same absent or incompatible hello,
  so any string naming a cause would be a guess presented as fact. Both the
  removal reason and the restart notice state only what 10x can verify, never
  why the extension is absent. This is also why Connections carries no
  separate degradation banner: the tier's real limits already surface at
  Remove and at the switch dialog, without inventing a diagnosis.
- No tier ever presents a control it cannot honor.

## Account stack presentation (revised 2026-08-27)

The predecessor design's rightward cascade — and its explicit "no
account-count badge" decision — are superseded. Both were wrong for the same
reason: the cascade spent horizontal space, the scarce axis next to the
composer, and it did so without a ring between overlapping wheels, so two or
three accounts visually blended into one shape (`Tests/TenXAppTests/ReferenceImages/provider-account-stack-states.png`,
before this revision, showed exactly that). At three accounts the cascade's
width also forced `ProviderUsageDockLayout` to move the whole dock above the
composer at 1180px even though nothing about the composer itself had
changed.

`ProviderAccountStackView` now collapses to the active account's wheel at
rest — pixel-identical to a single-account provider — and fans the rest
upward on hover or keyboard focus, overlapping the wheel below by design
(the same avatar-stack pattern the old cascade attempted) but with a
canvas-colored ring around every wheel once expanded, so overlapping discs
stay legible instead of dissolving into each other. The group is always
exactly one wheel wide, at rest and expanded, which is what makes the
1180px forced-above-composer case go away: `ProviderUsageDockLayout` no
longer derives per-provider width from account count because there is
nothing left to derive — every account-routing provider now measures like a
single wheel.

Collapsing at rest reopens the question the predecessor design closed:
without the cascade, the per-account activity centers the design already
relies on ("each account center counts sessions generating through that
exact account") are invisible until the group is expanded. Rather than
either losing that at-a-glance signal or keeping the cascade to preserve it,
the collapsed wheel carries a small count badge (`+N`, the number of other
connected accounts) that takes the accent color whenever any of those
collapsed accounts has a nonzero generating count — reversing "there is no
account-count badge" from the predecessor design. The badge ignores the
compact grayscale rule on purpose, the same way each wheel's own activity
core already does: decorative usage rings desaturate while the open chat
generates, but activity signals do not, because they exist specifically to
stay visible at a glance. A single-account provider gets no badge and is
unaffected by any of this.

Hover or focus landing on any account — including the foreground, which is
the only thing visible to hover or focus at rest — now raises, colorizes,
and promotes that account to the top of the z-stack. This fixes a latent
bug in the geometry the cascade shared: `visualState` gated raising on
`!item.isForeground`, so the foreground account could never be promoted.
The rightward layout never surfaced this, because the foreground already
held the highest resting z-index; the upward layout would have, since
hovering the only visible wheel at rest is how the collapsed siblings get
discovered in the first place.

The inline account selector inside the expanded corner panel
(`ProviderUsageDockView.expandedAccountSelector`) reuses the same component
with `alwaysExpanded: true` rather than collapsing — the panel already has
room and the user opened it specifically to compare accounts, so hiding
them behind another hover would cost a step for no space saved.

## Testing

- **Hash parity.** Fixtures generated by OMP's own `credentialPinHash` over a
  matrix covering email-only, accountId-only, both, org scope, and project
  scope, asserted against the Swift implementation. Absent-field and
  no-account-key cases included.
- **Tier detection.** Each of the three tiers and the two degradation paths
  (incompatible contract version, extension load failure) selected from
  controlled inputs.
- **t1 restart path.** New session re-adopts onto the pinned account before the
  first prompt; idle restart preserves the conversation; generating session
  queues and restarts on idle; a failed restart leaves the session usable on its
  previous account.
- **Extension.** Bun tests in `OmpExtension/`, covering the command loop, event
  translation, removal ordering, and redaction, reusing the ported cases.
- **Command loop.** Proven in isolation against a real OMP process before
  dependent work begins.
- **Generator idempotence** with the new build phase.
- **Existing suites** continue to pass; the account UI references are unchanged
  by this document.

## Out of scope

- Contributing any of this upstream to `can1357/oh-my-pi`.
- Adding accounts. Login is already a stock RPC command and is unchanged.
- Changing any approved product decision from the routing design.
- Removal in t1.

## Consequences for the current branch

Work continues on `tannerpham/resume-codex-implementation-833cbd`. The branch
already carries the coordinator, the UI, and verification evidence for the RPC
approach. That evidence is not deleted; it is amended to record that the
transport it verified was replaced and why, so the record stays accurate about
what was verified and when.

# Multi-Account Provider Routing

**Status:** Approved for implementation planning

**Date:** 2026-08-26
**Platform:** macOS 15+, Swift 6.1, SwiftUI
**Builds on:** `2026-08-25-provider-setup-usage-design.md` and
`2026-08-25-provider-usage-wheels-design.md`
**Companion change:** OMP typed RPC and credential-management support

## Goal

Let 10x connect multiple OAuth accounts for one provider, show each account's
real limits in the provider usage dock, and route each 10x-managed session to a
specific account without moving credentials into the application.

The active account remains the full-size foreground usage wheel. Other accounts
cascade behind it toward the right as smaller, unfocused wheels. Selecting an
account opens the existing bounded corner panel for inspection. Switching is a
separate confirmed action with explicit scope: this session, all current
managed sessions, or all new sessions.

OMP remains the credential authority. It owns stored secrets, exact-account
pinning, retry classification, quota health, and sibling-account failover. 10x
owns presentation, the provider primary preference, scope coordination, and
the set of sessions it manages.

This design supersedes two boundaries in the earlier provider designs:

- account-level activity replaces provider-only activity when the new account
  RPC is available;
- account pinning, exact-account removal, and an OMP contract change move into
  scope for this feature.

## Approved product decisions

- One provider may have multiple connected OAuth accounts.
- The account used by the open chat is the foreground wheel for that provider.
  If the open chat is not using the provider, the configured primary is
  foregrounded.
- Other accounts cascade behind the foreground wheel toward the right. There
  is no account-count badge.
- Each account center counts 10x-managed sessions currently generating through
  that exact account. A nonzero center keeps the existing pulse behavior.
- Compact color continues to follow the open chat's turn state. All account
  wheels are grayscale while that chat generates and colored while it is idle.
- Hovering or keyboard-focusing a background account raises and colorizes that
  account even while the rest of the compact dock is grayscale.
- Expanded usage is always in semantic color.
- Clicking an account inspects it. It never changes routing by itself.
- The expanded panel provides `Use this account` and `Manage accounts`.
- Every manual switch asks for one of three scopes: this session, all current
  sessions, or all new sessions.
- All new sessions is the same preference as the provider primary account.
- Idle managed sessions switch immediately. Generating sessions queue the
  latest requested switch until their current turn finishes.
- OMP exhausts its existing retry policy before automatically failing one
  affected session over to another eligible account.
- Automatic failover does not change the provider primary or unrelated
  sessions.
- A session that failed over stays on its backup after the primary recovers.
  New sessions try the primary again when OMP considers it eligible.
- Accounts are added and removed in Providers > Connections. The expanded
  usage panel links there.
- Removing an account waits for active managed turns, moves affected sessions,
  and reassigns the primary when necessary.
- The existing small corner panel remains bounded. Expansion does not become a
  full-size popup and does not move, resize, or indent the composer.

## Current foundation

The design extends working behavior rather than creating a second provider or
usage system.

### 10x

- `ProviderManagementViewModel` already owns provider discovery, login, usage,
  refresh state, and the Connections and Usage workspace sections.
- `ProviderManagementService` already owns the dedicated no-session OMP RPC
  client used for provider login.
- `OmpUsageService` and `ProviderUsagePresentation` already decode and present
  multiple account reports from `omp usage --json`.
- `ProviderUsageDockView` already owns collapsed and expanded dock interaction,
  a 360-point bounded panel, focus restoration, dismissal, and Reduce Motion.
- `ProviderUsageWheelView` already renders all duration-ordered limits, the
  generating-session activity core, grayscale, and semantic color.
- `SessionActivityRegistry` already observes every retained 10x-managed session
  and aggregates provider-level generating counts.

### OMP

- `AuthStorage.listOAuthAccounts(provider, sessionId)` already returns stored
  OAuth accounts in stable storage order with durable credential ids and safe
  identity fields.
- `AuthStorage.pinSessionOAuthAccount(provider, sessionId, credentialId)`
  already pins an exact OAuth row while allowing normal retry and quota
  handling to route around an unavailable account.
- `AuthStorage.removeCredential(provider, credentialId)` already removes one
  exact stored credential.
- `credential_pin` session entries already preserve the account that served a
  session across process restarts without writing raw identity into the session
  file.
- `/session pin` already proves exact-account selection through OMP's public
  session layer.
- Existing auth retry and usage-limit handling already rotates to an eligible
  sibling credential when an account-local failure requires it.

The missing boundary is a safe typed RPC surface for these capabilities and a
10x coordinator that applies them across managed sessions.

## Experience design

### Compact account stacks

```text
Provider group

      tertiary account
             ○
       backup account
           ○
    foreground account
           ◉
          OAI
```

Each provider remains one horizontal dock item with one three-letter provider
label beneath the complete account stack. The foreground account uses the
existing compact wheel diameter for the current responsive mode. Additional
accounts use the same wheel component with a smaller visual scale, overlap the
foreground account, and offset toward the right in stable Connections order.

The stack is drawn back to front so the foreground account owns the primary hit
target and accessibility position. Hovering or keyboard-focusing a background
account raises it above its siblings without changing which account is active.
Its rings temporarily use semantic color so a background account remains
legible during the global generating-time grayscale state.

Foreground selection is contextual:

1. for the provider used by the open chat, show that session's active account;
2. for every other provider, show its configured primary;
3. when either reference is missing, show the first eligible connected account
   in stable Connections order.

Each wheel's center receives the exact count for `(providerId, accountRef)`.
Only sessions whose runtime state is generating contribute. If OMP fails a turn
over during generation, the pulse and count move to the newly active account.

The existing responsive placement remains authoritative. The fit calculation
uses each rendered account stack's width instead of assuming one circle per
provider. When the trailing gutter cannot hold the complete dock, every stack
moves above the composer and uses the constrained wheel geometry. The composer
frame and bottom inset are not inputs that the dock may change.

### Expanded account usage

Clicking any foreground or background wheel grows the existing bounded corner
panel up and left. The clicked account is selected initially. The panel stays
360 points wide and bounded to the existing maximum height; account and limit
content scrolls internally.

The panel shows:

- provider and safe account identity;
- the selected account wheel in semantic color;
- the selected account's complete bar-based usage breakdown;
- exact account-level generating count;
- account selectors for the provider's other connected accounts;
- `Use this account`;
- `Manage accounts`;
- the existing close and dismissal behavior.

Selecting another account inside the expanded panel changes only the inspected
breakdown. Expanded wheels and bars always use semantic color, including while
the open chat is generating.

`Manage accounts` opens Providers > Connections focused on the selected
provider. Changing the open chat closes the account panel so a later action
cannot target a different session than the one the panel described.

### Switch confirmation

`Use this account` replaces the panel body with the existing small corner-modal
construction. It does not open a full-window sheet.

```text
Use [account]?
Choose where this account should be used.

( ) This session
    Switch the open session. If it is generating, switch after the current turn.

( ) All current sessions
    Switch every 10x-managed session using this provider. Generating sessions
    finish their current turn first.

( ) All new sessions
    Set this as the provider's primary account. Existing sessions stay unchanged.

Cancel                                      Switch account
```

Confirmation appears for every explicit switch. `All current sessions` does
not change the primary. `All new sessions` changes only the primary and does
not repin an existing managed session.

An unavailable account cannot be selected. The expanded panel shows `In use
for this session` as status text when applicable, while `Use this account`
remains available whenever another scope would still change routing. The
confirmation disables only the individual scopes already satisfied by the
selected account. The action is disabled entirely only when this session, all
current sessions, and the provider primary already use the account.

### Connections account management

Providers > Connections is the source of truth for adding and removing
accounts.

```text
OpenAI
  account@example.com      Primary · In use by 3 sessions
  work@example.com                   In use by 1 session

  Add account
```

`Add account` runs the existing OMP login flow and then refreshes account
metadata and usage. A successful login appends an account rather than replacing
another row.

Rows use the safest available provider identity. OMP may supply email, account
id, project, organization, workspace, or enterprise host metadata. 10x shows
only the fields needed to distinguish accounts. Duplicate visible identities
remain separate rows because their opaque account references differ.

Removing an account opens a confirmation that names affected managed sessions.
Idle sessions using it move first. Generating sessions finish their current
turn and then move. Only after no 10x-managed turn is using the account does the
no-session provider RPC remove that exact stored credential.

Affected sessions move to the provider primary when it remains eligible. If
the removed account is primary, the first eligible remaining account in stable
Connections order becomes primary, then affected sessions move to it. Removing
the last account uses stronger copy explaining that the provider will be
disconnected and affected sessions cannot continue through it.

This safety guarantee covers sessions managed by the current 10x process. 10x
cannot coordinate independent OMP terminal processes or other applications.

## Routing semantics

### Manual scopes

The main-actor coordinator expands one confirmed choice into per-session work:

```text
confirmed account choice
        |
        +-- this session --------> one matching SessionController
        |
        +-- all current ---------> every managed controller using provider
        |
        +-- all new -------------> persisted provider primary only

per-session application
        |
        +-- idle ----------------> set_session_provider_account now
        |
        +-- generating ----------> keep latest pending accountRef
                                      |
                                      +-- runtime becomes idle -> apply once
```

"Current sessions" means retained top-level sessions managed by this 10x
process. It does not include archived sessions, closed session files, CLI
sessions, or sessions owned by another application.

A new managed session receives the provider primary before its first turn. A
resumed session with a durable `credential_pin` keeps that session account
instead of being overwritten by a later primary change. Changing the primary
therefore affects sessions created afterward, not existing sessions.

### Automatic failover

OMP owns automatic retry and failover classification. 10x never parses provider
error text and never reimplements a retry budget.

```text
session request
    |
    v
normal OMP retries on preferred account
    |
    +-- success ----------------------> continue
    |
    +-- account-local auth/quota failure
            |
            v
      choose eligible sibling account
            |
            +-- found -> continue turn and emit account change
            |
            +-- none  -> stop rotation and return provider error
```

Only credential, quota, or account-availability failures that OMP already
classifies for credential rotation may switch accounts. Request validation,
model availability, tool, and ordinary server errors do not cause 10x account
routing changes.

Failover changes only the affected session. It does not change the provider
primary, repin other sessions, or open manual scope confirmation. The selected
backup becomes the affected session's durable pin after the turn. When the
primary's health block expires, newly created sessions try it again. Existing
failed-over sessions remain on their backups.

If every account is exhausted, OMP terminates credential rotation and reports
one provider failure. It must not cycle indefinitely.

### Conflict precedence

The latest valid explicit account choice wins for each managed session.

- A later queued choice replaces an earlier queued choice for that session.
- Automatic failover may change the credential used by the active turn, but a
  valid queued manual choice applies after the turn finishes.
- An account pending removal rejects new manual switches.
- If a queued target becomes unavailable or disappears, the session keeps its
  current valid account, 10x refreshes account state, and the switch reports a
  failure.
- Removal waits for active turns and account-switch queues involving its target
  to settle before deleting the credential.
- Pending switches are runtime state. Closing 10x discards them because their
  managed turn is no longer active.

## Architecture and ownership

```text
ProviderUsageDockView                 ProvidersView / Connections
  inspect + request switch              login + remove
             \                              /
              v                            v
              ProviderAccountCoordinator (@MainActor)
              + provider primary preferences
              + managed-session account map
              + pending post-turn switches
              + per-account generating counts
              + scope and removal coordination
                    |                 |
                    |                 +--> ProviderManagementViewModel
                    |                        + account metadata
                    |                        + batched account usage
                    |
                    +--> retained SessionControllers
                              |
                              v
                         typed OMP RPC
                         + list accounts
                         + set session account
                         + remove account
                         + account state/events
                              |
                              v
                         OMP AuthStorage
                         + credentials and identity
                         + durable pins
                         + retry and quota health
                         + sibling failover
```

### OMP responsibilities

OMP remains the only process that can read or mutate provider credentials. It:

- maps an opaque RPC account reference to one durable stored credential id;
- returns only safe identity and availability metadata;
- resolves batched account usage using credentials that remain inside OMP;
- validates that an account belongs to the requested provider;
- pins one session to one account and persists the pin;
- emits authoritative active-account changes;
- removes one exact credential;
- owns retry classification, health blocks, and automatic failover.

### 10x responsibilities

A new `@MainActor` `ProviderAccountCoordinator` owns application policy. It:

- persists `providerId -> accountRef` primary preferences using the existing
  lightweight application-preference mechanism;
- observes safe account summaries and usage from
  `ProviderManagementViewModel`;
- tracks each retained `SessionController`'s provider, active account, and
  generating state;
- expands confirmed scopes into per-controller pin requests;
- queues only the latest post-turn switch for a generating session;
- coordinates safe removal across the sessions 10x manages;
- publishes `(providerId, accountRef) -> generating count` for the dock.

`ProviderManagementViewModel` continues to own provider login, Connections,
and usage refresh. It gains safe account collections and account-level actions,
but does not become the session router.

`SessionActivityRegistry` either gains account references or is folded into the
coordinator if retaining both objects would duplicate the same per-session
state. Planning must choose the smaller implementation after inspecting the
final usage-wheel branch. There must be only one consumer of each
`RpcClient.events` stream.

`ProviderUsageDockView` remains presentation and interaction only. It receives
account presentation values, counts, callbacks, and the foreground generating
state. It does not call AuthStorage-shaped commands or manage session queues.

## Typed RPC contract

The account feature extends the negotiated OMP RPC with typed commands and
events. New commands use protocol-v2 envelopes and return an unsupported-command
error on older OMP versions. 10x feature-gates account controls when the bundled
or installed OMP does not expose them.

### Account metadata

`list_provider_accounts` accepts `providerId` and, on a session client, uses the
current session to mark the active account. The no-session provider client may
omit active state.

```text
ProviderAccountSummary
  providerId: String
  accountRef: String          opaque durable row reference
  displayLabel: String
  detailLabel: String?
  connectionOrder: Int
  availability: available | limited | unavailable
  isActiveForSession: Bool?
```

`accountRef` is stable across OAuth token refresh and storage reordering. It is
never shown to the user and must not be treated as an array position. OMP may
back it with the existing durable `credentialId`, but that representation stays
an OMP implementation detail.

### Batched account usage

`get_provider_account_usage` accepts `providerId` and returns all connected
accounts in one response. Stable account metadata stays separate because
Connections refreshes should not force quota network requests.

```text
ProviderAccountUsage
  providerId: String
  accountRef: String
  refreshedAt: Date
  usageWindows: [ProviderAccountUsageWindow]

ProviderAccountUsageWindow
  id: String
  label: String
  duration: normalized duration metadata when known
  sourceIndex: Int
  remainingFraction: Double?
  resetsAt: Date?
  status: String?
```

OMP reuses the provider usage adapters behind `omp usage --json`; it does not
create a second quota interpretation. Unknown fields remain ignorable. 10x
continues to clamp rendering values and order known windows by duration, with
shorter limits inside and longer limits outside.

This RPC response becomes authoritative for usage joined to `accountRef`.
`OmpUsageService` remains the provider-level compatibility fallback for older
OMP versions until 10x can require the account-capable contract; 10x never joins
an opaque account reference to a CLI report by guessing from visible identity.

### Session pinning

`set_session_provider_account` is sent through the target session's own RPC
client with `providerId` and `accountRef`. OMP validates the reference, pins the
stored OAuth account, and records durable `credential_pin` state so a restart
before another turn does not lose the explicit choice.

The response includes the authoritative selected summary. Pinning may still
route around that account later when OMP's normal failure policy determines it
is unavailable.

### Exact-account removal

`remove_provider_account` is sent through the no-session provider client with
`providerId` and `accountRef`. OMP validates provider ownership and delegates to
its exact credential-row removal. It returns whether the row was removed and a
refreshed safe account list. It never accepts or returns credential material.

10x calls this command only after its managed-session coordination completes.
OMP remains responsible for rejecting a stale, missing, or provider-mismatched
reference.

### Active-account state and events

`get_state` gains an `activeProviderAccounts` map so reconnect and session
resume can restore account attribution without waiting for another change.

OMP emits `provider_account_changed` when the effective session account changes:

```text
providerId: String
accountRef: String
reason: manual | automaticFailover
sequence: Int
```

The per-session monotonic sequence prevents a delayed response or event from
overwriting newer routing state. A manual pin response and event may describe
the same change; 10x deduplicates them by sequence and account reference.

### Login

The existing `login(providerId)` command remains the only add-account flow. A
successful login refreshes `list_provider_accounts` and batched usage. OMP's
existing credential deduplication remains authoritative.

## Loading, empty, compatibility, and errors

- One connected account preserves the current single-wheel presentation.
- No connected account removes that provider's stack and shows it as
  disconnected in Connections.
- Account metadata can load before account usage. Neutral ring tracks preserve
  the account's place while quota data loads.
- An account usage failure keeps the account visible and shows `Usage
  unavailable` in expanded usage.
- A stale or externally removed account reports `Account is no longer
  available.` and triggers a metadata refresh.
- If every account is unavailable, the stack remains inspectable but unavailable
  accounts cannot be selected for routing.
- Identical display labels remain separate. Safe secondary identity appears in
  Connections and expanded usage when available.
- If the stored primary disappears, 10x chooses the first eligible account in
  stable Connections order and persists the replacement.
- If OMP lacks the account commands, 10x retains the existing provider-level
  usage wheel and hides account routing and removal controls. It does not render
  a control that cannot work.
- Internal errors use the repository's traceable error format. User-facing copy
  never includes credential ids, account references, tokens, provider payloads,
  filesystem paths, or protocol errors.

## Security and privacy

- OAuth access tokens, refresh tokens, API keys, and serialized credentials
  never cross the account RPC boundary.
- Preferences store only `providerId -> accountRef` primary mappings.
- `accountRef` is opaque UI state, not authentication material, and is still
  excluded from visible copy and routine logs.
- OMP validates provider ownership for pin and removal requests.
- Account identity is limited to provider-supplied fields already available to
  OMP. Compact wheels do not expose identity text.
- Session files retain OMP's hashed `credential_pin` representation rather than
  raw email or account ids.
- 10x protects only its own managed sessions during removal. The confirmation
  copy must not claim coordination with external OMP processes.

## Accessibility and motion

- The provider abbreviation remains visual shorthand only. Accessibility names
  the full provider and selected account identity.
- Every account wheel is an independently reachable button, including wheels
  partially overlapped behind the foreground account.
- Accessibility values include account identity, exact active-session count,
  every remaining percentage, and reset information.
- Keyboard focus raises and colorizes a background account exactly like hover.
- Expanded focus order is account selector, usage breakdown, switch action,
  manage action, then close.
- Scope options use radio-group semantics. The confirmation title names the
  account and the action button states `Switch account`.
- Grayscale never carries the only generating signal. The numeric activity core
  remains visible.
- Reduce Motion removes pulses, stack elevation animation, account reordering,
  and the panel morph. It preserves numeric counts, a static active outline,
  color state, and focus movement.
- Focus returns to the account wheel that opened the panel after dismissal.

## Testing and verification

### OMP automated coverage

- RPC type and envelope tests for account list, batched usage, pin, removal,
  state, and account-change events.
- Redaction tests proving no credential material enters responses or events.
- Account reference tests for token refresh, storage reorder, duplicate labels,
  stale references, and provider mismatch.
- Pin tests proving exact selection, immediate `credential_pin` persistence,
  resume restoration, and normal failover around an unavailable pin.
- Removal tests for one exact credential, the last credential, remote auth
  storage, stale references, and cleanup of account health state.
- Failover tests proving retry exhaustion precedes rotation, only eligible
  failure classes rotate, one session changes, no-sibling failure terminates,
  and account-change reasons are correct.
- Batched usage tests covering partial account failures without dropping healthy
  sibling usage.

### 10x automated coverage

- OmpKit command encoding and response/event decoding for every new contract.
- Coordinator tests for all three scopes, immediate idle application, queued
  generating application, latest-choice replacement, and partial failure.
- Primary tests for persistence, missing-reference fallback, new-session
  application, resumed-session pin preservation, and failover non-mutation.
- Conflict tests for automatic failover plus queued manual choice, a target
  becoming unavailable, removal plus pending switches, and stale event sequence.
- Activity tests for multiple sessions on one account, different accounts for
  one provider, provider changes, failover during a turn, exits, and cleanup.
- Presentation tests for foreground selection, stable rightward order, account
  usage grouping, duration ring order, and identical visible labels.
- Layout tests proving account-stack width participates in side-versus-above
  placement and the composer geometry remains unchanged.
- Snapshot tests for one account, multiple accounts, hovered background account,
  generating grayscale, expanded semantic color, switch confirmation,
  Connections rows, safe removal, usage unavailable, and every-account
  unavailable.
- Accessibility tests for account labels, exact counts, keyboard order, radio
  semantics, focus restoration, and Reduce Motion.
- Compatibility tests proving an older OMP preserves the existing provider-only
  wheel and hides unsupported actions.

### Built application acceptance

Verification uses a built application, not a dev-only surface.

1. One account preserves the current single-wheel appearance.
2. Adding a second account in Connections creates the rightward background
   cascade without replacing the first account.
3. Hovering and keyboard-focusing a background account raises and colorizes it,
   including while the open chat generates.
4. Clicking either account opens the existing small corner panel, keeps the
   composer fixed, and focuses that account's real limits.
5. This session switches immediately while idle and queues while generating.
6. All current sessions switches every idle managed session and applies once to
   each generating session after its current turn.
7. All new sessions changes the primary without moving an existing session.
8. Concurrent managed sessions using different accounts produce exact center
   counts and pulses.
9. Automatic failover continues the affected turn, moves its count and
   foreground wheel, and leaves the primary unchanged.
10. A recovered primary serves new sessions while previously failed-over
    sessions remain on backup accounts.
11. Removing an in-use account waits for managed turns, reassigns affected
    sessions, and chooses a new primary when required.
12. Wide, compact-trigger, and minimum supported window widths show no clipping,
    horizontal scrollbar, collision, or composer movement.
13. Usage failure, stale reference, duplicate-label, and all-exhausted states
    remain inspectable and truthful.
14. VoiceOver, full keyboard navigation, and Reduce Motion preserve every state
    and action.
15. RPC inspection confirms that no token or secret appears in payloads,
    preferences, UI state, or logs.

Required evidence includes automated test output and screenshots from the built
app at wide, compact-trigger, and minimum supported widths. Screenshots cover
idle color, generating grayscale, hovered background color, expanded usage,
scope confirmation, Connections, and safe removal.

## Scope boundaries

- OAuth accounts only. Multiple API-key identities require a separate provider
  contract and are not inferred from this design.
- No credential editor or second credential store in 10x.
- No retries, provider-error classification, or account-health ranking in 10x.
- No migration of independent CLI sessions or sessions owned by another
  application.
- No automatic migration back to a recovered primary for existing sessions.
- No account-count badge, provider logo package, usage history, prediction, or
  rate-of-consumption chart.
- No composer geometry change and no full-window usage popup.

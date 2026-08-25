# Provider Setup and Usage

**Status:** Approved for implementation planning
**Date:** 2026-08-25
**Platform:** macOS 15+, Swift 6.1, SwiftUI
**OMP contract:** 18.0.4

## Goal

10x must let a user connect at least one OMP provider before entering the
workspace, manage those connections later, and inspect real provider usage
without opening OMP's terminal UI.

The first release provides native connection, reconnection, account status,
and usage inspection. It does not add logout, credential deletion, account
pinning, reset-credit redemption, or provider configuration that OMP does not
already expose through its current contracts.

## Approved product decisions

- Provider setup is required after OMP discovery when no available provider is
  authenticated.
- The first screen shows a curated starter set: ChatGPT, Anthropic, Cursor, and
  Google Cloud Code Assist. The complete dynamic OMP catalog remains one click
  away through search.
- Continue becomes available after one provider connects. The user may connect
  more providers before continuing.
- The first release supports connect, reconnect, and inspect. It does not
  invent unsupported logout or session-pinning controls.
- The expanded rail keeps a compact remaining-capacity summary. Selecting the
  summary opens a full provider workspace with Connections and Usage views.
- Multiple accounts stay distinct wherever OMP supplies account identity.
- The implementation uses OMP's existing login RPC and `omp usage --json`.
  OMP itself does not change in this work.

## User flow

```text
Launch
  |
  v
Locate and inspect OMP
  |
  v
Discover provider connection state
  |------------------------------|
  | authenticated provider      | no authenticated provider
  v                              v
New session               Required provider setup
                                 |
                                 v
                     Connect through native OAuth flow
                                 |
                                 v
                   Refresh connection and usage state
                                 |
                                 v
                  Continue after one provider connects
                                 |
                                 v
                            New session
```

After onboarding, Settings links to the Providers workspace. Selecting the
expanded rail usage summary opens the Usage view directly. Provider management
does not require a selected project or an active agent session.

## Architecture

One `@MainActor` provider feature model coordinates two adapters while session
runtime processes remain unchanged:

```text
SwiftUI surfaces
├── ProviderSetupView
├── ProvidersView
│   ├── Connections
│   └── Usage
└── ProviderUsageLedgerView
        |
        v
ProviderManagementViewModel
├── ProviderManagementService
│   └── no-session RpcClient
│       ├── get_login_providers
│       └── login + extension_ui_request events
└── OmpUsageService
    └── omp usage --json
```

### Application state and routing

`AppModel` owns the provider feature model beside the existing settings and
session models. Installing OMP constructs the provider services using the
resolved executable URL, loads connection state, and chooses the route:

- `.providerSetup` when discovery succeeds and no available provider reports
  `authenticated == true`;
- `.newSession` when at least one provider is authenticated;
- the existing `.setup` route when OMP cannot be located.

The shell gains a providers route with an initial destination of Connections or
Usage. Settings exposes a borderless Providers action. The rail usage summary
opens the same route with Usage selected. Completing provider setup returns to
New Session.

Provider discovery failure does not masquerade as an empty provider list. The
required setup surface remains visible with a retry action until discovery
succeeds.

### Provider RPC adapter

`RpcCommand` gains typed factories for `get_login_providers` and `login`. A
dedicated provider service owns one `RpcClient` configured with `noSession =
true`. It is separate from `SessionProcessManager` because provider setup must
work before a project or session exists.

The service is the single consumer of that client's event stream. It filters
login-related `extension_ui_request` frames and reuses the existing
`ExtensionUIRouter`, `ExtensionUIState`, `ExtensionUIResponse`, and
`ExtensionInputSheet` rather than creating a second OAuth event parser.

The supported login events are:

- `open_url`: validate the HTTP or HTTPS URL through `ExtensionUIRouter`, open
  it with `NSWorkspace`, and keep the provider row in a waiting state;
- `input`: present the existing native input sheet for a pasted code or redirect
  URL and return the value through `extension_ui_response`;
- `notify`: reduce honest OMP progress into the active provider row;
- `cancel` or an RPC error: clear transient login state without changing the
  last confirmed connection state.

Only one provider login runs at a time. Login uses OMP's ten-minute RPC timeout.
OMP 18.0.4 has no login-cancellation command, so Cancel shuts down this
dedicated no-session client and recreates it before the next discovery or login.
That terminates the pending OAuth flow without touching any session process.
Closing the provider model also shuts down its no-session process. Session RPC
event consumption remains untouched.

### Usage command adapter

`OmpUsageService` runs the resolved executable with `usage --json`. The runner
captures stdout, stderr, and termination status without invoking a shell. JSON
decodes into narrow typed structures for the fields 10x presents:

- generation and fetch timestamps;
- provider id;
- account identity metadata;
- usage limit id, label, scope, window, amount, status, and notes;
- accounts without usage reports;
- disabled credentials.

Unknown JSON fields are ignored so newer OMP releases remain compatible. The
large provider-specific `raw` payload is not requested or modeled. Capacity
statistics and reset-credit redemption are outside this release.

## Presentation model

The feature model exposes stable provider, account, and limit identities for
SwiftUI. It joins provider discovery with usage reports without treating either
source as a substitute for the other:

- discovery is authoritative for provider availability and authenticated
  status;
- usage reports are authoritative for account identity, limits, reset windows,
  and provider notes;
- disabled credentials are recovery records, not connected accounts;
- accounts without usage remain connected and show “Usage data unavailable.”

A progress bar is rendered only when a remaining fraction can be derived. The
precedence is explicit `remainingFraction`, the inverse of `usedFraction`, the
inverse of `used / limit`, or the inverse of percent-unit `used`. Values clamp
to 0...1 for rendering.

Percentages in 10x mean remaining capacity:

- above 20% uses cyan;
- 1...20% uses yellow;
- 0% uses signal red.

Limits with a used amount but no maximum show that factual amount in the detail
view and do not render a percentage bar. The rail includes only limits with a
computable remaining fraction. Its concise reset text uses a relative window;
the detail view shows the provider label and exact reset date when available.

The rail includes account identity only when a provider has multiple reports
or the identity is needed to distinguish rows. It remains scrollable and keeps
the existing height cap.

## Screens and interaction

### Required provider setup

The setup canvas follows the existing OMP setup composition: wordmark, large
Chillax title, sparse supporting text, and borderless actions.

The curated list shows provider name, a short factual account description, and
Connect. “Browse all providers” replaces the curated list in place with search
and the full available catalog; it does not open a modal or create another
route. Search matches provider name and id.

Continue is disabled until discovery confirms at least one authenticated
provider. A successful connection updates the row to Connected and enables
Continue. The user stays on the screen so additional providers can be added.

During login, the active row owns its progress and cancel state. OMP's browser
URL opens automatically. When OMP requests pasted input, the existing native
input sheet appears. Success, cancellation, timeout, and failure all return to
a stable provider list.

### Providers workspace

The Providers workspace uses the same maximum width, typography, whitespace,
and cyan section rules as Settings. A two-item borderless switch selects
Connections or Usage.

Connections shows authenticated providers first, then the curated starters,
then the searchable full catalog. A disabled credential appears with
Reconnect. Providers not currently available remain discoverable but their
action is disabled with a factual availability label.

Usage groups data by provider and then account. Each account owns its limits,
reset text, provider notes, and honest empty state. A refresh action and last
successful update time appear in the header. Raw account identity is shown in
this management surface because it is needed to distinguish accounts.

### Expanded rail usage

The existing `ProviderUsageLedgerView` becomes interactive and receives the
normalized usage presentation from the provider model. It remains hidden while
the rail is collapsed. Selecting it opens Providers with Usage selected.

The rail shows provider, optional account identity, allowance label, remaining
percentage, concise reset text, and a three-point bar. “Left” is not repeated.
It does not show connection errors, notes, amounts without limits, or recovery
actions; those belong in the detail view.

## Refresh behavior

Connection state and usage refresh:

1. after OMP installation;
2. after a successful login;
3. when the user selects Refresh;
4. when the app returns to the foreground and the last successful refresh is
   at least five minutes old.

Only one refresh runs at a time. A provider-list refresh and a usage refresh
may complete independently. Provider discovery controls onboarding eligibility;
usage failure never revokes a confirmed connection.

## Loading, empty, and error states

- Initial provider discovery shows row-shaped loading placeholders on the setup
  canvas.
- Discovery failure shows “Providers couldn’t be loaded.” and Try Again.
  Continue remains disabled.
- Login cancellation returns the row to its prior state.
- Login failure names the provider and offers Retry without exposing protocol
  errors, stack traces, filesystem paths, or credential values.
- Initial usage failure shows “Usage couldn’t be loaded.” with Try Again.
- Later usage failure preserves the last successful snapshot and shows
  “Usage couldn’t be refreshed. Showing data from 9:42 AM.” with the actual
  last-update time formatted for the current locale.
- Disabled credentials show “Reconnect to update usage.”
- Authenticated accounts without a usage endpoint show “Usage data
  unavailable.”
- No connected provider ever appears successful based only on stale usage data.

Internal errors retain the repository format
`[Module:Function] Description — {context}`. User surfaces map them to the
plain copy above.

## Accessibility

- Every provider action names the provider and action, such as “Connect
  Anthropic” or “Reconnect ChatGPT.”
- Progress changes are announced without repeatedly moving keyboard focus.
- Usage bars expose provider, account when needed, allowance label, percentage
  remaining, and reset time as one accessibility element.
- Color never carries status alone. Connected, low, exhausted, unavailable,
  and reconnect states all have text.
- Provider search, tabs, Continue, Refresh, and OAuth input are fully keyboard
  accessible.
- Reduced motion disables nonessential row and route transitions.

## Verification

### Automated

- OmpKit command tests cover the exact `get_login_providers` and `login`
  envelopes.
- Provider service tests cover discovery, one-login-at-a-time behavior,
  `open_url`, pasted input, cancellation, timeout, success, and failure.
- Usage decoder tests use fixtures for multiple accounts, disabled credentials,
  accounts without usage, unknown fields, missing maximums, reset windows, and
  fractional clamping.
- Presentation tests cover remaining-percentage derivation, tone thresholds,
  amount-only limits, account labels, and rail filtering.
- AppModel tests cover OMP missing, discovery failure, required provider setup,
  authenticated launch, setup completion, Settings entry, and rail entry.
- Snapshot tests cover provider loading, curated setup, full catalog, login in
  progress, connected setup, Connections, Usage, recovery, and expanded rail at
  the minimum 760x560 size and default 1180x760 size.

### Built application

- Build the Release configuration before manual verification.
- Confirm real provider discovery and usage rendering against the installed OMP
  without changing authentication state.
- Inspect setup, provider workspace, expanded rail, loading, empty, stale, and
  recovery states for clipping and horizontal scrolling at minimum and default
  window sizes.
- Verify keyboard navigation, VoiceOver labels, and reduced-motion behavior.
- OAuth completion remains a user test because it changes external account
  authentication.

## Explicitly excluded

- Logout or credential deletion.
- Choosing or pinning a specific OAuth account for an agent session.
- Reset-credit redemption and usage-history charts.
- Editing API keys directly in 10x or adding a second credential store.
- OMP protocol changes or a new OMP usage RPC.
- Provider logos or a new asset package. The first release uses typography and
  the existing 10x visual system.

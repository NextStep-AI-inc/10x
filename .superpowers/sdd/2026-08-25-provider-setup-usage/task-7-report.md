# Task 7: Connections and Usage Workspace

Status: DONE

## RED

Added navigation and 1180 × 760 workspace snapshot coverage before the
implementation, then regenerated the project and ran the focused command.
It failed as expected because `AppModel.openProviders`, `ProvidersView`, and
the `SettingsView` providers callback did not exist.

## GREEN

Implemented the provider workspace route, Settings entry, Connections catalog,
connection state row, Usage detail, recovery actions, and snapshot fixtures.

Recorded and visually inspected at 1180 × 760 points:

- `provider-connections.png`
- `provider-usage-detail.png`
- `provider-usage-stale.png`

The fixtures cover connected Cursor limits at 50% and 0%, an amount-only
request count, an Anthropic reconnect action, GitHub Copilot without usage,
and preserved stale data with a fixed last-update time.

## Verified

```sh
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' test
```

Result: 128 tests passed.

```sh
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' build
```

Result: Release build succeeded.

Visual review found no clipping or collisions in the three workspace
references. Connections keeps authenticated providers first, exposes
Connect/Reconnect/Cancel labels, and retains full-catalog search. Usage only
draws percentage bars for computable limits; it renders amount-only usage,
one note per account, unavailable account status, reconnect recovery, initial
failure, and preserved stale data. User-facing copy is plain and contains no
em dashes. The new provider views do not display credential causes, raw errors,
stderr, paths, protocol fields, or secrets.

## Not verified

The live OAuth flow was not exercised because it would alter external provider
authentication. The Task 8 rail Usage route is intentionally untouched.

## For you to test

- Open Settings, select Providers, and switch between Connections and Usage.
- Exercise a real Connect or Reconnect flow when changing authentication is
  acceptable.

## Files

- Added `ProvidersView`, `ProviderConnectionsView`, `ProviderConnectionRowView`,
  and `ProviderUsageDetailView`.
- Wired `AppModel`, `AppShellView`, Settings, navigation tests, workspace
  snapshots, reference images, and generated Xcode project files.

## Concerns

The generated scheme expands `RECORD_SNAPSHOTS` as an Xcode build setting,
which does not receive the shell environment variable in this workspace. The
three references were recorded through a temporary generated-scheme value and
then the project was regenerated; the committed scheme retains its generated
setting expression.

## Fix Round 1

### RED

Added a provider-model regression that sends a notification containing a fake
token, path, and protocol error while Cursor is connecting. Added grouping
coverage for a provider with reported usage, an unavailable account, and a
disabled credential. The first run failed because `ProviderUsageDetailGroup`
did not exist; the Usage snapshot also mismatched after the regression fixture
was expanded.

### GREEN

- Notification payload text is ignored at the feature-model boundary. The
  model publishes only fixed copy and, when known, the active provider ID.
- Connections associates messages by provider ID, not a substring match.
- Usage derives one stable group per provider, merging reported accounts,
  unavailable accounts, and credential recovery into one section.
- The workspace gives the detail scroll view an explicit remaining canvas,
  keeping its shared header and switch outside the scrolling detail.

Recorded and visually inspected the corrected `provider-usage-detail.png` at
1180 × 760. It shows the full Providers header, Cursor limits and amount-only
usage, GitHub Copilot's unavailable state, and Anthropic reconnect state with
no collisions or clipped account rows.

### Verified

```sh
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' test
```

Result: 130 tests passed.

```sh
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' build
```

Result: Release build succeeded.

### Concerns

No new concerns. The ledgered route/test minors remain intentionally untouched.

# First-Run Onboarding

**Status:** Approved for implementation planning
**Date:** 2026-08-26
**Platform:** macOS 15+, Swift 6.1, SwiftUI
**OMP contract:** 18.0.4 (no OMP change required)
**Builds on:** `2026-08-25-provider-setup-usage-design.md` and
`2026-08-25-startup-splash-preload-design.md`

> **Update, 2026-08-27:** The home-directory Git scan described below (Scan,
> the depth-measurement table, the Spotlight note, the consent-prompt
> rationale, and the related approved-decision and copy-table rows) was
> removed after live testing. Crawling the user's home directory to suggest
> projects was judged wrong on its own terms, independent of the consent-list
> mitigations this design built for it. The project step now suggests only
> folders 10x already knows about, the working directories of existing OMP
> sessions, via `ProjectSessionGrouper.choosableProjectURLs(from:including:)`
> (the same derivation the composer's project flyout already used). No disk
> crawl of any kind remains. The sections below are kept for the record of
> what was tried and why it did not ship; they no longer describe current
> behavior.

## Goal

Turn the two bare full-screen gates a new user hits today into one onboarding
flow with three requirements: OMP installed, one provider connected, one
project folder chosen.

Two of those gates exist. The third does not: nothing today asks for a project
folder, so a user with no prior sessions reaches the workspace with
`selectedProjectURL` still `nil`. This design adds that step, originally with
suggestions drawn from a scan for Git repositories (removed 2026-08-27, see
the update note above; suggestions now come from known session project
directories), lets the app install OMP rather than only locate it, and
replaces eight scattered routing decisions with one resolver.

## Approved product decisions

- Onboarding covers three requirements in a fixed order: install OMP, connect a
  provider, choose a project.
- A step is shown only when its requirement is unmet. A returning user sees no
  onboarding at all. A user who already has OMP sees two steps, not three.
- The step counter counts unmet steps at entry, so a satisfied requirement is
  never displayed as a pre-checked item.
- The flow is a full-screen route inside the workspace window, not a modal. The
  workspace cannot render behind a modal because `processManager`,
  `providerModel`, and `composerControls` are all `nil` until OMP is located.
- 10x runs the documented OMP install script itself. The command is shown
  verbatim before it runs, its output is streamed on screen, and choosing the
  executable manually remains available.
- ~~The project step scans for Git repositories and offers them as
  suggestions.~~ **Superseded 2026-08-27:** no scan. Suggestions come from
  known session project directories instead; see the update note above.
  Choosing a folder manually remains available and is the only control shown
  when there is nothing to suggest.
- ~~The scan never touches `~/Desktop`, `~/Documents`, or `~/Downloads`, so
  onboarding raises no macOS consent prompt the user did not ask for.~~
  **Superseded 2026-08-27:** moot, since nothing scans the disk anymore.
- Onboarding requires one project folder. Adding more during the step is
  allowed, subject to the existing two-entry retention in `RecentProjectStore`.

## Requirement resolution

The core of this change is one function. `AppRoute.setup` and
`AppRoute.providerSetup` are replaced by a single `onboarding` case carrying the
step:

```swift
enum OnboardingStep: Equatable, Sendable, CaseIterable {
    case installOmp
    case connectProvider
    case chooseProject
}
```

The decision itself is a pure function, so it can be tested as a table without
constructing an `AppModel`. `providerModel` is `private(set)`, which a table
test cannot populate:

```swift
extension OnboardingStep {
    /// The first requirement not satisfied by these inputs, or nil when the
    /// workspace is usable.
    static func firstUnmet(
        installation: OmpInstallation?,
        hasAuthenticatedProvider: Bool,
        selectedProjectURL: URL?
    ) -> OnboardingStep? {
        if installation == nil { return .installOmp }
        if !hasAuthenticatedProvider { return .connectProvider }
        if selectedProjectURL == nil { return .chooseProject }
        return nil
    }
}
```

`AppModel` feeds it and routes on the result:

```swift
func firstUnmetRequirement() -> OnboardingStep? {
    OnboardingStep.firstUnmet(
        installation: installation,
        hasAuthenticatedProvider: providerModel?.hasAuthenticatedProvider == true,
        selectedProjectURL: selectedProjectURL)
}

/// Routes to the first unmet requirement, or to the workspace. Preserves the
/// current force-to-`newSession` semantics of every site it replaces.
func gateRoute() {
    route = firstUnmetRequirement().map(AppRoute.onboarding) ?? .newSession
}
```

`gateRoute()` replaces eight existing decisions and adds one new call:

| Site | Today | After |
| --- | --- | --- |
| `AppModel` runtime prep, OMP missing | `route = .setup` | `gateRoute()` |
| `AppModel` runtime replacement, OMP missing | `route = .setup` | `gateRoute()` |
| `AppModel` runtime prep, services constructed | `route = .providerSetup` | `gateRoute()` |
| `AppModel` runtime replacement, services constructed | `route = .providerSetup` | `gateRoute()` |
| `AppModel` runtime prep, provider loaded | `hasAuthenticatedProvider ? .newSession : .providerSetup` | `gateRoute()` |
| `AppModel` runtime replacement, provider loaded | same ternary | `gateRoute()` |
| `AppModel` provider fallback load | same ternary | `gateRoute()` |
| `AppModel.completeProviderSetup()` | guard on provider, then `route = .newSession` | `gateRoute()` |
| End of recent-projects preparation | (none) | `gateRoute()` |

Rows three and four are interim assignments made after the OMP-backed services
are constructed but before `loadProviders()` returns. `gateRoute()` yields
`.onboarding(.connectProvider)` at those points, which is the same screen they
produce today, because `installation` is set and no provider is authenticated
yet.

`completeProviderSetup()` is the provider step's `Continue` handler and is the
one site where leaving it alone would defeat the feature: it would send the user
straight to the workspace with `selectedProjectURL` still `nil`, skipping the
project step. Its `hasAuthenticatedProvider` guard becomes redundant, because
`gateRoute()` keeps an unauthenticated user on the connect step.

`leaveSettings()` switches over `.setup` and `.providerSetup` to decide where
returning from Settings lands. Those cases become `.onboarding`, mapped to
`.newSession` exactly as before. Removing the two enum cases makes this a
compile error rather than a silent omission.

### Why the ninth call site is required

Startup stages run in order: runtime, settings, sessions, recent projects.
`selectedProjectURL` is assigned during the last of those. The runtime stage
therefore routes while the project requirement is still unmet, which for a
returning user is a false negative. Without a re-gate after recent projects are
prepared, **every** returning user would be shown the project step. The extra
call is what makes the resolver correct, not a convenience.

`gateRoute()` is idempotent, so calling it more often is safe.

### Preconditions

Every call site runs either before the splash hands off to the workspace, or
inside a runtime replacement that has already discarded managed sessions. No
site can therefore pull a user out of a session they are reading. This preserves
today's semantics exactly; the force-to-`newSession` behavior is not being
changed, only centralized.

### Resulting behavior

| User state | Steps shown |
| --- | --- |
| No OMP, no provider, no prior sessions | 3 |
| OMP installed, no provider, no prior sessions | 2 |
| OMP and provider, no prior sessions | 1 |
| Returning user with ranked projects | 0 |
| OMP removed while the app is running | re-enters at install |
| Provider credentials revoked while running | re-enters at connect |

Splash handoff is untouched. `2026-08-25-startup-splash-preload-design.md`
already states that the initial route follows requirement state; this changes
only how that state is computed.

## Executable discovery

### The install destination gap

`https://omp.sh/install` resolves its destination as:

```sh
INSTALL_DIR="${PI_INSTALL_DIR:-$HOME/.local/bin}"
```

The script installs through bun only when bun is already present and its
architecture matches the host. Otherwise it downloads the prebuilt binary to
`~/.local/bin`. A user with no bun, which is the expected first-run case, gets
`~/.local/bin/omp`.

`~/.local/bin` is in none of the app's candidate lists. Without adding it the
install step dead-ends: the script reports success, discovery reports nothing
found, and the user is returned to the same screen. Adding it also repairs
discovery for anyone who installed OMP manually before first opening 10x.

### One list instead of three

The same directory set is currently hardcoded three times:

- `OmpExecutableLocator.knownPaths`, the list the setup screen displays.
- `OmpExecutableLocator.candidates(preferredURL:)`, a second copy that is what
  discovery actually probes.
- `OmpProcessEnvironment.toolDirectories`, the PATH handed to spawned
  processes.

The comment on `toolDirectories` already states the intent: *"Same set the setup
screen lists, so the paths it claims to check are the paths a spawn can reach."*
Its `ponytail:` note says to revisit the static list only if installs outside
those three directories appear. One has.

`OmpProcessEnvironment.toolDirectories` becomes the single source, gaining
`~/.local/bin`. `knownPaths` derives its display strings from it, and
`candidates(preferredURL:)` derives its probe URLs from it. The display list and
the probe list can no longer drift apart.

## Install step

The install script is safe to drive from a subprocess: it contains no `read`,
no `sudo`, and no TTY interaction, and it runs its own `--version` smoke test
after installing. A binary that installs but cannot start is reported by the
script and is also caught by the existing `OmpLocation.unrunnable` case, which
already has its own screen copy.

### Behavior

1. The command is displayed verbatim, in mono, selectable, before anything runs.
2. `Install OMP` spawns `/bin/sh -c` with the documented command, using
   `OmpProcessEnvironment.resolved()` for PATH. Not a login shell: the
   `ponytail:` note on `OmpProcessEnvironment` records that sourcing rc files
   can hang on a slow profile, and the installer needs nothing from them.
3. Merged stdout and stderr stream into a scrolling mono log as they arrive.
4. Exit status 0 re-runs discovery automatically and `gateRoute()` advances.
5. A nonzero exit leaves the log on screen and the step in place.
6. `Locate OMP` remains available throughout, unchanged.

### Why not `OmpCommandRunner`

`OmpCommandRunner.run` returns `Data` collected with `readToEnd`, so output is
only available after the process exits. An installer that downloads over a
network needs its progress visible while it runs. A separate small
`OmpInstallRunner` uses `Process` with `readabilityHandler`, which is an
existing pattern in this codebase (`LineTransport`, `SessionHeaderMetadata`),
and supports cancellation by terminating the process.

`OmpCommandRunner` is not modified. It exists to run OMP itself with process
group cleanup, which is a different problem from a one-shot installer.

## Provider step

`ProviderSetupView`'s current body is reused as step content. Its wordmark,
title, and the shared `470pt` frame move up into the onboarding container. Its
provider list, search field, `ExtensionInputSheet` handling, connect and cancel
actions, and error copy are unchanged.

`Continue` keeps its existing rule: enabled once one provider is connected, and
the user may connect more before continuing.

This does not conflict with `2026-08-26-multi-account-provider-routing-design.md`.
That design places account management in Providers, Connections. Onboarding only
requires that one account is connected, which is the same condition
`hasAuthenticatedProvider` already expresses.

## Project step

### Suggestions (current, 2026-08-27)

No disk crawl. Suggestions are the working directories of existing OMP
sessions: `ProjectSessionGrouper.choosableProjectURLs(from: model.sessions)`,
the same call the composer's project flyout already made. A genuine
first-run user has no sessions, so the list is empty and `Choose folder…` is
the only control. The `### Scan` section immediately below describes the
home-directory crawl this replaced; it is historical, kept for the record.

### Scan (removed 2026-08-27, historical)

A directory scan of the user's home folder, off the main actor:

- Walk with `FileManager.enumerator` using `.skipsHiddenFiles` and
  `.skipsPackageDescendants`, over directories up to four levels below the home
  folder, bounded via the enumerator's `level`.
- A directory is a repository when it contains `.git` **as a directory**. A
  worktree's `.git` is a file, so worktrees are excluded without any special
  case. This checkout is an example of one.
- On finding a repository, stop descending into it. Repositories vendored inside
  another repository are therefore never reported, and neither are worktrees
  kept inside their own repository.
- Skip `Library`, `Desktop`, `Downloads`, `Documents`, and `.Trash` by name at
  the top level. `.skipsHiddenFiles` excludes dot-directories at every level, so
  a repository under `~/.config` is not offered.
- Do not descend into symbolic links, which also removes the possibility of a
  link cycle.
- Rank results by `contentModificationDateKey`, most recent first, and show at
  most twelve.
- The scan is cancellable and is cancelled when the step is left.

Depth is a measured choice. On a development machine on 2026-08-26, running this
exact algorithm over a home folder holding 55 repositories:

| Repositories at depth up to | Found | Time |
| --- | --- | --- |
| 2 | 26 | 0.061s |
| 3 | 40 | 0.057s |
| 4 | 55 | 0.053s |
| 5 | 55 | 0.078s |

Depth costs nothing once `Library` is skipped and the walk stops at each
repository, and the result set saturates at four. A `find`-based measurement is
not comparable, because `find` descends into `Library` and does not prune.

Spotlight was evaluated and rejected: it does not index dot-directories, so a
query for `.git` returns nothing.

The skip list is what keeps onboarding free of macOS consent prompts. Folders
excluded from the scan are still reachable through `Choose folder…`, because
`NSOpenPanel` grants access to what the user picks.

### Selection

Selecting a suggestion or choosing a folder records into `RecentProjectStore`
and sets `selectedProjectURL`. An explicit `Continue`, enabled once at least one
folder is chosen, advances through `gateRoute()`.

The step does **not** call `AppModel.chooseProject`. That method ends with
`route = .newSession`, so the first selection would leave onboarding
immediately and no second folder could ever be added. The step performs the
same two assignments without the routing and without the active-session
teardown, which has nothing to tear down during onboarding.

`RecentProjectStore` retains two entries and `rankedProjects` returns two,
because startup warms one OMP client per ranked project and the splash design
measured roughly 306 MB per client. Adding several folders during the step is
allowed; the two most recent are retained, which is the store's existing
contract for the whole app. Raising that cap is a memory decision and is out of
scope here.

## Views

```text
OnboardingView                     container: wordmark, title, step counter, Back
├── OnboardingInstallStepView      command, Install OMP, streamed log, Locate OMP
├── OnboardingProviderStepView     existing ProviderSetupView body
└── OnboardingProjectStepView      suggested repositories, Choose folder…
```

`AppShellView`'s two full-screen branches (`.setup`, `.providerSetup`) become
one branch for `.onboarding`. `SetupView` and `ProviderSetupView` are absorbed
into their step views rather than left as parallel screens.

### Navigation

The entry set is the list of unmet steps computed when onboarding is entered.
The step counter counts within that set.

`Back` is shown on every step except the first of the entry set, and returns to
the preceding step in that set even if its requirement has since been met. Only
the install step can be revisited that way, and it needs a satisfied rendering:
when `installation` is non-nil it shows the resolved executable path and
reported version instead of the command, with `Continue` to move forward again.
That is also the only place in the app that states which OMP binary 10x is
using, which is worth having when a machine holds more than one.

Steps otherwise advance on their own completion: discovery succeeding, the
provider step's existing `Continue`, and choosing a project folder.

### Shared chrome

The container owns what the two existing screens duplicate today: the
`BrandWordmark(width: 48)`, the `TenXTypography.title(size: 38)` heading in
`nearBlackHex`, the 14pt body line in `mutedTextHex`, the
`.frame(width: 470, alignment: .leading)`, and `.padding(56)`.

`ProviderSetupView` currently keeps its row chrome and skeleton rows private:
a 42pt row with a 1pt `separatorHex` bottom rule, and `ProviderSetupLoadingRows`.
The project step needs both. They are extracted into shared onboarding row
components used by both steps, rather than a second copy drifting from the
first.

The install log reuses the sizing already established by the provider list's
bounded scroll region, in `TenXTypography.mono()` at `mutedTextHex`, inside a
fixed-height `ScrollView` so a long install cannot push `Locate OMP` off screen.

### Copy

| Surface | Text |
| --- | --- |
| Install title | `Install OMP` |
| Install body | `10x starts and resumes agent sessions through OMP.` |
| Install command label | `Runs this command:` |
| Install primary | `Install OMP`, `Installing…` while running |
| Install failure | `Install failed. The output above shows why.` |
| Install secondary | `Locate OMP` (existing, with its existing hint) |
| Install, already satisfied | `Using OMP` over the path and version, with `Continue` |
| Unrunnable title | `OMP won’t run` (existing) |
| Unrunnable body | `10x found OMP but couldn’t run it. Its interpreter may be missing.` (existing) |
| Provider title | `Connect a provider` (existing) |
| Provider body | `Choose at least one provider to start sessions.` (existing) |
| Project title | `Choose a project` |
| Project body | `Sessions run in a project folder.` |
| Suggestions label | ~~`Found in your home folder`~~ **`Recent projects`** (2026-08-27) |
| Project empty | ~~`No Git repositories found in your home folder.`~~ **(removed 2026-08-27: no list, no error, just the controls)** |
| Project secondary | `Choose folder…` |
| Project primary | `Continue` |
| Step counter | `Step 1 of 3` |
| Back | `Back` |

No count of found repositories is displayed, which avoids a singular and plural
form in a dynamic string. (This no longer applies to a count of scan results,
since there is no scan; it is kept as it still describes the row list generally.)

### States

Each step owns its own states rather than deferring to a screen-level spinner.
~~The scan renders skeleton rows while it runs, in the shape the provider list
already uses, then the list or the empty line.~~ **Superseded 2026-08-27:**
the project step has no asynchronous work and therefore no loading state; it
renders the list (when there are known project directories) or nothing (when
there are none) synchronously. The install step is idle, running with visible
output, or failed with that output retained. Provider errors continue to use
the existing `providerMessage` and `loginMessage` paths.

Nothing reports success it has not confirmed: the install step advances only
after discovery actually finds a runnable executable, not after the script
prints its own success line.

## Testing

The units below carry the logic, following the pattern in
`OmpKit/Tests/OmpKitTests/ExecutableResolutionTests.swift`. The scanner unit
was removed on 2026-08-27 with the home-directory scan.

**Resolver.** A table over installation, provider authentication, and selected
project, asserting the route for every combination, including all nine call
sites. The returning-user case is explicit: routing during the runtime stage
yields the project step, and re-gating after recent projects are prepared
yields the workspace. Regression cases assert that removing OMP mid-run returns
to the install step and that a revoked provider returns to the connect step.

**~~Scanner.~~ Removed 2026-08-27.** The scanner and its test table (below,
kept for the record) no longer exist. `GitRepositoryScanner` and
`GitRepositoryScannerTests.swift` were deleted along with the disk crawl.
Project-step coverage now lives in `ProjectSessionGrouperTests.swift`
(`choosableProjectURLs` already had its own tests before this design existed)
and in `ViewSnapshotTests.swift`'s `onboarding-project-empty` /
`onboarding-project-populated` snapshots, which build `AppModel.sessions`
directly rather than a fixture tree on disk.

A temporary tree exercised every rule, asserting the found set, the ranking
order, the twelve-result cap, and that cancellation stopped the walk:

| Fixture | Expected |
| --- | --- |
| Repository at depth 1 | found |
| Repository at depth 4 | found |
| Repository at depth 5 | not found |
| Repository nested inside another repository | not found, outer is |
| Worktree whose `.git` is a file | not found |
| Repository under a dot-directory | not found |
| Repository under a skip-list name | not found |
| Directory holding a `.git` *file* only | not found |
| Symbolic link forming a cycle | not followed, walk terminates |

**Install runner.** An injected process double proving that exit 0 triggers
re-discovery, that a nonzero exit retains output and leaves the step in place,
and that leaving the step terminates a running install.

**Discovery.** Extends the existing coverage with `~/.local/bin/omp`, and
asserts that the displayed path list and the probed candidate list are derived
from the same source.

Visual verification is against a real build, per `verifying-work`: each of the
three steps, the two-step and one-step entries, the failed install with output
retained, and the project step with and without suggestions. (There is no
longer a skeleton state for the project step; see the update note at the top
of this document.)

## Out of scope

- Raising the two-project retention cap in `RecentProjectStore`.
- Creating directories or running `git init` for a user starting from nothing.
- ~~Scanning `~/Desktop`, `~/Documents`, or `~/Downloads`, with or without an
  opt-in control.~~ Moot as of 2026-08-27: the project step scans nothing at
  all, see the update note at the top of this document.
- Multi-account provider connection, which
  `2026-08-26-multi-account-provider-routing-design.md` owns.
- Re-showing onboarding on demand from Settings.
- Updating an already-installed OMP.

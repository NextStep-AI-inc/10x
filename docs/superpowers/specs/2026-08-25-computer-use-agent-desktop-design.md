# 10x Computer Use and Agent Desktop

**Status:** Approved
**Date:** 2026-08-25  
**Platform:** macOS 15+, Swift 6.1, SwiftUI  
**Integration baseline:** OMP 18.0.4 (`@oh-my-pi/pi-coding-agent`), RPC protocol v2

## Product goal

Add full-desktop computer use to 10x without interrupting the person using the
Mac. After one-time setup, a user explicitly enables computer access for one
session. The model can then launch dedicated application windows, operate them
through OMP's native computer tool, and return visual verification evidence.

The preferred experience isolates agent-owned windows in an Agent Desktop
provided by AeroSpace or Hammerspoon. When isolation is unavailable, 10x falls
back to OMP's background-window control. 10x never silently switches desktops,
steals focus, moves the pointer, or types into the user's active application.

V1 proves this loop end to end:

1. Configure macOS permissions and an isolation preference.
2. Enable computer use for one session.
3. Create or reuse an Agent Desktop without changing the active desktop.
4. Launch and claim a dedicated application window.
5. Let OMP inspect and control that window without disrupting unrelated work.
6. Show screenshots, actions, state, and failures in the transcript.
7. Pause for an explicit handoff if macOS requires foreground control.
8. Stop immediately and preserve unsaved work.

## Existing foundation

10x does not need a second desktop-automation engine. OMP 18.0.4 already ships
a session-scoped `computer` tool with:

- window and display discovery;
- window or desktop screenshots;
- macOS Accessibility trees and semantic actions;
- background and foreground pointer or keyboard delivery;
- read-only inspection runs;
- persistent JavaScript state;
- cancellation, timeouts, capability reporting, and existing approval gates.

`computer.enabled` defaults to false. `/computer on` enables it only for the
current OMP session without persisting a global setting. 10x currently renders
the tool through its generic fallback and does not render image blocks from
tool results.

OMP has no Agent Desktop, window ownership, helper integration, or hard policy
that blocks foreground delivery. Those are the responsibilities added by this
design. OMP remains the only component that executes model-authored desktop
actions.

## Decisions

| Concern | Decision |
|---|---|
| Desktop scope | Full Mac after explicit setup and per-session enablement |
| Runtime authorization | Off at every session start; enable once per session |
| Isolation | Layered provider: AeroSpace, Hammerspoon, background fallback |
| Window choice | Prefer dedicated instances or new windows |
| Existing windows | Use only when the user's request requires them |
| Foreground control | Suspend and request handoff; never take focus silently |
| Concurrency | One computer-enabled 10x session per Mac in V1 |
| Automation engine | Reuse OMP's native `computer` tool |
| Helper installation | Detect and guide; never install or reconfigure silently |
| Space implementation | No bundled private Space APIs and no SIP changes |

## System architecture

```text
SessionController
      |
      +-- ComputerUseController
      |   +-- session enable/disable
      |   +-- readiness and permission state
      |   +-- active-run cancellation
      |   +-- foreground handoff
      |
      +-- AgentDesktopCoordinator
          +-- AeroSpaceProvider
          +-- HammerspoonProvider
          +-- BackgroundProvider
                  |
                  +-- DedicatedWindowLauncher
                          |
                          +-- AgentDesktopManifest

OMP child process
      |
      +-- /computer on|off|status
      +-- native computer worker
          +-- screenshots
          +-- Accessibility
          +-- background input
          +-- foreground handoff gate
```

### Component boundaries

`ComputerUseController` is the session-facing state machine. It coordinates
setup readiness, Agent Desktop preparation, OMP enablement, the one-active-
session invariant, handoff requests, emergency stop, and cleanup. It exposes a
narrow observable state to SwiftUI and does not execute helper commands itself.

`ComputerUseLease` is an advisory lock in 10x Application Support containing
the owning process and session identity. The operating-system lock, not the
file contents, is authoritative and is released if the owner crashes. It
enforces the one-computer-session rule across multiple 10x processes without
leaving a stale permanent lock.

`AgentDesktopCoordinator` is an actor responsible for provider selection and
the lifecycle of the session's desktop manifest. Provider calls use explicit
argument arrays, bounded timeouts, validated output, and no shell evaluation.

`AgentDesktopProvider` is a small interface implemented by AeroSpace,
Hammerspoon, and the background fallback. A provider reports capabilities,
prepares a workspace, installs a temporary window watcher, moves or restores a
window, and releases its workspace. Provider-specific behavior does not leak
into `SessionController` or views.

`DedicatedWindowLauncher` launches a new process when the application supports
it. For single-instance applications, it requests a new window and compares
the provider's before and after window snapshots. It claims only new windows.

`AgentDesktopManifest` is ephemeral session state containing the provider and
workspace identifier, owned process IDs, owned window IDs, borrowed existing
windows, and original locations needed for restoration. V1 adds no database.

## Isolation providers

### Automatic selection

The user preference is `Automatic`, `AeroSpace`, `Hammerspoon`, or
`Background Only`. Automatic uses this order:

1. A running AeroSpace installation whose CLI responds and passes its probe.
2. A running Hammerspoon installation with the versioned 10x integration and
   required Accessibility access.
3. OMP background-window control without a separate workspace.

A selected provider is a preference, not an assertion. Every session prepares
and probes it again. A missing or unhealthy preferred helper produces a clear
degraded state and offers the background fallback.

### AeroSpace

AeroSpace creates an emulated workspace named `10x-<session-token>`. Before an
application launches, 10x installs a temporary detection rule or watcher. The
new window is moved by window ID without focusing the workspace. V1 does not
edit AeroSpace's persistent configuration. Empty temporary workspaces are
allowed to disappear naturally after cleanup.

AeroSpace is preferred in Automatic mode because its workspace model avoids
native Space switching and does not require disabling System Integrity
Protection. Its emulation is still subject to off-screen capture behavior, so
the provider must pass the same runtime screenshot and background-input probes
as every other provider.

### Hammerspoon

Hammerspoon reuses one designated native Agent Desktop. A small versioned 10x
integration watches for claimed windows and moves them immediately. Creating or
selecting the Space happens only during explicit setup because Mission Control
becomes visible. 10x neither bundles private Space APIs nor modifies the user's
Hammerspoon configuration without confirmation.

The integration validates its own version and exposes only the operations 10x
needs. If it disappears or becomes incompatible, 10x preserves the manifest,
stops moving windows, and offers background fallback.

### Background fallback

The fallback does not claim a separate workspace. It launches dedicated
windows and relies on OMP's background input and Accessibility actions. It
never raises a window automatically. If an application rejects background
delivery, the operation enters the foreground-handoff flow.

## Window ownership

Dedicated windows are a strong convention, not a security sandbox. The
enablement grants OMP full-desktop access, and stock macOS permissions are not
scoped to the manifest.

The launch flow is:

1. Snapshot relevant windows.
2. Register the provider's temporary watcher.
3. Launch a new application instance when supported.
4. Otherwise request a new window from the existing process.
5. Diff window IDs and claim only newly created windows.
6. Move claimed windows into the Agent Desktop.
7. Record ownership and original placement in the manifest.

Existing windows are never moved merely because their application matches. If
the user's request explicitly depends on an existing authenticated or
stateful window, OMP may operate it in place through background control. Such a
window is marked borrowed and is never closed, moved, or restored by cleanup.

On session cleanup, 10x closes only windows and processes it launched when that
is safe. Unsaved documents remain open in the Agent Desktop and are reported to
the user. A helper failure never causes 10x to guess ownership.

## Setup experience

Settings gains a specialized Computer Use section above the generated
`computer.*` OMP rows. It shows:

- OMP version and computer-tool availability;
- screen-capture, Accessibility, and background-input readiness;
- the selected isolation preference;
- detected helper, integration version, and health;
- actions to open the relevant System Settings panes;
- helper-specific setup instructions;
- a harmless setup test with per-capability results.

Capability checks run through the actual OMP process identity used by a 10x
session so the displayed permission state matches execution. Helper permissions
are checked separately because Hammerspoon and AeroSpace have their own macOS
identities. The model-free readiness check starts a disposable `--no-session`
OMP RPC process and runs the local `/computer on`, `/computer status`, and
`/computer off` commands. It does not invoke a model or create session history.
The setup test separately verifies helper discovery and window placement; live
screenshot and input behavior remains part of the first enabled-session probe
and the Release acceptance flow.

The setup persists only the 10x isolation preference and helper metadata. It
does not set OMP's global `computer.enabled` value. The generated setting remains
discoverable but explains that 10x manages enablement per session.

10x never silently installs a helper, writes its configuration, disables SIP,
or grants permissions. Every setup mutation has an explicit user action and a
plain description of its effect.

## Session lifecycle

### State model

```text
off -> preparing -> ready -> controlling
           |          |          |
           +------> unavailable  +--> needsHandoff
                                      |
                                      +--> controlling | ready

any enabled state --stop--> stopping --> off
```

New sessions start `off`. Enabling computer use first disables another enabled
session in the same 10x process, then acquires the cross-process lease. If a
different 10x process owns the lease, enablement stops with an `In use`
explanation rather than disrupting that process. After acquiring the lease,
10x prepares and probes the Agent Desktop and sends `/computer on` to the active
OMP process. The state becomes `ready` only after OMP confirms tool availability.

`controlling` begins on a live computer tool event and ends when that call
completes. `needsHandoff` is blocking: no focus-changing action has executed.
`unavailable` includes missing OMP support, permissions, helper failure without
a safe fallback, or an incompatible active model.

Stop cancels the active tool call, denies a pending handoff, waits for the OMP
turn boundary, sends `/computer off`, and releases owned resources. Screen
lock, logout, sleep, helper termination, or permission revocation performs the
same fail-closed transition and requires explicit re-enablement.

## Foreground handoff and OMP requirement

OMP 18.0.4 defaults to background delivery but cannot guarantee that
model-authored computer JavaScript will never request foreground input, raise a
window, or focus an Accessibility element. A system-prompt instruction is not
a sufficient enforcement boundary.

The complete V1 therefore requires a narrow upstream OMP enhancement:

1. A session policy `foreground: require-handoff` is passed to the computer
   supervisor.
2. Foreground input, window raising, or focus-changing Accessibility actions
   suspend before execution.
3. OMP emits a blocking extension UI request containing the target, action
   class, and reason.
4. 10x presents `Open Agent Desktop and Continue` or `Cancel`.
5. Approval authorizes only the pending operation and then resumes the same
   tool call. It does not grant a session-wide foreground exception.
6. Cancellation or Stop wakes and denies the suspended operation.

```text
foreground operation
        |
        v
OMP suspends before side effect
        |
        v
10x handoff request
  | approve              | cancel
  v                      v
switch visibly,       fail the call
run once, resume      without focus change
```

10x version-gates this contract. Older OMP versions may use best-effort
background mode, clearly labeled as unable to guarantee focus isolation. They
cannot claim the complete Agent Desktop safety contract.

OMP's existing point-of-risk confirmations remain authoritative for sending,
publishing, purchasing, deletion, account changes, permission grants, and
other consequential actions. Foreground handoff is an additional interaction
boundary, not a replacement approval system.

## Presentation

The session header exposes `Computer: Off`, `Preparing`, `Ready`,
`Controlling`, `Needs handoff`, or `Unavailable`. While enabled it also exposes
`Stop Computer`. The action is distinct from stopping a normal response.

Computer tool events receive a dedicated registry entry and card. The card
shows:

- target application or desktop;
- running, complete, failed, or cancelled state;
- background, read-only, or handoff mode;
- latest screenshot with a gallery for additional screenshots;
- textual output and returned values;
- capture, input, and Accessibility capability failures;
- collapsed JavaScript and raw-detail disclosure.

Image content blocks in OMP tool results are preserved and rendered rather
than discarded by the current text-only extractor. Persisted history maps the
same image and detail data when the session is reopened.

10x does not add continuous screen recording or a second screenshot archive.
It displays only the captures OMP emitted for a tool call and relies on OMP's
existing transcript and temporary-artifact lifecycle. This keeps capture
event-driven and avoids silently retaining unrelated desktop activity.

While active, a temporary menu-bar item reports which application 10x is
controlling and offers Stop. A global emergency shortcut invokes the same Stop
path. Neither control changes desktop focus.

The handoff card explains which application rejected background control and
why foreground access is necessary. Continuing visibly opens the Agent Desktop;
10x never switches and switches back automatically.

## Error handling

| Failure | Result |
|---|---|
| OMP lacks the computer tool | `Unavailable` with required-version guidance |
| Active model cannot expose the tool | `Unavailable` until model changes |
| Screen capture or Accessibility denied | Stop and link to the correct Settings pane |
| Preferred helper absent | Offer background fallback without changing preference |
| Helper command timeout or malformed output | Preserve manifest, stop provider mutation, report sanitized error |
| Helper exits during control | Abort active control; fall back only after a fresh probe |
| Off-screen capture fails | Enter `Needs handoff`; never switch automatically |
| Background input rejected | Suspend at the OMP foreground gate |
| Window disappears | Remove only that owned window from the manifest |
| Ownership is ambiguous | Do not move or close the window |
| Stop or cancellation races completion | One idempotent cleanup path wins |
| Unsaved owned document | Leave open and report it |

Errors follow the repository's traceable format and sanitize window titles,
paths, scripts, and screen content where they could expose private data.

## Verification strategy

### Unit and contract coverage

- Provider selection and explicit-preference behavior.
- Computer-use state transitions and the one-active-session invariant.
- Manifest ownership, borrowing, restoration, and conservative cleanup.
- Fixed-argument helper commands, bounded timeouts, validated JSON, and
  shell-injection resistance.
- Fake AeroSpace and Hammerspoon executables covering success, disappearance,
  incompatible versions, malformed output, and failure.
- OMP RPC fixtures for `/computer on`, `/computer off`, image-bearing computer
  results, capability details, cancellation, handoff, and old-version gating.
- Screenshot-content extraction and persisted-history mapping.
- Snapshot coverage for setup, computer cards, galleries, degraded isolation,
  handoff, and Stop.

### Release-build acceptance

Run the real built app in these configurations:

1. AeroSpace installed and selected.
2. Hammerspoon installed and selected.
3. Neither helper available, using background fallback.
4. Preferred helper stopped during a live run.
5. Screen-capture or Accessibility permission revoked.
6. An older OMP version without foreground handoff.

The core behavioral test keeps the tester actively typing in an unrelated
application while the agent launches a dedicated TextEdit document, isolates
it, captures it, edits it through Accessibility or background input, and
returns screenshot evidence. Repeat with a browser window. Any stolen focus,
moved pointer, misplaced keystroke, relocated existing window, or automatic
desktop switch fails the release gate.

Additional live checks stop during an active run, deny and approve foreground
handoff, close an owned window, preserve an unsaved document, reopen persisted
computer activity, and verify the menu-bar emergency stop. Capture screenshots
from the Release build for every major UI state.

## V1 scope boundaries

V1 intentionally excludes:

- automatic installation of AeroSpace or Hammerspoon;
- unconfirmed edits to helper configuration;
- disabling SIP or bundling private Space-management APIs;
- virtual machines or separate macOS user accounts;
- hard security sandboxing of OMP's full-desktop access;
- multiple concurrent computer-controlling sessions;
- Windows and Linux isolation providers;
- automatic foreground takeover based on idle time;
- guaranteed isolated instances for applications that expose neither new
  processes nor independently identifiable windows.

## Sources

- OMP computer tool: <https://github.com/can1357/oh-my-pi/blob/main/docs/tools/computer.md>
- AeroSpace workspace model: <https://nikitabobko.github.io/AeroSpace/guide#emulation-of-virtual-workspaces>
- AeroSpace commands: <https://nikitabobko.github.io/AeroSpace/commands.html>
- Hammerspoon Spaces API: <https://www.hammerspoon.org/docs/hs.spaces.html>
- Apple window collection behavior: <https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct>
- yabai Space and window commands: <https://github.com/asmvik/yabai/blob/master/doc/yabai.asciidoc>

## Implementation ordering constraint

The 10x implementation may proceed in parallel with OMP rendering, setup,
provider, and lifecycle work, but the foreground-handoff release gate depends
on the upstream OMP policy and extension-UI contract. 10x must not describe the
feature as non-interrupting on an OMP version that lacks that enforcement.

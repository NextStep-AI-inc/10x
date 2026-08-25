# Inline File References and Preferred IDE

**Status:** Approved in chat; awaiting written-spec review
**Date:** 2026-08-25
**Parent spec:** `docs/superpowers/specs/2026-08-24-chat-transcript-experience.md`

## Goal

Make file locations in the transcript useful without filling the interface with
absolute paths. A file reference must expose two distinct actions:

1. Select the file name to open the file with the macOS system default.
2. Select the adjacent IDE action to open the file in the IDE chosen in 10x
   Settings.

The same interaction must work for assistant references and file-oriented tool
activity. The preferred IDE is an application preference owned by 10x, not an
OMP configuration value.

## Scope

### Included

- A shared inline file-reference component for assistant references and
  Read, Edit, and Write tool headers.
- File icon, clean file name, and optional line suffix.
- System-default opening from the primary file action.
- A separate `Open in <IDE>` ghost action.
- Full resolved path while Option is held over the file reference.
- A searchable Preferred IDE row in the General section of Settings.
- Detection of Xcode, Cursor, Visual Studio Code, Zed, Nova, and Sublime Text.
- A `Choose application…` route for another installed macOS application.
- Persistence of the user's last explicit IDE selection.
- Copy Reference and Reveal in Finder context-menu actions.

### Excluded from V1

- Per-project or per-worktree IDE preferences.
- Command-line editor configuration.
- Automatic selection based on the most recently used application.
- Silent fallback to another IDE when the selected application is unavailable.
- Editor-specific URL schemes or line-and-column navigation.
- Remote paths or files unavailable to the local Mac.
- OMP configuration, schema, or RPC changes.

## User experience

### Inline reference

The default reference is one borderless row:

```text
[file icon] RpcClient.swift:42    Open in Cursor
```

- The primary action uses the existing compact reference typography and a
  native file symbol. It shows the basename plus a line suffix when one exists.
- Selecting the primary action asks macOS to open the file with its registered
  default application.
- The IDE action is a cyan ghost action. Its label names the selected
  application, such as `Open in Cursor` or `Open in Xcode`.
- Before an IDE has been selected, the secondary action reads `Choose IDE`.
  Selecting it opens Settings and moves keyboard focus to Preferred IDE.
- If a previously selected application can no longer be resolved, the action
  returns to `Choose IDE`. 10x does not silently change the preference.
- Holding Option while the pointer is over the primary action replaces the
  basename with the resolved absolute path. The path uses SF Mono and wraps at
  path separators inside the transcript column; it never widens the window.
  Releasing Option or leaving the reference restores the compact label.
- The full path is always present in the accessibility label, and the context
  menu can copy the reference, so Option-hover is not the only way to obtain
  the location.

The component uses the existing white, near-black, and cyan visual tokens. It
adds no fill, border, pill, shadow, or decorative background. Hover, focus, and
pressed states use the existing ghost-action treatment.

### Context menu

The primary file action exposes:

- Open with System Default
- Open in the selected IDE, when that application is available
- Reveal in Finder
- Copy Reference

`Copy Reference` copies the original path and line suffix supplied by the
transcript. `Reveal in Finder` and both open actions use the resolved local URL.

### Missing files

A reference whose resolved URL does not exist remains visible and copyable. Its
icon and label use the muted text token, and open/reveal actions are disabled.
The full path remains available through Option-hover and accessibility.

### Tool headers

Read, Edit, and Write cards use the same file reference in their collapsed and
expanded headers. The disclosure control and file actions are siblings, not
nested buttons:

```text
[disclosure] Read    [file] RpcClient.swift    Open in Cursor    Complete
```

Selecting the disclosure region expands or collapses the tool. Selecting a file
action never changes disclosure state. When the three regions do not fit on one
line, the IDE action moves beneath the file action while preserving reading and
keyboard order.

### Settings

Preferred IDE appears as an app-owned row in the existing continuous General
section. It is included in Settings search by display name, description, and
application name.

The row contains a native menu with:

- every supported application currently installed;
- the current custom application, if one was chosen and still resolves;
- `Choose application…`;
- `None`, which clears the IDE preference.

The row is explicitly labeled as a 10x preference. It is not counted or shown
as an OMP key and does not use the OMP default-value/reset affordance. Selecting
an application saves immediately and updates every visible file reference.
When the saved application is unavailable, the menu shows its saved name with
`Unavailable`; choosing an installed application or `None` clears that state.

## Architecture

### `IDEApplication`

A small value type represents an application that can open a file:

- stable selection identifier;
- display name;
- application URL;
- bundle identifier when available;
- whether the application is one of the known IDEs or a custom choice.

Known applications are identified by bundle identifier rather than a hard-coded
installation path.

### `IDERegistry`

The registry owns application discovery. It asks `NSWorkspace` for the known
bundle identifiers and returns only applications that resolve on the current
Mac. The custom picker uses `NSOpenPanel`, accepts `.app` bundles, and validates
the selected URL before returning it.

Discovery is local and runs when Settings needs the menu or when a stored
selection must be resolved. It does not scan arbitrary directories or access
the network.

### `IDEPreferenceStore`

The preference store owns one optional IDE selection and publishes changes to
the SwiftUI environment. It uses `UserDefaults` for the selection metadata:

- known IDEs persist their bundle identifier;
- custom applications persist a security-scoped bookmark and display name.

The store resolves the saved value through `IDERegistry` at launch. A stale or
unresolvable value remains stored so the UI can show that the choice is
unavailable, but it is not used to open files. Choosing a new application or
`None` replaces it.

### `FileOpenService`

The file-opening service has four operations:

1. Resolve an absolute or relative reference against the active session's
   project or worktree URL.
2. Open the resolved URL with the macOS system default.
3. Open the resolved URL with the current preferred IDE by using
   `NSWorkspace` and the resolved application URL.
4. Reveal the resolved URL in Finder.

When a custom application is selected, the service brackets the open operation
with security-scoped resource access and releases that access after macOS
accepts or rejects the request.

Path resolution standardizes the URL before existence checks. An absolute path
does not use the project URL. A relative path requires the session project or
worktree URL; without that base, it remains unavailable rather than resolving
against the app process's current directory.

### Shared SwiftUI component

The existing `TranscriptReferenceView` evolves into the shared file-reference
surface rather than introducing parallel transcript and tool variants. It owns:

- compact and Option-expanded labels;
- hover, keyboard, and modifier-key state;
- existence and availability presentation;
- primary, IDE, and context-menu actions;
- accessibility labels and hints.

Its dependencies are supplied explicitly: the parsed reference, resolution
base URL, file-opening service, IDE preference, and Settings navigation action.
Web references keep their current browser-opening behavior and do not show an
IDE action.

### App integration

`AppModel` creates the shared registry, preference store, and file-opening
service for the app lifetime. The app shell injects them into Settings and the
session surface. `ActiveSessionView` supplies the selected session's project or
worktree URL for relative resolution.

`ToolCardScaffold` separates its current all-in-one header button into sibling
disclosure and trailing-content regions. Read, Edit, and Write pass a typed file
reference into the trailing region. Other tool cards keep their existing text
subtitle and disclosure behavior.

## Data flow

```text
Session project/worktree URL
        │
        ▼
parsed file reference ──► FileOpenService ──► resolved local URL
        │                         │
        │                         ├── primary action ──► system default
        │                         ├── context menu ────► Finder / copy
        │                         └── IDE action
        │                                  │
        ▼                                  ▼
InlineFileReferenceView ◄──── IDEPreferenceStore ◄──── Settings
                                         │
                                         ▼
                                    IDERegistry
```

An IDE selection publishes immediately. Existing references update their label
and availability without reloading the transcript.

## Error handling

- Missing or unresolved files disable open and reveal actions without removing
  the reference.
- A missing project base disables relative file actions and leaves the original
  reference copyable.
- A stored IDE that cannot be resolved produces the `Choose IDE` state; it does
  not fall back to the first installed IDE.
- A custom application bookmark that cannot be resolved is treated as an
  unavailable preference until the user chooses again.
- A launch failure keeps the reference usable and temporarily adds a red inline
  status: `Couldn’t open <file name>` for the system default or `Couldn’t open in
  <application>` for the IDE action. The normal actions return after four
  seconds or the next interaction, and VoiceOver announces the same result. No
  modal or persistent banner is added.
- Internal errors follow the repository's traceable error format and do not put
  raw `NSWorkspace` or bookmark details in user-facing text.

## Accessibility and keyboard behavior

- The file and IDE actions are separate keyboard stops with 32-point minimum hit
  targets.
- The primary accessibility label includes `File reference`, the resolved full
  path when available, and the line number.
- The IDE action label states its full result, such as `Open RpcClient.swift in
  Cursor`.
- Disclosure state belongs only to the tool disclosure control.
- Option-hover is a visual enhancement. Copy, open, and full-path information
  remain available without a pointer or modifier key.
- Color is never the only indication of missing or unavailable state.

## Verification

### Automated checks

- Resolve absolute paths without a project base.
- Resolve relative paths against a project or worktree URL.
- Reject relative paths when no base URL exists.
- Preserve the original reference for Copy Reference.
- Discover each known IDE by bundle identifier through an injected workspace
  lookup.
- Persist and restore known and custom IDE selections.
- Return an unavailable state for a stale bundle identifier or bookmark.
- Clear the preference with `None`.
- Keep tool disclosure independent from file actions.

### Real Release-build checks

- Select a preferred IDE in Settings, return to a session, and verify every
  visible file reference changes to `Open in <IDE>`.
- Select the file name and verify macOS opens it with the system default.
- Select the IDE action and verify the chosen application opens the file.
- Hold Option over a short and a long reference and verify the full path appears
  without horizontal clipping.
- Verify an assistant reference and collapsed Read, Edit, and Write tool cards.
- Verify a relative tool path resolves against the active worktree.
- Verify a missing file remains visible, muted, and copyable with open/reveal
  actions disabled.
- Remove or rename a chosen test application and verify the UI returns to
  `Choose IDE` without selecting another IDE.
- Test the transcript at compact and full window widths, with keyboard-only
  navigation and VoiceOver labels.

Screenshots from the real Release app must show the Settings selection, a normal
inline reference, Option-expanded path, compact tool header, and missing-file
state.

## Acceptance criteria

- File references show a file icon and clean name instead of a persistent full
  path.
- Selecting the clean name opens the resolved file through the macOS default.
- Holding Option over the reference shows the full resolved path.
- A separate ghost action opens the file in the user's selected IDE.
- The selected IDE is configured in the continuous Settings form and persists
  across app launches.
- Common installed IDEs are discovered, and another `.app` can be selected.
- No IDE is guessed on first launch or substituted when the preference becomes
  unavailable.
- Assistant references and Read, Edit, and Write tool headers share one visual
  and behavioral component.
- Tool expansion remains independent from file-opening actions.
- The feature adds no decorative fill, border, pill, or shadow.
- Missing files remain identifiable and copyable without pretending they can be
  opened.

## Approaches considered

1. **Shared IDE service and local preference store (selected).** Keeps file
   behavior consistent across transcript and tool surfaces while cleanly
   separating 10x preferences from OMP configuration. The tradeoff is a small
   app-owned preference subsystem.
2. **View-local `@AppStorage`.** Fewer types initially, but duplicates discovery
   and stale-application handling across Settings and transcript views.
3. **Store the IDE in OMP configuration.** Centralizes settings visually but
   writes a 10x-only concern into an external tool's configuration contract.

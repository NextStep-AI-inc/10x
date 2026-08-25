# Session Rail Management Design

## Goal

Use the rail's available height, make overflow unmistakable, and let people archive or delete session history from the rail without risking project source files.

## Scope

- Let the session list fill the space between the wordmark and pinned bottom utilities.
- Show the five newest sessions in each project by default.
- Disclose hidden sessions through the project tree and expand each project on demand.
- Add visible rail-level scroll controls without replacing normal scrolling.
- Add right-click archive and delete actions for sessions and project groups.
- Add a separate screen for restoring or deleting archived session history.

This work never modifies or deletes a project's source directory. Archived sessions are excluded from the active rail and active-session search. Searching inside the archive screen is not part of this change.

## Rail layout and navigation

The wordmark remains fixed at the top. The session map becomes the flexible middle region instead of capping itself at 58 percent of available height. The Archived entry is pinned below that region and above the existing provider-usage area when usage data is present.

The session map remains a normal `ScrollView`. Light up and down chevrons overlay its top and bottom edges. A chevron appears only while content exists beyond that edge. Clicking one advances approximately four visible 32-point rows with the existing motion curve; trackpad, mouse-wheel, keyboard-focus, and direct-item navigation continue to scroll normally. Reduced-motion mode performs the same jump without animation.

Each project starts with its five newest sessions. When more exist:

- The collapsed rail terminates the project's connector with `...`.
- The expanded rail terminates the connector with `Show N more`.
- Selecting `Show N more` reveals the remaining sessions for that project and replaces the disclosure with `Show recent 5`.
- Expansion is held in memory for the current app run and does not alter session ordering or persist as a preference.

The disclosure is part of the tree, not a detached row. Its marker uses the same connector geometry and muted styling as session markers. In collapsed mode the ellipsis is informational and its accessibility label announces the hidden count. In expanded mode the disclosure is a button whose accessibility label includes the hidden count and expand or collapse action.

## Context actions and confirmation

Right-clicking a live session offers:

- `Archive Session`
- `Delete Session...`

Right-clicking a live project offers:

- `Archive Project Sessions`
- `Delete Project Sessions...`

Session deletion confirms the session title and states that the transcript is permanently deleted. Project deletion confirms the project name and number of affected transcripts, and states that project files are not changed. Archive actions are reversible and do not require confirmation.

If an action includes the open session, `AppModel` closes its runtime through `SessionProcessManager`, clears the active controller, and navigates to New Session before changing the file. The rail then reloads from storage.

## Archive screen

A pinned `Archived` entry opens a dedicated route. The screen groups archived sessions by their original project and preserves newest-first ordering.

Archived-session context actions are:

- `Restore Session`
- `Delete Session...`

Archived-project context actions are:

- `Restore Project Sessions`
- `Delete Project Sessions...`

The screen owns honest empty and error states. Restoring returns the transcript to the active rail. If its original destination already contains a file with the same name, restoration stops without overwriting either file and reports the conflict.

## Storage and application flow

`SessionLibrary` remains the owner of transcript discovery and adds archived listing and mutation operations. The archive root is a sibling of the active session root named `archived-sessions`. Archive moves preserve each transcript's bucket-relative path so restoration can return it to the exact original location.

Session operations accept a `SessionMetadata` path. Project operations accept the current group's session paths; they never derive or operate on the project's source URL. After any operation, active and archived lists are reloaded from disk so the UI reflects partial filesystem failures truthfully.

The library never overwrites a destination. It creates missing archive bucket directories as needed, invalidates affected cache entries, and emits the existing change signal. Each failed file remains at its source. Multi-session operations report the paths that failed while preserving successful moves or deletions.

`AppModel` exposes action methods and confirmation state to the rail and archive screen. File errors are sanitized into a concise alert that names the attempted action and affected session or project, without showing transcript contents.

## Components

- `RailPresentation` limits project children and emits a connected overflow item based on expanded-project IDs.
- `FloatingRailView` owns per-project disclosure state, scroll-edge state, chevron controls, and live-item context menus.
- `ArchivedSessionsView` renders archived groups and their restore/delete menus.
- `AppRoute` and `AppShellView` add the archived destination.
- `AppModel` coordinates runtime shutdown, confirmation, mutations, reloading, and errors.
- `SessionLibrary` owns active/archive file movement, restoration, deletion, listing, cache invalidation, and change notification.

Existing typography, marker geometry, spacing, context-menu construction, alert conventions, and SF Symbols remain the visual system. No new styling abstraction is introduced.

## Verification

Automated coverage will prove:

- Five-session default grouping, connected hidden-count disclosure, per-project expansion, and collapse.
- Chevron visibility at both scroll boundaries and four-row navigation targets.
- Session and project archive, archived listing, restore, destination-conflict handling, and deletion using temporary roots.
- Project actions affect only supplied transcript paths and never project source directories.
- Confirmation copy and routing for both deletion scopes.
- Open-session cleanup before archive or delete.
- Accessibility labels for overflow controls, Archived navigation, and context actions.
- Collapsed rail, expanded rail, expanded project, context-menu, confirmation, empty archive, and populated archive snapshots.

Final verification requires the full macOS test suite, a Release build, and manual inspection of the real app at short and tall window heights in collapsed and expanded rail states.

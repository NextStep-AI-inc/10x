# Session Renaming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a person rename current and inactive OMP sessions through native macOS controls, persist the name through OMP, synchronize every title surface, and make archive Restore visible.

**Architecture:** `AppModel` owns one rename request and coordinates the mutation. Managed sessions use their existing `SessionController`; cold sessions briefly use `SessionProcessManager.open`, which already reuses a handle by path, and close only the handle opened for the rename. OMP's existing `set_session_name` RPC remains the only persistence writer so its title slot, title-change history, and title index stay consistent.

**Tech Stack:** Swift 6.2, SwiftUI, Observation, Swift Testing, OmpKit RPC.

---

### Task 1: Define rename request behavior

**Files:**
- Create: `App/Sessions/SessionRenameRequest.swift`
- Test: `Tests/TenXAppTests/SessionRenameTests.swift`

- [ ] **Step 1: Write failing tests for a prefilled title and trimmed blank validation**

Assert that a request stores the session path, cwd, original title, editable draft, and returns `Enter a session name.` when the draft contains only whitespace.

- [ ] **Step 2: Run the focused test and verify the type is missing**

Run: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests/SessionRenameTests`

Expected: FAIL because `SessionRenameRequest` is undefined.

- [ ] **Step 3: Implement the value type**

Use a `SessionRenameRequest` struct with stable path identity, `metadata`, mutable `draft`, and optional `errorMessage`. Keep normalization in one computed property so UI and submit use the same trimmed value.

- [ ] **Step 4: Re-run the focused test**

Expected: PASS.

### Task 2: Coordinate managed and cold renames

**Files:**
- Modify: `App/Application/AppModel.swift`
- Modify: `App/Sessions/SessionController.swift` (parent integration)
- Test: `Tests/TenXAppTests/SessionRenameTests.swift`
- Test: `Tests/TenXAppTests/AppModelNavigationTests.swift`

- [ ] **Step 1: Write failing tests for cancel, blank save, success, and transport failure**

Assert Cancel clears the request without sending a command; blank Save keeps the request and adds the validation message; successful Save closes the request and reloads metadata; failed Save keeps the request, draft, and old visible title.

- [ ] **Step 2: Write failing lifecycle tests**

Use an injected fake process manager. Assert a retained controller receives the rename without a second open. Assert a cold session opens once, sends once, and has no retained handle after completion.

- [ ] **Step 3: Add the controller API**

Add `func rename(to name: String) async throws`. It must let any in-flight generated title finish before sending the explicit user rename, send `.setSessionName(name)`, and update `title` only after success.

- [ ] **Step 4: Add AppModel request and submit methods**

Guard with `isSessionMutationInFlight`. Prefer `managedController(for:)`; otherwise borrow an existing process-manager handle or open a cold one and close only the cold handle. On success reload active and archived metadata. On failure retain the request draft and set `Could not rename this session.`

- [ ] **Step 5: Re-run focused tests**

Expected: PASS, including no duplicate runtime and failure-state assertions.

### Task 3: Add native rename entry points and form

**Files:**
- Create: `App/Sessions/SessionRenameView.swift`
- Modify: `App/Sessions/SessionHeaderView.swift`
- Modify: `App/Sessions/ActiveSessionView.swift`
- Modify: `App/Shell/AppShellView.swift`
- Modify: `App/Shell/FloatingRailView.swift`
- Test: `Tests/TenXAppTests/SessionRenameTests.swift`

- [ ] **Step 1: Write failing presentation tests**

Assert the form exposes Rename session, Session name, Cancel, and Rename; blank validation is visible; saving disables duplicate submission; Escape cancels.

- [ ] **Step 2: Implement the modal form**

Match the existing `CornerCard` modal pattern. Autofocus and select the title field, keep the draft bound to `AppModel`, show its inline validation/save error, and keep Cancel available while idle.

- [ ] **Step 3: Add entry points**

Add `Rename Session...` before Archive in rail context menus. Make the current header title a plain native action with `Rename Session...` in its context menu and an accessibility rename action, routed through `ActiveSessionView` to `AppModel`.

- [ ] **Step 4: Re-run focused tests**

Expected: PASS.

### Task 4: Make archive Restore visible

**Files:**
- Modify: `App/Sessions/ArchivedSessionsView.swift`
- Test: `Tests/TenXAppTests/ViewSnapshotTests.swift`

- [ ] **Step 1: Add a failing archive-row accessibility/presentation check**

Assert each populated archive row exposes a visible `Restore` button as a separate accessibility element.

- [ ] **Step 2: Add the visible action**

Place a compact `Restore` button after the date. Keep the existing context-menu and named accessibility actions, and stop the row from ignoring the button's accessibility subtree.

- [ ] **Step 3: Inspect, then record affected archive snapshots**

Run the populated light and dark archive snapshot tests, inspect the rendered results for spacing and clipping, then accept only the intentional Restore-button differences.

Expected: visible Restore controls with no title/date clipping at the snapshot width.

### Task 5: Synchronization and verification

**Files:**
- Test: `Tests/TenXAppTests/SessionSearchServiceTests.swift` (parent integration if already owned elsewhere)

- [ ] **Step 1: Verify search index replacement after a rename**

Index the old title, mutate the fixture using OMP-compatible title persistence, reload metadata, then assert the old title no longer matches and the new title does.

- [ ] **Step 2: Run focused suites**

Run SessionRename, SessionController, AppModelNavigation, SessionSearchService, and populated archive snapshot tests.

Expected: PASS with no warnings.

- [ ] **Step 3: Regenerate the project**

Run: `ruby scripts/generate_xcodeproj.rb`

Expected: the new Swift source and test files are included; do not hand-edit `project.pbxproj`.

- [ ] **Step 4: Verify the Release UI**

Rename the current session from its header and an inactive session from the rail. Verify Cancel, blank validation, retained draft on an induced save failure, reopen persistence, updated search result, and visible Restore from the archive screen.


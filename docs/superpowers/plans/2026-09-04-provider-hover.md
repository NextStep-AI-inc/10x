# Provider Hover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make provider and account hover previews enlarge only the wheel under the pointer while keeping every configured provider available when usage details are pinned.

**Architecture:** Preserve the existing `ProviderAccountStackView` account identity, routing, confirmation, stable stack footprint, and per-account limit rendering. Add a small pure geometry policy for provider-wheel hover so SwiftUI renders a larger wheel inside an unchanged hit target, then reuse one complete provider selector row at the top of every pinned-details state.

**Tech Stack:** SwiftUI, Observation, Swift Testing, existing snapshot harness

**Spec:** `docs/superpowers/specs/2026-09-04-interaction-improvements.md`

## Global Constraints

- Work only in `App/Providers/ProviderAccountStackView.swift`, `App/Providers/ProviderUsageDockView.swift`, `App/Providers/ProviderUsageWheelView.swift`, `App/Providers/ProviderUsageDockLayout.swift`, and provider geometry/interaction tests.
- Preserve account routing, confirmation, capability, removal, scope, usage attribution, and focus-restoration behavior.
- Keep every configured provider visible and selectable while details or switch confirmation are pinned.
- Hover changes visual size and z-order without changing the semantic hit region; mouse leave restores the resting state.
- Every account keeps its own identity and every computable usage-limit ring.
- Escape, outside click, and the existing visible close action dismiss pinned details.
- Reduce Motion applies hover state without interpolation; activity core and outline scale with the wheel.
- Do not change dependencies, tool APIs, generated project files, `AppModel`, `SessionController`, or Settings.
- The parent owns Debug/Release builds, live reproduction, screenshots, staging, and commits.

---

### Task 1: Provider hover geometry

**Files:**
- Modify: `App/Providers/ProviderUsageDockLayout.swift`
- Test: `Tests/TenXAppTests/ProviderUsageDockLayoutTests.swift`

**Interfaces:**
- Produces: `ProviderUsageDockWheelHoverGeometry.init(restingDiameter:)`, `visualScale(isHovered:)`, `hitTargetDiameter`, and `animationDuration(reduceMotion:)`.
- Consumes: `ProviderAccountStackGeometry.minimumHitTarget` and the existing compact wheel diameter.

- [ ] **Step 1: Write failing geometry tests**

Add `hoveredProviderWheelEnlargesInsideAStableSemanticTarget()` to assert a 54-point wheel renders above scale `1`, an idle wheel renders at scale `1`, and `hitTargetDiameter` is identical in both states. Add `providerWheelHoverDoesNotAnimateWithReduceMotion()` to assert a normal animation duration and `nil` under Reduce Motion.

- [ ] **Step 2: Run the exact tests and verify RED**

Run the parent-provided focused test command with selectors `ProviderUsageDockLayoutTests/hoveredProviderWheelEnlargesInsideAStableSemanticTarget()` and `ProviderUsageDockLayoutTests/providerWheelHoverDoesNotAnimateWithReduceMotion()`.

Expected: compile failure because `ProviderUsageDockWheelHoverGeometry` does not exist.

- [ ] **Step 3: Implement the pure geometry policy**

Define the value type in `ProviderUsageDockLayout.swift`. Keep the hit target derived only from resting diameter, return `1` at rest and a restrained enlargement scale on hover, and return no animation duration when Reduce Motion is enabled.

- [ ] **Step 4: Run both selectors and verify GREEN**

Expected: both tests pass and the summary reports two tests.

### Task 2: Provider-only wheel hover

**Files:**
- Modify: `App/Providers/ProviderUsageDockView.swift`
- Test: `Tests/TenXAppTests/ProviderUsageDockFocusTests.swift`

**Interfaces:**
- Consumes: `ProviderUsageDockWheelHoverGeometry` from Task 1.
- Preserves: `ProviderUsageDockInteraction.inspectProvider(providerID:)`, account inspection, and focus restoration.

- [ ] **Step 1: Write a failing interaction-state test**

Add `providerHoverTracksOneTransientProviderAndClearsOnMouseLeave()` against a small observable hover-state helper. Assert entering OpenAI then Cursor leaves only Cursor hovered, and leaving Cursor clears the hover without changing `ProviderUsageDockInteraction.inspectedProviderID`.

- [ ] **Step 2: Run the selector and verify RED**

Run selector `ProviderUsageDockFocusTests/providerHoverTracksOneTransientProviderAndClearsOnMouseLeave()`.

Expected: compile failure because the transient hover helper does not exist.

- [ ] **Step 3: Apply hover in the existing provider button**

Track one transient provider ID in `ProviderUsageDockView`. Scale only the matching provider-only wheel, retain the unchanged semantic frame and content shape, promote its z-index during hover, and animate only when Reduce Motion is off. Keep click inspection separate from hover.

- [ ] **Step 4: Run the selector and Task 1 selectors**

Expected: all three tests pass.

### Task 3: Complete provider selector in every pinned state

**Files:**
- Modify: `App/Providers/ProviderUsageDockView.swift`
- Test: `Tests/TenXAppTests/ProviderUsageDockFocusTests.swift`

**Interfaces:**
- Produces: a single `expandedProviderSelector` used above provider details, account details, and switch confirmation.
- Consumes: the existing `accountStack`, `expandedProviderButton`, `inspect(provider:account:)`, and `inspectProvider(_:)` paths.

- [ ] **Step 1: Write a failing presentation test**

Add `pinnedSelectorKeepsEveryProviderInConnectionOrder()` using a mixed fixture with account-routing and provider-only entries. Assert the selector presentation retains every provider ID in input order rather than reducing to the inspected provider.

- [ ] **Step 2: Run the selector and verify RED**

Run selector `ProviderUsageDockFocusTests/pinnedSelectorKeepsEveryProviderInConnectionOrder()`.

Expected: compile failure because the selector presentation does not expose the complete ordered provider set.

- [ ] **Step 3: Reuse one selector above all pinned content**

Move provider selection into one row in `expandedPanel`. Render account-routing providers with their existing account stack so account identities and limits stay distinct; render provider-only entries with the hoverable provider button. Remove the provider-only and selected-account duplicate selector rows from the detail branches. Leave the existing full-screen outside target, Escape handler, close action, and routing confirmation content unchanged.

- [ ] **Step 4: Run all focused provider selectors**

Expected: geometry, hover state, pinned selector, routing, focus restoration, account stack, and ring geometry tests pass.

### Task 4: Source handoff

**Files:**
- Inspect: all files listed above

**Interfaces:**
- Produces: exact changed-file list and exact Swift Testing selectors for parent integration.

- [ ] **Step 1: Review the owned diff**

Confirm no generated project, app model, session controller, settings, dependency, or unrelated source changed. Confirm provider/account click handlers still call the original inspection and confirmation methods.

- [ ] **Step 2: Run focused tests only if the parent has not started the shared build**

Use exact function selectors and report the full test summary. Do not start duplicate Debug or Release builds.

- [ ] **Step 3: Notify the parent that source is ready**

Report new files, changed files, exact selectors, verification performed, verification deferred to the parent, and that live hover reproduction/screenshot QA remains outstanding.

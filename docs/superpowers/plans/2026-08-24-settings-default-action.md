# Settings Default Action Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Settings Reset label with the actual OMP default value, which writes that value through the ordinary setting update path when selected.

**Architecture:** OMP remains the single source of truth by adding a read-only `default` member to each safe `config list --json` entry. The macOS app parses that optional metadata, hides the action for older OMP versions and credentials, and renders the formatted value as a compact borderless action that calls `config set`.

**Tech Stack:** Bun, TypeScript 7, Swift 6, SwiftUI, Swift Testing, Xcode snapshot tests

**Spec:** `docs/superpowers/specs/2026-08-24-10x-omp-macos-gui-design.md`

## Global Constraints

- OMP schema metadata is authoritative; the macOS app must not hardcode defaults.
- Credential defaults are never emitted or displayed.
- The JSON addition is backward-compatible, and the app hides the action when `default` is absent.
- The action displays only the formatted value beside its icon, without “Default” or “Reset” visible copy.
- Clicking the action uses `omp config set KEY VALUE`, not `omp config reset KEY`.
- The control is borderless cyan with no fill, perimeter, or shadow except temporary hover feedback.

---

### Task 1: Expose safe defaults in OMP config metadata

**Files:**
- Modify: `packages/coding-agent/test/config-cli.test.ts`
- Modify: `packages/coding-agent/src/cli/config-cli.ts`
- Modify: `packages/coding-agent/CHANGELOG.md`

**Interfaces:**
- Consumes: `getDefault(path: SettingPath)` from `config/settings`.
- Produces: `omp config list --json` entries shaped as `{ value?, default?, redacted?, type, description }`, with `default` omitted for credentials and schema defaults that are `undefined`.

- [ ] **Step 1: Write the failing CLI contract test**

Set `autoResume` to `true` in an isolated CLI config directory, run `config list --json`, and assert that its entry reports `value: true` and `default: false`. Assert that a credential entry has no `default` property, protecting consumers from treating secret metadata as displayable.

- [ ] **Step 2: Run the focused test and verify RED**

```bash
bun test packages/coding-agent/test/config-cli.test.ts
```

Expected: the default-metadata assertion fails because the JSON entry has no `default` member.

- [ ] **Step 3: Add the metadata field**

In `handleList`, extend the result entry type with `default?: unknown`. For non-credential definitions, construct the entry with `default: getDefault(def.path)` alongside the current value, type, and description. Preserve the credential branch exactly except for its widened result type so it emits neither a credential value nor a default.

- [ ] **Step 4: Add the user-facing changelog entry**

Under `packages/coding-agent/CHANGELOG.md` → `## [Unreleased]` → `### Added`, add: `Exposed schema defaults in JSON config listings for settings clients.`

- [ ] **Step 5: Verify the OMP slice is GREEN**

```bash
bun test packages/coding-agent/test/config-cli.test.ts
bun check
```

Expected: the focused CLI tests and repository checks pass.

---

### Task 2: Render and apply default values in 10x Settings

**Files:**
- Modify: `Tests/TenXAppTests/SettingsCatalogTests.swift`
- Modify: `Tests/TenXAppTests/OmpConfigServiceTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Modify: `Tests/TenXAppTests/ReferenceImages/continuous-settings.png`
- Modify: `App/Settings/SettingDefinition.swift`
- Modify: `App/Settings/SettingsCatalog.swift`
- Modify: `App/Settings/SettingControlView.swift`
- Modify: `App/Settings/SettingsViewModel.swift`
- Modify: `App/Settings/OmpConfigService.swift`

**Interfaces:**
- Consumes: optional `default` metadata from `omp config list --json`.
- Produces: `SettingDefinition.defaultValue: JSONValue?` and a visible default-value action only when that value exists and the setting is not secret.
- Produces: default selection through the existing `SettingsViewModel.save(_:value:)` and `OmpConfigService.set(key:value:)` path.

- [ ] **Step 1: Write failing catalog and command tests**

Add `default` to the Settings catalog fixture, assert it becomes `definition.defaultValue`, and assert credential definitions discard both current and default values. Update the service command test to remove the reset command expectation, preserving the exact `config set` assertion.

- [ ] **Step 2: Update the snapshot fixture and record the initial visual delta**

Add representative boolean, enum, and number defaults to `SnapshotConfigRunner`. Record `continuous-settings.png` only after the app renders each default as an icon plus value with no Reset label.

- [ ] **Step 3: Run the focused app tests and verify RED**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/SettingsCatalogTests \
  -only-testing:TenXAppTests/OmpConfigServiceTests \
  -only-testing:TenXAppTests/ViewSnapshotTests test
```

Expected: compilation or expectations fail because `defaultValue` and the new visual action do not exist.

- [ ] **Step 4: Parse defaults without leaking credentials**

Add `defaultValue` to `SettingDefinition`. In `SettingsCatalog.build(from:)`, assign `nil` when `isSecret` is true and otherwise read `source["default"]`. Leave missing defaults as `nil` for backward compatibility.

- [ ] **Step 5: Replace Reset with the default-value action**

In `SettingControlView`, render the action only when `definition.defaultValue` exists. Its label is `Image(systemName: "arrow.uturn.backward")` plus the compact formatted JSON value; an empty string displays as `""`. Apply `GhostActionStyle()` and accessibility copy `Set <display label> to default <formatted value>`. On selection call `model.save(definition, value: defaultValue)`. Remove the unused reset methods from `SettingsViewModel` and `OmpConfigService`.

- [ ] **Step 6: Verify the app slice and refresh the snapshot**

```bash
RECORD_SNAPSHOTS=1 xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' -only-testing:TenXAppTests/ViewSnapshotTests/continuousSettingsSnapshot test
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' test
```

Expected: all app tests pass and the Settings snapshot shows compact cyan icon/value actions without Reset labels.

- [ ] **Step 7: Build and inspect the production app**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData clean build
```

Launch the explicit Release bundle, confirm its process survives and its window renders, then inspect the Settings snapshot and live Settings surface at common and minimum window sizes. The installed OMP 18.0.4 binary will exercise the backward-compatible no-default state until the companion OMP patch is released.

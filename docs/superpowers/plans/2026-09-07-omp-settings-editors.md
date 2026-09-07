# OMP Settings Editors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace free-text/JSON settings controls in 10x with curated dropdowns and structured editors, fed by hand-curated metadata seeded from OMP's shipped schema.

**Architecture:** A generated-then-hand-maintained `SettingMetadata` table (enum options with labels/descriptions, known array value sets, gap-fill descriptions) merges into `SettingsCatalog` at load. `SettingControlView` routes enums to a new `InlineDropdown`, records to curated full-width editors (flagship: `modelRoles`), and arrays to one of four treatments. Drift tests probe the live `omp` binary with sentinel values.

**Tech Stack:** SwiftUI, swift-testing, OmpKit (`JSONValue`), bun (seed script only).

**Spec:** `docs/superpowers/specs/2026-09-07-omp-settings-editors-design.md`

**Repo rules that apply to every task:**
- New Swift files under `App/` or `Tests/` require `ruby scripts/generate_xcodeproj.rb` before commit. Never hand-edit `project.pbxproj`.
- Test command: `xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests test`
- Single suite: append `/ClassName` to `-only-testing:TenXAppTests`
- Tests use swift-testing (`import Testing`, `@Test`, `#expect`), not XCTest.

---

### Task 1: Seed generator + generated SettingMetadata.swift

**Files:**
- Create: `scripts/seed_setting_metadata.ts`
- Create: `App/Settings/SettingMetadata.swift` (generated output, committed)

- [ ] **Step 1: Write the generator**

```ts
// Seed generator for App/Settings/SettingMetadata.swift.
// Reads the installed OMP package's settings schema and `omp config list --json`,
// then emits plain Swift data: enum options (with human labels/descriptions) and
// known array value sets. Rerun when OMP updates; SettingMetadataDriftTests flag
// drift against the installed omp binary.
//
// Usage: bun scripts/seed_setting_metadata.ts > App/Settings/SettingMetadata.swift

import { homedir } from "node:os";

const PKG = `${homedir()}/.bun/install/global/node_modules/@oh-my-pi/pi-coding-agent`;
const OMP = `${homedir()}/.bun/bin/omp`;

const { SETTINGS_SCHEMA } = await import(`${PKG}/src/config/settings-schema.ts`);
const { COMPACTION_METHOD_CHOICES } = await import(`${PKG}/src/session/compaction-methods.ts`);
const { SEARCH_PROVIDER_CHOICES } = await import(`${PKG}/src/web/search/types.ts`);
const { IMAGE_PROVIDER_CHOICES } = await import(`${PKG}/src/tools/image-providers.ts`);

const listProc = Bun.spawnSync([OMP, "config", "list", "--json"]);
const listed = JSON.parse(listProc.stdout.toString());

// Model roles OMP defines (from modelRoles' shape; not enumerated in the schema).
const MODEL_ROLES = ["default", "plan", "advisor", "smol", "commit", "designer", "slow", "task", "tiny", "vision"];

const esc = (s: string): string =>
  s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n");

const swiftOpt = (v: string, label?: string | null, detail?: string | null): string => {
  const parts = [`"${esc(v)}"`];
  if (label && label !== v) parts.push(`label: "${esc(label)}"`);
  if (detail) parts.push(`detail: "${esc(detail)}"`);
  return `SettingOption(${parts.join(", ")})`;
};

const enumLines: string[] = [];
for (const [key, def] of Object.entries(SETTINGS_SCHEMA) as [string, any][]) {
  if (def.type !== "enum") continue;
  const opts = Array.isArray(def.ui?.options) && def.ui.options.length
    ? def.ui.options.map((o: any) => swiftOpt(o.value, o.label, o.description))
    : (def.values ?? []).map((v: string) => swiftOpt(v));
  if (opts.length) {
    enumLines.push(`        "${esc(key)}": [\n            ${opts.join(",\n            ")},\n        ],`);
  }
}

const knownArrays: [string, string[]][] = [
  ["cycleOrder", MODEL_ROLES],
  ["compaction.methodOrder", COMPACTION_METHOD_CHOICES.map((c: any) => c.value)],
  ["providers.webSearchOrder", SEARCH_PROVIDER_CHOICES.map((c: any) => c.value)],
  ["providers.imageOrder", IMAGE_PROVIDER_CHOICES.map((c: any) => c.value)],
];
const arrayLines = knownArrays.map(([key, values]) =>
  `        "${esc(key)}": [${values.map((v) => `"${esc(v)}"`).join(", ")}],`);

console.log(`import Foundation

// Seeded from OMP's shipped settings schema by scripts/seed_setting_metadata.ts.
// Hand-maintain from here; SettingMetadataDriftTests flag drift against the
// installed omp binary.

struct SettingOption: Equatable {
    let value: String
    var label: String? = nil
    var detail: String? = nil
}

enum SettingMetadata {
    static let enumOptions: [String: [SettingOption]] = [
${enumLines.join("\n")}
    ]

    /// Gap-fill text for keys whose omp config list entry ships no description.
    /// OMP's own runtime description always wins when present. Hand-written;
    /// the schema documents no keys beyond what config list already reports.
    static let descriptions: [String: String] = [:]

    /// Closed value sets for array settings, where OMP's source enumerates them.
    static let knownArrayValues: [String: [String]] = [
${arrayLines.join("\n")}
    ]

    /// Array keys whose values come from the live model/provider catalog.
    static let catalogFedArrays: Set<String> = [
        "enabledModels", "modelProviderOrder", "enabledProviders", "disabledProviders",
    ]
}
`);
```

- [ ] **Step 2: Run it, verify output**

Run: `bun scripts/seed_setting_metadata.ts > App/Settings/SettingMetadata.swift`
Expected: exit 0; file contains 87 enum keys (`grep -c '": \[' App/Settings/SettingMetadata.swift` ≈ 92), ~375 `SettingOption(` entries, and the four `knownArrayValues` rows. (Verified working during planning against OMP 18.1.10.)

- [ ] **Step 3: Regenerate project and build**

Run: `ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add scripts/seed_setting_metadata.ts App/Settings/SettingMetadata.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat(settings): seed SettingMetadata from OMP schema"
```

---

### Task 2: SettingDefinition.enumOptions + catalog merge

**Files:**
- Modify: `App/Settings/SettingDefinition.swift`
- Modify: `App/Settings/SettingsCatalog.swift:14-24`
- Test: `Tests/TenXAppTests/SettingsCatalogMetadataTests.swift` (new)

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import TenXApp

struct SettingsCatalogMetadataTests {
    private func entry(_ key: String, type: String = "enum", description: String = "") -> JSONValue {
        .object(["value": .string("x"), "type": .string(type), "description": .string(description)])
    }

    @Test func curatedEnumOptionsAttachToDefinition() {
        let catalog = SettingsCatalog.build(from: .object(["followUpMode": entry("followUpMode")]))
        #expect(catalog.definition(key: "followUpMode")?.enumOptions.map(\.value) == ["all", "one-at-a-time"])
    }

    @Test func uncuratedEnumGetsNoOptions() {
        let catalog = SettingsCatalog.build(from: .object(["some.unknownEnum": entry("some.unknownEnum")]))
        #expect(catalog.definition(key: "some.unknownEnum")?.enumOptions == [])
    }

    @Test func runtimeDescriptionWinsOverCurated() {
        let catalog = SettingsCatalog.build(from: .object(["modelRoles": entry("modelRoles", type: "record", description: "OMP text")]))
        #expect(catalog.definition(key: "modelRoles")?.description == "OMP text")
    }

    @Test func curatedDescriptionFillsGap() {
        // Requires "modelRoles" to have a hand-written entry in SettingMetadata.descriptions (Task 11).
        let catalog = SettingsCatalog.build(from: .object(["modelRoles": entry("modelRoles", type: "record")]))
        #expect(catalog.definition(key: "modelRoles")?.description.isEmpty == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... -only-testing:TenXAppTests/SettingsCatalogMetadataTests test`
Expected: FAIL — `enumOptions` does not compile (property doesn't exist yet). Add the test file to the project first: `ruby scripts/generate_xcodeproj.rb`.

- [ ] **Step 3: Implement**

In `SettingDefinition.swift`, add the property (defaulted so existing constructions keep compiling):

```swift
struct SettingDefinition: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let displayLabel: String
    var value: JSONValue?
    let defaultValue: JSONValue?
    let type: SettingValueType
    let description: String
    let category: SettingsCategory
    let isSecret: Bool
    let requiresRestart: Bool
    var enumOptions: [SettingOption] = []

    var usesFullWidthEditor: Bool {
        type == .record || key == "bashInterceptor.patterns"
    }
}
```

In `SettingsCatalog.build`, merge metadata:

```swift
let runtimeDescription = source["description"]?.stringValue ?? ""
return SettingDefinition(
    key: key,
    displayLabel: displayLabel(for: key),
    value: isSecret ? nil : source["value"],
    defaultValue: isSecret ? nil : source["default"],
    type: SettingValueType(rawValue: source["type"]?.stringValue ?? "unknown"),
    description: runtimeDescription.isEmpty
        ? SettingMetadata.descriptions[key] ?? ""
        : runtimeDescription,
    category: category(for: key),
    isSecret: isSecret,
    requiresRestart: requiresRestart(key),
    enumOptions: SettingMetadata.enumOptions[key] ?? [])
```

Note: `curatedDescriptionFillsGap` stays red until Task 11 lands the hand-written descriptions. That's expected — keep it.

- [ ] **Step 4: Run tests**

Expected: first three PASS, `curatedDescriptionFillsGap` FAILS until Task 11.

- [ ] **Step 5: Commit**

```bash
git add App/Settings/SettingDefinition.swift App/Settings/SettingsCatalog.swift Tests/TenXAppTests/SettingsCatalogMetadataTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat(settings): merge curated metadata into catalog"
```

---

### Task 3: EnumPresentation + InlineDropdown + enum routing

**Files:**
- Create: `App/Settings/EnumPresentation.swift`
- Create: `App/Settings/InlineDropdown.swift`
- Modify: `App/Settings/SettingControlView.swift:66` (the `.string, .enumeration, .unknown` case)
- Test: `Tests/TenXAppTests/EnumPresentationTests.swift` (new)

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import TenXApp

struct EnumPresentationTests {
    private let options = [
        SettingOption("always-ask", label: "Always ask", detail: "read-only auto-approved"),
        SettingOption("write", label: "Write"),
        SettingOption("yolo", label: "Yolo"),
    ]

    @Test func knownValueHasNoCustomMarker() {
        let p = EnumPresentation(options: options, currentValue: "write")
        #expect(p.customValue == nil)
        #expect(p.displayText(for: "write") == "Write")
    }

    @Test func unknownValueSurfacesAsCustom() {
        let p = EnumPresentation(options: options, currentValue: "ultra")
        #expect(p.customValue == "ultra")
        #expect(p.displayText(for: "ultra") == "ultra")
    }

    @Test func emptyValueIsNotCustom() {
        #expect(EnumPresentation(options: options, currentValue: "").customValue == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails** (after `ruby scripts/generate_xcodeproj.rb`)

Expected: FAIL — `EnumPresentation` undefined.

- [ ] **Step 3: Implement EnumPresentation**

```swift
import Foundation

struct EnumPresentation: Equatable {
    let options: [SettingOption]
    let currentValue: String
    /// Non-nil when the current value is not one of the curated options.
    let customValue: String?

    init(options: [SettingOption], currentValue: String) {
        self.options = options
        self.currentValue = currentValue
        self.customValue = currentValue.isEmpty || options.contains { $0.value == currentValue }
            ? nil : currentValue
    }

    func displayText(for value: String) -> String {
        options.first { $0.value == value }?.label ?? value
    }
}
```

- [ ] **Step 4: Implement InlineDropdown** (shared by enums, record editors, array editors)

```swift
import SwiftUI

struct InlineDropdown: View {
    let options: [SettingOption]
    let current: String
    /// Shown when current is empty (e.g. "Add…" for list editors).
    var prompt: String? = nil
    var allowsOther = true
    let onSelect: (String) -> Void

    @State private var isExpanded = false
    @State private var showsOther = false
    @State private var otherDraft = ""

    private var presentation: EnumPresentation {
        EnumPresentation(options: options, currentValue: current)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(current.isEmpty ? (prompt ?? "") : presentation.displayText(for: current))
                        .font(TenXTypography.mono(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    if presentation.customValue != nil {
                        Text("custom")
                            .font(TenXTypography.mono(size: 8))
                            .foregroundStyle(TenXPalette.color(TenXPalette.yellowHex))
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(TenXPalette.color(TenXPalette.nearBlackHex))
                        .frame(height: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(prompt ?? "Value")

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    if let custom = presentation.customValue {
                        optionRow(value: custom, label: custom,
                                  detail: "Current value (not a known option)", selected: true)
                    }
                    ForEach(options, id: \.value) { option in
                        optionRow(value: option.value,
                                  label: option.label ?? option.value,
                                  detail: option.detail,
                                  selected: option.value == current)
                    }
                    if allowsOther {
                        Divider()
                        if showsOther {
                            HStack(spacing: 4) {
                                TextField("Custom value", text: $otherDraft)
                                    .textFieldStyle(.plain)
                                    .font(TenXTypography.mono(size: 11))
                                    .onSubmit(commitOther)
                                Button("Apply", action: commitOther)
                                    .buttonStyle(GhostActionStyle())
                            }
                            .padding(8)
                        } else {
                            Button {
                                showsOther = true
                            } label: {
                                Text("Other…")
                                    .font(TenXTypography.mono(size: 10))
                                    .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .background(TenXPalette.color(TenXPalette.canvasHex))
                .overlay(Rectangle().stroke(TenXPalette.color(TenXPalette.separatorHex)))
            }
        }
    }

    private func optionRow(value: String, label: String, detail: String?, selected: Bool) -> some View {
        Button {
            onSelect(value)
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded = false }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(TenXTypography.body(size: 12, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(TenXTypography.body(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .lineLimit(2)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func commitOther() {
        let value = otherDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onSelect(value)
        otherDraft = ""
        showsOther = false
        isExpanded = false
    }
}
```

- [ ] **Step 5: Route enums in SettingControlView**

Replace the `.string, .enumeration, .unknown(_)` case:

```swift
case .enumeration where !definition.enumOptions.isEmpty:
    InlineDropdown(
        options: definition.enumOptions,
        current: definition.value?.stringValue ?? "",
        onSelect: { value in
            Task { await model.save(definition, value: .string(value)) }
        })
case .string, .enumeration, .unknown(_):
    editableField(prompt: definition.isSecret ? "Secure value" : "Value") {
        await model.save(definition, value: .string(draftText))
    }
```

- [ ] **Step 6: Run tests + build**

Expected: EnumPresentationTests PASS, app builds.

- [ ] **Step 7: Commit**

```bash
git add App/Settings/EnumPresentation.swift App/Settings/InlineDropdown.swift App/Settings/SettingControlView.swift Tests/TenXAppTests/EnumPresentationTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat(settings): dropdown control for curated enums"
```

---

### Task 4: Full-width row layout

**Files:**
- Modify: `App/Settings/SettingRowView.swift:8-34`

- [ ] **Step 1: Restructure the row**

Records and the object-array render label/description/key on top, editor full-width below:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 10) {
        if definition.usesFullWidthEditor {
            metaBlock
            SettingControlView(definition: definition, model: model)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: 30) {
                metaBlock
                SettingControlView(definition: definition, model: model)
                    .frame(width: 300, alignment: .trailing)
            }
        }
        if let error = model.error(for: definition.key) {
            Text(error)
                .font(TenXTypography.mono(size: 9))
                .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
        }
    }
    .padding(.vertical, 15)
    .accessibilityElement(children: .contain)
}

private var metaBlock: some View {
    VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
            Text(definition.displayLabel)
                .font(TenXTypography.body(size: 13, weight: .semibold))
            if definition.requiresRestart {
                Text("RESTART")
                    .font(TenXTypography.mono(size: 8, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.yellowHex))
            }
        }
        if !definition.description.isEmpty {
            Text(definition.description)
                .font(TenXTypography.body(size: 11))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .fixedSize(horizontal: false, vertical: true)
        }
        Text(definition.key)
            .font(TenXTypography.mono(size: 9))
            .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
```

- [ ] **Step 2: Build, eyeball one record row in the running app**

Run: `xcodebuild ... build` then run the app, open Settings → Models → `modelRoles` (still the raw-JSON field at this point, now full-width — reverted in Task 7).

- [ ] **Step 3: Commit**

```bash
git add App/Settings/SettingRowView.swift
git commit -m "feat(settings): full-width row layout for structured editors"
```

---

### Task 5: ModelRoleValue parsing

**Files:**
- Create: `App/Settings/ModelRoleValue.swift`
- Test: `Tests/TenXAppTests/ModelRoleValueTests.swift` (new)

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import TenXApp

struct ModelRoleValueTests {
    @Test func parsesProviderModelAndEffort() {
        let v = ModelRoleValue(raw: "openai-codex/gpt-5.6-sol:max")
        #expect(v == ModelRoleValue(provider: "openai-codex", modelID: "gpt-5.6-sol", effort: "max"))
        #expect(v?.raw == "openai-codex/gpt-5.6-sol:max")
    }

    @Test func parsesWithoutEffort() {
        let v = ModelRoleValue(raw: "cursor/composer-2.5-fast")
        #expect(v == ModelRoleValue(provider: "cursor", modelID: "composer-2.5-fast", effort: nil))
        #expect(v?.raw == "cursor/composer-2.5-fast")
    }

    @Test func modelIdMayContainSlashes() {
        let v = ModelRoleValue(raw: "openrouter/google/gemini-x:high")
        #expect(v?.provider == "openrouter")
        #expect(v?.modelID == "google/gemini-x")
        #expect(v?.effort == "high")
    }

    @Test func unknownSuffixIsPartOfModelID() {
        let v = ModelRoleValue(raw: "provider/model:turbo")
        #expect(v?.modelID == "model:turbo")
        #expect(v?.effort == nil)
    }

    @Test func rejectsGarbage() {
        #expect(ModelRoleValue(raw: "noslash") == nil)
        #expect(ModelRoleValue(raw: "/model") == nil)
        #expect(ModelRoleValue(raw: "provider/") == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails** (after regenerating project)

Expected: FAIL — type undefined.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Parsed form of a modelRoles entry: "provider/model-id" with optional
/// ":effort" suffix. Model ids may contain "/" (e.g. openrouter/google/gemini-x);
/// the provider is the first path component. A ":" suffix only counts as effort
/// when it is a known effort name — otherwise it belongs to the model id.
struct ModelRoleValue: Equatable {
    var provider: String
    var modelID: String
    var effort: String?

    static let efforts = ["minimal", "low", "medium", "high", "xhigh", "max"]

    init(provider: String, modelID: String, effort: String? = nil) {
        self.provider = provider
        self.modelID = modelID
        self.effort = effort
    }

    init?(raw: String) {
        guard let slash = raw.firstIndex(of: "/") else { return nil }
        let provider = String(raw[raw.startIndex..<slash])
        var rest = String(raw[raw.index(after: slash)...])
        var effort: String? = nil
        if let colon = rest.lastIndex(of: ":") {
            let suffix = String(rest[rest.index(after: colon)...])
            if Self.efforts.contains(suffix) {
                effort = suffix
                rest = String(rest[rest.startIndex..<colon])
            }
        }
        guard !provider.isEmpty, !rest.isEmpty else { return nil }
        self.provider = provider
        self.modelID = rest
        self.effort = effort
    }

    var raw: String {
        "\(provider)/\(modelID)" + (effort.map { ":\($0)" } ?? "")
    }
}
```

- [ ] **Step 4: Run tests** — Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add App/Settings/ModelRoleValue.swift Tests/TenXAppTests/ModelRoleValueTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat(settings): model role value parsing"
```

---

### Task 6: Catalog wiring for settings

**Files:**
- Modify: `App/Settings/SettingsViewModel.swift`
- Modify: `App/Application/AppDependencies.swift:35-38` and `:52-55`

- [ ] **Step 1: Extend SettingsViewModel**

```swift
@ObservationIgnored private let catalogService: OmpModelCatalogService?
private(set) var catalogModels: [ComposerModelInfo] = []

init(service: OmpConfigService, catalog: OmpModelCatalogService? = nil) {
    self.service = service
    self.catalogService = catalog
}

func loadCatalogIfNeeded() async {
    guard catalogModels.isEmpty, let catalogService else { return }
    if let snapshot = try? await catalogService.load() {
        catalogModels = snapshot.models
    }
}
```

- [ ] **Step 2: Pass the catalog in both makeSettingsModel closures in AppDependencies**

```swift
SettingsViewModel(
    service: OmpConfigService(
        runner: OmpConfigProcessRunner(executableURL: executableURL)),
    catalog: OmpModelCatalogService(executableURL: executableURL))
```

- [ ] **Step 3: Build** — Expected: BUILD SUCCEEDED (existing tests construct `SettingsViewModel(service:)`; the defaulted parameter keeps them compiling).

- [ ] **Step 4: Commit**

```bash
git add App/Settings/SettingsViewModel.swift App/Application/AppDependencies.swift
git commit -m "feat(settings): wire model catalog into settings model"
```

---

### Task 7: ModelRolesEditor

**Files:**
- Create: `App/Settings/ModelRolesEditor.swift`
- Modify: `App/Settings/SettingControlView.swift` (record routing)
- Test: `Tests/TenXAppTests/ModelRolesEditorTests.swift` (new)

- [ ] **Step 1: Write the failing test** (serialization + ordering logic, not the view)

```swift
import Testing
import OmpKit
@testable import TenXApp

struct ModelRolesEditorTests {
    @Test func entriesFollowKnownRoleOrderThenAlphabetical() {
        let value: JSONValue = .object([
            "vision": .string("anthropic/claude-opus-4-8:xhigh"),
            "plan": .string("anthropic/claude-fable-5:max"),
            "custom-role": .string("cursor/composer-2.5-fast"),
        ])
        let entries = ModelRolesEditor.entries(from: value)
        #expect(entries.map(\.role) == ["plan", "vision", "custom-role"])
    }

    @Test func unparseableValuesAreDroppedFromEditingButPreservedOnSave() {
        // A value that fails to parse stays in the record untouched.
        let value: JSONValue = .object([
            "plan": .string("anthropic/claude-fable-5:max"),
            "weird": .string("garbage"),
        ])
        var entries = ModelRolesEditor.entries(from: value)
        entries[0].value.effort = "high"
        let object = ModelRolesEditor.jsonObject(from: entries, preserving: value)
        #expect(object["plan"] == .string("anthropic/claude-fable-5:high"))
        #expect(object["weird"] == .string("garbage"))
    }

    @Test func catalogModelsBecomeOptions() {
        let models = [ComposerModelInfo(modelID: "composer-2.5-fast", name: "Composer 2.5 Fast",
                                        provider: "cursor", api: nil, thinkingEfforts: [], requiresEffort: false)]
        let options = ModelRolesEditor.modelOptions(from: models)
        #expect(options == [SettingOption("cursor/composer-2.5-fast", label: "Composer 2.5 Fast", detail: "cursor")])
    }
}
```

Check `ComposerModelInfo`'s actual memberwise init signature in `App/Sessions/ComposerModelInfo.swift` and adjust the test's argument order to match.

- [ ] **Step 2: Run test to verify it fails** (after regenerating project)

- [ ] **Step 3: Implement ModelRolesEditor**

```swift
import SwiftUI
import OmpKit

struct ModelRoleEntry: Equatable, Identifiable {
    var id: String { role }
    var role: String
    var value: ModelRoleValue
}

struct ModelRolesEditor: View {
    let definition: SettingDefinition
    let model: SettingsViewModel

    @State private var entries: [ModelRoleEntry]

    static let knownRoles = ["default", "plan", "advisor", "smol", "commit",
                             "designer", "slow", "task", "tiny", "vision"]

    init(definition: SettingDefinition, model: SettingsViewModel) {
        self.definition = definition
        self.model = model
        _entries = State(initialValue: Self.entries(from: definition.value ?? .object([:])))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($entries) { $entry in
                HStack(spacing: 8) {
                    Text(entry.role)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
                        .frame(width: 70, alignment: .leading)
                    InlineDropdown(
                        options: Self.modelOptions(from: model.catalogModels),
                        current: "\(entry.value.provider)/\(entry.value.modelID)",
                        onSelect: { selection in
                            if let parsed = ModelRoleValue(raw: selection) {
                                entry.value.provider = parsed.provider
                                entry.value.modelID = parsed.modelID
                                entry.value.effort = nil
                                save()
                            }
                        })
                    if !effortOptions(for: entry.value).isEmpty {
                        InlineDropdown(
                            options: effortOptions(for: entry.value),
                            current: entry.value.effort ?? "",
                            prompt: "effort",
                            allowsOther: false,
                            onSelect: { effort in
                                entry.value.effort = effort.isEmpty ? nil : effort
                                save()
                            })
                        .frame(width: 90)
                    }
                    Button {
                        entries.removeAll { $0.role == entry.role }
                        save()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                    .accessibilityLabel("Remove \(entry.role)")
                }
            }
            let unused = Self.knownRoles.filter { role in !entries.contains { $0.role == role } }
            if !unused.isEmpty {
                Menu("Add role") {
                    ForEach(unused, id: \.self) { role in
                        Button(role) {
                            entries.append(ModelRoleEntry(role: role, value: defaultValue(for: role)))
                            sortEntries()
                            save()
                        }
                    }
                }
                .font(TenXTypography.body(size: 12, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
            }
            Text("Saved as a whole record; removing all rows restores OMP defaults.")
                .font(TenXTypography.body(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
        .task { await model.loadCatalogIfNeeded() }
    }

    private func defaultValue(for role: String) -> ModelRoleValue {
        // New roles start from the "default" role's model when one is set.
        if let d = entries.first(where: { $0.role == "default" })?.value { return d }
        return ModelRoleValue(provider: "", modelID: "", effort: nil)
    }

    private func effortOptions(for value: ModelRoleValue) -> [SettingOption] {
        guard let found = model.catalogModels.first(where: {
            $0.provider == value.provider && $0.modelID == value.modelID
        }), !found.thinkingEfforts.isEmpty else { return [] }
        return found.thinkingEfforts.map { SettingOption($0) }
    }

    private func sortEntries() {
        entries.sort { a, b in
            let ia = Self.knownRoles.firstIndex(of: a.role) ?? .max
            let ib = Self.knownRoles.firstIndex(of: b.role) ?? .max
            return ia == ib ? a.role < b.role : ia < ib
        }
    }

    private func save() {
        let object = Self.jsonObject(from: entries, preserving: definition.value ?? .object([:]))
        Task { await model.save(definition, value: object) }
    }

    static func entries(from value: JSONValue) -> [ModelRoleEntry] {
        let object = value.objectValue ?? [:]
        return object.compactMap { role, raw in
            raw.stringValue.flatMap(ModelRoleValue.init(raw:)).map {
                ModelRoleEntry(role: role, value: $0)
            }
        }.sorted { a, b in
            let ia = knownRoles.firstIndex(of: a.role) ?? .max
            let ib = knownRoles.firstIndex(of: b.role) ?? .max
            return ia == ib ? a.role < b.role : ia < ib
        }
    }

    /// Serializes edited entries; roles whose values never parsed are carried
    /// over from the original record so editing can't silently drop them.
    static func jsonObject(from entries: [ModelRoleEntry], preserving original: JSONValue) -> JSONValue {
        var object = original.objectValue ?? [:]
        for entry in entries {
            object[entry.role] = .string(entry.value.raw)
        }
        let editedRoles = Set(entries.map(\.role))
        let originallyParsed = Set(entries(from: original).map(\.role))
        for role in originallyParsed where !editedRoles.contains(role) {
            object[role] = nil  // parsed row was removed by the user
        }
        return .object(object)
    }

    static func modelOptions(from models: [ComposerModelInfo]) -> [SettingOption] {
        models.map { SettingOption("\($0.provider)/\($0.modelID)", label: $0.name, detail: $0.provider) }
    }
}
```

- [ ] **Step 4: Route records in SettingControlView**

Replace `case .record:` with:

```swift
case .record:
    if definition.key == "modelRoles" {
        ModelRolesEditor(definition: definition, model: model)
    } else {
        RecordSettingEditor(definition: definition, model: model,
                            valueKind: RecordSettingEditor.valueKind(for: definition.key))
    }
```

(`RecordSettingEditor` arrives in Task 8 — land Tasks 7 and 8 together before building, or temporarily route non-modelRoles records to the existing JSON field. Prefer: implement Task 8 Step 3's struct first, then build.)

- [ ] **Step 5: Run tests + build** — Expected: ModelRolesEditorTests PASS.

- [ ] **Step 6: Commit**

```bash
git add App/Settings/ModelRolesEditor.swift App/Settings/SettingControlView.swift Tests/TenXAppTests/ModelRolesEditorTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat(settings): model roles editor with catalog-fed pickers"
```

---

### Task 8: RecordSettingEditor (generic + curated variants)

**Files:**
- Create: `App/Settings/RecordSettingEditor.swift`
- Test: `Tests/TenXAppTests/RecordSettingEditorTests.swift` (new)

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import OmpKit
@testable import TenXApp

struct RecordSettingEditorTests {
    @Test func textKindSerializesStrings() {
        let object = RecordSettingEditor.jsonObject(
            from: [RecordEntry(key: "task", value: "on")], kind: .text)
        #expect(object == .object(["task": .string("on")]))
    }

    @Test func numberKindSerializesNumbers() {
        let object = RecordSettingEditor.jsonObject(
            from: [RecordEntry(key: "openai", value: "4")], kind: .number)
        #expect(object == .object(["openai": .int(4)]))
    }

    @Test func stringListKindSerializesArrays() {
        let object = RecordSettingEditor.jsonObject(
            from: [RecordEntry(key: "default", value: "openai/gpt-4o-mini, google/*")], kind: .stringList)
        #expect(object == .object(["default": .array([.string("openai/gpt-4o-mini"), .string("google/*")])]))
    }

    @Test func emptyKeysAreDropped() {
        let object = RecordSettingEditor.jsonObject(
            from: [RecordEntry(key: "", value: "x")], kind: .text)
        #expect(object == .object([:]))
    }

    @Test func valueKindAssignments() {
        #expect(RecordSettingEditor.valueKind(for: "tools.approval") == .policy)
        #expect(RecordSettingEditor.valueKind(for: "providers.maxInFlightRequests") == .number)
        #expect(RecordSettingEditor.valueKind(for: "task.agentModelOverrides") == .model)
        #expect(RecordSettingEditor.valueKind(for: "retry.fallbackChains") == .stringList)
        #expect(RecordSettingEditor.valueKind(for: "modelTags") == .text)
        #expect(RecordSettingEditor.valueKind(for: "anything.else") == .text)
    }

    @Test func stringListEntriesJoinWithCommas() {
        let value: JSONValue = .object(["default": .array([.string("a"), .string("b")])])
        #expect(RecordSettingEditor.entries(from: value, kind: .stringList)
            == [RecordEntry(key: "default", value: "a, b")])
    }
}
```

- [ ] **Step 2: Run test to verify it fails** (after regenerating project)

- [ ] **Step 3: Implement**

```swift
import SwiftUI
import OmpKit

enum RecordValueKind: Equatable {
    case text        // generic string value (also: agentAdvisor, agentPrewalk)
    case policy      // allow/prompt/deny dropdown (tools.approval)
    case number      // numeric field (providers.maxInFlightRequests)
    case model       // catalog-fed model dropdown (task.agentModelOverrides)
    case stringList  // comma-separated ordered list (retry.fallbackChains)
}

struct RecordEntry: Equatable, Identifiable {
    var id: String { key }
    var key: String
    var value: String
}

struct RecordSettingEditor: View {
    let definition: SettingDefinition
    let model: SettingsViewModel
    let valueKind: RecordValueKind

    @State private var entries: [RecordEntry]

    init(definition: SettingDefinition, model: SettingsViewModel, valueKind: RecordValueKind) {
        self.definition = definition
        self.model = model
        self.valueKind = valueKind
        _entries = State(initialValue: Self.entries(from: definition.value ?? .object([:]), kind: valueKind))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($entries) { $entry in
                HStack(spacing: 8) {
                    Text(entry.key)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
                        .frame(width: 110, alignment: .leading)
                    valueControl(for: $entry)
                    Button {
                        entries.removeAll { $0.key == entry.key }
                        save()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                    .accessibilityLabel("Remove \(entry.key)")
                }
            }
            Button("Add entry") {
                entries.append(RecordEntry(key: "key", value: ""))
            }
            .buttonStyle(GhostActionStyle())
        }
        .task { await model.loadCatalogIfNeeded() }
    }

    @ViewBuilder
    private func valueControl(for entry: Binding<RecordEntry>) -> some View {
        switch valueKind {
        case .policy:
            InlineDropdown(
                options: [SettingOption("allow"), SettingOption("prompt"), SettingOption("deny")],
                current: entry.wrappedValue.value,
                allowsOther: false,
                onSelect: { entry.wrappedValue.value = $0; save() })
            .frame(width: 130)
        case .model:
            InlineDropdown(
                options: ModelRolesEditor.modelOptions(from: model.catalogModels),
                current: entry.wrappedValue.value,
                onSelect: { entry.wrappedValue.value = $0; save() })
        case .number, .text, .stringList:
            TextField(valueKind == .stringList ? "a, b, c" : "Value", text: entry.projectedValue.value)
                .textFieldStyle(.plain)
                .font(TenXTypography.mono(size: 11))
                .padding(.vertical, 5)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(TenXPalette.color(TenXPalette.nearBlackHex)).frame(height: 1)
                }
                .onSubmit { save() }
        }
    }

    private func save() {
        let object = Self.jsonObject(from: entries, kind: valueKind)
        Task { await model.save(definition, value: object) }
    }

    static func valueKind(for key: String) -> RecordValueKind {
        switch key {
        case "tools.approval": .policy
        case "providers.maxInFlightRequests": .number
        case "task.agentModelOverrides": .model
        case "retry.fallbackChains": .stringList
        default: .text
        }
    }

    static func entries(from value: JSONValue, kind: RecordValueKind) -> [RecordEntry] {
        (value.objectValue ?? [:]).sorted { $0.key < $1.key }.map { key, raw in
            switch kind {
            case .stringList:
                RecordEntry(key: key, value: (raw.arrayValue ?? []).compactMap(\.stringValue).joined(separator: ", "))
            default:
                RecordEntry(key: key, value: raw.stringValue ?? "")
            }
        }
    }

    static func jsonObject(from entries: [RecordEntry], kind: RecordValueKind) -> JSONValue {
        var object: [String: JSONValue] = [:]
        for entry in entries where !entry.key.isEmpty {
            switch kind {
            case .number:
                if let number = Double(entry.value) {
                    object[entry.key] = number == number.rounded() ? .int(Int(number)) : .double(number)
                }
            case .stringList:
                object[entry.key] = .array(
                    entry.value.split(separator: ",").map {
                        .string($0.trimmingCharacters(in: .whitespaces))
                    })
            case .text, .policy, .model:
                object[entry.key] = .string(entry.value)
            }
        }
        return .object(object)
    }
}
```

Note: `images.urls.credentials` values are masked by the catalog already (`isSecret` strips the value); the generic editor will show empty rows for it — acceptable, secrets stay write-only via CLI.

- [ ] **Step 4: Run tests + build** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/Settings/RecordSettingEditor.swift Tests/TenXAppTests/RecordSettingEditorTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat(settings): structured record editors"
```

---

### Task 9: ObjectArraySettingEditor (bashInterceptor.patterns)

**Files:**
- Create: `App/Settings/ObjectArraySettingEditor.swift`
- Modify: `App/Settings/SettingControlView.swift` (array routing)
- Test: `Tests/TenXAppTests/ObjectArraySettingEditorTests.swift` (new)

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import OmpKit
@testable import TenXApp

struct ObjectArraySettingEditorTests {
    @Test func roundTripsInterceptorPatterns() {
        let value: JSONValue = .array([
            .object(["pattern": .string("^\\s*cat\\s+"), "tool": .string("read"), "message": .string("Use read")]),
        ])
        let entries = ObjectArraySettingEditor.interceptorEntries(from: value)
        #expect(entries.count == 1)
        #expect(entries[0].pattern == "^\\s*cat\\s+")
        #expect(ObjectArraySettingEditor.jsonArray(from: entries) == value)
    }

    @Test func rejectsBadRegex() {
        #expect(ObjectArraySettingEditor.isValidPattern("[unclosed") == false)
        #expect(ObjectArraySettingEditor.isValidPattern("^ok$") == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails** (after regenerating project)

- [ ] **Step 3: Implement**

```swift
import SwiftUI
import OmpKit

struct InterceptorPatternEntry: Equatable, Identifiable {
    let id: UUID = UUID()
    var pattern: String
    var tool: String
    var message: String
}

/// Structured editor for bashInterceptor.patterns — the one array-of-objects
/// setting. Each entry is a card with labeled pattern/tool/message fields.
struct ObjectArraySettingEditor: View {
    let definition: SettingDefinition
    let model: SettingsViewModel

    @State private var entries: [InterceptorPatternEntry]

    private static let toolOptions = ["read", "bash", "write", "edit", "grep", "glob"]
        .map { SettingOption($0) }

    init(definition: SettingDefinition, model: SettingsViewModel) {
        self.definition = definition
        self.model = model
        _entries = State(initialValue: Self.interceptorEntries(from: definition.value ?? .array([])))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($entries) { $entry in
                VStack(spacing: 4) {
                    fieldRow(label: "PATTERN", text: $entry.pattern,
                             invalid: !Self.isValidPattern(entry.pattern))
                    HStack(spacing: 8) {
                        Text("TOOL")
                            .font(TenXTypography.mono(size: 9))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            .frame(width: 56, alignment: .leading)
                        InlineDropdown(
                            options: Self.toolOptions,
                            current: entry.tool,
                            onSelect: { entry.tool = $0; save() })
                        .frame(width: 140)
                        Spacer()
                        Button {
                            entries.removeAll { $0.id == entry.id }
                            save()
                        } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                        .accessibilityLabel("Remove pattern")
                    }
                    fieldRow(label: "MESSAGE", text: $entry.message, invalid: false)
                }
                .padding(8)
                .overlay(Rectangle().stroke(TenXPalette.color(TenXPalette.separatorHex)))
            }
            Button("Add pattern") {
                entries.append(InterceptorPatternEntry(pattern: "", tool: "read", message: ""))
            }
            .buttonStyle(GhostActionStyle())
        }
    }

    private func fieldRow(label: String, text: Binding<String>, invalid: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(TenXTypography.mono(size: 9))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .frame(width: 56, alignment: .leading)
            TextField(label, text: text)
                .textFieldStyle(.plain)
                .font(TenXTypography.mono(size: 10))
                .padding(.vertical, 3)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(invalid
                              ? TenXPalette.color(TenXPalette.signalRedHex)
                              : TenXPalette.color(TenXPalette.nearBlackHex))
                        .frame(height: 1)
                }
                .onSubmit { if !invalid { save() } }
        }
    }

    private func save() {
        Task { await model.save(definition, value: Self.jsonArray(from: entries)) }
    }

    static func interceptorEntries(from value: JSONValue) -> [InterceptorPatternEntry] {
        (value.arrayValue ?? []).compactMap { item in
            guard let object = item.objectValue,
                  let pattern = object["pattern"]?.stringValue else { return nil }
            return InterceptorPatternEntry(
                pattern: pattern,
                tool: object["tool"]?.stringValue ?? "read",
                message: object["message"]?.stringValue ?? "")
        }
    }

    static func jsonArray(from entries: [InterceptorPatternEntry]) -> JSONValue {
        .array(entries.map {
            .object(["pattern": .string($0.pattern),
                     "tool": .string($0.tool),
                     "message": .string($0.message)])
        })
    }

    static func isValidPattern(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }
}
```

Route in SettingControlView's `.array` case:

```swift
case .array:
    if definition.key == "bashInterceptor.patterns" {
        ObjectArraySettingEditor(definition: definition, model: model)
    } else if let known = SettingMetadata.knownArrayValues[definition.key] {
        KnownSetArrayEditor(definition: definition, model: model, knownValues: known)
    } else if SettingMetadata.catalogFedArrays.contains(definition.key) {
        KnownSetArrayEditor(definition: definition, model: model, knownValues: catalogValues)
    } else {
        arrayEditor
    }
```

(`KnownSetArrayEditor` arrives in Task 10 — land 9 and 10 together before building, or temporarily keep `arrayEditor` for the other branches.)

- [ ] **Step 4: Run tests + build** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/Settings/ObjectArraySettingEditor.swift App/Settings/SettingControlView.swift Tests/TenXAppTests/ObjectArraySettingEditorTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat(settings): mini-form editor for bash interceptor patterns"
```

---

### Task 10: KnownSetArrayEditor (+ catalog-fed lists)

**Files:**
- Create: `App/Settings/KnownSetArrayEditor.swift`
- Test: `Tests/TenXAppTests/KnownSetArrayEditorTests.swift` (new)

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import OmpKit
@testable import TenXApp

struct KnownSetArrayEditorTests {
    @Test func remainingValuesExcludeCurrentItems() {
        let remaining = KnownSetArrayEditor.remaining(known: ["a", "b", "c"], items: ["b"])
        #expect(remaining == ["a", "c"])
    }

    @Test func moveUpSwapsNeighbors() {
        #expect(KnownSetArrayEditor.movingUp(["a", "b", "c"], index: 1) == ["b", "a", "c"])
        #expect(KnownSetArrayEditor.movingUp(["a", "b"], index: 0) == ["a", "b"])
    }

    @Test func serializesToStringArray() {
        #expect(KnownSetArrayEditor.jsonArray(from: ["smol", "default"])
            == .array([.string("smol"), .string("default")]))
    }

    @Test func catalogValuesAreSelectors() {
        let models = [ComposerModelInfo(modelID: "m1", name: "M1", provider: "p1",
                                        api: nil, thinkingEfforts: [], requiresEffort: false),
                      ComposerModelInfo(modelID: "m2", name: "M2", provider: "p2",
                                        api: nil, thinkingEfforts: [], requiresEffort: false)]
        #expect(KnownSetArrayEditor.modelSelectors(from: models) == ["p1/m1", "p2/m2"])
        #expect(KnownSetArrayEditor.providerIDs(from: models) == ["p1", "p2"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails** (after regenerating project)

- [ ] **Step 3: Implement**

```swift
import SwiftUI
import OmpKit

/// Reorderable list editor for arrays with a closed value set (cycleOrder,
/// compaction.methodOrder, …) or values fed by the live catalog
/// (enabledModels, disabledProviders, …). ponytail: up/down buttons instead
/// of drag-and-drop; upgrade path is DragGesture if reordering feels cramped.
struct KnownSetArrayEditor: View {
    let definition: SettingDefinition
    let model: SettingsViewModel
    let knownValues: [String]

    @State private var items: [String]

    init(definition: SettingDefinition, model: SettingsViewModel, knownValues: [String]) {
        self.definition = definition
        self.model = model
        self.knownValues = knownValues
        _items = State(initialValue: (definition.value?.arrayValue ?? []).compactMap(\.stringValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 6) {
                    Text(item)
                        .font(TenXTypography.mono(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    Spacer()
                    Button {
                        items = Self.movingUp(items, index: index)
                        save()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(index == 0)
                    Button {
                        items = Self.movingUp(items, index: index + 1)
                        save()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(index == items.count - 1)
                    Button {
                        items.remove(at: index)
                        save()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                    .accessibilityLabel("Remove \(item)")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
            }
            let remaining = Self.remaining(known: knownValues, items: items)
            if !remaining.isEmpty {
                InlineDropdown(
                    options: remaining.map { SettingOption($0) },
                    current: "",
                    prompt: "Add…",
                    allowsOther: true,
                    onSelect: { value in
                        items.append(value)
                        save()
                    })
            }
        }
        .frame(maxWidth: 290)
        .task { await model.loadCatalogIfNeeded() }
    }

    private func save() {
        Task { await model.save(definition, value: Self.jsonArray(from: items)) }
    }

    static func remaining(known: [String], items: [String]) -> [String] {
        known.filter { !items.contains($0) }
    }

    static func movingUp(_ items: [String], index: Int) -> [String] {
        var copy = items
        guard copy.indices.contains(index), index > 0 else { return copy }
        copy.swapAt(index, index - 1)
        return copy
    }

    static func jsonArray(from items: [String]) -> JSONValue {
        .array(items.map { .string($0) })
    }

    static func modelSelectors(from models: [ComposerModelInfo]) -> [String] {
        models.map { "\($0.provider)/\($0.modelID)" }
    }

    static func providerIDs(from models: [ComposerModelInfo]) -> [String] {
        Array(Set(models.map(\.provider))).sorted()
    }
}
```

For catalog-fed keys, `catalogValues` in the SettingControlView routing (Task 9 Step 3) is:

```swift
var catalogValues: [String] {
    switch definition.key {
    case "enabledModels", "modelProviderOrder":
        KnownSetArrayEditor.modelSelectors(from: model.catalogModels)
    default: // enabledProviders, disabledProviders
        KnownSetArrayEditor.providerIDs(from: model.catalogModels)
    }
}
```

**Verify during implementation:** the exact selector format `enabledModels` expects (`provider/model-id` vs bare id) by running `omp config set enabledModels '["__sentinel__"]'` and reading the error. If OMP wants a different shape, adjust `modelSelectors` accordingly; if it accepts anything, keep selectors.

- [ ] **Step 4: Run tests + build** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/Settings/KnownSetArrayEditor.swift Tests/TenXAppTests/KnownSetArrayEditorTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "feat(settings): known-set and catalog-fed array editors"
```

---

### Task 11: Hand-written gap-fill descriptions

**Files:**
- Modify: `App/Settings/SettingMetadata.swift` (the `descriptions` table only — do not regenerate)

- [ ] **Step 1: Fill in the user-facing subset**

Write terse, factual descriptions for the keys a user plausibly opens. Start with exactly these (the rest of the 124 stay blank — internal keys):

```swift
static let descriptions: [String: String] = [
    "modelRoles": "Which model OMP uses for each internal job (plan, advisor, smol, …). Values are provider/model-id with an optional :effort suffix.",
    "modelTags": "Free-form tags attached to model selectors, used by routing rules.",
    "cycleOrder": "Model roles the cycle keybinding rotates through, in order.",
    "enabledModels": "Models offered in the composer picker. Empty means all available models.",
    "modelProviderOrder": "Provider priority when the same model is reachable through several providers.",
    "enabledProviders": "Providers OMP may use. Empty means all connected providers.",
    "disabledProviders": "Providers OMP must not use, even if connected.",
    "shellPath": "Shell OMP uses for bash tool calls when none is inherited.",
    "extensions": "Extension identifiers OMP loads at startup.",
    "disabledExtensions": "Extensions to skip loading.",
    "statusLine.leftSegments": "Status line segments rendered left of the prompt, in order.",
    "statusLine.rightSegments": "Status line segments rendered right of the prompt, in order.",
    "task.agentModelOverrides": "Per-agent model overrides; beats modelRoles for that agent.",
    "task.agentAdvisor": "Per-agent advisor participation (on/off-style values).",
    "task.agentPrewalk": "Per-agent prewalk configuration.",
    "model.toolCallLoopGuard.exemptTools": "Tools exempt from the repeated-tool-call loop guard.",
]
```

- [ ] **Step 2: Run the Task 2 test that was red**

Run: `xcodebuild ... -only-testing:TenXAppTests/SettingsCatalogMetadataTests test`
Expected: all four PASS, including `curatedDescriptionFillsGap`.

- [ ] **Step 3: Commit**

```bash
git add App/Settings/SettingMetadata.swift
git commit -m "feat(settings): hand-written descriptions for undocumented keys"
```

---

### Task 12: Drift tests

**Files:**
- Create: `Tests/TenXAppTests/SettingMetadataDriftTests.swift`

- [ ] **Step 1: Write the test**

```swift
import Foundation
import Testing
@testable import TenXApp

/// Opt-in drift check for the hand-curated SettingMetadata table against the
/// installed omp binary. Every probe fails by construction, so the user's
/// config is never mutated. Run with OMP_DRIFT_TESTS=1.
///
/// Mechanism (verified against OMP 18.1.10):
/// - `omp config set <enum-key> <sentinel>` exits 1, stderr lists "Valid values: …"
/// - `omp config set <unknown-key> x` exits 1 with "Unknown setting"
struct SettingMetadataDriftTests {
    struct Result { let exitCode: Int32; let stdout: String; let stderr: String }

    static let ompPath: String? = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [home.appending(path: ".bun/bin/omp").path,
                          "/opt/homebrew/bin/omp", "/usr/local/bin/omp"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    static func run(_ arguments: [String]) throws -> Result {
        let omp = try #require(ompPath, "omp binary not installed")
        let process = Process()
        process.executableURL = URL(filePath: omp)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return Result(exitCode: process.terminationStatus,
                      stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                      stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OMP_DRIFT_TESTS"] == "1"))
    func curatedEnumOptionsMatchOmp() async throws {
        for (key, options) in SettingMetadata.enumOptions.sorted(by: { $0.key < $1.key }) {
            let result = try Self.run(["config", "set", key, "__10x_drift_sentinel__"])
            #expect(result.exitCode != 0, "\(key): sentinel set unexpectedly succeeded")
            guard !result.stderr.contains("Unknown setting") else {
                Issue.record("\(key): no longer a known OMP setting")
                continue
            }
            guard let range = result.stderr.range(of: "Valid values: ") else {
                Issue.record("\(key): no Valid values list in error — \(result.stderr)")
                continue
            }
            let listed = result.stderr[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: ", ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            #expect(listed == options.map(\.value),
                    "\(key): OMP has \(listed), curated table has \(options.map(\.value))")
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OMP_DRIFT_TESTS"] == "1"))
    func curatedKeysStillExist() async throws {
        let result = try Self.run(["config", "list", "--json"])
        #expect(result.exitCode == 0)
        let listed = try JSONDecoder().decode(JSONValue.self, from: Data(result.stdout.utf8))
        let keys = Set(listed.objectValue?.keys ?? [:].keys)
        let curated = SettingMetadata.enumOptions.keys
            + SettingMetadata.knownArrayValues.keys
            + SettingMetadata.catalogFedArrays
            + SettingMetadata.descriptions.keys
        for key in curated {
            #expect(keys.contains(key), "\(key): curated but no longer reported by omp config list")
        }
    }
}
```

Serial runtime is ~60–90s for 87 enum probes — acceptable for an opt-in lane.

- [ ] **Step 2: Run the drift lane**

Run: `OMP_DRIFT_TESTS=1 xcodebuild ... -only-testing:TenXAppTests/SettingMetadataDriftTests test`
Expected: PASS (the table was seeded from this exact OMP build). Also run without the env var: both tests SKIP.

- [ ] **Step 3: Commit**

```bash
git add Tests/TenXAppTests/SettingMetadataDriftTests.swift 10x.xcodeproj/project.pbxproj
git commit -m "test(settings): opt-in drift tests for curated metadata"
```

---

### Task 13: Full verification

- [ ] **Step 1: Full test suite**

Run: `xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests test`
Expected: all PASS (drift tests skipped without the env var).

- [ ] **Step 2: Manual pass in the running app**

Build and run; open Settings. Verify against the approved mockups (`.superpowers/brainstorm/`):
- An enum (e.g. Tools → Tool Approval Mode) shows the dropdown with labels/descriptions; Other… reveals the text field.
- Models → Model Roles shows the full-width editor; changing a role's model saves (check `omp config get modelRoles`).
- A record (Interaction → Tool Approval Policies) adds/removes rows.
- Bash → Bash Interceptor Patterns edits cards; an invalid regex shows the red underline and does not save.
- Search finds a gap-fill description (e.g. "cycle keybinding").

- [ ] **Step 3: Commit any fixes from the manual pass**

---

## Self-review notes

- Spec coverage: §1 metadata (Task 1–2), §2 enum control (Task 3), §3 records (Tasks 4–8), §4 arrays (Tasks 9–10), descriptions (Task 11), drift tests (Task 12), verification (Task 13). Non-goals respected: no tab/group adoption, no runtime schema parsing, booleans/numbers/strings untouched.
- Type names used consistently: `SettingOption`, `SettingMetadata.{enumOptions,descriptions,knownArrayValues,catalogFedArrays}`, `EnumPresentation`, `InlineDropdown`, `ModelRoleValue`, `ModelRoleEntry`, `ModelRolesEditor.{entries,jsonObject,modelOptions}`, `RecordValueKind`, `RecordEntry`, `RecordSettingEditor.{valueKind,entries,jsonObject}`, `InterceptorPatternEntry`, `ObjectArraySettingEditor.{interceptorEntries,jsonArray,isValidPattern}`, `KnownSetArrayEditor.{remaining,movingUp,jsonArray,modelSelectors,providerIDs}`.
- Tasks 7/8 and 9/10 cross-reference (routing lands before the routed types); each pair should be built together or routed temporarily to existing controls.

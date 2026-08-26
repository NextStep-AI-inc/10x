# Composer Session Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the shared composer footer’s Model, Thinking, and Fast controls real for new and active sessions, backed by OMP RPC and config (no app-side defaults).

**Architecture:** A `@MainActor` `ComposerControlsModel` loads the model catalog and current selection through a no-session RPC client, persists new-session model/thinking defaults through `OmpConfigService`, and applies live `set_*` commands on an active `SessionController`. `ComposerSessionControlsView` replaces the inert footer stubs in both composers. Spawn uses `--provider` / `--model` / `--thinking`; Fast is applied post-open via `set_fast_mode`.

**Tech Stack:** Swift 6.1, SwiftUI, Observation, Swift Testing, OmpKit RPC, macOS 15+, existing `GhostActionStyle` / `OmpConfigService` / provider auth list

**Spec:** `docs/superpowers/specs/2026-08-25-composer-session-controls-design.md`

## Global Constraints

- Preserve compatibility with OMP 18.0.4+. Do not require an OMP change.
- Work on `main` (explicit quick-iteration exception from the spec).
- No UserDefaults for model/thinking/fast. Defaults come from and write to OMP config.
- Model menu: authenticated providers only, flat list, no search.
- Fast mode is `set_fast_mode` (priority service tier), not the `-fast` model id suffix.
- Active-session model changes must not rewrite `modelRoles`.
- Persist `modelRoles` by reading the full object, updating `default`, and writing the whole object (`omp config set modelRoles.default` is rejected by OMP).
- User-facing copy: factual, compact, no em dashes, no stack traces or raw protocol dumps.
- After every new App/Tests/OmpKit source file: `ruby scripts/generate_xcodeproj.rb` before `xcodebuild`.
- Do not mutate the user’s real OMP defaults during automated tests (fake runners / in-memory fakes only).

## File Map

### OmpKit

- `OmpKit/Sources/OmpKit/Wire/RpcCommand.swift` — add `setFastMode(enabled:)`
- `OmpKit/Sources/OmpKit/RpcClient.swift` — optional `provider` / `model` / `thinking` on `RpcClientConfiguration.resolvedArguments`
- `OmpKit/Sources/OmpKit/SessionProcessManager.swift` — `openNew` accepts optional spawn selection
- `OmpKit/Tests/OmpKitTests/CommandEncodingTests.swift` — `set_fast_mode` envelope
- `OmpKit/Tests/OmpKitTests/RpcClientTests.swift` — argv ordering for spawn flags

### Catalog + presentation

- `App/Sessions/ComposerModelInfo.swift` — decoded catalog model + thinking metadata
- `App/Sessions/ComposerControlsPresentation.swift` — filter authenticated models, thinking options, fast visibility, role string encode/decode
- `App/Sessions/OmpModelCatalogService.swift` — no-session `get_state` + `get_available_models`
- `App/Sessions/ComposerDefaultPersisting.swift` — protocol + `OmpComposerDefaultStore` wrapping `OmpConfigService`

### Feature model + session bridge

- `App/Sessions/ComposerControlsModel.swift` — selection state, menus, persist vs live apply
- `App/Sessions/SessionController.swift` — `setModel` / `setThinkingLevel` / `setFastMode`; `openNew` takes selection; apply fast after open
- `App/Application/AppDependencies.swift` — factory for `ComposerControlsModel`
- `App/Application/AppModel.swift` — own the model; seed on install / new session; pass selection into `startNewSession`

### UI

- `App/Sessions/ComposerSessionControlsView.swift` — Model / Thinking / Fast ghost controls
- `App/Sessions/ComposerView.swift` — replace inert Model/Thinking stubs; keep Local stub; embed shared controls
- `App/Sessions/NewSessionView.swift` — pass `composerControls` into `ComposerView`

### Tests

- `Tests/TenXAppTests/ComposerControlsPresentationTests.swift`
- `Tests/TenXAppTests/OmpModelCatalogServiceTests.swift`
- `Tests/TenXAppTests/ComposerDefaultStoreTests.swift`
- `Tests/TenXAppTests/ComposerControlsModelTests.swift`
- `Tests/TenXAppTests/SessionControllerComposerControlsTests.swift` (or extend `SessionControllerTests.swift`)
- `Tests/TenXAppTests/ViewSnapshotTests.swift` + reference images for Fast present/absent

---

### Task 1: OmpKit `set_fast_mode` + spawn argv flags

**Files:**
- Modify: `OmpKit/Sources/OmpKit/Wire/RpcCommand.swift`
- Modify: `OmpKit/Sources/OmpKit/RpcClient.swift`
- Modify: `OmpKit/Sources/OmpKit/SessionProcessManager.swift`
- Modify: `OmpKit/Tests/OmpKitTests/CommandEncodingTests.swift`
- Modify: `OmpKit/Tests/OmpKitTests/RpcClientTests.swift`
- Modify: `OmpKit/Tests/OmpKitTests/ProcessManagerTests.swift`

**Interfaces:**
- Produces: `RpcCommand.setFastMode(enabled: Bool)`
- Produces: `RpcClientConfiguration.provider: String?`, `.model: String?`, `.thinking: String?` inserted into `resolvedArguments` after `--mode rpc` / `--no-title` and before resume/no-session flags, matching port-spec order: `--provider`, `--model`, `--thinking`
- Produces: `SessionProcessManager.openNew(projectDirectory:provider:model:thinking:)` with optional String args defaulting to nil

- [ ] **Step 1: Write failing command + argv tests**

```swift
@Test func setFastModeEncodesEnabledBool() throws {
    let obj = try json(try RpcCommand.setFastMode(enabled: false).encodedLine(id: "req_fast"))
    #expect(obj["type"] as? String == "set_fast_mode")
    #expect(obj["enabled"] as? Bool == false)
}

@Test func spawnFlagsFollowProviderModelThinkingOrder() {
    var cfg = RpcClientConfiguration()
    cfg.provider = "anthropic"
    cfg.model = "claude-opus-4-8"
    cfg.thinking = "high"
    cfg.noSession = true
    #expect(cfg.resolvedArguments == [
        "--mode", "rpc", "--no-title",
        "--provider", "anthropic",
        "--model", "claude-opus-4-8",
        "--thinking", "high",
        "--no-session",
    ])
}
```

- [ ] **Step 2: Run OmpKit tests to verify failure**

Run: `cd OmpKit && swift test --filter setFastModeEncodesEnabledBool`
Expected: FAIL (method missing)

- [ ] **Step 3: Implement command factory + configuration fields**

Add to `RpcCommand`:

```swift
public static func setFastMode(enabled: Bool) -> RpcCommand {
    RpcCommand(type: "set_fast_mode", fields: ["enabled": .bool(enabled)])
}
```

Extend `RpcClientConfiguration`:

```swift
public var provider: String?
public var model: String?
public var thinking: String?
```

Update `resolvedArguments` (non-raw path) to append provider/model/thinking after `--no-title` and before `-r` / `--no-session`.

Update `openNew` to accept optional `provider`/`model`/`thinking` and assign them onto the configuration before `start()`.

- [ ] **Step 4: Run OmpKit tests**

Run: `cd OmpKit && swift test --filter 'setFastModeEncodesEnabledBool|spawnFlagsFollowProviderModelThinkingOrder|realOmpArgvIsBuiltCorrectly'`
Expected: PASS (update `realOmpArgvIsBuiltCorrectly` only if expectations change)

- [ ] **Step 5: Commit**

```bash
git add OmpKit
git commit -m "feat(ompkit): add set_fast_mode and spawn model flags"
```

---

### Task 2: Model info + pure presentation helpers

**Files:**
- Create: `App/Sessions/ComposerModelInfo.swift`
- Create: `App/Sessions/ComposerControlsPresentation.swift`
- Create: `Tests/TenXAppTests/ComposerControlsPresentationTests.swift`

**Interfaces:**
- Produces:

```swift
struct ComposerModelInfo: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let provider: String
    let api: String?
    let thinkingEfforts: [String]
    let requiresEffort: Bool
}

enum ComposerControlsPresentation {
    static func authenticatedModels(
        catalog: [ComposerModelInfo],
        authenticatedProviderIDs: Set<String>
    ) -> [ComposerModelInfo]

    static func thinkingOptions(for model: ComposerModelInfo?) -> [String]
    // returns ["auto"] + efforts when efforts non-empty; empty when no thinking

    static func supportsFastMode(model: ComposerModelInfo?) -> Bool
    // true for openai / openai-codex / anthropic-messages api / google(+vertex);
    // false for cursor and unknown

    static func roleDefaultValue(provider: String, modelID: String) -> String
    // "\(provider)/\(modelID)"

    static func parseRoleDefault(_ value: String) -> (provider: String, modelID: String)?
}
```

- [ ] **Step 1: Write failing presentation tests**

```swift
@Test func authenticatedModelsKeepOnlySignedInProviders() {
    let catalog = [
        ComposerModelInfo(id: "a", name: "A", provider: "anthropic", api: "anthropic-messages", thinkingEfforts: ["high"], requiresEffort: false),
        ComposerModelInfo(id: "b", name: "B", provider: "cursor", api: "cursor-agent", thinkingEfforts: [], requiresEffort: false),
    ]
    let filtered = ComposerControlsPresentation.authenticatedModels(
        catalog: catalog,
        authenticatedProviderIDs: ["anthropic"])
    #expect(filtered.map(\.id) == ["a"])
}

@Test func thinkingOptionsIncludeAutoWhenEffortsExist() {
    let model = ComposerModelInfo(id: "m", name: "M", provider: "anthropic", api: nil, thinkingEfforts: ["low", "high"], requiresEffort: false)
    #expect(ComposerControlsPresentation.thinkingOptions(for: model) == ["auto", "low", "high"])
    #expect(ComposerControlsPresentation.thinkingOptions(for: nil).isEmpty)
}

@Test func supportsFastModeMatchesOMPServiceTierFamilies() {
    let anthropic = ComposerModelInfo(id: "x", name: "X", provider: "amazon-bedrock", api: "anthropic-messages", thinkingEfforts: [], requiresEffort: false)
    let cursor = ComposerModelInfo(id: "y", name: "Y", provider: "cursor", api: "cursor-agent", thinkingEfforts: [], requiresEffort: false)
    let codex = ComposerModelInfo(id: "z", name: "Z", provider: "openai-codex", api: nil, thinkingEfforts: [], requiresEffort: false)
    #expect(ComposerControlsPresentation.supportsFastMode(model: anthropic))
    #expect(!ComposerControlsPresentation.supportsFastMode(model: cursor))
    #expect(ComposerControlsPresentation.supportsFastMode(model: codex))
}
```

- [ ] **Step 2: Run test to verify failure**

Run:
```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/ComposerControlsPresentationTests test
```
Expected: FAIL (types missing)

- [ ] **Step 3: Implement types + helpers**

Keep `supportsFastMode` aligned with OMP’s `serviceTierFamily` rules from `@oh-my-pi/pi-ai` (openrouter namespace prefixes optional; include if cheap).

- [ ] **Step 4: Re-run presentation tests**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/ComposerModelInfo.swift App/Sessions/ComposerControlsPresentation.swift Tests/TenXAppTests/ComposerControlsPresentationTests.swift 10x.xcodeproj
git commit -m "feat(sessions): add composer model presentation helpers"
```

---

### Task 3: No-session catalog service

**Files:**
- Create: `App/Sessions/OmpModelCatalogService.swift`
- Create: `Tests/TenXAppTests/OmpModelCatalogServiceTests.swift`

**Interfaces:**
- Consumes: `ProviderRPCClient` (reuse protocol from `ProviderManaging.swift`) or a narrow `ModelCatalogRPCClient` with `start` / `send` / `shutdown`
- Produces:

```swift
struct ComposerCatalogSnapshot: Equatable, Sendable {
    let models: [ComposerModelInfo]
    let selected: ComposerModelInfo?
    let thinkingLevel: String?
    let fastModeEnabled: Bool
    let fastModeActive: Bool
}

actor OmpModelCatalogService {
    init(executableURL: URL)
    init(clientFactory: ...) // test seam
    func load() async throws -> ComposerCatalogSnapshot
    func shutdown() async
}
```

Decode `get_available_models` → `data.models[]` with keys `id`, `name`, `provider`, `api`, `thinking.efforts`, `thinking.requiresEffort`.
Decode `get_state` → `data.model`, `thinkingLevel`, `fastModeEnabled`, `fastModeActive`.

- [ ] **Step 1: Write failing service test with fake RPC client**

Mirror `FakeProviderRPCClient` patterns from `ProviderTestFixtures.swift`: scripted responses for `get_state` and `get_available_models`.

```swift
@Test func catalogServiceDecodesStateAndModels() async throws {
    let fake = FakeProviderRPCClient(responses: [stateResponse, modelsResponse])
    let service = OmpModelCatalogService(clients: [fake]) // or factory returning fake
    let snapshot = try await service.load()
    #expect(snapshot.selected?.id == "claude-opus-4-8")
    #expect(snapshot.models.count == 2)
    #expect(snapshot.thinkingLevel == "high")
    #expect(snapshot.fastModeEnabled == false)
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `ruby scripts/generate_xcodeproj.rb && xcodebuild ... -only-testing:TenXAppTests/OmpModelCatalogServiceTests test`
Expected: FAIL

- [ ] **Step 3: Implement `OmpModelCatalogService`**

Use `noSession: true` configuration. Own a single client lifecycle (start once per `load` or keep warm like providers — YAGNI: start, fetch both commands, leave client for reuse until `shutdown`). Prefer the simpler start-per-load if concurrency code threatens size; document with `ponytail:` if keeping a long-lived client.

- [ ] **Step 4: Re-run service tests**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/OmpModelCatalogService.swift Tests/TenXAppTests/OmpModelCatalogServiceTests.swift 10x.xcodeproj
git commit -m "feat(sessions): load composer model catalog via no-session RPC"
```

---

### Task 4: Persist OMP model/thinking defaults

**Files:**
- Create: `App/Sessions/ComposerDefaultPersisting.swift`
- Create: `Tests/TenXAppTests/ComposerDefaultStoreTests.swift`

**Interfaces:**
- Produces:

```swift
protocol ComposerDefaultPersisting: Sendable {
    func setDefaultModel(provider: String, modelID: String) async throws
    func setDefaultThinkingLevel(_ level: String) async throws
}

struct OmpComposerDefaultStore: ComposerDefaultPersisting {
    init(config: OmpConfigService)
}
```

Implementation for model:

1. `list()` or get current settings object for `modelRoles`
2. Read existing `.objectValue` map (or empty)
3. Set `default` string to `ComposerControlsPresentation.roleDefaultValue(...)`
4. `set(key: "modelRoles", value: .object(updated))`

Thinking: `set(key: "defaultThinkingLevel", value: .string(level))`

- [ ] **Step 1: Write failing store tests with `FakeConfigRunner`**

```swift
@Test func storeUpdatesOnlyModelRolesDefaultKey() async throws {
    let runner = RecordingConfigRunner(initialListJSON: """
    {"modelRoles":{"value":{"default":"cursor/old","commit":"cursor/c"},"type":"object"}}
    """)
    let store = OmpComposerDefaultStore(config: OmpConfigService(runner: runner))
    try await store.setDefaultModel(provider: "anthropic", modelID: "claude-opus-4-8")
    #expect(runner.lastSetKey == "modelRoles")
    #expect(runner.lastSetValueContainsDefault == "anthropic/claude-opus-4-8")
    #expect(runner.lastSetValueContainsCommit == "cursor/c")
}
```

Adapt to whatever list JSON shape `OmpConfigService.list()` already returns (settings values may be wrapped `{value,type}` — match existing `SettingsViewModel` parsing if needed; if `list()` returns raw values already decoded, use that).

- [ ] **Step 2: Run failing test**

Expected: FAIL

- [ ] **Step 3: Implement store**

If `list()` wraps values, unwrap `modelRoles` the same way Settings does. Keep other roles intact.

- [ ] **Step 4: Re-run tests**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/ComposerDefaultPersisting.swift Tests/TenXAppTests/ComposerDefaultStoreTests.swift 10x.xcodeproj
git commit -m "feat(sessions): persist composer defaults through omp config"
```

---

### Task 5: `ComposerControlsModel`

**Files:**
- Create: `App/Sessions/ComposerControlsModel.swift`
- Create: `Tests/TenXAppTests/ComposerControlsModelTests.swift`

**Interfaces:**
- Consumes: `OmpModelCatalogService`, `ComposerDefaultPersisting`, authenticated provider IDs provider (closure or `ProviderManagementViewModel` snapshot)
- Produces:

```swift
@MainActor @Observable
final class ComposerControlsModel {
    private(set) var models: [ComposerModelInfo] = []
    private(set) var selectedModel: ComposerModelInfo?
    private(set) var thinkingLevel: String = "auto"
    private(set) var isFastModeEnabled: Bool = false
    private(set) var isFastModeVisible: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var isMutating: Bool = false
    private(set) var errorMessage: String?

    var thinkingOptions: [String] { ComposerControlsPresentation.thinkingOptions(for: selectedModel) }
    var spawnSelection: ComposerSpawnSelection { ... } // provider, modelID, thinking, fastIntent

    func refresh(authenticatedProviderIDs: Set<String>) async
    func selectModel(_ model: ComposerModelInfo, mode: ComposerControlsMode) async
    func selectThinking(_ level: String, mode: ComposerControlsMode) async
    func setFastMode(_ enabled: Bool, mode: ComposerControlsMode) async
    func attachActiveSession(_ controller: SessionController)
    func detachActiveSession()
}

enum ComposerControlsMode { case newSession, activeSession }

struct ComposerSpawnSelection: Equatable, Sendable {
    let provider: String?
    let modelID: String?
    let thinking: String?
    let fastModeEnabled: Bool
}
```

Behavior:
- `refresh`: load catalog; filter; seed selection from snapshot; compute fast visibility
- `selectModel` / `selectThinking` in `.newSession`: optimistic UI only after successful persist; on failure keep prior selection + `errorMessage`
- same methods in `.activeSession`: call into attached `SessionController` setters; do not persist roles
- `setFastMode` in `.newSession`: store intent only (`isFastModeEnabled`); in `.activeSession`: live RPC
- `detachActiveSession`: clear controller bridge; caller triggers `refresh` to re-seed from OMP defaults

- [ ] **Step 1: Write failing view-model tests**

Cover: filter on refresh; new-session persist called; active path does not call persist; failed persist leaves selection; fast hidden for cursor.

- [ ] **Step 2: Run failing tests**

Expected: FAIL

- [ ] **Step 3: Implement `ComposerControlsModel`**

Inject catalog + store + optional `SessionController` bridge via weak/unowned main-actor reference set by `attach`/`detach`.

- [ ] **Step 4: Re-run tests**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/ComposerControlsModel.swift Tests/TenXAppTests/ComposerControlsModelTests.swift 10x.xcodeproj
git commit -m "feat(sessions): add composer controls feature model"
```

---

### Task 6: SessionController apply path

**Files:**
- Modify: `App/Sessions/SessionController.swift`
- Modify: `App/Application/AppModel.swift` (`startNewSession`)
- Test: extend `Tests/TenXAppTests/SessionControllerTests.swift` or add `SessionControllerComposerControlsTests.swift`

**Interfaces:**
- Produces:

```swift
// SessionController
func openNew(projectURL: URL, selection: ComposerSpawnSelection?) async
func setModel(provider: String, modelID: String) async
func setThinkingLevel(_ level: String) async
func setFastMode(_ enabled: Bool) async -> Bool // false when unsupported
```

`openNew`:
1. Call `processManager.openNew(projectDirectory:provider:model:thinking:)`
2. `finishOpening`
3. If `selection?.fastModeEnabled == true`, call `setFastMode(true)` (ignore soft failure by clearing UI intent via return value)

Update labels from `set_model` / `get_state` / existing event handlers (`modelName`, `thinkingLevel`).

- [ ] **Step 1: Write failing controller tests with fake process manager / client**

Assert `openNew` forwards spawn flags and sends `set_fast_mode` when requested.

- [ ] **Step 2: Run failing tests**

Expected: FAIL

- [ ] **Step 3: Implement controller methods + AppModel wiring**

```swift
// AppModel.startNewSession
let selection = composerControls?.spawnSelection
await controller.openNew(projectURL: selectedProjectURL, selection: selection)
composerControls?.attachActiveSession(controller)
```

On `openNewSession()` / returning to new session after archive: `detachActiveSession()` then `await composerControls?.refresh(...)`.

- [ ] **Step 4: Re-run tests**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/SessionController.swift App/Application/AppModel.swift Tests/TenXAppTests/10x.xcodeproj
git commit -m "feat(sessions): apply composer selection on open and live set_*"
```

---

### Task 7: Wire dependencies + UI controls

**Files:**
- Modify: `App/Application/AppDependencies.swift`
- Modify: `App/Application/AppModel.swift` (construct/shutdown `composerControls` beside provider model)
- Create: `App/Sessions/ComposerSessionControlsView.swift`
- Modify: `App/Sessions/ComposerView.swift`
- Modify: `App/Sessions/NewSessionView.swift`
- Modify: `App/Sessions/ActiveSessionView.swift` (if composer is built there)
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Add reference images for Fast present/absent

**Interfaces:**
- `ComposerView` gains optional `controls: ComposerControlsModel?` and `controlsMode: ComposerControlsMode`
- Active presentation replaces plain `Text(controller.modelName)` / thinking labels with the shared controls view (steer/follow-up buttons stay)

UI sketch:

```swift
struct ComposerSessionControlsView: View {
    let model: ComposerControlsModel
    let mode: ComposerControlsMode

    var body: some View {
        HStack(spacing: 4) {
            Menu { /* ForEach model.models */ } label: {
                Text(model.selectedModel?.name ?? "Model")
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(GhostActionStyle(...))
            .disabled(model.isLoading || model.isMutating || model.models.isEmpty)

            if !model.thinkingOptions.isEmpty {
                Menu { /* thinkingOptions */ } label: {
                    Text(model.thinkingLevel.capitalized)
                }
                ...
            }

            if model.isFastModeVisible {
                Button(model.isFastModeEnabled ? "Fast" : "Fast") {
                    Task { await model.setFastMode(!model.isFastModeEnabled, mode: mode) }
                }
                .buttonStyle(GhostActionStyle(color: model.isFastModeEnabled ? cyan : nearBlack))
            }
        }
    }
}
```

Show `model.errorMessage` as one-line caption under the footer row inside `ComposerView` when non-nil.

- [ ] **Step 1: Write/adjust snapshot tests for new + active footer (Fast on/off)**

- [ ] **Step 2: Run snapshots expecting failure / missing images**

- [ ] **Step 3: Implement UI + dependency wiring; regenerate project; record snapshots**

Follow existing snapshot harness conventions in `ViewSnapshotTests.swift` / `SnapshotHarness.swift`.

- [ ] **Step 4: Run full relevant tests**

```bash
ruby scripts/generate_xcodeproj.rb
cd OmpKit && swift test
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' test
```

Expected: PASS

- [ ] **Step 5: Manual smoke (agent or user)**

1. Launch Debug build with at least one authenticated provider.
2. New Session: open Model menu, switch provider/model, confirm chip label updates.
3. Change Thinking; confirm label.
4. On an Anthropic model, Fast appears and toggles; on Cursor, Fast is hidden.
5. Start session; confirm first turn uses the selected model (header/metadata).
6. Mid-session switch model; confirm it does not change `omp config get modelRoles` default.
7. Return to New Session; confirm chips re-seed from OMP defaults.

- [ ] **Step 6: Commit**

```bash
git add App Tests 10x.xcodeproj
git commit -m "feat(sessions): wire shared model thinking and fast composer controls"
```

---

## Spec coverage check

| Spec requirement | Task |
|------------------|------|
| Shared Model / Thinking / Fast controls | 5, 7 |
| Separate ghost buttons + native menus | 7 |
| No-session catalog | 3 |
| Authenticated-only flat list | 2, 5 |
| OMP-backed defaults, no UserDefaults | 4, 5 |
| New-session persist modelRoles + thinking | 4, 5 |
| Active `set_*` without role persist | 5, 6 |
| Spawn flags + post-open fast | 1, 6 |
| Fast = service tier, hide when unsupported | 2, 5, 7 |
| Errors / disable while mutating | 5, 7 |
| Tests listed in spec | 2–7 |
| Local stub unchanged | 7 |
| Work on main | Global Constraints |

## Placeholder / consistency notes

- `modelRoles` must be written as a full object update (verified against live OMP 18.0.4).
- `ComposerSpawnSelection` naming is fixed in Tasks 5–6; do not rename mid-plan.
- Fast visibility uses the presentation helper, not a probe `set_fast_mode` call, for menu rendering; live unsupported still handled when toggling on active sessions.

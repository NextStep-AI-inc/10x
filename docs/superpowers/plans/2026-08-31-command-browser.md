# Composer Command Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a keyboard-complete `/` command browser to both composers, backed by the live OMP command catalog and native Model, Effort, and Fast controls.

**Architecture:** Extend OmpKit with a typed, forward-compatible slash-command value and decoder. Generalize the existing warm model catalog into one project-aware composer catalog that publishes command snapshots without starting a second OMP process, then attach the same `ComposerCommandModel` to either that warm source or the active `SessionController`. Keep matching and availability pure, keep execution in the model/controller layer, and render one square-edged SwiftUI overlay above the existing composer.

**Tech Stack:** Swift 6 with strict concurrency, SwiftUI on macOS 15+, Observation, OmpKit JSON-RPC, Swift Testing, generated Xcode project, byte-for-byte PNG snapshots.

**Spec:** `docs/superpowers/specs/2026-08-31-command-browser-design.md`

---

## Execution preflight

- Work only in `/Users/tannerpham/CS Projects/.worktrees/10x-command-browser-design` on `codex/command-browser-design`.
- Invoke `writing-prs` before changing production code. Push `codex/command-browser-design` and open a draft PR against `main`; keep the design commit `9e30835` as the branch base.
- Do not merge, deploy, change dependencies, or edit `10x.xcodeproj/project.pbxproj` by hand.
- Run `bundle exec ruby scripts/generate_xcodeproj.rb` whenever App or Tests Swift files are added or renamed.
- Filter Swift Testing functions with their trailing parentheses, for example `-only-testing:'TenXAppTests/slashTriggerRequiresTheFirstNonWhitespaceCharacter()'`. Confirm the log reports a nonzero Swift Testing count.
- Record snapshots with `TEST_RUNNER_RECORD_SNAPSHOTS=1`; never use an unprefixed environment variable.
- User-facing strings in this plan are fixed copy. Do not add em dashes, internal RPC names, or performed states such as “Thinking…”.
- UI styling uses `TenXPalette`, `TenXTypography`, the existing one-pixel near-black stroke, and the existing 160 ms shelf transition. Do not add shadows, rounded panel chrome, or new design tokens.
- Direct tool invocation remains out of scope. OMP tools can appear only through OMP's own `/tools` command.

### Fixed browser copy

| State | Copy |
| --- | --- |
| Header | `COMMANDS` |
| Loading | `Loading session commands…` |
| Discovery unavailable title | `Session commands unavailable` |
| Discovery unavailable body | `Model, Effort, and Fast remain available. Retry after the session reconnects.` |
| New Session command source | `Start a session to use OMP commands.` |
| Direct no match | `No commands match “/<query>”.` |
| Typo fallback heading | `Close results` |
| Removed active command | `This command is no longer available.` |
| Native control during streaming | `Applies to the next request` |
| OMP row during streaming | `Runs after the current response` |

## File structure

| File | Responsibility |
| --- | --- |
| `OmpKit/Sources/OmpKit/Wire/AvailableSlashCommand.swift` (create) | Typed command, source, subcommand, and shared snapshot decoder |
| `OmpKit/Tests/OmpKitTests/AvailableSlashCommandTests.swift` (create) | Wire-contract decoding and malformed-entry coverage |
| `App/Sessions/ComposerCommandCatalogState.swift` (create) | Loading, available, and unavailable catalog state shared by warm and active sources |
| `App/Sessions/OmpModelCatalogService.swift` → `App/Sessions/ComposerCatalogService.swift` (rename) | One project-aware no-session process for models, state, commands, and live command updates |
| `App/Sessions/ComposerControlsModel.swift` (modify) | Accept project-aware catalog loads and expose the shared catalog to the command model |
| `Tests/TenXAppTests/OmpModelCatalogServiceTests.swift` → `Tests/TenXAppTests/ComposerCatalogServiceTests.swift` (rename) | Warm client reuse, cwd replacement, command loading, update, and shutdown tests |
| `App/Sessions/CommandBrowserPresentation.swift` (create) | Trigger parsing, source mapping, row identity, availability, ordering, search, and ranking |
| `Tests/TenXAppTests/CommandBrowserPresentationTests.swift` (create) | Pure trigger, source, ranking, collision, availability, and live-selection tests |
| `App/Sessions/ComposerCommandModel.swift` (create) | Browser state machine, source attachment, navigation, child routes, native mutations, and execution routing |
| `Tests/TenXAppTests/ComposerCommandModelTests.swift` (create) | Keyboard intents, child behavior, generation safety, and execution-route tests |
| `App/Sessions/TranscriptEventProcessor.swift` (modify) | Forward command updates and agent lifecycle events as control traffic |
| `Tests/TenXAppTests/TranscriptEventProcessorTests.swift` (modify) | Prove command metadata is lossless and transcript-silent |
| `App/Sessions/SessionController.swift` (modify) | Active command catalog, slash-command send path, forced Follow up, delayed attachment disposition |
| `Tests/TenXAppTests/SessionControllerCommandTests.swift` (create) | Active discovery, streaming policy, local/agent command lifecycle, attachment identity, and failure recovery |
| `Tests/TenXAppTests/Fixtures/composer_fake_server.py` (modify) | Deterministic command catalog and slash-command response modes |
| `App/Application/AppModel.swift` (modify) | Own and lifecycle-bind `ComposerCommandModel` beside existing controls |
| `App/Application/AppDependencies.swift` (modify) | Continue constructing one shared composer catalog through the controls factory |
| `Tests/TenXAppTests/StartupTestFixtures.swift` (modify) | Command-capable fake catalog used by AppModel tests |
| `Tests/TenXAppTests/AppModelNavigationTests.swift` (modify) | Warm/active attachment and project-refresh lifecycle tests |
| `App/Sessions/ModelPickerContent.swift` (create) | Reusable model search and row list used by footer and slash child |
| `App/Sessions/ModelPickerFlyout.swift` (modify) | Compose the extracted model content inside the existing shelf chrome |
| `App/Sessions/CommandBrowserNativeControlsView.swift` (create) | `/model`, `/effort`, and `/fast` child surfaces |
| `App/Sessions/CommandBrowserView.swift` (create) | Source rail, result list, detail pane, errors, empty states, pointer and accessibility actions |
| `App/Sessions/ComposerView.swift` (modify) | Trigger/open/close logic, overlay placement, keyboard routing, focus restoration, flyout exclusivity |
| `App/Sessions/NewSessionView.swift` (modify) | Supply warm command model and preserve existing project/send gates |
| `App/Sessions/ActiveSessionView.swift` (modify) | Supply active command model and reset the browser on session replacement |
| `App/Sessions/CommandBrowserAccessibility.swift` (create) | Natural VoiceOver labels, values, source counts, and queued-state wording |
| `Tests/TenXAppTests/AccessibilityLabelTests.swift` (modify) | Accessibility copy and pluralization tests |
| `Tests/TenXAppTests/ViewSnapshotTests.swift` (modify) | Root, streaming, native child, unavailable, no-match, and minimum-window snapshots |
| `Tests/TenXAppTests/ReferenceImages/*.png` (create) | Reviewed visual references for the new browser states |

---

### Task 1: Decode OMP's slash-command contract in OmpKit

**Files:**
- Create: `OmpKit/Sources/OmpKit/Wire/AvailableSlashCommand.swift`
- Create: `OmpKit/Tests/OmpKitTests/AvailableSlashCommandTests.swift`

- [x] **Step 1: Write the failing decoder tests**

Create `OmpKit/Tests/OmpKitTests/AvailableSlashCommandTests.swift` with these free `@Test` functions:

```swift
import Testing
@testable import OmpKit

@Test func availableCommandsDecoderKeepsTheCompleteContract() throws {
    let payload: JSONValue = .object(["commands": .array([
        .object([
            "name": .string("compact"),
            "aliases": .array([.string("summarize")]),
            "description": .string("Compact the current session"),
            "input": .object(["hint": .string("[instructions]")]),
            "subcommands": .array([
                .object([
                    "name": .string("status"),
                    "description": .string("Show compaction status"),
                    "usage": .string("/compact status"),
                ]),
            ]),
            "source": .string("builtin"),
        ]),
    ])])

    let commands = try AvailableSlashCommandDecoder.decodeSnapshot(payload)

    #expect(commands == [AvailableSlashCommand(
        name: "compact",
        aliases: ["summarize"],
        description: "Compact the current session",
        inputHint: "[instructions]",
        subcommands: [AvailableSlashSubcommand(
            name: "status",
            description: "Show compaction status",
            usage: "/compact status")],
        source: .builtin)])
}

@Test func availableCommandsDecoderKeepsUnknownSources() throws {
    let payload: JSONValue = .object(["commands": .array([
        .object(["name": .string("future"), "source": .string("remote_pack")]),
    ])])

    let command = try #require(AvailableSlashCommandDecoder.decodeSnapshot(payload).first)
    #expect(command.source == .other("remote_pack"))
    #expect(command.source.rawValue == "remote_pack")
}

@Test func availableCommandsDecoderDropsMalformedSiblingsAndSubcommands() throws {
    let payload: JSONValue = .object(["commands": .array([
        .object(["description": .string("missing name")]),
        .object([
            "name": .string("skill:brainstorming"),
            "source": .string("skill"),
            "subcommands": .array([
                .object(["description": .string("missing name")]),
                .object(["name": .string("resume"), "usage": .string("resume <id>")]),
            ]),
        ]),
    ])])

    let commands = try AvailableSlashCommandDecoder.decodeSnapshot(payload)
    #expect(commands.map(\.name) == ["skill:brainstorming"])
    #expect(commands[0].subcommands.map(\.name) == ["resume"])
}

@Test func availableCommandsDecoderRejectsMalformedTopLevelPayload() {
    #expect(throws: AvailableSlashCommandDecodingError.invalidSnapshot) {
        try AvailableSlashCommandDecoder.decodeSnapshot(.object(["commands": .string("wrong")]))
    }
}
```

- [x] **Step 2: Run the OmpKit test and verify it fails**

Run:

```bash
swift test --package-path OmpKit --filter AvailableSlashCommand
```

Expected: compilation fails because `AvailableSlashCommandDecoder` and its value types do not exist.

- [x] **Step 3: Implement the typed command and shared decoder**

Create `OmpKit/Sources/OmpKit/Wire/AvailableSlashCommand.swift` with this public surface:

```swift
import Foundation

public enum AvailableSlashCommandSource: Sendable, Equatable, Hashable {
    case builtin
    case skill
    case extensionCommand
    case custom
    case mcpPrompt
    case file
    case other(String)

    public init(rawValue: String) {
        self = switch rawValue {
        case "builtin": .builtin
        case "skill": .skill
        case "extension": .extensionCommand
        case "custom": .custom
        case "mcp_prompt": .mcpPrompt
        case "file": .file
        default: .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .builtin: "builtin"
        case .skill: "skill"
        case .extensionCommand: "extension"
        case .custom: "custom"
        case .mcpPrompt: "mcp_prompt"
        case .file: "file"
        case .other(let value): value
        }
    }
}

public struct AvailableSlashSubcommand: Sendable, Equatable, Hashable {
    public let name: String
    public let description: String?
    public let usage: String?

    public init(name: String, description: String? = nil, usage: String? = nil) {
        self.name = name
        self.description = description
        self.usage = usage
    }
}

public struct AvailableSlashCommand: Sendable, Equatable, Hashable {
    public let name: String
    public let aliases: [String]
    public let description: String?
    public let inputHint: String?
    public let subcommands: [AvailableSlashSubcommand]
    public let source: AvailableSlashCommandSource

    public init(
        name: String,
        aliases: [String] = [],
        description: String? = nil,
        inputHint: String? = nil,
        subcommands: [AvailableSlashSubcommand] = [],
        source: AvailableSlashCommandSource
    ) {
        self.name = name
        self.aliases = aliases
        self.description = description
        self.inputHint = inputHint
        self.subcommands = subcommands
        self.source = source
    }
}

public enum AvailableSlashCommandDecodingError: Error, Sendable, Equatable {
    case invalidSnapshot
}

public enum AvailableSlashCommandDecoder {
    public static func decodeSnapshot(_ value: JSONValue) throws -> [AvailableSlashCommand] {
        guard let values = value["commands"]?.arrayValue else {
            throw AvailableSlashCommandDecodingError.invalidSnapshot
        }
        return values.compactMap(decodeCommand)
    }

    private static func decodeCommand(_ value: JSONValue) -> AvailableSlashCommand? {
        guard let object = value.objectValue,
              let name = nonempty(object["name"]?.stringValue),
              let rawSource = nonempty(object["source"]?.stringValue)
        else { return nil }
        return AvailableSlashCommand(
            name: name,
            aliases: object["aliases"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            description: nonempty(object["description"]?.stringValue),
            inputHint: nonempty(object["input"]?["hint"]?.stringValue),
            subcommands: object["subcommands"]?.arrayValue?.compactMap(decodeSubcommand) ?? [],
            source: AvailableSlashCommandSource(rawValue: rawSource))
    }

    private static func decodeSubcommand(_ value: JSONValue) -> AvailableSlashSubcommand? {
        guard let object = value.objectValue,
              let name = nonempty(object["name"]?.stringValue)
        else { return nil }
        return AvailableSlashSubcommand(
            name: name,
            description: nonempty(object["description"]?.stringValue),
            usage: nonempty(object["usage"]?.stringValue))
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
```

- [x] **Step 4: Run all OmpKit tests**

Run: `swift test --package-path OmpKit`

Expected: all OmpKit tests pass, including four new decoder tests.

- [x] **Step 5: Commit**

```bash
git add OmpKit/Sources/OmpKit/Wire/AvailableSlashCommand.swift OmpKit/Tests/OmpKitTests/AvailableSlashCommandTests.swift
git commit -m "feat(ompkit): decode available slash commands"
```

---

### Task 2: Generalize the warm composer catalog

**Files:**
- Create: `App/Sessions/ComposerCommandCatalogState.swift`
- Rename: `App/Sessions/OmpModelCatalogService.swift` → `App/Sessions/ComposerCatalogService.swift`
- Modify: `App/Sessions/ComposerControlsModel.swift`
- Rename: `Tests/TenXAppTests/OmpModelCatalogServiceTests.swift` → `Tests/TenXAppTests/ComposerCatalogServiceTests.swift`
- Modify: test catalog fakes that conform to `ComposerCatalogLoading`

- [x] **Step 1: Add failing service tests**

Rename the test file and update its fake client to expose an event continuation,
record received `RpcClientConfiguration` values, and provide `record(_:)` and
`emit(_:)` actor methods. Add tests that assert:

```swift
@Test func composerCatalogLoadsModelsAndCommandsThroughOneClient() async throws {
    let commandsResponse = RpcResponse(
        id: "commands",
        command: "get_available_commands",
        success: true,
        data: .object(["commands": .array([
            .object(["name": .string("compact"), "source": .string("builtin")]),
        ])]))
    let fake = FakeCatalogRPCClient(
        responses: [stateResponse, modelsResponse, commandsResponse])
    let service = ComposerCatalogService(
        executableURL: URL(filePath: "/tmp/omp"),
        clientFactory: { configuration in
            await fake.record(configuration)
            return fake
        })

    let snapshot = try await service.load(
        projectURL: URL(filePath: "/tmp/project", directoryHint: .isDirectory))

    #expect(snapshot.models.count == 2)
    #expect(snapshot.commandCatalog == .available([
        AvailableSlashCommand(name: "compact", source: .builtin),
    ]))
    #expect(await fake.commands.map(\.command.type) == [
        "get_state", "get_available_models", "get_available_commands",
    ])
    #expect(await fake.configurations.map(\.cwd?.path) == ["/tmp/project"])
}

@Test func composerCatalogPublishesCompleteCommandUpdates() async throws {
    let fake = FakeCatalogRPCClient(
        responses: [stateResponse, modelsResponse, emptyCommandsResponse])
    let service = ComposerCatalogService(
        executableURL: URL(filePath: "/tmp/omp"),
        clientFactory: { _ in fake })
    let updates = service.commandUpdates
    _ = try await service.load(projectURL: URL(filePath: "/tmp/project"))
    await fake.emit(.event(
        type: "available_commands_update",
        payload: .object(["commands": .array([
            .object(["name": .string("retry"), "source": .string("builtin")]),
        ])])))

    var iterator = updates.makeAsyncIterator()
    #expect(await iterator.next() == .available([]))
    #expect(await iterator.next() == .available([
        AvailableSlashCommand(name: "retry", source: .builtin),
    ]))
}

@Test func changingCatalogProjectReplacesTheWarmClient() async throws {
    let factory = CatalogClientFactory()
    let service = ComposerCatalogService(
        executableURL: URL(filePath: "/tmp/omp"),
        clientFactory: factory.make)

    _ = try await service.load(projectURL: URL(filePath: "/tmp/one"))
    _ = try await service.load(projectURL: URL(filePath: "/tmp/two"))

    #expect(await factory.configurations.map(\.cwd?.path) == ["/tmp/one", "/tmp/two"])
    #expect(await factory.clients[0].shutdownCount == 1)
}

@Test func unsupportedCommandDiscoveryKeepsTheModelCatalogUsable() async throws {
    let fake = FakeCatalogRPCClient(responses: [
        stateResponse,
        modelsResponse,
        RpcResponse(id: "commands", command: "get_available_commands", success: false,
                    error: "unsupported"),
    ])
    let service = ComposerCatalogService(
        executableURL: URL(filePath: "/tmp/omp"),
        clientFactory: { _ in fake })

    let snapshot = try await service.load(projectURL: nil)

    #expect(snapshot.models.count == 2)
    #expect(snapshot.commandCatalog == .unavailable)
}
```

- [x] **Step 2: Run the targeted tests and verify they fail**

First rename the files, regenerate the project, then run:

```bash
mv App/Sessions/OmpModelCatalogService.swift App/Sessions/ComposerCatalogService.swift
mv Tests/TenXAppTests/OmpModelCatalogServiceTests.swift Tests/TenXAppTests/ComposerCatalogServiceTests.swift
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/composerCatalogLoadsModelsAndCommandsThroughOneClient()' \
  -only-testing:'TenXAppTests/changingCatalogProjectReplacesTheWarmClient()'
```

Expected: compilation fails because the renamed service and command state are not implemented.

- [x] **Step 3: Add the catalog state and project-aware protocol**

Create `App/Sessions/ComposerCommandCatalogState.swift`:

```swift
import OmpKit

enum ComposerCommandCatalogState: Equatable, Sendable {
    case loading
    case available([AvailableSlashCommand])
    case unavailable
}
```

Change `ComposerCatalogLoading` and `ComposerCatalogSnapshot` to:

```swift
protocol ComposerCatalogLoading: AnyObject, Sendable {
    var commandUpdates: AsyncStream<ComposerCommandCatalogState> { get }
    func load(projectURL: URL?) async throws -> ComposerCatalogSnapshot
    func shutdown() async
}

struct ComposerCatalogSnapshot: Equatable, Sendable {
    let models: [ComposerModelInfo]
    let selected: ComposerModelInfo?
    let thinkingLevel: String?
    let fastModeEnabled: Bool
    let fastModeActive: Bool
    let commandCatalog: ComposerCommandCatalogState
}
```

Update `ComposerControlsModel.refresh` to accept `projectURL: URL?`, call `catalog.load(projectURL:)`, and keep command availability independent from model errors. Make the injected catalog internal read-only so `AppModel` can pass the same instance to `ComposerCommandModel`:

```swift
@ObservationIgnored let catalog: any ComposerCatalogLoading

func refresh(authenticatedProviderIDs: Set<String>, projectURL: URL?) async {
    isLoading = true
    defer { isLoading = false }
    do {
        let snapshot = try await catalog.load(projectURL: projectURL)
        models = ComposerControlsPresentation.authenticatedModels(
            catalog: snapshot.models,
            authenticatedProviderIDs: authenticatedProviderIDs)
        recentModels = recents.rankedModels(from: models)
        if let activeSession {
            applyLiveSelection(activeSession.liveComposerSelection)
        } else {
            if let selected = snapshot.selected,
               models.contains(where: { $0.id == selected.id }) {
                selectedModel = selected
            } else {
                selectedModel = models.first
            }
            thinkingLevel = snapshot.thinkingLevel ?? "auto"
            applyFastModeVisibility(preservingEnabled: snapshot.fastModeEnabled)
        }
        errorMessage = nil
    } catch {
        errorMessage = "Models couldn’t be loaded."
    }
}
```

- [x] **Step 4: Implement one warm client and its command update task**

Rename the actor and error to `ComposerCatalogService` and `ComposerCatalogServiceError`. Keep `configuration` mutable, set `configuration.cwd` to the standardized project URL before creating a client, and replace the client only when cwd changes. Add one event task and one `bufferingNewest(1)` update stream:

```swift
actor ComposerCatalogService: ComposerCatalogLoading {
    nonisolated let commandUpdates: AsyncStream<ComposerCommandCatalogState>

    private var configuration: RpcClientConfiguration
    private let commandContinuation: AsyncStream<ComposerCommandCatalogState>.Continuation
    private var client: CatalogRPCClientBox?
    private var eventTask: Task<Void, Never>?

    func load(projectURL: URL?) async throws -> ComposerCatalogSnapshot {
        try await selectProject(projectURL)
        let client = try await clientForLoad()
        let state = try await client.send(.getState(), timeout: nil)
        let models = try await client.send(.getAvailableModels(), timeout: nil)
        let commands: ComposerCommandCatalogState
        do {
            let response = try await client.send(.getAvailableCommands(), timeout: nil)
            guard let data = response.data else {
                throw AvailableSlashCommandDecodingError.invalidSnapshot
            }
            commands = .available(try AvailableSlashCommandDecoder.decodeSnapshot(data))
        } catch {
            commands = .unavailable
        }
        commandContinuation.yield(commands)
        return try parseSnapshot(state: state.data, models: models.data, commands: commands)
    }

    private func consume(_ frame: RpcFrame) {
        guard case .event("available_commands_update", let payload) = frame else { return }
        do {
            commandContinuation.yield(.available(
                try AvailableSlashCommandDecoder.decodeSnapshot(payload)))
        } catch {
            commandContinuation.yield(.unavailable)
        }
    }
}
```

`shutdown()` must cancel and await `eventTask`, shut down the client once, clear it, yield `.unavailable`, and finish the update stream. `selectProject(_:)` must cancel the old event task and shut down the old client before mutating cwd.

- [x] **Step 5: Update catalog fakes and all refresh call sites**

Every fake `ComposerCatalogLoading` gets a buffered stream and accepts `projectURL`. Every call to `refresh` passes the current project:

```swift
await composerControls?.refresh(
    authenticatedProviderIDs: authenticatedIDs,
    projectURL: selectedProjectURL)
```

Snapshot-only fakes return `.available([])` so existing model-picker snapshots remain unchanged.

- [x] **Step 6: Run catalog and existing controls tests**

Run:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/composerCatalogLoadsModelsAndCommandsThroughOneClient()' \
  -only-testing:'TenXAppTests/composerCatalogPublishesCompleteCommandUpdates()' \
  -only-testing:'TenXAppTests/changingCatalogProjectReplacesTheWarmClient()' \
  -only-testing:'TenXAppTests/unsupportedCommandDiscoveryKeepsTheModelCatalogUsable()' \
  -only-testing:'TenXAppTests/catalogServiceDecodesStateAndModels()'
```

Expected: five tests execute and pass. Then run
`xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:TenXAppTests`
and confirm the full app test target passes.

- [x] **Step 7: Commit**

```bash
git add App/Sessions/ComposerCommandCatalogState.swift App/Sessions/ComposerCatalogService.swift App/Sessions/ComposerControlsModel.swift App/Application/AppModel.swift Tests/TenXAppTests 10x.xcodeproj
git commit -m "feat(composer): publish the OMP command catalog"
```

---

### Task 3: Build deterministic command-browser presentation

**Files:**
- Create: `App/Sessions/CommandBrowserPresentation.swift`
- Create: `Tests/TenXAppTests/CommandBrowserPresentationTests.swift`

- [x] **Step 1: Write failing trigger, mapping, ordering, and ranking tests**

Cover the approved matrix with free tests. Use these exact assertions as the core:

```swift
private let browserFixtureCommands = [
    AvailableSlashCommand(
        name: "model",
        description: "OMP model command",
        source: .builtin),
    AvailableSlashCommand(
        name: "compact",
        aliases: ["summarize"],
        description: "Compact the current session",
        inputHint: "[instructions]",
        source: .builtin),
    AvailableSlashCommand(
        name: "add-dir",
        description: "Add a working directory",
        source: .extensionCommand),
    AvailableSlashCommand(
        name: "skill:brainstorming",
        description: "Explore requirements before implementation",
        source: .skill),
    AvailableSlashCommand(
        name: "release-notes",
        description: "Draft release notes",
        source: .custom),
]

private func matchNames(_ query: String) -> [String] {
    CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: query,
        selectedSource: .all,
        mode: .activeIdle)
        .rows.map(\.canonicalName)
}

@Test func slashTriggerRequiresTheFirstNonWhitespaceCharacter() {
    #expect(CommandBrowserPresentation.parseDraft("/")?.query == "")
    #expect(CommandBrowserPresentation.parseDraft("  /model")?.query == "model")
    #expect(CommandBrowserPresentation.parseDraft("/skill:brainstorming plan it")?.arguments == "plan it")
    #expect(CommandBrowserPresentation.parseDraft("open /model") == nil)
    #expect(CommandBrowserPresentation.parseDraft("https://example.com") == nil)
    #expect(CommandBrowserPresentation.parseDraft("src/App/Thing.swift") == nil)
    #expect(CommandBrowserPresentation.parseDraft("hello\n/model") == nil)
}

@Test func browserMapsEveryKnownAndUnknownOMPSource() {
    #expect(CommandBrowserPresentation.source(for: .builtin) == .commands)
    #expect(CommandBrowserPresentation.source(for: .skill) == .skills)
    #expect(CommandBrowserPresentation.source(for: .extensionCommand) == .extensions)
    #expect(CommandBrowserPresentation.source(for: .custom) == .prompts)
    #expect(CommandBrowserPresentation.source(for: .mcpPrompt) == .prompts)
    #expect(CommandBrowserPresentation.source(for: .file) == .prompts)
    #expect(CommandBrowserPresentation.source(for: .other("future")) == .other)
}

@Test func appRowsReplaceSameNamedOMPRowsAndLeadStableRootOrder() {
    let rows = CommandBrowserPresentation.rows(
        commands: browserFixtureCommands,
        mode: .activeIdle)
    #expect(rows.prefix(3).map(\.canonicalName) == ["model", "effort", "fast"])
    #expect(rows.filter { $0.canonicalName == "model" }.count == 1)
    #expect(rows.dropFirst(3).map(\.source).starts(with: [.commands, .commands]))
}

@Test func browserMatchingUsesCanonicalAliasNamespaceAndSeparators() {
    #expect(matchNames("adddir") == ["add-dir"])
    #expect(matchNames("brainstorming") == ["skill:brainstorming"])
    #expect(matchNames("sum") == ["compact"])
}

@Test func closeResultsAreVisibleButNotInitiallySelected() {
    let result = CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: "modle",
        selectedSource: .all,
        mode: .activeIdle)
    #expect(result.heading == "Close results")
    #expect(result.rows.map(\.canonicalName).contains("model"))
    #expect(result.initialSelection == nil)
}

@Test func newSessionShowsOnlyAppSkillsAndPromptsInAll() {
    let result = CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: "",
        selectedSource: .all,
        mode: .newSession)
    #expect(Set(result.rows.map(\.source)).isSubset(of: [.app, .skills, .prompts]))
    #expect(result.sources.first { $0.id == .commands }?.message
        == "Start a session to use OMP commands.")
}
```

Add tests for exact, prefix, word-boundary, substring, subcommand, description/usage order; alphabetical tie-breaking; alias display; duplicate identity; malformed unknown source; empty sources; and selection retention by `(rawSource, canonicalName)`.

- [x] **Step 2: Regenerate and verify the tests fail**

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/slashTriggerRequiresTheFirstNonWhitespaceCharacter()'
```

Expected: compilation fails because `CommandBrowserPresentation` does not exist.

- [x] **Step 3: Implement the pure presentation values**

Define these non-SwiftUI values in `CommandBrowserPresentation.swift`:

```swift
enum CommandBrowserSource: String, CaseIterable, Sendable {
    case all = "All"
    case app = "App"
    case commands = "Commands"
    case skills = "Skills"
    case extensions = "Extensions"
    case prompts = "Prompts"
    case other = "Other"
}

enum CommandBrowserMode: Equatable, Sendable {
    case newSession
    case activeIdle
    case activeStreaming
    case unavailable
}

enum AppCommand: String, CaseIterable, Sendable {
    case model
    case effort
    case fast
}

struct CommandBrowserRowID: Hashable, Sendable {
    let rawSource: String
    let canonicalName: String
}

struct CommandBrowserRow: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case app(AppCommand)
        case omp(AvailableSlashCommand)
    }

    let id: CommandBrowserRowID
    let canonicalName: String
    let aliases: [String]
    let summary: String
    let inputHint: String?
    let subcommands: [AvailableSlashSubcommand]
    let source: CommandBrowserSource
    let rawSource: String
    let kind: Kind
    let availabilityMessage: String?
    let executionNote: String?
}

struct ParsedSlashDraft: Equatable, Sendable {
    let query: String
    let arguments: String
}

struct CommandBrowserResult: Equatable, Sendable {
    let sources: [CommandBrowserSourceItem]
    let rows: [CommandBrowserRow]
    let heading: String?
    let initialSelection: CommandBrowserRowID?
}

struct CommandBrowserSourceItem: Identifiable, Equatable, Sendable {
    let id: CommandBrowserSource
    let count: Int
    let message: String?
}
```

Implement source mapping, fixed App descriptors, App collision replacement, stable ordering, New Session availability, streaming notes, and the rank ladder from the spec. Normalize matching by lowercasing and removing `:`, `_`, and `-`. Run bounded Damerau-Levenshtein only when direct results are empty, cap distance at two, and set `initialSelection` to `nil` for close results.

- [x] **Step 4: Run every presentation test**

Run each newly added free function explicitly or run the full target. Confirm the log includes all new tests and no `Executed 0 tests` line:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests
```

Expected: the full app test target passes.

- [x] **Step 5: Commit**

```bash
git add App/Sessions/CommandBrowserPresentation.swift Tests/TenXAppTests/CommandBrowserPresentationTests.swift 10x.xcodeproj
git commit -m "feat(composer): rank slash command suggestions"
```

---

### Task 4: Implement the command-browser state machine

**Files:**
- Create: `App/Sessions/ComposerCommandModel.swift`
- Create: `Tests/TenXAppTests/ComposerCommandModelTests.swift`

- [x] **Step 1: Write failing state-machine tests**

Create a fake catalog with a controllable update stream, fake controls, and a fake session conforming to the protocol below. Add tests for:

```swift
@Test @MainActor func commandModelOpensOnlyForAValidSlashDraft() async {
    let fixture = CommandModelFixture()
    #expect(!fixture.model.updateDraft("hello /model"))
    #expect(fixture.model.updateDraft(" /"))
    #expect(fixture.model.isPresented)
    #expect(fixture.model.selectedRowID?.canonicalName == "model")
}

@Test @MainActor func commandModelNavigatesRowsAndSourcesWithoutMovingTextFocus() async {
    let fixture = CommandModelFixture(commands: browserFixtureCommands)
    _ = fixture.model.updateDraft("/")
    fixture.model.moveSelection(.next)
    fixture.model.moveSelection(.last)
    fixture.model.cycleSource(.forward)
    fixture.model.selectVisibleSource(at: 3)
    #expect(fixture.model.selectedSource == .skills)
    #expect(fixture.model.selectedRowID == fixture.model.visibleRows.last?.id)
}

@Test @MainActor func tabCompletesWithoutExecuting() async {
    let fixture = CommandModelFixture(commands: browserFixtureCommands)
    _ = fixture.model.updateDraft("/comp")
    let effect = await fixture.model.complete(draft: "/comp")
    #expect(effect == .replaceDraft("/compact "))
    #expect(await fixture.session.sentCommands.isEmpty)
}

@Test @MainActor func selectingAWorkflowEntersArgumentsBeforeSending() async {
    let fixture = CommandModelFixture(commands: browserFixtureCommands)
    _ = fixture.model.updateDraft("/brainstorming")
    #expect(await fixture.model.activate(draft: "/brainstorming", attachments: [])
        == .replaceDraft("/skill:brainstorming "))
    #expect(fixture.model.route == .arguments(
        CommandBrowserRowID(rawSource: "skill", canonicalName: "skill:brainstorming")))
}

@Test @MainActor func escapeReturnsFromChildThenClosesRootWithoutChangingDraft() async {
    let fixture = CommandModelFixture(commands: browserFixtureCommands)
    _ = fixture.model.updateDraft("/model")
    _ = await fixture.model.activate(draft: "/model", attachments: [])
    #expect(fixture.model.back() == .keepDraft)
    #expect(fixture.model.route == .root)
    #expect(fixture.model.back() == .dismiss)
}

@Test @MainActor func staleCatalogGenerationCannotReplaceTheAttachedSession() async {
    let fixture = CommandModelFixture()
    fixture.model.attachActiveSession(fixture.session)
    await fixture.catalog.emit(.available([
        AvailableSlashCommand(name: "stale", source: .builtin),
    ]))
    await fixture.session.emit(.available([
        AvailableSlashCommand(name: "current", source: .builtin),
    ]))
    #expect(await eventually { fixture.model.visibleRows.contains { $0.canonicalName == "current" } })
    #expect(!fixture.model.visibleRows.contains { $0.canonicalName == "stale" })
}
```

Also test Home, End, Page Up, Page Down, source cycling, direct source indices, removed selected row, removed active child, unavailable copy, native child routes, active idle execution, streaming execution, and new-session workflow execution.

- [x] **Step 2: Regenerate and verify the first test fails**

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/commandModelOpensOnlyForAValidSlashDraft()'
```

Expected: compilation fails because `ComposerCommandModel` is missing.

- [x] **Step 3: Define the state machine and source protocol**

Use this public-to-App surface:

```swift
@MainActor
protocol ComposerCommandSession: AnyObject {
    var runtimeState: SessionRuntimeState { get }
    var commandCatalogState: ComposerCommandCatalogState { get }
    var commandUpdates: AsyncStream<ComposerCommandCatalogState> { get }
    func sendSlashCommand(_ text: String) async
}

enum CommandBrowserRoute: Equatable {
    case root
    case subcommands(CommandBrowserRowID)
    case arguments(CommandBrowserRowID)
    case native(AppCommand)
}

enum CommandBrowserMove { case previous, next, first, last, pagePrevious, pageNext }
enum CommandBrowserCycle { case forward, backward }

enum CommandBrowserEffect: Equatable {
    case none
    case keepDraft
    case dismiss
    case replaceDraft(String)
    case executed
}

@MainActor
@Observable
final class ComposerCommandModel {
    private(set) var isPresented = false
    private(set) var selectedSource: CommandBrowserSource = .all
    private(set) var selectedRowID: CommandBrowserRowID?
    private(set) var route: CommandBrowserRoute = .root
    private(set) var catalogState: ComposerCommandCatalogState = .loading
    private(set) var inlineMessage: String?
    private var availableCommands: [AvailableSlashCommand] = []
    private var parsedDraft: ParsedSlashDraft?
    private var mode: CommandBrowserMode = .newSession

    init(
        catalog: any ComposerCatalogLoading,
        controls: ComposerControlsModel,
        onStartNewSession: @escaping @MainActor (String, [ComposerAttachment]) -> Void
    )

    var visibleRows: [CommandBrowserRow] { presentation.rows }
    var visibleSources: [CommandBrowserSourceItem] { presentation.sources }
    var highlightedRow: CommandBrowserRow? {
        visibleRows.first { $0.id == selectedRowID }
    }

    private var presentation: CommandBrowserResult {
        CommandBrowserPresentation.present(
            commands: availableCommands,
            query: parsedDraft?.query ?? "",
            selectedSource: selectedSource,
            mode: mode)
    }

    func updateDraft(_ draft: String) -> Bool
    func moveSelection(_ move: CommandBrowserMove)
    func cycleSource(_ direction: CommandBrowserCycle)
    func selectVisibleSource(at oneBasedIndex: Int)
    func selectSource(_ source: CommandBrowserSource)
    func highlight(_ id: CommandBrowserRowID)
    func complete(draft: String) async -> CommandBrowserEffect
    func activate(draft: String, attachments: [ComposerAttachment]) async -> CommandBrowserEffect
    func applyModel(_ model: ComposerModelInfo) async -> CommandBrowserEffect
    func applyEffort(_ level: String) async -> CommandBrowserEffect
    func applyFast(_ enabled: Bool) async -> CommandBrowserEffect
    func back() -> CommandBrowserEffect
    func dismiss()
    func attachActiveSession(_ session: any ComposerCommandSession)
    func detachActiveSession()
}
```

Keep all ordering and matching calls in `CommandBrowserPresentation`. The model owns only current draft parse, source, identity, route, attachment to warm/active streams, and execution decisions. Each source attachment increments a generation; update tasks check the captured generation before mutating state.

- [x] **Step 4: Implement native and OMP activation rules**

The activation switch must be exhaustive:

```swift
if case .arguments = route {
    await executeSlash(canonicalSlashText(from: draft), attachments: attachments)
    return .executed
}
guard let row = highlightedRow else {
    await executeSlash(canonicalSlashText(from: draft), attachments: attachments)
    return .executed
}
switch row.kind {
case .app(let command):
    route = .native(command)
    return .none
case .omp(let command) where !command.subcommands.isEmpty:
    route = .subcommands(row.id)
    return .replaceDraft("/\(command.name) ")
case .omp(let command) where command.inputHint != nil || row.source == .skills || row.source == .prompts:
    route = .arguments(row.id)
    return .replaceDraft("/\(command.name) ")
case .omp(let command):
    await executeSlash("/\(command.name)", attachments: attachments)
    return .executed
}
```

`executeSlash` calls the attached active session when present. In New Session it calls an injected `@MainActor (String, [ComposerAttachment]) -> Void` closure only for available Skills and Prompts. It never executes unavailable Commands or Extensions. Completion uses the canonical name and never an alias.

- [x] **Step 5: Implement native mutation wrappers**

Add `applyModel`, `applyEffort`, and `applyFast` methods that delegate to the existing `ComposerControlsModel`. Capture the prior `errorMessage`, await the mutation, and dismiss only when the control model has no new error. On failure keep the child open and copy the sanitized control error into `inlineMessage`. During active streaming, set the detail note to `Applies to the next request` without delaying the mutation.

Each successful native method calls `dismiss()` and returns
`.replaceDraft("")`; the view applies that effect to clear only the slash draft.
Attachments are never passed to or changed by these methods. A failed mutation
returns `.none` so the child and draft stay open. `/fast` Status uses the same
successful dismissal effect without calling `setFastMode`.

- [x] **Step 6: Run all model tests**

Run the full app target and verify every new free function executes:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests
```

Expected: all tests pass.

- [x] **Step 7: Commit**

```bash
git add App/Sessions/ComposerCommandModel.swift Tests/TenXAppTests/ComposerCommandModelTests.swift 10x.xcodeproj
git commit -m "feat(composer): add command browser state machine"
```

---

### Task 5: Publish active-session command catalogs

**Files:**
- Modify: `App/Sessions/TranscriptEventProcessor.swift`
- Modify: `App/Sessions/SessionController.swift`
- Modify: `Tests/TenXAppTests/TranscriptEventProcessorTests.swift`
- Create: `Tests/TenXAppTests/SessionControllerCommandTests.swift`
- Modify: `Tests/TenXAppTests/Fixtures/composer_fake_server.py`

- [x] **Step 1: Write failing control-routing tests**

Add a processor test that consumes an `available_commands_update` event and proves it appears on `controlEvents` without changing snapshot revision or items. Add `agent_start` and `turn_start` forwarding assertions because the delayed attachment path needs those lifecycle boundaries.

```swift
@Test func commandUpdatesForwardWithoutMutatingTheTranscript() async throws {
    let processor = TranscriptEventProcessor(publicationInterval: .seconds(60))
    let before = await processor.currentSnapshot()
    var controls = processor.controlEvents.makeAsyncIterator()
    let frame = try RpcFrame.decode(line: Data(
        #"{"type":"available_commands_update","commands":[{"name":"compact","source":"builtin"}]}"#.utf8))
    await processor.consume(frame)

    let control = try #require(await controls.next())
    let after = await processor.currentSnapshot()
    #expect(control.controlLabel == "event:available_commands_update")
    #expect(after.revision == before.revision)
    #expect(after.items == before.items)
}
```

- [x] **Step 2: Write failing active-catalog tests**

Extend the Python fixture with `get_available_commands` and an update mode. Add tests:

```swift
@Test @MainActor func activeSessionLoadsAndReplacesAvailableCommands() async throws {
    let manager = commandFakeManager(mode: "catalog-update")
    let controller = SessionController(processManager: manager)
    await controller.openNew(projectURL: try commandTemporaryDirectory())

    #expect(controller.commandCatalogState == .available([
        AvailableSlashCommand(name: "compact", source: .builtin),
    ]))
    #expect(await eventually {
        controller.commandCatalogState == .available([
            AvailableSlashCommand(name: "retry", source: .builtin),
        ])
    })
    await manager.closeAll()
}

@Test @MainActor func staleSessionCommandUpdateCannotReplaceRestartedCatalog() async throws {
    let manager = commandFakeManager(mode: "delayed-catalog-update")
    let controller = SessionController(processManager: manager)
    let project = try commandTemporaryDirectory()
    await controller.openNew(projectURL: project)
    await controller.restart()
    #expect(await eventually {
        !controller.availableCommands.contains { $0.name == "stale" }
    })
    await manager.closeAll()
}
```

- [x] **Step 3: Regenerate and verify the tests fail**

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/commandUpdatesForwardWithoutMutatingTheTranscript()' \
  -only-testing:'TenXAppTests/activeSessionLoadsAndReplacesAvailableCommands()'
```

Expected: assertions fail because updates are not forwarded or stored.

- [x] **Step 4: Forward command and lifecycle control traffic**

Add these event types to `TranscriptEventProcessor.isControlFrame`:

```swift
case "available_commands_update",
     "agent_start",
     "turn_start":
    return true
```

Do not add reducer cases; the existing default `.none` keeps command metadata transcript-silent. Lifecycle events retain their existing runtime mutation.

- [x] **Step 5: Add the active command stream to SessionController**

Add:

```swift
private(set) var commandCatalogState: ComposerCommandCatalogState = .loading
var availableCommands: [AvailableSlashCommand] {
    guard case .available(let commands) = commandCatalogState else { return [] }
    return commands
}
nonisolated let commandUpdates: AsyncStream<ComposerCommandCatalogState>
private let commandContinuation: AsyncStream<ComposerCommandCatalogState>.Continuation
```

Initialize the buffered stream in both initializers. In `finishOpening`, request `get_available_commands` after `get_state`, decode the complete response, publish it, and use `.unavailable` on unsupported/malformed responses without failing session opening. In `applyEventMetadata`, decode `available_commands_update` and publish a full replacement. Reset to `.loading` when a new pipeline begins and `.unavailable` when it stops.

- [x] **Step 6: Run processor and active-catalog tests**

Run the new functions plus existing processor/controller tests. Expected: all selected tests execute and pass.

- [x] **Step 7: Commit**

```bash
git add App/Sessions/TranscriptEventProcessor.swift App/Sessions/SessionController.swift Tests/TenXAppTests/TranscriptEventProcessorTests.swift Tests/TenXAppTests/SessionControllerCommandTests.swift Tests/TenXAppTests/Fixtures/composer_fake_server.py 10x.xcodeproj
git commit -m "feat(sessions): publish active slash commands"
```

---

### Task 6: Add slash execution and exact attachment disposition

**Files:**
- Modify: `App/Sessions/SessionController.swift`
- Modify: `Tests/TenXAppTests/SessionControllerCommandTests.swift`
- Modify: `Tests/TenXAppTests/Fixtures/composer_fake_server.py`

- [x] **Step 1: Add failing slash-execution tests**

Give the fixture modes `slash-local`, `slash-agent`, `slash-legacy-agent`, `slash-failure`, and `slash-streaming-record`. Record the complete prompt body, images, and streaming behavior. Add tests proving:

```swift
@Test @MainActor func localSlashCommandKeepsAttachmentsAndReturnsIdle() async throws {
    let fixture = try SlashControllerFixture(mode: "slash-local")
    fixture.controller.draft = "/usage"
    fixture.controller.attachments = [fixture.firstAttachment]

    await fixture.controller.sendSlashCommand("/usage")

    #expect(fixture.controller.draft.isEmpty)
    #expect(fixture.controller.attachments.map(\.id) == [fixture.firstAttachment.id])
    #expect(fixture.controller.runtimeState == .idle)
    #expect(fixture.controller.items.isEmpty)
}

@Test @MainActor func agentSlashCommandClearsOnlyAcceptedAttachmentIdentities() async throws {
    let fixture = try SlashControllerFixture(mode: "slash-agent")
    fixture.controller.attachments = [fixture.firstAttachment]
    let send = Task { await fixture.controller.sendSlashCommand("/skill:brainstorming plan it") }
    await fixture.waitUntilPromptArrives()
    fixture.controller.attachments.append(fixture.secondAttachment)
    await send.value

    #expect(fixture.controller.attachments.map(\.id) == [fixture.secondAttachment.id])
}

@Test @MainActor func legacyAgentLifecycleClearsPendingAttachments() async throws {
    let fixture = try SlashControllerFixture(mode: "slash-legacy-agent")
    fixture.controller.attachments = [fixture.firstAttachment]
    await fixture.controller.sendSlashCommand("/compact")
    #expect(await eventually { fixture.controller.attachments.isEmpty })
}

@Test @MainActor func slashCommandDuringStreamingAlwaysUsesFollowUp() async throws {
    let fixture = try SlashControllerFixture(mode: "slash-streaming-record")
    fixture.controller.selectStreamingBehavior(.steer)
    await fixture.enterStreamingState()
    await fixture.controller.sendSlashCommand("/retry")
    #expect(try fixture.recordedStreamingBehavior() == "followUp")
}

@Test @MainActor func slashTransportFailureRestoresDraftAndAttachments() async throws {
    let fixture = try SlashControllerFixture(mode: "slash-failure")
    fixture.controller.attachments = [fixture.firstAttachment]
    await fixture.controller.sendSlashCommand("/compact")
    #expect(fixture.controller.draft == "/compact")
    #expect(fixture.controller.attachments.map(\.id) == [fixture.firstAttachment.id])
}
```

`recordedStreamingBehavior()` decodes the fixture JSON through a small
`Decodable` record type. Do not use a type cast in the test helper.

- [x] **Step 2: Run the focused tests and verify they fail**

Run the five free test functions explicitly. Expected: compilation fails because `sendSlashCommand` is not implemented.

- [x] **Step 3: Extract the shared prompt request core**

Keep `sendPrompt()` behavior unchanged by moving its transport work into a private method with explicit policy:

```swift
private enum AttachmentDisposition {
    case clearImmediately
    case waitForAgent
}

private struct PendingSlashAttachments {
    let ids: Set<ComposerAttachment.ID>
    let generation: UInt64
}

func sendPrompt() async {
    await send(
        text: draft,
        behavior: runtimeState == .streaming ? streamingBehavior : nil,
        attachmentDisposition: .clearImmediately,
        failureFunction: "sendPrompt")
}

func sendSlashCommand(_ text: String) async {
    await send(
        text: text,
        behavior: runtimeState == .streaming ? .followUp : nil,
        attachmentDisposition: .waitForAgent,
        failureFunction: "sendSlashCommand")
}
```

The shared `send` method captures the exact staged attachments, clears the slash draft immediately, marks runtime streaming optimistically, sends canonical text at byte zero, and restores text only when the current draft is still empty after transport failure.

- [x] **Step 4: Implement attachment disposition from response and events**

For `.waitForAgent`:

```swift
switch response.data?["agentInvoked"]?.boolValue {
case true:
    removeAttachments(withIDs: stagedIDs)
case false:
    pendingSlashAttachments = nil
    runtimeState = .idle
    await context.processor?.setRuntimeState(.idle)
case nil:
    pendingSlashAttachments = PendingSlashAttachments(
        ids: stagedIDs,
        generation: context.generation)
}
```

In `applyEventMetadata`, clear those exact IDs on `agent_start` or `turn_start` when the generation matches. On `prompt_result`, discard the pending record without removing attachments. Never replace the full attachments array, because images added after the command was sent must survive.

- [x] **Step 5: Run the slash tests and regression suite**

Run the five new tests, then all app tests. Confirm existing ordinary prompt tests still pass and the fixture records `followUp` while the visible composer mode remains Steer.

- [x] **Step 6: Commit**

```bash
git add App/Sessions/SessionController.swift Tests/TenXAppTests/SessionControllerCommandTests.swift Tests/TenXAppTests/Fixtures/composer_fake_server.py
git commit -m "feat(sessions): execute slash commands safely"
```

---

### Task 7: Bind one command model through AppModel lifecycle

**Files:**
- Modify: `App/Application/AppModel.swift`
- Modify: `App/Application/AppDependencies.swift`
- Modify: `App/Sessions/ComposerCommandModel.swift`
- Modify: `App/Sessions/NewSessionView.swift`
- Modify: `App/Sessions/ActiveSessionView.swift`
- Modify: `Tests/TenXAppTests/StartupTestFixtures.swift`
- Modify: `Tests/TenXAppTests/AppModelNavigationTests.swift`

- [x] **Step 1: Write failing AppModel lifecycle tests**

Add tests that prove `composerCommands` is created with the same catalog instance held by controls, detached to warm New Session mode, attached to the current controller, refreshed when the selected project changes, and stopped before the catalog shuts down.

```swift
@Test @MainActor func appModelSharesOneCatalogBetweenControlsAndCommands() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let model = fixture.model()
    await model.bootstrap()

    let controls = try #require(model.composerControls)
    let commands = try #require(model.composerCommands)
    #expect(commands.testingCatalogIdentity == ObjectIdentifier(controls.catalog))
}

@Test @MainActor func openingAndLeavingASessionSwitchesCommandSources() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let model = fixture.model()
    await model.bootstrap()
    model.openSession(fixture.sessionMetadata())
    #expect(await eventually { model.composerCommands?.isAttachedToActiveSession == true })
    model.openNewSession()
    #expect(model.composerCommands?.isAttachedToActiveSession == false)
}
```

Expose test-only identity and attachment state under `#if DEBUG`; do not expose the service publicly.

- [x] **Step 2: Run the focused tests and verify they fail**

Run both functions explicitly. Expected: compilation fails because `AppModel.composerCommands` does not exist.

- [x] **Step 3: Create and lifecycle-bind the command model**

Add `private(set) var composerCommands: ComposerCommandModel?`. Whenever controls are created, create commands from `controls.catalog` and `controls`:

```swift
let commands = ComposerCommandModel(
    catalog: controls.catalog,
    controls: controls,
    onStartNewSession: { [weak self] prompt, attachments in
        self?.startNewSession(prompt: prompt, attachments: attachments)
    })
```

Whenever controls attach/detach a `SessionController`, make the command model attach/detach in the same branch. On project selection and foreground/provider refresh, call the existing controls refresh; the shared service publishes its command result to the command model. During shutdown or runtime replacement, stop command observation before `controls.shutdown()` closes the shared catalog.

- [x] **Step 4: Pass the model to both composer hosts**

Add `commands: ComposerCommandModel?` to `ComposerView`. `NewSessionView` passes `model.composerCommands`; `ActiveSessionView` passes the same model after AppModel has attached the controller. Do not add a second command model in either SwiftUI view.

- [x] **Step 5: Run AppModel and full app tests**

Run the new lifecycle functions, existing startup/navigation tests, then the entire app target. Expected: all pass with one warm catalog client per selected project.

- [x] **Step 6: Commit**

```bash
git add App/Application App/Sessions/ComposerCommandModel.swift App/Sessions/NewSessionView.swift App/Sessions/ActiveSessionView.swift Tests/TenXAppTests/StartupTestFixtures.swift Tests/TenXAppTests/AppModelNavigationTests.swift
git commit -m "feat(app): bind composer command sources"
```

---

### Task 8: Reuse model-picker content in native command children

**Files:**
- Create: `App/Sessions/ModelPickerContent.swift`
- Modify: `App/Sessions/ModelPickerFlyout.swift`
- Create: `App/Sessions/CommandBrowserNativeControlsView.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`

- [x] **Step 1: Add a failing shared-content snapshot**

Add `commandBrowserModelChildSnapshot()` that renders the model child with two providers, a selected model, loading false, and no footer trigger. The expected panel area is square-edged and uses the same model rows as `composerWithModelFlyoutSnapshot()`.

- [x] **Step 2: Regenerate and verify the snapshot is missing**

Run only `commandBrowserModelChildSnapshot()`. Expected: the test fails and writes `command-browser-model-child.actual.png` because the new view does not exist or has no reference.

- [x] **Step 3: Extract reusable model content**

Move search field, list region, row identity, highlight movement, and scroll-to-highlight from `ModelPickerFlyout` into `ModelPickerContent`. Keep the footer flyout's settings region and stepped trigger chrome in `ModelPickerFlyout`.

```swift
struct ModelPickerContent: View {
    let sections: [ModelPickerSection]
    let selectedModel: ComposerModelInfo?
    let isLoading: Bool
    let isMutating: Bool
    let hasCatalog: Bool
    @Binding var query: String
    let onSelectModel: (ComposerModelInfo) -> Void
    let onCancel: () -> Void
}
```

The footer flyout composes `ModelPickerContent` with its existing dimensions and then renders Effort/Fast settings and trigger. Existing footer and model-picker snapshots must remain byte-identical.

- [x] **Step 4: Implement the three native child surfaces**

`CommandBrowserNativeControlsView` switches on `AppCommand`:

- `/model`: `ModelPickerContent`; selecting a model calls `await commandModel.applyModel(model)`.
- `/effort`: rows from `controls.thinkingOptions`; Enter/click calls `applyEffort`.
- `/fast`: `On`, `Off`, and `Status`; Status displays the current state and returns to root without mutating.

Use exact labels `Model`, `Effort`, `Fast mode`, `On`, `Off`, `Status`, `Applies to the next request`, and existing sanitized control errors. Escape calls `commandModel.back()` and restores editor focus.

- [x] **Step 5: Preserve existing snapshots and record the new child**

Run all existing model-picker and composer footer snapshots first; they must pass without recording. Then record only the new child:

```bash
TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild test -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/commandBrowserModelChildSnapshot()'
```

Open the PNG and verify row typography, selection, border, spacing, and no clipping before accepting it.

- [x] **Step 6: Commit**

```bash
git add App/Sessions/ModelPickerContent.swift App/Sessions/ModelPickerFlyout.swift App/Sessions/CommandBrowserNativeControlsView.swift Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/ReferenceImages/command-browser-model-child.png 10x.xcodeproj
git commit -m "feat(composer): reuse native command controls"
```

---

### Task 9: Build the command-browser panel

**Files:**
- Create: `App/Sessions/CommandBrowserView.swift`
- Create: `App/Sessions/CommandBrowserAccessibility.swift`
- Modify: `Tests/TenXAppTests/AccessibilityLabelTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`

- [x] **Step 1: Write failing accessibility tests**

Add natural labels and pluralization:

```swift
@Test func commandBrowserAccessibilityNamesRowsAndQueueState() {
    #expect(CommandBrowserAccessibility.rowLabel(
        name: "compact",
        description: "Compact the current session",
        source: "Commands",
        position: 4,
        count: 12,
        executionNote: "Runs after the current response"
    ) == "compact, Compact the current session, Commands, 4 of 12, Runs after the current response")
}

@Test func commandBrowserAccessibilityPluralizesSourceCounts() {
    #expect(CommandBrowserAccessibility.sourceValue(count: 1) == "1 command")
    #expect(CommandBrowserAccessibility.sourceValue(count: 2) == "2 commands")
}
```

- [x] **Step 2: Add failing panel snapshots**

Add deterministic snapshots for:

- `commandBrowserRootSnapshot()` at 780 × 520 with App, Commands, Skills, Extensions, and Prompts.
- `commandBrowserStreamingSnapshot()` showing `Runs after the current response`.
- `commandBrowserUnavailableSnapshot()` with the App-only message.
- `commandBrowserNoMatchSnapshot()` showing `No commands match “/modxyz”.`
- `commandBrowserMinimumWindowSnapshot()` inside a 760 × 560 shell.

- [x] **Step 3: Implement metrics and the three-column panel**

Create one root `CommandBrowserView` and private row components in the same file, matching existing repo practice. Use these bounded metrics:

```swift
enum CommandBrowserMetrics {
    static let sourceWidth: CGFloat = 132
    static let resultWidth: CGFloat = 286
    static let minimumDetailWidth: CGFloat = 210
    static let rowHeight: CGFloat = 34
    static let headerHeight: CGFloat = 34
    static let minimumHeight: CGFloat = 220
    static let maximumHeight: CGFloat = 360
}
```

The view structure is:

```swift
VStack(spacing: 0) {
    header
    separator
    HStack(spacing: 0) {
        sourceRail
        verticalSeparator
        resultList
        verticalSeparator
        detailOrChild
    }
}
.background(Color.white)
.overlay(Rectangle().stroke(TenXPalette.color(TenXPalette.nearBlackHex), lineWidth: 1))
.dismissesOnOutsideInteraction(silhouette: Rectangle(), onDismiss: onDismiss)
.accessibilityElement(children: .contain)
.accessibilityLabel("Commands")
```

Only the result column scrolls. Source and detail columns stay fixed. Collapse detail before the source rail if available width drops below the three-column minimum. Use `FlyoutRowBackground` for selected/hovered rows and cyan text/accent for the active source; do not add decorative dividers beyond the column separators.

- [x] **Step 4: Wire pointer and accessibility actions to model intents**

Single click highlights and activates a row through the same model methods as Enter. Hover changes only background. Add VoiceOver adjustable actions for previous/next result, named actions for each source, full untruncated help text, position/count values, queued notes, expanded state for children, and announcements for loading completion, errors, source changes, and removed commands.

- [x] **Step 5: Record and inspect the panel snapshots**

Record only the five new functions with `TEST_RUNNER_RECORD_SNAPSHOTS=1`. Open every PNG. Verify:

- the panel belongs to the existing square composer system;
- row spacing is even;
- no column, label, tooltip, or border clips;
- the minimum-size detail collapses before navigation;
- streaming and unavailable states are honest and readable;
- the panel contains no em dash or marketing copy.

- [x] **Step 6: Run accessibility and snapshot regressions**

Run all `AccessibilityLabelTests` free functions and the complete app test target. Existing reference images must remain unchanged except the deliberately extracted model child if its new reference was reviewed in Task 8.

- [x] **Step 7: Commit**

```bash
git add App/Sessions/CommandBrowserView.swift App/Sessions/CommandBrowserAccessibility.swift Tests/TenXAppTests/AccessibilityLabelTests.swift Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/ReferenceImages 10x.xcodeproj
git commit -m "feat(composer): render the command browser"
```

---

### Task 10: Integrate slash triggering and keyboard control into ComposerView

**Files:**
- Modify: `App/Sessions/ComposerView.swift`
- Modify: `App/Sessions/NewSessionView.swift`
- Modify: `App/Sessions/ActiveSessionView.swift`
- Modify: `Tests/TenXAppTests/ComposerCommandModelTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`

- [x] **Step 1: Add failing key-routing tests**

Extract a pure `ComposerCommandKeyRouting` helper in `ComposerView.swift` and test these mappings:

```swift
@Test func commandBrowserKeyRoutingCoversTheWholeModalWithoutAPointer() {
    #expect(route(.upArrow, modifiers: []) == .move(.previous))
    #expect(route(.downArrow, modifiers: []) == .move(.next))
    #expect(route(.home, modifiers: []) == .move(.first))
    #expect(route(.end, modifiers: []) == .move(.last))
    #expect(route(.pageUp, modifiers: []) == .move(.pagePrevious))
    #expect(route(.pageDown, modifiers: []) == .move(.pageNext))
    #expect(route(.tab, modifiers: [.control]) == .cycle(.forward))
    #expect(route(.tab, modifiers: [.control, .shift]) == .cycle(.backward))
    #expect(route(KeyEquivalent("3"), modifiers: [.command]) == .sourceIndex(3))
    #expect(route(.return, modifiers: []) == .activate)
    #expect(route(.tab, modifiers: []) == .complete)
    #expect(route(.escape, modifiers: []) == .back)
    #expect(route(.leftArrow, modifiers: []) == nil)
}
```

- [x] **Step 2: Verify the routing test fails**

Run only `commandBrowserKeyRoutingCoversTheWholeModalWithoutAPointer()`. Expected: compilation fails because the router is missing.

- [x] **Step 3: Add command flyout state and draft observation**

Extend:

```swift
enum ComposerFlyout: Equatable {
    case project
    case model
    case commands
}
```

When the composer is available, `onChange(of: draft)` calls `commands.updateDraft(draft)`. A true result sets `flyout = .commands`, which closes Project or Model. Removing the valid leading slash closes only the command browser and leaves the remaining draft untouched. Opening Project or Model dismisses command state. Disabled loading/stopped/failed composers never open it.

- [x] **Step 4: Route keys before ordinary Return-to-send**

Replace the Return-only handler with one handler that first checks `flyout == .commands`. Map every approved key to a command-model intent and return `.handled`; return `.ignored` for text editing, paste, Backspace, Left, Right, and modified Return so the `TextEditor` remains the editing surface.

For `.replaceDraft`, assign the canonical text and keep editor focus. For `.executed` or `.dismiss`, close the flyout and restore focus. Enter with close results and no explicit highlight submits the unchanged typed slash through the existing send path; it never silently corrects the typo.

- [x] **Step 5: Attach the overlay above the composer without relayout**

Add the browser to `composerCard.overlay(alignment: .topLeading)` and align its bottom edge to the composer's top edge:

```swift
if flyout == .commands, let commands {
    CommandBrowserView(
        model: commands,
        controls: controls,
        controlsMode: controlsMode,
        onEffect: applyCommandEffect,
        onDismiss: dismissCommands)
        .alignmentGuide(.top) { dimensions in dimensions[.bottom] }
        .transition(shelfTransition)
        .zIndex(2)
}
```

Use the existing `shelfAnimation`; Reduce Motion remains `.identity`. The overlay must not change transcript or composer height.

- [x] **Step 6: Add integrated snapshots**

Add and record:

- active composer with `/` root browser and attachments;
- New Session with Commands source selected and unavailable explanation;
- active streaming with Steer visibly selected while the highlighted command says it will run after the response;
- browser plus long command names at 760 × 560.

Inspect every new image and confirm existing composer, model flyout, attachments, Stop, and growth snapshots remain byte-identical.

- [x] **Step 7: Run the complete app test target**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests
```

Expected: all tests pass with a nonzero Swift Testing summary.

- [x] **Step 8: Commit**

```bash
git add App/Sessions/ComposerView.swift App/Sessions/NewSessionView.swift App/Sessions/ActiveSessionView.swift Tests/TenXAppTests/ComposerCommandModelTests.swift Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/ReferenceImages
git commit -m "feat(composer): open commands from slash input"
```

---

### Task 11: Verify the complete real experience

**Files:**
- Modify only if evidence reveals a scoped defect in the approved flow
- Create: `docs/superpowers/evidence/2026-08-31-command-browser/README.md`
- Create: `docs/superpowers/evidence/2026-08-31-command-browser/*.png`

- [x] **Step 1: Regenerate and prove the generated project is stable**

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
git diff --check
git status --short
```

Expected: generation succeeds, whitespace check is clean, and only intentional branch files are modified.

- [x] **Step 2: Run both complete test gates**

```bash
swift test --package-path OmpKit
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-command-browser-tests
```

Expected: all OmpKit and TenXApp tests pass. Save the final test counts in the evidence README.

- [x] **Step 3: Build Release from the feature worktree**

```bash
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-command-browser-release
```

Expected: `** BUILD SUCCEEDED **` and the app exists at `/private/tmp/tenx-command-browser-release/Build/Products/Release/10x.app`.

- [x] **Step 4: Launch the Release build using `launching-local-builds`**

Confirm branch and SHA, ensure no other session owns this worktree's app instance, then launch:

```bash
open -n /private/tmp/tenx-command-browser-release/Build/Products/Release/10x.app
```

Use Computer Use to confirm the window is visible and responsive before making any handoff claim. Keep the app alive for the user flow; do not kill another session's app.

- [x] **Step 5: Walk the keyboard-only matrix in the real build**

Use an authenticated OMP setup and realistic command catalog. Without a mouse:

1. In New Session type `/`, move through every source with Control-Tab and Command-1 through the last visible rail index, inspect unavailable Commands/Extensions, and Escape.
2. Open `/model`, `/effort`, and `/fast`; apply each with keys and confirm footer state changes with no synthetic user/assistant turn.
3. Select a skill, add arguments, attach an image, and start the session.
4. In an idle active session run a local command and confirm attachment preservation.
5. Start a response, leave Steer selected, choose an OMP workflow, and confirm it is queued as Follow up.
6. Exercise Tab completion, subcommands, invalid arguments, close typo results, Escape child/root behavior, and restored prompt focus.
7. Cause a catalog refresh while open and confirm identity retention/removal recovery.

Capture screenshots of root, native child, New Session unavailable, streaming queued, and minimum 760 × 560 states into the evidence folder.

- [ ] **Step 6: Walk pointer, accessibility, layout, and motion parity**

Repeat source selection, row activation, scrolling, outside dismissal, and child cancellation with the pointer. Run VoiceOver and Full Keyboard Access through sources, rows, details, child controls, errors, and dismissal. Resize continuously from 760 × 560 to a large window and verify no clipping or transcript relayout. Enable Reduce Motion and verify opening/closing uses no motion.

- [x] **Step 7: Document evidence and clean the bench**

Write the README with branch/SHA, exact build/test commands and counts, covered matrix, skipped checks with reasons, and screenshot names. Stop the feature app after Tanner finishes testing; remove only this task's `/private/tmp/tenx-command-browser-*` build directories.

- [x] **Step 8: Commit evidence and run the final diff gate**

```bash
git add docs/superpowers/evidence/2026-08-31-command-browser
git commit -m "test(composer): verify command browser flow"
git diff --check main...HEAD
git status --short --branch
```

Expected: clean status and no whitespace errors.

- [ ] **Step 9: Review and prepare the draft PR**

Invoke `reviewing-code` against the complete `main...HEAD` diff. Fix only findings that block the approved command-browser flow, rerun affected tests and the Release-build check, then invoke `verifying-work` before changing the draft PR to ready. Update the PR's Basic tests and Manual verification sections with the evidence README. Do not merge without Tanner's explicit approval.

---

## Spec coverage map

| Spec requirement | Plan task |
| --- | --- |
| Typed OMP contract, unknown sources, malformed siblings | 1 |
| One warm project-aware process, live updates, App-only fallback | 2 |
| Trigger, source mapping, stable order, ranking, close matches | 3 |
| Keyboard intents, source switching, child routes, live selection | 4 |
| Active-session initial and replacement catalogs | 5 |
| Forced Follow up, local versus agent lifecycle, attachments | 6 |
| Warm/active lifecycle and New Session execution | 7 |
| Reused native Model, Effort, Fast controls | 8 |
| Three-column UI, copy, pointer, VoiceOver, layout | 9 |
| Composer focus, trigger, flyout exclusivity, keyboard integration | 10 |
| Release build, real user flow, snapshots, motion, evidence | 11 |

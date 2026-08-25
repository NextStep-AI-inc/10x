# Provider Setup and Usage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Require one connected OMP provider before first use, provide native connection management, and render real per-account usage in the provider workspace and expanded rail.

**Architecture:** A dedicated no-session `RpcClient` handles provider discovery and OAuth login while a separate process adapter decodes `omp usage --json`. One `@MainActor` feature model joins those sources into setup, Connections, Usage, and rail presentation without changing agent-session processes.

**Tech Stack:** Swift 6.1, SwiftUI, Observation, Swift Testing, AppKit `Process` and `NSWorkspace`, OmpKit RPC v2, macOS 15+

**Spec:** `docs/superpowers/specs/2026-08-25-provider-setup-usage-design.md`

## Global Constraints

- Preserve compatibility with OMP 18.0.4. Do not require an OMP change or a new usage RPC.
- Keep provider RPC separate from `SessionProcessManager`; setup must work without a project or agent session.
- Do not add dependencies, provider logos, credential storage, logout, account pinning, reset-credit redemption, or usage history.
- Use the existing 10x palette, typography, `GhostActionStyle`, `ExtensionUIRouter`, `ExtensionInputSheet`, and rail patterns.
- User-facing text must be factual, compact, free of em dashes, and must never expose stack traces, protocol fields, paths, or credential values.
- Keep Swift strict concurrency enabled and use typed `Sendable` values at actor boundaries.
- Every new source or test file must be followed by `ruby scripts/generate_xcodeproj.rb` before `xcodebuild`.
- Verification uses builds, not a dev server. Do not mutate real provider authentication during automated or agent-run manual checks.
- Baseline on 2026-08-25: `cd OmpKit && swift test` passed 125 tests; `xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' test` passed 90 tests.

## File Map

### OmpKit

- `OmpKit/Sources/OmpKit/Wire/RpcCommand.swift`: add provider discovery and login command factories.
- `OmpKit/Tests/OmpKitTests/CommandEncodingTests.swift`: assert the exact provider command envelopes.

### Provider data and services

- `App/Providers/ProviderLoginProvider.swift`: typed provider discovery row.
- `App/Providers/ProviderUsageSnapshot.swift`: narrow decoding of `omp usage --json`.
- `App/Providers/ProviderUsagePresentation.swift`: provider, account, limit, reset, amount, tone, and rail derivation. This replaces `App/Shell/ProviderUsagePresentation.swift`.
- `App/Providers/OmpUsageRunning.swift`: injectable process runner for `omp usage --json`.
- `App/Providers/OmpUsageService.swift`: exact command invocation and snapshot decoding.
- `App/Providers/ProviderManaging.swift`: provider RPC interface used by the feature model and tests.
- `App/Providers/ProviderManagementService.swift`: dedicated no-session RPC lifecycle and login event forwarding.
- `App/Providers/ProviderManagementViewModel.swift`: main-actor orchestration, catalog filtering, refresh state, OAuth sheet state, and normalized usage.

### Provider UI

- `App/Providers/ProviderSetupView.swift`: required first-run curated setup and full-catalog search.
- `App/Providers/ProvidersView.swift`: provider workspace header and Connections/Usage switch.
- `App/Providers/ProviderConnectionsView.swift`: connected-first catalog and per-provider login states.
- `App/Providers/ProviderConnectionRowView.swift`: one provider row with its own loading, failure, and action state.
- `App/Providers/ProviderUsageDetailView.swift`: provider/account usage, empty states, stale warning, and reconnect actions.

### App integration

- `App/Application/AppDependencies.swift`: live provider-model factory.
- `App/Application/AppModel.swift`: provider model ownership, onboarding gate, navigation, and foreground refresh entry point.
- `App/Application/AppRoute.swift`: provider setup and provider workspace routes.
- `App/Shell/AppShellView.swift`: route the setup and provider canvases.
- `App/Shell/FloatingRailView.swift`: source usage from the provider model and open Usage.
- `App/Shell/ProviderUsageLedgerView.swift`: nested provider/account summary and button semantics.
- `App/Settings/SettingsView.swift`: borderless Providers entry action.
- `App/TenXApp.swift`: request a stale refresh when the scene becomes active.

### Tests and reference images

- `Tests/TenXAppTests/ProviderUsageSnapshotTests.swift`
- `Tests/TenXAppTests/ProviderUsagePresentationTests.swift`
- `Tests/TenXAppTests/OmpUsageServiceTests.swift`
- `Tests/TenXAppTests/ProviderManagementServiceTests.swift`
- `Tests/TenXAppTests/ProviderManagementViewModelTests.swift`
- `Tests/TenXAppTests/ProviderTestFixtures.swift`
- `Tests/TenXAppTests/AppModelNavigationTests.swift`
- `Tests/TenXAppTests/AccessibilityLabelTests.swift`
- `Tests/TenXAppTests/ViewSnapshotTests.swift`
- `Tests/TenXAppTests/ReferenceImages/provider-*.png`
- `10x.xcodeproj/project.pbxproj`

---

### Task 1: Add the Provider Login RPC Commands

**Files:**
- Modify: `OmpKit/Sources/OmpKit/Wire/RpcCommand.swift:65-86`
- Modify: `OmpKit/Tests/OmpKitTests/CommandEncodingTests.swift`

**Interfaces:**
- Consumes: existing `RpcCommand(type:fields:)` and `encodedLine(id:)`.
- Produces: `RpcCommand.getLoginProviders()` and `RpcCommand.login(providerID:)`.

- [ ] **Step 1: Write the failing command-envelope tests**

Append exact assertions:

```swift
@Test func providerLoginCommandsMatchTheOMPContract() throws {
    let list = try json(try RpcCommand.getLoginProviders().encodedLine(id: "providers"))
    #expect(list.count == 2)
    #expect(list["id"] as? String == "providers")
    #expect(list["type"] as? String == "get_login_providers")

    let login = try json(try RpcCommand.login(providerID: "openai-codex")
        .encodedLine(id: "login"))
    #expect(login["id"] as? String == "login")
    #expect(login["type"] as? String == "login")
    #expect(login["providerId"] as? String == "openai-codex")
}
```

- [ ] **Step 2: Run the focused test and confirm the missing factories fail compilation**

Run:

```bash
cd OmpKit
swift test --filter providerLoginCommandsMatchTheOMPContract
```

Expected: compile failure because `getLoginProviders` and `login(providerID:)` do not exist.

- [ ] **Step 3: Add the minimal command factories**

Add under a `// MARK: - Login` section:

```swift
public static func getLoginProviders() -> RpcCommand {
    RpcCommand(type: "get_login_providers")
}

public static func login(providerID: String) -> RpcCommand {
    RpcCommand(type: "login", fields: ["providerId": .string(providerID)])
}
```

- [ ] **Step 4: Run the focused and full OmpKit suites**

Run:

```bash
cd OmpKit
swift test --filter providerLoginCommandsMatchTheOMPContract
swift test
```

Expected: focused PASS; full suite PASS with at least 126 executed tests and only the existing opt-in integration skips.

- [ ] **Step 5: Commit the RPC contract**

```bash
git add OmpKit/Sources/OmpKit/Wire/RpcCommand.swift OmpKit/Tests/OmpKitTests/CommandEncodingTests.swift
git commit -m "feat(ompkit): add provider login commands"
```

---

### Task 2: Decode Usage and Derive Honest Presentation

**Files:**
- Create: `App/Providers/ProviderUsageSnapshot.swift`
- Create: `App/Providers/ProviderUsagePresentation.swift`
- Delete: `App/Shell/ProviderUsagePresentation.swift`
- Create: `Tests/TenXAppTests/ProviderUsageSnapshotTests.swift`
- Modify: `Tests/TenXAppTests/ProviderUsagePresentationTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` via generator

**Interfaces:**
- Consumes: OMP's `usage --json` fields and `OmpKit.JSONValue` for unstructured metadata.
- Produces: `OmpUsageSnapshot`, `ProviderUsagePresentation.make(snapshot:providerNames:now:)`, `ProviderUsageProvider`, `ProviderUsageAccount`, `ProviderUsageLimit`, `ProviderUsageAmount`, and `ProviderCredentialIssue`.

- [ ] **Step 1: Add a realistic failing decoder fixture**

Create a test containing a report, an amount without a limit, an account without usage, a disabled credential, and an unknown field:

```swift
let usageSnapshotFixtureData = Data(#"""
    {
      "generatedAt":1787675745954,
      "reports":[{
        "provider":"cursor",
        "fetchedAt":1787675745599,
        "limits":[
          {"id":"cursor:models","label":"Cursor Models","scope":{"provider":"cursor","windowId":"monthly"},"window":{"id":"monthly","label":"Monthly","resetsAt":1788061624000},"amount":{"usedFraction":0.499,"unit":"percent"},"status":"ok"},
          {"id":"cursor:requests","label":"Requests","scope":{"provider":"cursor"},"amount":{"used":4,"unit":"requests"}}
        ],
        "metadata":{"email":"tanner@example.com"},
        "futureField":{"ignored":true}
      }],
      "accountsWithoutUsage":[{"provider":"github-copilot","email":"work@example.com"}],
      "disabledCredentials":[{"id":2,"provider":"anthropic","type":"oauth","cause":"refresh failed","email":"old@example.com","disabledAtMs":1787616419000}],
      "capacity":{}
    }
    """#.utf8)

func usageSnapshotFixture() throws -> OmpUsageSnapshot {
    try JSONDecoder().decode(OmpUsageSnapshot.self, from: usageSnapshotFixtureData)
}

@Test func usageSnapshotDecodesTheNarrowOMPContract() throws {
    let snapshot = try usageSnapshotFixture()
    #expect(snapshot.reports[0].limits.count == 2)
    #expect(snapshot.reports[0].metadata?["email"]?.stringValue == "tanner@example.com")
    #expect(snapshot.accountsWithoutUsage[0].provider == "github-copilot")
    #expect(snapshot.disabledCredentials[0].provider == "anthropic")
}
```

- [ ] **Step 2: Add failing presentation tests for remaining capacity and rail filtering**

Extend the existing tests with exact behavior:

```swift
@Test func usagePresentationShowsRemainingCapacityAndOmitsUnboundedRailAmounts() throws {
    let snapshot = try usageSnapshotFixture()
    let presentation = ProviderUsagePresentation.make(
        snapshot: snapshot,
        providerNames: ["cursor": "Cursor"],
        now: Date(timeIntervalSince1970: 1_787_675_746))

    let account = try #require(presentation.providers.first?.accounts.first)
    #expect(account.label == "tanner@example.com")
    #expect(account.limits[0].percentage == 50)
    #expect(account.limits[0].tone == .standard)
    #expect(account.amounts == [ProviderUsageAmount(id: "cursor:requests", label: "Requests", value: 4, unit: "requests")])
    #expect(presentation.railProviders[0].accounts[0].limits.map(\.label) == ["Cursor Models"])
}

@Test func remainingCapacityClampsAndUsesAttentionTones() {
    #expect(ProviderUsageLimit.remainingPercentage(usedFraction: -0.2) == 100)
    #expect(ProviderUsageLimit.remainingPercentage(usedFraction: 0.82) == 18)
    #expect(ProviderUsageLimit.remainingPercentage(usedFraction: 1.4) == 0)
}
```

- [ ] **Step 3: Run focused tests and confirm the new types are missing**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/usageSnapshotDecodesTheNarrowOMPContract \
  -only-testing:TenXAppTests/usagePresentationShowsRemainingCapacityAndOmitsUnboundedRailAmounts test
```

Expected: compile failure for `OmpUsageSnapshot` and the expanded presentation types.

- [ ] **Step 4: Implement the narrow Decodable contract**

Define `Sendable`, `Equatable`, `Decodable` structs with optional fields where OMP may omit data:

```swift
struct OmpUsageSnapshot: Decodable, Equatable, Sendable {
    let generatedAt: Int64
    let reports: [OmpUsageReport]
    let accountsWithoutUsage: [OmpUsageAccountIdentity]
    let disabledCredentials: [OmpDisabledCredential]

    static let empty = OmpUsageSnapshot(
        generatedAt: 0,
        reports: [],
        accountsWithoutUsage: [],
        disabledCredentials: [])
}

struct OmpUsageReport: Decodable, Equatable, Sendable {
    let provider: String
    let fetchedAt: Int64
    let limits: [OmpUsageLimit]
    let metadata: [String: JSONValue]?
}

struct OmpUsageLimit: Decodable, Equatable, Sendable {
    let id: String
    let label: String
    let scope: OmpUsageScope
    let window: OmpUsageWindow?
    let amount: OmpUsageAmount
    let status: String?
    let notes: [String]?
}

struct OmpUsageScope: Decodable, Equatable, Sendable {
    let provider: String
    let accountId: String?
    let projectId: String?
    let orgId: String?
    let modelId: String?
    let tier: String?
    let windowId: String?
    let shared: Bool?
}

struct OmpUsageWindow: Decodable, Equatable, Sendable {
    let id: String
    let label: String?
    let resetsAt: Int64?
}

struct OmpUsageAmount: Decodable, Equatable, Sendable {
    let used: Double?
    let limit: Double?
    let remaining: Double?
    let usedFraction: Double?
    let remainingFraction: Double?
    let unit: String
}

struct OmpUsageAccountIdentity: Decodable, Equatable, Sendable {
    let provider: String
    let email: String?
    let accountId: String?
    let projectId: String?
    let enterpriseUrl: String?
    let orgId: String?
    let orgName: String?
}

struct OmpDisabledCredential: Decodable, Equatable, Sendable {
    let id: Int
    let provider: String
    let type: String
    let cause: String
    let email: String?
    let accountId: String?
    let orgId: String?
    let orgName: String?
    let disabledAtMs: Int64
}
```

Let synthesized decoding supply `nil` for omitted optional keys. Do not model `raw`, `capacity`, or reset-credit redemption.

- [ ] **Step 5: Implement deterministic presentation derivation**

Move the existing presentation types to `App/Providers` and expand them. Keep the tone thresholds already tested. Derive remaining fraction in this order:

```swift
private static func remainingFraction(_ amount: OmpUsageAmount) -> Double? {
    if let remaining = amount.remainingFraction { return clamp(remaining) }
    if let used = amount.usedFraction { return clamp(1 - used) }
    if let used = amount.used, let limit = amount.limit, limit > 0 {
        return clamp(1 - used / limit)
    }
    if amount.unit == "percent", let used = amount.used {
        return clamp(1 - used / 100)
    }
    return nil
}

private static func clamp(_ value: Double) -> Double {
    min(max(value, 0), 1)
}
```

Define `ProviderUsagePresentation.empty` with empty provider, missing-account, and credential-issue arrays. Keep `lastUsageRefresh` only on `ProviderManagementViewModel`; the empty presentation must not represent a successful refresh.

Use `Int((fraction * 100).rounded())`, milliseconds-since-epoch dates, locale-aware detail reset text, concise rail reset text, provider-id fallback names, stable ids, and account labels in this order: email, account id, project id, then “Connected account.”

- [ ] **Step 6: Regenerate the project and run the focused tests**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/usageSnapshotDecodesTheNarrowOMPContract \
  -only-testing:TenXAppTests/usagePresentationShowsRemainingCapacityAndOmitsUnboundedRailAmounts \
  -only-testing:TenXAppTests/providerUsageToneMakesOnlyLowAndExhaustedLimitsAttentionStates test
```

Expected: all selected tests PASS.

- [ ] **Step 7: Commit the usage contract and presentation**

```bash
git add App/Providers App/Shell/ProviderUsagePresentation.swift Tests/TenXAppTests/ProviderUsageSnapshotTests.swift Tests/TenXAppTests/ProviderUsagePresentationTests.swift 10x.xcodeproj
git commit -m "feat(providers): model provider usage"
```

---

### Task 3: Run the Exact Usage Command

**Files:**
- Create: `App/Providers/OmpUsageRunning.swift`
- Create: `App/Providers/OmpUsageService.swift`
- Create: `Tests/TenXAppTests/OmpUsageServiceTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` via generator

**Interfaces:**
- Consumes: `OmpUsageSnapshot` from Task 2 and the resolved OMP executable URL.
- Produces: `OmpUsageLoading.loadUsage() async throws -> OmpUsageSnapshot`, `OmpUsageService`, and `OmpUsageProcessRunner`.

- [ ] **Step 1: Write failing tests for exact arguments and sanitized failure**

```swift
@Test func usageServiceRunsTheExactJSONCommand() async throws {
    let runner = FakeUsageRunner(result: Data(#"{"generatedAt":1,"reports":[],"accountsWithoutUsage":[],"disabledCredentials":[],"capacity":{}}"#.utf8))
    let snapshot = try await OmpUsageService(runner: runner).loadUsage()
    #expect(snapshot.generatedAt == 1)
    #expect(await runner.calls == [["usage", "--json"]])
}

@Test func usageServiceErrorDoesNotExposeStderr() async {
    let service = OmpUsageService(runner: FailingUsageRunner())
    await #expect(throws: OmpUsageServiceError.self) {
        _ = try await service.loadUsage()
    }
}
```

The failing runner's underlying message must contain a fake credential and path; assert the localized service error contains neither.

Use these test doubles so the test also proves call capture is actor-safe:

```swift
private actor FakeUsageRunner: OmpUsageRunning {
    private let result: Data
    private(set) var calls: [[String]] = []

    init(result: Data) { self.result = result }

    func run(arguments: [String]) async throws -> Data {
        calls.append(arguments)
        return result
    }
}

private struct FailingUsageRunner: OmpUsageRunning {
    func run(arguments: [String]) async throws -> Data {
        throw FakeUsageFailure("token=secret at /Users/example/.omp")
    }
}

private struct FakeUsageFailure: Error {
    let detail: String
    init(_ detail: String) { self.detail = detail }
}
```

- [ ] **Step 2: Run the focused tests and confirm the service is missing**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/usageServiceRunsTheExactJSONCommand test
```

Expected: compile failure for `OmpUsageService` and `OmpUsageRunning`.

- [ ] **Step 3: Implement the runner and service**

Use the existing config-runner pattern, but keep usage-specific errors and never return stderr:

```swift
protocol OmpUsageLoading: Sendable {
    func loadUsage() async throws -> OmpUsageSnapshot
}

protocol OmpUsageRunning: Sendable {
    func run(arguments: [String]) async throws -> Data
}

actor OmpUsageService: OmpUsageLoading {
    private let runner: any OmpUsageRunning

    init(runner: any OmpUsageRunning) { self.runner = runner }

    func loadUsage() async throws -> OmpUsageSnapshot {
        do {
            let data = try await runner.run(arguments: ["usage", "--json"])
            return try JSONDecoder().decode(OmpUsageSnapshot.self, from: data)
        } catch {
            throw OmpUsageServiceError.loadFailed
        }
    }
}

enum OmpUsageServiceError: LocalizedError {
    case loadFailed

    var errorDescription: String? {
        "[Providers:OmpUsageService] Unable to load provider usage — {usage}"
    }
}
```

`OmpUsageProcessRunner` must invoke `Process` directly with the executable URL, drain stdout and stderr concurrently, require exit status zero, and discard stderr content after determining success.

- [ ] **Step 4: Regenerate and run service plus full app tests**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/usageServiceRunsTheExactJSONCommand \
  -only-testing:TenXAppTests/usageServiceErrorDoesNotExposeStderr test
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' test
```

Expected: focused PASS; full app suite PASS.

- [ ] **Step 5: Commit the usage adapter**

```bash
git add App/Providers/OmpUsageRunning.swift App/Providers/OmpUsageService.swift Tests/TenXAppTests/OmpUsageServiceTests.swift 10x.xcodeproj
git commit -m "feat(providers): load usage from OMP"
```

---

### Task 4: Own Provider Discovery and OAuth in a No-Session Client

**Files:**
- Create: `App/Providers/ProviderLoginProvider.swift`
- Create: `App/Providers/ProviderManaging.swift`
- Create: `App/Providers/ProviderManagementService.swift`
- Create: `Tests/TenXAppTests/ProviderManagementServiceTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` via generator

**Interfaces:**
- Consumes: Task 1 RPC factories, `RpcClientConfiguration.noSession`, `RpcClient.events`, and `ExtensionUIRequest`.
- Produces: `ProviderLoginProvider`, `ProviderManaging`, discovery, login, cancellation, response, event stream, and shutdown methods.

- [ ] **Step 1: Write failing discovery and event-forwarding tests**

Use a fake `ProviderRPCClient` actor with controllable responses and an `AsyncStream<RpcFrame>`. Assert:

```swift
private let providerListResponse = RpcResponse(
    id: "providers",
    command: "get_login_providers",
    success: true,
    data: .object(["providers": .array([
        .object([
            "id": .string("cursor"),
            "name": .string("Cursor"),
            "available": .bool(true),
            "authenticated": .bool(true),
        ]),
    ])]))

private let loginResponse = RpcResponse(
    id: "login",
    command: "login",
    success: true,
    data: .object(["providerId": .string("cursor")]))

private let openURLFrame = RpcFrame.extensionUIRequest(ExtensionUIRequest(
    id: "open",
    method: "open_url",
    payload: .object([
        "type": .string("extension_ui_request"),
        "id": .string("open"),
        "method": .string("open_url"),
        "url": .string("https://example.com/login"),
    ])))

@Test func providerServiceDiscoversTypedProviders() async throws {
    let fake = FakeProviderRPCClient(responses: [providerListResponse])
    let service = ProviderManagementService(
        executableURL: URL(fileURLWithPath: "/tmp/omp"),
        clientFactory: { _ in fake })

    let providers = try await service.providers()
    #expect(providers == [
        ProviderLoginProvider(id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    #expect(await fake.commands.map(\.type) == ["get_login_providers"])
}

@Test func providerServiceForwardsLoginExtensionRequests() async throws {
    let fake = FakeProviderRPCClient(responses: [loginResponse])
    let service = ProviderManagementService(executableURL: URL(fileURLWithPath: "/tmp/omp"), clientFactory: { _ in fake })
    let eventTask = Task { await service.events.first { _ in true } }
    await fake.emit(openURLFrame)
    #expect(await eventTask.value?.method == "open_url")
}
```

The fake client must record `startCount`, `commands`, `rawCommands`, and `shutdownCount`, return queued responses, and expose `emit(_:)` through its stream continuation. Add a cancellation test proving `cancelLogin()` increments `shutdownCount` and the next discovery calls the injected factory and `start()` again.

- [ ] **Step 2: Run focused tests and confirm the service types are missing**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/providerServiceDiscoversTypedProviders \
  -only-testing:TenXAppTests/providerServiceForwardsLoginExtensionRequests test
```

Expected: compile failure for provider service types.

- [ ] **Step 3: Define the narrow RPC seam**

```swift
protocol ProviderRPCClient: Sendable {
    var events: AsyncStream<RpcFrame> { get }
    func start() async throws -> ReadyFrame
    func send(_ command: RpcCommand, timeout: Duration?) async throws -> RpcResponse
    func sendRaw(_ command: RpcCommand) async throws
    func shutdown() async
}

extension RpcClient: ProviderRPCClient {}

protocol ProviderManaging: Sendable {
    var events: AsyncStream<ExtensionUIRequest> { get }
    func providers() async throws -> [ProviderLoginProvider]
    func login(providerID: String) async throws
    func respond(requestID: String, body: [String: JSONValue]) async throws
    func cancelLogin() async
    func shutdown() async
}
```

`ProviderLoginProvider` is `Identifiable`, `Equatable`, and `Sendable`, with `id`, `name`, `isAvailable`, and `isAuthenticated`.

- [ ] **Step 4: Implement lazy no-session lifecycle and parsing**

`ProviderManagementService` must:

1. create `RpcClientConfiguration` with the resolved executable and `noSession = true`;
2. lazily start one client;
3. launch exactly one task that forwards only `.extensionUIRequest` frames;
4. parse `data.providers` without force casts;
5. call `.login(providerID:)` with `.seconds(600)`;
6. send existing `extensionUIResponse` bodies through `sendRaw`;
7. on cancel, cancel the event task, shut down the client, and clear it so the next call creates a fresh process.

Use an `AsyncStream<ExtensionUIRequest>` continuation created in `init`. Finish the stream only in `shutdown`, not during a cancel/recreate cycle.

- [ ] **Step 5: Run provider service and full OmpKit tests**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/ProviderManagementServiceTests test
cd OmpKit && swift test
```

Expected: provider service tests PASS; OmpKit suite PASS.

- [ ] **Step 6: Commit the provider RPC service**

```bash
git add App/Providers/ProviderLoginProvider.swift App/Providers/ProviderManaging.swift App/Providers/ProviderManagementService.swift Tests/TenXAppTests/ProviderManagementServiceTests.swift 10x.xcodeproj
git commit -m "feat(providers): manage OMP provider login"
```

---

### Task 5: Orchestrate Provider State in One Feature Model

**Files:**
- Create: `App/Providers/ProviderManagementViewModel.swift`
- Create: `Tests/TenXAppTests/ProviderManagementViewModelTests.swift`
- Create: `Tests/TenXAppTests/ProviderTestFixtures.swift`
- Modify: `10x.xcodeproj/project.pbxproj` via generator

**Interfaces:**
- Consumes: `ProviderManaging`, `OmpUsageLoading`, `ExtensionUIRouter`, `ProviderUsagePresentation`, `NSWorkspace` through an injected URL opener, and a clock closure.
- Produces: `ProviderWorkspaceSection`, catalog/search state, onboarding eligibility, login state, OAuth sheet state, refresh errors, last update, and `railProviders`.

- [ ] **Step 1: Write failing tests for catalog ordering and onboarding eligibility**

```swift
@MainActor
@Test func providerModelLoadsCuratedConnectedFirstAndGatesContinue() async {
    let providers = [
        ProviderLoginProvider(id: "anthropic", name: "Anthropic", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
        ProviderLoginProvider(id: "zai", name: "Z.AI", isAvailable: true, isAuthenticated: false),
    ]
    let model = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: providers),
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })

    await model.load()

    #expect(model.hasAuthenticatedProvider)
    #expect(model.visibleProviders.map(\.id) == ["cursor", "anthropic"])
    model.showAllProviders()
    #expect(model.visibleProviders.map(\.id) == ["cursor", "anthropic", "zai"])
}
```

The curated id order is `openai-codex`, `anthropic`, `cursor`, `google-gemini-cli`; authenticated rows sort before disconnected rows while preserving that curated order, then full-catalog rows sort by localized name.

- [ ] **Step 2: Write failing tests for login events and stale refresh**

Add tests proving:

- an `open_url` event opens the validated `launchUrl` and keeps the active provider id;
- an `input` event becomes `sheetRequest` and `respond` emits the exact extension response body;
- successful login reloads providers and usage;
- cancel delegates to `cancelLogin` and clears transient state;
- a usage failure preserves the prior presentation and records a plain stale warning;
- `refreshIfStale` does nothing before 300 seconds and refreshes at 300 seconds.

Use exact assertions such as:

```swift
#expect(model.usageMessage == "Usage couldn’t be refreshed. Showing data from 4:00 PM.")
#expect(await usageService.loadCount == 2)
```

Create reusable test actors in `ProviderTestFixtures.swift`:

```swift
actor FakeProviderService: ProviderManaging {
    nonisolated let events: AsyncStream<ExtensionUIRequest>
    private let continuation: AsyncStream<ExtensionUIRequest>.Continuation
    private var storedProviders: [ProviderLoginProvider]
    private(set) var loginIDs: [String] = []
    private(set) var responses: [(String, [String: JSONValue])] = []
    private(set) var cancelCount = 0
    private var providerError: (any Error & Sendable)?

    init(
        providers: [ProviderLoginProvider],
        providerError: (any Error & Sendable)? = nil
    ) {
        storedProviders = providers
        self.providerError = providerError
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    func providers() async throws -> [ProviderLoginProvider] {
        if let providerError { throw providerError }
        return storedProviders
    }
    func login(providerID: String) async throws {
        loginIDs.append(providerID)
        storedProviders = storedProviders.map { provider in
            guard provider.id == providerID else { return provider }
            return ProviderLoginProvider(
                id: provider.id,
                name: provider.name,
                isAvailable: provider.isAvailable,
                isAuthenticated: true)
        }
    }
    func respond(requestID: String, body: [String: JSONValue]) async throws {
        responses.append((requestID, body))
    }
    func cancelLogin() async { cancelCount += 1 }
    func shutdown() async { continuation.finish() }
    func emit(_ request: ExtensionUIRequest) { continuation.yield(request) }
}

enum FakeProviderError: Error, Sendable {
    case discoveryFailed
}

actor FakeUsageService: OmpUsageLoading {
    private let snapshot: OmpUsageSnapshot
    private(set) var loadCount = 0
    var isFailing = false

    init(snapshot: OmpUsageSnapshot) { self.snapshot = snapshot }

    func loadUsage() async throws -> OmpUsageSnapshot {
        loadCount += 1
        if isFailing { throw OmpUsageServiceError.loadFailed }
        return snapshot
    }

    func setFailing(_ value: Bool) { isFailing = value }
}
```

Also provide this reusable constructor so routing and snapshot tests use the same deterministic model without duplicating fixtures:

```swift
@MainActor
func providerTestModel(
    providers: [ProviderLoginProvider],
    snapshot: OmpUsageSnapshot = .empty,
    providerError: (any Error & Sendable)? = nil,
    now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 100) }
) -> ProviderManagementViewModel {
    ProviderManagementViewModel(
        providerService: FakeProviderService(
            providers: providers,
            providerError: providerError),
        usageService: FakeUsageService(snapshot: snapshot),
        openURL: { _ in },
        now: now,
        formatTime: { _ in "4:00 PM" })
}
```

- [ ] **Step 3: Run focused tests and confirm the model is missing**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/ProviderManagementViewModelTests test
```

Expected: compile failure for `ProviderManagementViewModel`.

- [ ] **Step 4: Implement the observable state contract**

Start with these stable properties and methods:

```swift
enum ProviderWorkspaceSection: Equatable, Sendable {
    case connections
    case usage
}

@MainActor
@Observable
final class ProviderManagementViewModel {
    var query = ""
    var isShowingAllProviders = false
    var selectedSection: ProviderWorkspaceSection = .connections
    private(set) var providers: [ProviderLoginProvider] = []
    private(set) var usage = ProviderUsagePresentation.empty
    private(set) var isLoadingProviders = false
    private(set) var isRefreshingUsage = false
    private(set) var providerMessage: String?
    private(set) var usageMessage: String?
    private(set) var activeLoginProviderID: String?
    private(set) var loginMessage: String?
    private(set) var sheetRequest: ExtensionUIState?
    private(set) var lastUsageRefresh: Date?

    private let formatTime: @Sendable (Date) -> String

    var hasAuthenticatedProvider: Bool { providers.contains { $0.isAvailable && $0.isAuthenticated } }
    var visibleProviders: [ProviderLoginProvider] {
        let selected = isShowingAllProviders
            ? providers
            : providers.filter { Self.curatedProviderIDs.contains($0.id) || $0.isAuthenticated }
        let matching = query.isEmpty
            ? selected
            : selected.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || $0.id.localizedCaseInsensitiveContains(query)
            }
        return matching.sorted(by: Self.providerOrder)
    }
    var railProviders: [ProviderUsageProvider] { usage.railProviders }

    func load() async
    func refresh() async
    func refreshIfStale() async
    func login(_ provider: ProviderLoginProvider) async
    func cancelLogin() async
    func respond(to request: ExtensionUIState, with response: ExtensionUIResponse) async
    func showAllProviders()

    private static let curatedProviderIDs = [
        "openai-codex",
        "anthropic",
        "cursor",
        "google-gemini-cli",
    ]

    private static func providerOrder(
        _ lhs: ProviderLoginProvider,
        _ rhs: ProviderLoginProvider
    ) -> Bool {
        if lhs.isAuthenticated != rhs.isAuthenticated { return lhs.isAuthenticated }
        let lhsIndex = curatedProviderIDs.firstIndex(of: lhs.id) ?? Int.max
        let rhsIndex = curatedProviderIDs.firstIndex(of: rhs.id) ?? Int.max
        if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
```

The initializer accepts `formatTime`, defaulting to locale-aware shortened time formatting. Tests inject `{ _ in "4:00 PM" }`, so stale-warning assertions are deterministic across machines and locales.

Consume the provider service event stream in one task. Reuse `ExtensionUIRouter.parse`; accept only `.openURL`, `.input`, `.notification`, and `.cancel` for this feature. UI strings must match the spec exactly. Provider discovery and usage loads may complete independently, but each has its own in-flight guard.

- [ ] **Step 5: Run model tests and the full app suite**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/ProviderManagementViewModelTests test
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' test
```

Expected: focused PASS; full app suite PASS.

- [ ] **Step 6: Commit the feature model**

```bash
git add App/Providers/ProviderManagementViewModel.swift Tests/TenXAppTests/ProviderManagementViewModelTests.swift Tests/TenXAppTests/ProviderTestFixtures.swift 10x.xcodeproj
git commit -m "feat(providers): coordinate connection state"
```

---

### Task 6: Gate First Run on Provider Setup

**Files:**
- Create: `App/Providers/ProviderSetupView.swift`
- Modify: `App/Application/AppDependencies.swift`
- Modify: `App/Application/AppModel.swift:7-130`
- Modify: `App/Application/AppRoute.swift`
- Modify: `App/Shell/AppShellView.swift:8-61`
- Modify: `Tests/TenXAppTests/AppModelNavigationTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Create: `Tests/TenXAppTests/ReferenceImages/provider-setup-required.png`
- Create: `Tests/TenXAppTests/ReferenceImages/provider-setup-connected.png`
- Modify: `10x.xcodeproj/project.pbxproj` via generator

**Interfaces:**
- Consumes: `ProviderManagementViewModel.load`, `hasAuthenticatedProvider`, `visibleProviders`, login methods, and OAuth sheet state.
- Produces: `.providerSetup`, `.providers(ProviderWorkspaceSection)`, `AppModel.completeProviderSetup`, and the required setup canvas.

- [ ] **Step 1: Write failing route-gate tests**

Add injected dependency tests for three outcomes:

```swift
@MainActor
@Test func bootstrapRequiresProviderWhenOMPHasNoAuthenticatedProvider() async {
    let providerModel = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
    ])
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))

    await model.bootstrap()

    #expect(model.route == .providerSetup)
}

@MainActor
@Test func bootstrapOpensNewSessionWhenAProviderIsAuthenticated() async {
    let providerModel = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))
    await model.bootstrap()
    #expect(model.route == .newSession)
}

@MainActor
@Test func providerDiscoveryFailureKeepsRequiredSetupVisible() async {
    let providerModel = providerTestModel(
        providers: [],
        providerError: FakeProviderError.discoveryFailed)
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))
    await model.bootstrap()
    #expect(model.route == .providerSetup)
}
```

Add the exact dependency helper in `AppModelNavigationTests.swift`:

```swift
private struct InstalledOmpLocator: OmpLocating {
    func locate(preferredURL: URL?) async -> OmpInstallation? {
        OmpInstallation(
            executableURL: URL(filePath: "/tmp/omp"),
            version: "test")
    }
}

@MainActor
private func testDependencies(
    providerModel: ProviderManagementViewModel
) -> AppDependencies {
    AppDependencies(
        ompLocator: InstalledOmpLocator(),
        sessionLibrary: SessionLibrary(root: URL(
            filePath: "/tmp/10x-provider-tests-empty",
            directoryHint: .isDirectory)),
        makeProviderModel: { _ in providerModel })
}
```

- [ ] **Step 2: Add failing setup snapshots**

Render `ProviderSetupView` at `760x560` for disconnected and connected preview models. The connected fixture must show Cursor authenticated and Continue enabled. Recordings must be named exactly `provider-setup-required` and `provider-setup-connected`.

- [ ] **Step 3: Run focused tests and confirm routes and view are missing**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/bootstrapRequiresProviderWhenOMPHasNoAuthenticatedProvider \
  -only-testing:TenXAppTests/providerSetupRequiredSnapshot test
```

Expected: compile failure for `.providerSetup` and `ProviderSetupView`.

- [ ] **Step 4: Wire provider dependencies and routes**

Add to `AppDependencies`:

```swift
let makeProviderModel: @MainActor @Sendable (URL) -> ProviderManagementViewModel
```

The live factory constructs `ProviderManagementService`, `OmpUsageService`, `OmpUsageProcessRunner`, and an `NSWorkspace.shared.open` URL closure from the resolved executable URL.

Add routes:

```swift
enum AppRoute: Equatable {
    case setup
    case providerSetup
    case newSession
    case session(String)
    case settings
    case providers(ProviderWorkspaceSection)
}
```

`AppModel.install` stores `private(set) var providerModel: ProviderManagementViewModel?`, constructs and loads it, routes to provider setup on discovery failure or no authentication, and routes to New Session only after confirmed authentication. Add:

```swift
func completeProviderSetup() {
    guard providerModel?.hasAuthenticatedProvider == true else { return }
    route = .newSession
}
```

- [ ] **Step 5: Build the required setup view**

Use the approved copy and behavior:

- title: `Connect a provider`
- subtitle: `Choose at least one provider to start sessions.`
- curated provider rows first;
- `Browse all providers` replaces the curated list with search in place;
- `Continue` stays disabled until `hasAuthenticatedProvider`;
- active login row shows honest progress and Cancel;
- `.sheet(item:)` reuses `ExtensionInputSheet`;
- discovery failure shows `Providers couldn’t be loaded.` and `Try again`.

Keep the setup route outside the rail and top actions, matching the existing OMP setup canvas.

- [ ] **Step 6: Record snapshots, then run focused tests**

```bash
ruby scripts/generate_xcodeproj.rb
RECORD_SNAPSHOTS=1 xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/providerSetupRequiredSnapshot \
  -only-testing:TenXAppTests/providerSetupConnectedSnapshot test
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/AppModelNavigationTests \
  -only-testing:TenXAppTests/providerSetupRequiredSnapshot \
  -only-testing:TenXAppTests/providerSetupConnectedSnapshot test
```

Expected: route and snapshot tests PASS.

- [ ] **Step 7: Commit required onboarding**

```bash
git add App/Application App/Providers/ProviderSetupView.swift App/Shell/AppShellView.swift Tests/TenXAppTests/AppModelNavigationTests.swift Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/ReferenceImages/provider-setup-*.png 10x.xcodeproj
git commit -m "feat(providers): require provider setup"
```

---

### Task 7: Add the Connections and Usage Workspace

**Files:**
- Create: `App/Providers/ProvidersView.swift`
- Create: `App/Providers/ProviderConnectionsView.swift`
- Create: `App/Providers/ProviderConnectionRowView.swift`
- Create: `App/Providers/ProviderUsageDetailView.swift`
- Modify: `App/Application/AppModel.swift`
- Modify: `App/Shell/AppShellView.swift`
- Modify: `App/Settings/SettingsView.swift:3-47`
- Modify: `Tests/TenXAppTests/AppModelNavigationTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Create: `Tests/TenXAppTests/ReferenceImages/provider-connections.png`
- Create: `Tests/TenXAppTests/ReferenceImages/provider-usage-detail.png`
- Create: `Tests/TenXAppTests/ReferenceImages/provider-usage-stale.png`
- Modify: `10x.xcodeproj/project.pbxproj` via generator

**Interfaces:**
- Consumes: provider model state and methods from Task 5 plus `.providers(section)` from Task 6.
- Produces: `AppModel.openProviders(_:)`, settings entry, workspace navigation, detailed account usage, and recovery actions.

- [ ] **Step 1: Write failing navigation tests**

```swift
@MainActor
@Test func openProvidersSelectsTheRequestedWorkspaceSection() async {
    let providerModel = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))
    await model.bootstrap()
    model.openProviders(.usage)
    #expect(model.route == .providers(.usage))
    #expect(model.providerModel?.selectedSection == .usage)
}
```

Also assert Settings' Providers action invokes `.providers(.connections)` without changing settings data.

- [ ] **Step 2: Add failing workspace snapshots**

Use a preview provider model containing:

- Cursor connected with two limits at 50% and 0%;
- one amount-only request count;
- Anthropic disabled with a reconnect action;
- GitHub Copilot connected without usage;
- a stale usage warning with a fixed last-update time.

Render Connections, Usage, and stale Usage at `1180x760` with the exact reference names in the Files list.

- [ ] **Step 3: Run focused tests and confirm the workspace views are missing**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/openProvidersSelectsTheRequestedWorkspaceSection \
  -only-testing:TenXAppTests/providerConnectionsSnapshot test
```

Expected: compile failure for workspace views and `openProviders`.

- [ ] **Step 4: Build the workspace shell and Connections view**

`ProvidersView` owns the shared header, last-update text, Refresh action, and borderless Connections/Usage switch. `ProviderConnectionsView` owns the connected-first list and search. `ProviderConnectionRowView` owns its progress, failure, Connected, Connect, Reconnect, unavailable, and Cancel states.

Pass models and closures explicitly; do not let row views reach into `AppModel`. Reuse `GhostActionStyle` and existing typography. Use these accessibility labels:

```swift
"Connect \(provider.name)"
"Reconnect \(provider.name)"
"Cancel \(provider.name) connection"
```

- [ ] **Step 5: Build Usage detail and error states**

`ProviderUsageDetailView` groups by provider and account. Render:

- bars only for percentage limits;
- exact reset descriptions in detail;
- amount-only rows such as `4 requests used`;
- provider notes once per account section;
- `Usage data unavailable.` for authenticated missing-report accounts;
- `Reconnect to update usage.` for disabled credentials;
- `Usage couldn’t be loaded.` for first-load failure;
- the last successful snapshot plus the stale warning for later failure.

No view may render `cause`, stderr, a path, or a raw RPC error.

- [ ] **Step 6: Wire Settings and provider routes**

Change `SettingsView` to accept `let onOpenProviders: () -> Void` and add a borderless `Providers` action beside the settings count. `AppShellView` supplies `model.openProviders(.connections)` and renders `ProvidersView` for `.providers`.

- [ ] **Step 7: Record and verify workspace snapshots**

```bash
ruby scripts/generate_xcodeproj.rb
RECORD_SNAPSHOTS=1 xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/providerConnectionsSnapshot \
  -only-testing:TenXAppTests/providerUsageDetailSnapshot \
  -only-testing:TenXAppTests/providerUsageStaleSnapshot test
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/providerConnectionsSnapshot \
  -only-testing:TenXAppTests/providerUsageDetailSnapshot \
  -only-testing:TenXAppTests/providerUsageStaleSnapshot \
  -only-testing:TenXAppTests/AppModelNavigationTests test
```

Expected: all workspace snapshots and navigation tests PASS.

- [ ] **Step 8: Commit the provider workspace**

```bash
git add App/Providers App/Application/AppModel.swift App/Shell/AppShellView.swift App/Settings/SettingsView.swift Tests/TenXAppTests/AppModelNavigationTests.swift Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/ReferenceImages/provider-*.png 10x.xcodeproj
git commit -m "feat(providers): add connection and usage workspace"
```

---

### Task 8: Connect Real Usage to the Expanded Rail and Foreground Refresh

**Files:**
- Modify: `App/Shell/ProviderUsageLedgerView.swift`
- Modify: `App/Shell/FloatingRailView.swift:52-93`
- Modify: `App/Application/AppModel.swift`
- Modify: `App/TenXApp.swift`
- Modify: `Tests/TenXAppTests/AccessibilityLabelTests.swift`
- Modify: `Tests/TenXAppTests/AppModelNavigationTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Create: `Tests/TenXAppTests/ReferenceImages/provider-usage-rail.png`

**Interfaces:**
- Consumes: `ProviderManagementViewModel.railProviders`, `refreshIfStale`, and `.providers(.usage)`.
- Produces: interactive nested ledger, foreground refresh entry point, and accessibility coverage.

- [ ] **Step 1: Write failing accessibility and rail-navigation tests**

```swift
@Test func providerUsageLabelNamesRemainingCapacityAndReset() {
    #expect(ProviderUsageAccessibility.limitLabel(
        provider: "Cursor",
        account: "tanner@example.com",
        allowance: "Cursor Models",
        percentage: 50,
        reset: "5 days"
    ) == "Cursor, tanner@example.com, Cursor Models, 50 percent remaining, resets in 5 days")
}

@MainActor
@Test func openProviderUsageSelectsUsageRoute() async {
    let providerModel = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))
    await model.bootstrap()
    model.openProviders(.usage)
    #expect(model.route == .providers(.usage))
}
```

Add a view snapshot with two accounts to prove identity appears only when needed and the ledger stays within its 210-point height cap.

- [ ] **Step 2: Write a failing foreground-staleness test**

Inject the fixed clock and assert `AppModel.refreshProvidersIfNeeded()` delegates to the provider model once the five-minute boundary is reached but not before it.

- [ ] **Step 3: Run focused tests and confirm the accessibility helper is missing**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/providerUsageLabelNamesRemainingCapacityAndReset \
  -only-testing:TenXAppTests/providerUsageRailSnapshot test
```

Expected: compile failure for `ProviderUsageAccessibility` and the new ledger shape.

- [ ] **Step 4: Make the ledger nested and interactive**

Replace the flat provider limit loop with provider, optional account, and limit loops. Make the `Usage` heading a plain button that opens the detail route, and add an `Open usage details` accessibility action to the container. Do not wrap the `ScrollView` in a button because that would break ledger scrolling. Preserve hidden indicators, expanded-only hit testing, and the existing cyan/yellow/red bar colors.

Remove `AppModel.providerUsages`; `FloatingRailView` reads:

```swift
let providers = model.providerModel?.railProviders ?? []
```

Calculate height from provider, visible account, and limit counts, capped at 210 points.

- [ ] **Step 5: Add foreground refresh**

Add an app-model method:

```swift
func refreshProvidersIfNeeded() async {
    await providerModel?.refreshIfStale()
}
```

In `TenXApp`, observe `scenePhase` and call it only when the scene becomes `.active`. Do not refresh on every view appearance.

- [ ] **Step 6: Record the rail snapshot and run integration tests**

```bash
RECORD_SNAPSHOTS=1 xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/providerUsageRailSnapshot test
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/providerUsageRailSnapshot \
  -only-testing:TenXAppTests/AccessibilityLabelTests \
  -only-testing:TenXAppTests/AppModelNavigationTests test
```

Expected: all selected tests PASS with no snapshot mismatch.

- [ ] **Step 7: Commit rail and lifecycle integration**

```bash
git add App/Shell/ProviderUsageLedgerView.swift App/Shell/FloatingRailView.swift App/Application/AppModel.swift App/TenXApp.swift Tests/TenXAppTests/AccessibilityLabelTests.swift Tests/TenXAppTests/AppModelNavigationTests.swift Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/ReferenceImages/provider-usage-rail.png
git commit -m "feat(providers): surface usage in the rail"
```

---

### Task 9: Verify the Complete Built Experience

**Files:**
- Modify only if verification exposes a defect in the approved scope.
- Update: this plan's task checkboxes and verification notes as each command completes.

**Interfaces:**
- Consumes: the complete provider feature from Tasks 1-8.
- Produces: green suites, a clean Release build, real read-only OMP evidence, screenshots from the real build, and an honest handoff.

- [x] **Step 1: Regenerate the project and confirm the worktree is clean except planned changes**

```bash
ruby scripts/generate_xcodeproj.rb
git diff --check
git status --short
```

Expected: no whitespace errors and no unplanned files.

- [x] **Step 2: Run every automated test from fresh evidence**

```bash
cd OmpKit && swift test
cd ..
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' test
```

Expected: OmpKit and app suites PASS; record exact executed counts and skips.

- [x] **Step 3: Build Release**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' clean build
```

Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 4: Verify live OMP data without changing authentication**

Use the resolved `/Users/tannerpham/.bun/bin/omp` only for read operations:

```bash
/Users/tannerpham/.bun/bin/omp usage --json --redact
```

Launch the Release app using the `launching-local-builds` skill. Confirm the Providers workspace reflects real discovery and usage, including current connected, missing-usage, or disabled states. Do not select Connect or Reconnect.

- [ ] **Step 5: Drive the real UI at minimum and default sizes**

In the built app, verify:

1. provider setup and workspace at 760x560 and 1180x760;
2. Connections/Usage keyboard switching;
3. provider search and Browse all providers;
4. expanded rail scrolling and Usage navigation;
5. no horizontal scrollbar, clipped copy, colliding controls, or hidden focus;
6. VoiceOver labels name provider, account when needed, percentage remaining, and reset;
7. reduced motion removes nonessential transitions.

Capture built-app screenshots of Connections, Usage, and the expanded rail. The current real profile already has an authenticated provider, so use the SwiftUI snapshot for required setup and report that the routed setup screen was not live-verified. Do not add a test-mode product path solely to manufacture a screenshot.

- [x] **Step 6: Record the external-auth verification boundary**

State explicitly:

```text
Not verified: completing a real OAuth login, because that changes external account authentication.
For Tanner to test: connect one disconnected provider, complete browser or pasted-code authorization, confirm Continue enables, relaunch, and confirm the provider remains connected.
```

- [x] **Step 7: Commit only verification-driven source changes**

If verification required a scoped fix, rerun the failing command and full affected suite, then commit:

```bash
git status --short
git add App OmpKit Tests 10x.xcodeproj
git diff --cached --check
git commit -m "fix(providers): correct verified provider UI defect"
```

If no source changed, do not create an empty verification commit.

- [x] **Step 8: Update branch coordination state**

The repository currently has no Git remote, so report that a draft PR could not be opened. If a remote is added before execution finishes, push without force and open or update a draft PR using the committed spec and this plan as links. Do not merge or mark ready without Tanner's instruction and green CI.

#### Task 9 verification notes (2026-08-25)

- Preflight: regenerated `10x.xcodeproj`; `git diff --check` passed and the worktree was clean before verification.
- Automated: `swift test` passed 126 OmpKit tests with 2 existing opt-in integration skips. `xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' test` passed 137 app tests with no skips after the verification fix.
- Release: fresh `xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' clean build` passed. The separate Release process was visible and remained alive at PID 53024 after the walkthrough.
- Live OMP: `/Users/tannerpham/.bun/bin/omp usage --json --redact` returned 1 Cursor report with 3 limits, 0 accounts without usage, and 2 disabled credentials. The built Providers workspace showed connected, missing-usage, and reconnect states without selecting Connect or Reconnect.
- UI: default 1180×760 Connections, Usage, and expanded-rail screenshots are saved under `/Users/tannerpham/.codex/visualizations/2026/08/25/01a039c4-60b0-7fd3-8328-0e4672d1c53c`. Browse all showed 137 providers; search filtered Gemini; the rail scrolled and opened Usage. A live overlap between the expanded rail and canvas was fixed by sharing the 64/220-point content inset (`cd89630`).
- Partial Step 5: live minimum-size resizing, keyboard-only section switching, focus-ring inspection, and reduced-motion behavior could not be confirmed with the available accessibility controls. Required setup was snapshot-only because the real profile was already authenticated.
- Not verified: completing a real OAuth login, because that changes external account authentication.
- For Tanner to test: connect one disconnected provider, complete browser or pasted-code authorization, confirm Continue enables, relaunch, and confirm the provider remains connected.
- Coordination: no Git remote is configured, so no draft PR was opened, pushed, merged, or marked ready.

#### Task 9 Fix Round 1 verification notes (2026-08-25)

- Fixed the rail-collapse transition defect in `7951ec3`: removed the rail's independent 0.2-second implicit animation. The 64/220-point rail width, labels, and `AppShellView` canvas inset now all snap on the same `RailExpansionModel.isExpanded` update, with no transition left that can transiently overlap the canvas.
- Regression evidence: the existing `contentInsetMatchesTheExpandedRailWidth` behavior test passed. A timing assertion is not exposed by the SwiftUI test harness; no brittle source-text test was added. `-only-testing:10xTests/RailExpansionModelTests` was rejected because that is not a scheme member, while `-only-testing:TenXAppTests` and the unfiltered app command each passed all 137 tests.
- Fresh verification: standalone `swift test` passed 126 OmpKit tests with 2 existing opt-in skips; the full app suite passed 137 tests with no skips; clean Release build passed.
- Rebuilt Release PID 63956 is visibly rendered and alive. Repeated Settings/Providers and expanded-rail Usage interactions showed the rebuilt Connections, Usage, and rail surfaces with no overlap. Screenshots at the existing Task 9 paths were replaced from this rebuilt process. Connect and Reconnect were not selected.

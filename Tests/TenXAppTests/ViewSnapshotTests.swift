import Foundation
import OmpKit
import SwiftUI
import Testing
@testable import TenXApp

@MainActor
@Test func genericToolCardSnapshot() throws {
    let presentation = ToolPresentation(
        id: "snapshot-tool",
        name: "custom_future_tool",
        arguments: .object(["query": .string("Bauhaus interface")]),
        result: .object(["content": .array([
            .object(["type": .string("text"), "text": .string("Completed locally")]),
        ])]),
        phase: .complete,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: Date(timeIntervalSince1970: 1.4))
    try assertSnapshot(
        ToolCardView(presentation: presentation)
            .frame(width: 720),
        name: "generic-tool-card")
}

@MainActor
@Test func approvalCardSnapshot() throws {
    try assertSnapshot(
        ApprovalCardView(
            state: .confirm(
                id: "approval",
                title: "Allow this command?",
                message: "Run the local test suite in this project.",
                timeout: nil),
            onRespond: { _ in },
            onOpenURL: { _ in },
            onCopyURL: { _ in })
            .frame(width: 720),
        name: "approval-card")
}

@MainActor
@Test func setupSnapshot() throws {
    try assertSnapshot(SetupView(model: AppModel()), name: "omp-missing")
}

@MainActor
@Test func providerSetupRequiredSnapshot() async throws {
    let model = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "openai-codex", name: "ChatGPT", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "anthropic", name: "Claude", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "google-gemini-cli", name: "Gemini CLI", isAvailable: true, isAuthenticated: false),
    ])
    await model.load()

    try assertSnapshot(
        ProviderSetupView(model: model, onContinue: {}),
        name: "provider-setup-required",
        size: CGSize(width: 760, height: 560))
}

@MainActor
@Test func providerSetupStarterSnapshots() async throws {
    try await assertProviderSetupStarterSnapshot(
        id: "openai-codex",
        name: "ChatGPT",
        snapshotName: "provider-setup-starter-chatgpt")
    try await assertProviderSetupStarterSnapshot(
        id: "anthropic",
        name: "Claude",
        snapshotName: "provider-setup-starter-claude")
    try await assertProviderSetupStarterSnapshot(
        id: "cursor",
        name: "Cursor",
        snapshotName: "provider-setup-starter-cursor")
    try await assertProviderSetupStarterSnapshot(
        id: "google-gemini-cli",
        name: "Gemini CLI",
        snapshotName: "provider-setup-starter-google-cloud")
}

@MainActor
@Test func providerSetupLoadingSnapshot() async throws {
    let loadingGate = LoadGate()
    let service = FakeProviderService(providers: [])
    await service.enqueueProviderGate(loadingGate)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    let loading = Task { await model.load() }
    await loadingGate.waitForStart()

    try assertSnapshot(
        ProviderSetupView(model: model, onContinue: {}),
        name: "provider-setup-loading",
        size: CGSize(width: 760, height: 560))

    await loadingGate.release()
    await loading.value
}

@MainActor
@Test func providerSetupConnectedSnapshot() async throws {
    let model = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
        ProviderLoginProvider(
            id: "google-gemini-cli", name: "Gemini CLI", isAvailable: true, isAuthenticated: false),
    ])
    await model.load()

    try assertSnapshot(
        ProviderSetupView(model: model, onContinue: {}),
        name: "provider-setup-connected",
        size: CGSize(width: 760, height: 560))
}

@MainActor
@Test func providerSetupBrowseAllSnapshot() async throws {
    let model = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "openai-codex", name: "OpenAI Codex", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "anthropic", name: "Anthropic", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
        ProviderLoginProvider(
            id: "google-gemini-cli", name: "Gemini CLI", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "github-copilot", name: "GitHub Copilot", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "ollama", name: "Ollama", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "sourcegraph", name: "Sourcegraph", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "zed", name: "Zed", isAvailable: true, isAuthenticated: false),
    ])
    await model.load()
    model.showAllProviders()

    try assertSnapshot(
        ProviderSetupView(model: model, onContinue: {}),
        name: "provider-setup-browse-all-minimum-size",
        size: CGSize(width: 760, height: 560))
}

@MainActor
@Test func providerSetupBrowseAllMixedRowsMinimumSizeSnapshot() async throws {
    let model = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "github-copilot", name: "GitHub Copilot", isAvailable: true, isAuthenticated: true),
        ProviderLoginProvider(
            id: "openai-codex", name: "OpenAI Codex", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "ollama", name: "Ollama", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "anthropic", name: "Anthropic", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "sourcegraph", name: "Sourcegraph", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "zed", name: "Zed", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "google-gemini-cli", name: "Gemini CLI", isAvailable: true, isAuthenticated: false),
    ])
    await model.load()
    model.showAllProviders()

    try assertSnapshot(
        ProviderSetupView(model: model, onContinue: {}),
        name: "provider-setup-browse-all-mixed-rows-minimum-size",
        size: CGSize(width: 760, height: 560))
}

@MainActor
@Test func providerSetupLoginFailureSnapshot() async throws {
    let service = FakeProviderService(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
    ], loginError: .loginFailed)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) },
        formatTime: { _ in "4:00 PM" })
    await model.load()
    let provider = try #require(model.providers.first)
    await model.login(provider)

    try assertSnapshot(
        ProviderSetupView(model: model, onContinue: {}),
        name: "provider-setup-login-failure",
        size: CGSize(width: 760, height: 560))
}

@MainActor
@Test func providerSetupActiveLoginAndCancelSnapshots() async throws {
    let loginGate = LoginGate()
    let service = FakeProviderService(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
    ], loginGate: loginGate)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    await model.load()
    let provider = try #require(model.providers.first)
    let login = Task { await model.login(provider) }
    await loginGate.waitForStart()

    try assertSnapshot(
        ProviderSetupView(model: model, onContinue: {}),
        name: "provider-setup-active-login",
        size: CGSize(width: 760, height: 560))

    await model.cancelLogin()
    try assertSnapshot(
        ProviderSetupView(model: model, onContinue: {}),
        name: "provider-setup-login-cancelled",
        size: CGSize(width: 760, height: 560))

    await loginGate.release()
    await login.value
}

@MainActor
@Test func providerSetupInputSheetSnapshotDuringActiveLogin() async throws {
    let loginGate = LoginGate()
    let service = FakeProviderService(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
    ], loginGate: loginGate)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    await model.load()
    let provider = try #require(model.providers.first)
    let login = Task { await model.login(provider) }
    await loginGate.waitForStart()
    await service.emit(ExtensionUIRequest(
        id: "paste-code",
        method: "input",
        payload: .object([
            "title": .string("Paste the code"),
            "placeholder": .string("Authorization code"),
        ])))
    await waitForModelState { model.sheetRequest?.id == "paste-code" }
    let request = try #require(model.sheetRequest)

    try assertSnapshot(
        ExtensionInputSheet(request: request, onSubmit: { _ in }, onCancel: {}),
        name: "provider-setup-input-sheet",
        size: CGSize(width: 576, height: 280))

    await model.cancelLogin()
    await loginGate.release()
    await login.value
}

@MainActor
@Test func runtimeRecoverySnapshot() throws {
    try assertSnapshot(
        RuntimeRecoveryView(
            exitCode: 143,
            onRestart: {},
            onOpenLog: {},
            onDismiss: {})
            .frame(width: 720),
        name: "runtime-recovery")
}

@MainActor
@Test func continuousSettingsSnapshot() async throws {
    let model = SettingsViewModel(service: OmpConfigService(runner: SnapshotConfigRunner()))
    let suiteName = "TenXAppTests.SettingsSnapshot.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registry = IDERegistry.testing(applications: [:])
    let store = IDEPreferenceStore(defaults: defaults, registry: registry)
    let providerModel = try providerWorkspaceModel()
    await model.load()
    try assertSnapshot(
        SettingsView(
            model: model,
            registry: registry,
            store: store,
            providerModel: providerModel),
        name: "continuous-settings")
}

@MainActor
@Test func settingsProvidersEmbeddedSnapshot() async throws {
    let model = SettingsViewModel(service: OmpConfigService(runner: SnapshotConfigRunner()))
    let providerModel = try providerWorkspaceModel()
    await model.load()
    await providerModel.load()

    try assertSnapshot(
        ProvidersView(model: providerModel, onBack: {}),
        name: "settings-providers-embedded",
        size: CGSize(width: 1180, height: 760))
}

@MainActor
@Test func fileTypeIconCatalogSnapshot() throws {
    try assertSnapshot(
        HStack(spacing: 24) {
            VStack(spacing: 7) {
                FileTypeIcon(path: "Feature.swift", isAvailable: true)
                Text("Feature.swift")
            }
            VStack(spacing: 7) {
                FileTypeIcon(path: "client.ts", isAvailable: true)
                Text("client.ts")
            }
            VStack(spacing: 7) {
                FileTypeIcon(path: "Component.tsx", isAvailable: true)
                Text("Component.tsx")
            }
        }
        .font(TenXTypography.body(size: 11))
        .padding(18)
        .background(Color.white),
        name: "file-type-icon-catalog",
        size: CGSize(width: 300, height: 90))
}

@MainActor
@Test func fileReferenceStatesSnapshot() throws {
    let suiteName = "TenXAppTests.FileReferenceStates.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let cursorURL = URL(filePath: "/Applications/Cursor.app")
    let registry = IDERegistry.testing(applications: [
        "com.todesktop.230313mzl4w4u92": cursorURL,
    ])
    let selectedStore = IDEPreferenceStore(defaults: defaults, registry: registry)
    try selectedStore.select(#require(registry.installedApplications().first))

    let emptySuiteName = "TenXAppTests.FileReferenceStates.Empty.\(UUID().uuidString)"
    let emptyDefaults = try #require(UserDefaults(suiteName: emptySuiteName))
    defer { emptyDefaults.removePersistentDomain(forName: emptySuiteName) }
    let emptyStore = IDEPreferenceStore(defaults: emptyDefaults, registry: registry)

    let fullReference = ResolvedFileReference(
        originalPath: "App/FileReferences/FileReferenceLabel.swift",
        line: 42,
        url: URL(filePath: "/Users/example/Projects/10x/App/FileReferences/FileReferenceLabel.swift"),
        exists: true)

    try assertSnapshot(
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Selected IDE")
                    .font(TenXTypography.body(size: 11, weight: .semibold))
                TranscriptReferenceView(reference: .file(
                    path: "App/Sessions/TranscriptView.swift",
                    line: 42))
                    .environment(selectedStore)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("No IDE")
                    .font(TenXTypography.body(size: 11, weight: .semibold))
                TranscriptReferenceView(reference: .file(
                    path: "App/Sessions/TranscriptView.swift",
                    line: nil))
                    .environment(emptyStore)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Missing file · disabled actions")
                    .font(TenXTypography.body(size: 11, weight: .semibold))
                TranscriptReferenceView(reference: .file(
                    path: "App/Sessions/RemovedView.swift",
                    line: 8))
                    .environment(selectedStore)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Full path")
                    .font(TenXTypography.body(size: 11, weight: .semibold))
                FlowLayout(spacing: 2) {
                    FileReferenceLabel(reference: fullReference, showsFullPath: true)
                }
                .frame(width: 430, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Compact width")
                    .font(TenXTypography.body(size: 11, weight: .semibold))
                TranscriptReferenceView(reference: .file(
                    path: "App/FileReferences/FileReferenceLabel.swift",
                    line: 42))
                    .environment(selectedStore)
                    .frame(width: 250, alignment: .leading)
            }
        }
        .environment(\.fileReferenceBaseURL, snapshotProjectURL)
        .environment(\.fileOpenService, snapshotFileOpenService)
        .frame(width: 560, alignment: .leading),
        name: "file-reference-states",
        size: CGSize(width: 640, height: 520))
}

@MainActor
@Test func activityFileReferencesSnapshot() throws {
    let suiteName = "TenXAppTests.ActivityFileReferences.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registry = IDERegistry.testing(applications: [
        "com.todesktop.230313mzl4w4u92": URL(filePath: "/Applications/Cursor.app"),
    ])
    let store = IDEPreferenceStore(defaults: defaults, registry: registry)
    try store.select(#require(registry.installedApplications().first))
    let timestamp = Date(timeIntervalSince1970: 1)

    let read = ToolPresentation(
        id: "reference-read",
        name: "read",
        arguments: .object(["path": .string("App/Sessions/TranscriptView.swift")]),
        result: snapshotTextResult("struct TranscriptView: View { … }"),
        phase: .complete,
        startDate: timestamp,
        endDate: timestamp.addingTimeInterval(0.3))
    let edit = ToolPresentation(
        id: "reference-edit",
        name: "edit",
        arguments: .object(["path": .string("App/Sessions/ActiveSessionView.swift")]),
        result: .object(["details": .object(["diff": .string("-old\n+new")])]),
        phase: .complete,
        startDate: timestamp,
        endDate: timestamp.addingTimeInterval(0.7))
    let write = ToolPresentation(
        id: "reference-write",
        name: "write",
        arguments: .object([
            "path": .string("App/FileReferences/FileReferenceLabel.swift"),
            "content": .string("import SwiftUI"),
        ]),
        result: snapshotTextResult("Wrote file"),
        phase: .complete,
        startDate: timestamp,
        endDate: timestamp.addingTimeInterval(0.5))
    let disclosureState = ToolDisclosureState()
    disclosureState.collapseAll(ids: [read.id, edit.id, write.id])

    try assertSnapshot(
        VStack(alignment: .leading, spacing: 18) {
            ReadToolCardView(presentation: read)
            EditToolCardView(presentation: edit)
            WriteToolCardView(presentation: write)
            ReadToolCardView(presentation: read)
                .frame(width: 360, alignment: .leading)
        }
        .environment(\.toolDisclosureState, disclosureState)
        .environment(store)
        .environment(\.fileReferenceBaseURL, snapshotProjectURL)
        .environment(\.fileOpenService, snapshotFileOpenService)
        .frame(width: 720, alignment: .leading),
        name: "activity-file-references",
        size: CGSize(width: 800, height: 520))
}

@MainActor
@Test func providerConnectionsSnapshot() async throws {
    let model = try providerWorkspaceModel()
    await model.load()

    try assertSnapshot(
        ProvidersView(model: model),
        name: "provider-connections",
        size: CGSize(width: 1180, height: 760))
}

@MainActor
@Test func providerConnectionsActiveLoginSnapshot() async throws {
    let loginGate = LoginGate()
    let service = FakeProviderService(
        providers: providerWorkspaceProviders,
        loginGate: loginGate)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: try providerWorkspaceSnapshot()),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 1_787_675_746) })
    await model.load()
    let provider = try #require(model.providers.first(where: { $0.id == "anthropic" }))
    let login = Task { await model.login(provider) }
    await loginGate.waitForStart()

    try assertSnapshot(
        ProvidersView(model: model),
        name: "provider-connections-active-login",
        size: CGSize(width: 1180, height: 760))

    await model.cancelLogin()
    await loginGate.release()
    await login.value
}

@MainActor
@Test func providerConnectionsFailureSnapshot() async throws {
    let service = FakeProviderService(
        providers: providerWorkspaceProviders,
        loginError: .loginFailed)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: try providerWorkspaceSnapshot()),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 1_787_675_746) })
    await model.load()
    let provider = try #require(model.providers.first(where: { $0.id == "anthropic" }))
    await model.login(provider)

    try assertSnapshot(
        ProvidersView(model: model),
        name: "provider-connections-failure",
        size: CGSize(width: 1180, height: 760))
}

@MainActor
@Test func providerUsageDetailSnapshot() async throws {
    let model = try providerWorkspaceModel()
    await model.load()
    model.selectedSection = .usage

    try assertSnapshot(
        ProvidersView(model: model),
        name: "provider-usage-detail",
        size: CGSize(width: 1180, height: 760))
}

@MainActor
@Test func providerUsageStaleSnapshot() async throws {
    let providerService = FakeProviderService(providers: providerWorkspaceProviders)
    let usageService = FakeUsageService(snapshot: try providerWorkspaceSnapshot())
    let model = ProviderManagementViewModel(
        providerService: providerService,
        usageService: usageService,
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 1_787_675_746) },
        formatTime: { _ in "9:35 AM" })
    await model.load()
    await usageService.setFailing(true)
    await model.refresh()
    model.selectedSection = .usage

    try assertSnapshot(
        ProvidersView(model: model),
        name: "provider-usage-stale",
        size: CGSize(width: 1180, height: 760))
}

@MainActor
@Test func providerUsageDockIdleSnapshot() throws {
    try assertSnapshot(
        ProviderUsageDockView(
            providers: providerUsageDockProviders,
            activeCounts: ["anthropic": 2],
            isForegroundGenerating: false)
            // macOS exposes the public Reduce Motion key as read-only.
            .environment(\._accessibilityReduceMotion, true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing),
        name: "provider-usage-dock-idle",
        size: CGSize(width: 430, height: 460))
}

@MainActor
@Test func providerUsageDockGeneratingSnapshot() throws {
    try assertSnapshot(
        ProviderUsageDockView(
            providers: providerUsageDockProviders,
            activeCounts: ["anthropic": 2],
            isForegroundGenerating: true)
            .environment(\._accessibilityReduceMotion, true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing),
        name: "provider-usage-dock-generating",
        size: CGSize(width: 430, height: 460))
}

@MainActor
@Test func providerUsageDockExpandedSnapshot() throws {
    try assertSnapshot(
        ProviderUsageDockView(
            providers: providerUsageDockProviders,
            activeCounts: ["anthropic": 2],
            isForegroundGenerating: true,
            initiallySelectedProviderID: "anthropic")
            .environment(\._accessibilityReduceMotion, true),
        name: "provider-usage-dock-expanded",
        size: CGSize(width: 430, height: 460))
}

@MainActor
@Test func fullShellExpandedRailOverflowSnapshot() async throws {
    let providerModel = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: fullShellProviders),
        usageService: FakeUsageService(snapshot: try fullShellUsageSnapshot()),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 1_787_675_746) })
    let model = AppModel(dependencies: AppDependencies(
        ompLocator: SnapshotOmpLocator(),
        sessionLibrary: SessionLibrary(root: URL(
            filePath: "/tmp/10x-full-shell-snapshot",
            directoryHint: .isDirectory)),
        sessionSearch: SessionSearchService(),
        makeProviderModel: { _ in providerModel },
        makeComposerControls: stubComposerControlsFactory))
    await model.bootstrap()
    model.selectedProjectURL = URL(filePath: "/tmp/full-shell-project", directoryHint: .isDirectory)
    model.sessions = fullShellSessions
    let railExpansion = RailExpansionModel()
    railExpansion.pointerEntered()

    try assertSnapshot(
        AppShellView(model: model, railExpansion: railExpansion),
        name: "full-shell-expanded-rail-overflow",
        size: CGSize(width: 760, height: 560))
}

@MainActor
@Test func brandActionsMenuSnapshot() throws {
    let model = AppModel()
    model.route = .newSession

    try assertSnapshot(
        BrandActionsMenuView(
            model: model,
            isPresented: .constant(true),
            revealsImmediately: true),
        name: "brand-actions-menu",
        size: CGSize(width: 220, height: 180))
}

@MainActor
@Test func fullShellUsageDockSmallWindowSnapshot() async throws {
    let providerModel = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: fullShellProviders),
        usageService: FakeUsageService(snapshot: try fullShellUsageSnapshot()),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 1_787_675_746) })
    let model = AppModel(dependencies: AppDependencies(
        ompLocator: SnapshotOmpLocator(),
        sessionLibrary: SessionLibrary(root: URL(
            filePath: "/tmp/10x-full-shell-usage-dock-snapshot",
            directoryHint: .isDirectory)),
        sessionSearch: SessionSearchService(),
        makeProviderModel: { _ in providerModel },
        makeComposerControls: stubComposerControlsFactory))
    await model.bootstrap()
    model.selectedProjectURL = URL(filePath: "/tmp/full-shell-project", directoryHint: .isDirectory)
    model.sessions = fullShellSessions

    try assertSnapshot(
        AppShellView(model: model),
        name: "full-shell-usage-dock-small-window",
        size: CGSize(width: 760, height: 560))
}

@MainActor
@Test func fullShellUsageDockWideWindowSnapshot() async throws {
    let providerModel = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: fullShellProviders),
        usageService: FakeUsageService(snapshot: try fullShellUsageSnapshot()),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 1_787_675_746) })
    let model = AppModel(dependencies: AppDependencies(
        ompLocator: SnapshotOmpLocator(),
        sessionLibrary: SessionLibrary(root: URL(
            filePath: "/tmp/10x-full-shell-wide-usage-dock-snapshot",
            directoryHint: .isDirectory)),
        sessionSearch: SessionSearchService(),
        makeProviderModel: { _ in providerModel },
        makeComposerControls: stubComposerControlsFactory))
    await model.bootstrap()
    model.selectedProjectURL = URL(filePath: "/tmp/full-shell-project", directoryHint: .isDirectory)
    model.sessions = fullShellSessions

    try assertSnapshot(
        AppShellView(model: model),
        name: "full-shell-usage-dock-wide-window",
        size: CGSize(width: 1280, height: 760))
}

@MainActor
private func providerWorkspaceModel() throws -> ProviderManagementViewModel {
    providerTestModel(
        providers: providerWorkspaceProviders,
        snapshot: try providerWorkspaceSnapshot(),
        now: { Date(timeIntervalSince1970: 1_787_675_746) })
}

@MainActor
private func assertProviderSetupStarterSnapshot(
    id: String,
    name: String,
    snapshotName: String
) async throws {
    let model = providerTestModel(providers: [
        ProviderLoginProvider(id: id, name: name, isAvailable: true, isAuthenticated: false),
    ])
    await model.load()

    try assertSnapshot(
        ProviderSetupView(model: model, onContinue: {}),
        name: snapshotName,
        size: CGSize(width: 760, height: 560))
}

private struct SnapshotOmpLocator: OmpLocating {
    func locate(preferredURL: URL?) async -> OmpInstallation? {
        OmpInstallation(executableURL: URL(filePath: "/tmp/omp"), version: "test")
    }
}

private let providerUsageDockProviders = [
    ProviderUsageProvider(
        id: "anthropic",
        name: "Anthropic",
        accounts: [
            providerUsageDockAccount(
                id: "anthropic:personal",
                label: "tanner@example.com",
                limits: [
                    providerUsageDockLimit(
                        id: "anthropic:personal:five-hour",
                        label: "5 hour",
                        percentage: 82,
                        reset: "in 2 hours",
                        rank: 300),
                    providerUsageDockLimit(
                        id: "anthropic:personal:weekly",
                        label: "Weekly",
                        percentage: 20,
                        reset: "in 4 days",
                        rank: 10_080),
                ]),
            providerUsageDockAccount(
                id: "anthropic:work",
                label: "work@example.com",
                limits: [
                    providerUsageDockLimit(
                        id: "anthropic:work:monthly",
                        label: "Monthly",
                        percentage: 0,
                        reset: "in 18 days",
                        rank: 43_200),
                ]),
        ]),
    ProviderUsageProvider(
        id: "openai-codex",
        name: "OpenAI Codex",
        accounts: [
            providerUsageDockAccount(
                id: "openai-codex:personal",
                label: "tanner@example.com",
                limits: [
                    providerUsageDockLimit(
                        id: "openai-codex:personal:five-hour",
                        label: "5 hour",
                        percentage: 62,
                        reset: "in 2 hours",
                        rank: 300),
                ]),
        ]),
    ProviderUsageProvider(
        id: "cursor",
        name: "Cursor",
        accounts: [
            providerUsageDockAccount(
                id: "cursor:personal",
                label: "tanner@example.com",
                limits: [
                    providerUsageDockLimit(
                        id: "cursor:personal:weekly",
                        label: "Weekly",
                        percentage: 14,
                        reset: "in 5 days",
                        rank: 10_080),
                ]),
        ]),
]

private func providerUsageDockAccount(
    id: String,
    label: String,
    limits: [ProviderUsageLimit]
) -> ProviderUsageAccount {
    ProviderUsageAccount(
        id: id,
        label: label,
        identity: ProviderUsageAccountIdentity(
            email: label,
            accountID: nil,
            projectID: nil,
            enterpriseURL: nil,
            orgID: nil,
            orgName: nil),
        limits: limits,
        amounts: [],
        notes: [],
        isUsageAvailable: true)
}

private func providerUsageDockLimit(
    id: String,
    label: String,
    percentage: Int,
    reset: String,
    rank: Int
) -> ProviderUsageLimit {
    ProviderUsageLimit(
        id: id,
        label: label,
        percentage: percentage,
        detailReset: reset,
        railReset: reset,
        windowDurationRank: rank)
}

private let providerWorkspaceProviders = [
    ProviderLoginProvider(
        id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ProviderLoginProvider(
        id: "anthropic", name: "Anthropic", isAvailable: true, isAuthenticated: false),
    ProviderLoginProvider(
        id: "github-copilot", name: "GitHub Copilot", isAvailable: true, isAuthenticated: true),
    ProviderLoginProvider(
        id: "openai-codex", name: "ChatGPT", isAvailable: true, isAuthenticated: false),
    ProviderLoginProvider(
        id: "local", name: "Local Provider", isAvailable: false, isAuthenticated: false),
]

private let fullShellProviders = [
    ProviderLoginProvider(id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ProviderLoginProvider(id: "anthropic", name: "Claude", isAvailable: true, isAuthenticated: true),
    ProviderLoginProvider(id: "openai-codex", name: "ChatGPT", isAvailable: true, isAuthenticated: true),
]

private let fullShellSessions: [SessionMetadata] = (0..<28).map { index in
    SessionMetadata(
        path: "/tmp/full-shell-session-\(index).jsonl",
        sessionId: "full-shell-\(index)",
        cwd: "/tmp/full-shell-project",
        title: "Provider usage review \(index + 1)",
        created: Date(timeIntervalSince1970: TimeInterval(index)),
        modified: Date(timeIntervalSince1970: TimeInterval(index)),
        sizeBytes: 1_024,
        status: .complete)
}

private func providerWorkspaceSnapshot() throws -> OmpUsageSnapshot {
    try JSONDecoder().decode(OmpUsageSnapshot.self, from: Data(#"""
    {
      "generatedAt":1787675745954,
      "reports":[{
        "provider":"cursor",
        "fetchedAt":1787675745599,
        "limits":[
          {"id":"cursor:models","label":"Cursor Models","scope":{"provider":"cursor"},"window":{"id":"monthly","label":"Monthly","resetsAt":1788061624000},"amount":{"usedFraction":0.5,"unit":"percent"},"notes":["Shared across Cursor models."]},
          {"id":"cursor:burst","label":"Burst requests","scope":{"provider":"cursor"},"window":{"id":"daily","label":"Daily","resetsAt":1787700000000},"amount":{"usedFraction":1,"unit":"percent"}},
          {"id":"cursor:requests","label":"Requests","scope":{"provider":"cursor"},"amount":{"used":4,"unit":"requests"}}
        ],
        "metadata":{"email":"tanner@example.com"}
      }],
      "accountsWithoutUsage":[{"provider":"github-copilot","email":"work@example.com"}],
      "disabledCredentials":[{"id":2,"provider":"anthropic","type":"oauth","cause":"refresh failed","email":"old@example.com","disabledAtMs":1787616419000}]
    }
    """#.utf8))
}

private func fullShellUsageSnapshot() throws -> OmpUsageSnapshot {
    try JSONDecoder().decode(OmpUsageSnapshot.self, from: Data(#"""
    {
      "generatedAt":1787675745954,
      "reports":[
        {"provider":"cursor","fetchedAt":1787675745599,"limits":[
          {"id":"cursor:models","label":"Models","scope":{"provider":"cursor"},"window":{"id":"monthly","label":"Monthly","resetsAt":1788061624000},"amount":{"remainingFraction":0.5,"unit":"percent"}},
          {"id":"cursor:fast","label":"Fast requests","scope":{"provider":"cursor"},"window":{"id":"daily","label":"Daily","resetsAt":1787700000000},"amount":{"remainingFraction":0.3,"unit":"percent"}},
          {"id":"cursor:slow","label":"Slow requests","scope":{"provider":"cursor"},"window":{"id":"daily","label":"Daily","resetsAt":1787700000000},"amount":{"remainingFraction":0.7,"unit":"percent"}}
        ],"metadata":{"email":"cursor@example.com"}},
        {"provider":"anthropic","fetchedAt":1787675745599,"limits":[
          {"id":"anthropic:weekly","label":"Weekly","scope":{"provider":"anthropic"},"window":{"id":"weekly","label":"Weekly","resetsAt":1788061624000},"amount":{"remainingFraction":0.4,"unit":"percent"}},
          {"id":"anthropic:five-hour","label":"5 hour","scope":{"provider":"anthropic"},"window":{"id":"five-hour","label":"5 hour","resetsAt":1787700000000},"amount":{"remainingFraction":0.2,"unit":"percent"}},
          {"id":"anthropic:sonnet","label":"Sonnet","scope":{"provider":"anthropic"},"window":{"id":"daily","label":"Daily","resetsAt":1787700000000},"amount":{"remainingFraction":0.8,"unit":"percent"}}
        ],"metadata":{"email":"claude@example.com"}},
        {"provider":"openai-codex","fetchedAt":1787675745599,"limits":[
          {"id":"openai:five-hour","label":"5 hour","scope":{"provider":"openai-codex"},"window":{"id":"five-hour","label":"5 hour","resetsAt":1788061624000},"amount":{"remainingFraction":0.5,"unit":"percent"}},
          {"id":"openai:weekly","label":"Weekly","scope":{"provider":"openai-codex"},"window":{"id":"weekly","label":"Weekly","resetsAt":1787700000000},"amount":{"remainingFraction":0.6,"unit":"percent"}},
          {"id":"openai:priority","label":"Priority","scope":{"provider":"openai-codex"},"window":{"id":"daily","label":"Daily","resetsAt":1787700000000},"amount":{"remainingFraction":0.9,"unit":"percent"}}
        ],"metadata":{"email":"chatgpt@example.com"}}
      ],
      "accountsWithoutUsage":[],
      "disabledCredentials":[]
    }
    """#.utf8))
}

@MainActor
@Test func userMessageSnapshot() throws {
    let message = TranscriptMessage(
        id: "user-message",
        raw: .object([
            "role": .string("user"),
            "content": .string("Make the transcript compact, but keep every useful detail available."),
        ]),
        timestamp: Date(timeIntervalSince1970: 1_787_601_600),
        isFinal: true)
    try assertSnapshot(
        MessageBubbleView(message: message).frame(width: 720),
        name: "chat-user-message",
        size: CGSize(width: 800, height: 220))
}

@MainActor
@Test func richAssistantMessageSnapshot() throws {
    let message = TranscriptMessage(
        id: "assistant-message",
        raw: .object([
            "role": .string("assistant"),
            "content": .string("""
            # Transcript ready

            The agent view now keeps **routine work compact** while preserving the detail you need.

            - Actual model and mode attribution
            - Structured code with copy
            - Actionable [documentation](https://example.com/docs)

            | Surface | Behavior |
            | --- | --- |
            | Source | Wraps by default without losing indentation |
            | References | Stay where the response introduced them |

            > Changes stay quiet until they need attention.

            ```swift
            let state = TranscriptState.compact // preserve the reader's place
            if state.isReady {
                render(state, references: true, maximumVisibleCharacters: 120)
            }
            ```
            """),
        ]),
        timestamp: Date(timeIntervalSince1970: 1_787_601_600),
        attribution: TranscriptResponseAttribution(
            provider: "openai-codex",
            model: "gpt-5.6-sol",
            mode: "design",
            agent: nil,
            modelRole: nil),
        isFinal: true)
    try assertSnapshot(
        MessageBubbleView(message: message)
            .environment(snapshotEmptyIDEStore)
            .frame(width: 720),
        name: "chat-rich-assistant",
        size: CGSize(width: 800, height: 700))
}

@MainActor
@Test func wrappedSourceSurfaceSnapshot() throws {
    let source = SourcePresentation(language: "swift", text: """
    struct TranscriptRow: View {
        let count = 12 // preserve indentation and explain the line

        var body: some View {
            Text("A deliberately long source line that wraps inside the transcript instead of escaping underneath the activity card")
        }
    }
    """)

    try assertSnapshot(
        SourceSurface(presentation: source)
            .frame(width: 430),
        name: "source-wrapped",
        size: CGSize(width: 500, height: 340))
}

@MainActor
@Test func scrollingSourceSurfaceSnapshot() throws {
    let source = SourcePresentation(language: "swift", text: """
    struct TranscriptRow: View {
        let count = 12 // preserve indentation and explain the line
        let title = "A deliberately long source line kept at its exact width for horizontal inspection"
    }
    """)

    try assertSnapshot(
        SourceSurface(
            presentation: source,
            isInitiallyWrapped: false)
            .frame(width: 430),
        name: "source-scrolling",
        size: CGSize(width: 500, height: 250))
}

@MainActor
@Test func longWrappingMessageSnapshot() throws {
    let longValue = String(repeating: "unbroken-segment-", count: 38)
    let longReference = "/tmp/" + String(repeating: "nested-folder/", count: 8)
        + "a-very-long-reference-name-that-must-not-overflow.swift:42"
    let message = TranscriptMessage(
        id: "long-message",
        raw: .object([
            "role": .string("assistant"),
            "content": .string("The output stays inside the transcript:\n\n\(longValue)\n\n`\(longReference)`"),
        ]),
        attribution: TranscriptResponseAttribution(
            provider: nil,
            model: "claude-sonnet-4-6",
            mode: nil,
            agent: nil,
            modelRole: nil),
        isFinal: true)
    try assertSnapshot(
        MessageBubbleView(message: message)
            .environment(snapshotEmptyIDEStore)
            .frame(width: 520),
        name: "chat-long-wrapping",
        size: CGSize(width: 600, height: 420))
}

@MainActor
@Test func activityDisclosureSnapshot() throws {
    let running = ToolPresentation(
        id: "running-tool",
        name: "bash",
        arguments: .object(["command": .string("swift test --filter Transcript")]),
        result: .object(["content": .array([
            .object([
                "type": .string("text"),
                "text": .string((1...14).map { "Test step \($0) passed" }.joined(separator: "\n")),
            ]),
        ])]),
        phase: .running,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: Date(timeIntervalSince1970: 5.6))
    let failed = ToolPresentation(
        id: "failed-tool",
        name: "bash",
        arguments: .object(["command": .string("swift build")]),
        result: .object(["content": .array([
            .object(["type": .string("text"), "text": .string("Compilation failed at TranscriptView.swift:42")]),
        ])]),
        phase: .failed,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: Date(timeIntervalSince1970: 1.8))
    try assertSnapshot(
        VStack(spacing: 18) {
            ToolCardView(presentation: running)
            ToolCardView(presentation: failed)
        }
        .frame(width: 720),
        name: "activity-running-error",
        size: CGSize(width: 800, height: 520))
}

@MainActor
@Test func semanticToolSurfacesSnapshot() throws {
    let timestamp = Date(timeIntervalSince1970: 1)
    let source = ToolPresentation(
        id: "semantic-source",
        name: "read",
        arguments: .object(["path": .string("App/Sessions/TranscriptView.swift")]),
        result: snapshotTextResult("struct TranscriptView: View {\n    let controller: SessionController\n}"),
        phase: .complete,
        startDate: timestamp,
        endDate: timestamp.addingTimeInterval(0.3))
    let collection = ToolPresentation(
        id: "semantic-collection",
        name: "web_search",
        arguments: .object(["query": .string("Open multimodal protocol")]),
        result: .object(["details": .object(["results": .array([
            .object([
                "title": .string("OMP reference"),
                "url": .string("https://example.com/omp"),
                "snippet": .string("A typed protocol for model tools and ordered content blocks."),
            ]),
            .object([
                "title": .string("Tool result guide"),
                "url": .string("https://example.com/tools"),
                "snippet": .string("Text, resources, images, and structured details remain in order."),
            ]),
        ])])]),
        phase: .complete,
        startDate: timestamp,
        endDate: timestamp.addingTimeInterval(0.6))
    let previewPath = snapshotProjectURL
        .appending(path: "Tests/TenXAppTests/ReferenceImages/source-wrapped.png")
        .path
    let mcp = ToolPresentation(
        id: "semantic-mcp",
        name: "mcp__vision__render",
        arguments: .object(["quality": .string("high")]),
        result: .object([
            "content": .array([
                .object(["type": .string("text"), "text": .string("Rendered preview")]),
                .object([
                    "type": .string("image"),
                    "url": .string(previewPath),
                    "mimeType": .string("image/png"),
                    "name": .string("Wrapped source preview"),
                ]),
                .object([
                    "type": .string("resource_link"),
                    "name": .string("Render report"),
                    "uri": .string("https://example.com/report"),
                ]),
                .object([
                    "type": .string("image"),
                    "data": .string("not-valid-base64"),
                    "mimeType": .string("image/png"),
                    "name": .string("Malformed preview"),
                ]),
            ]),
            "details": .object([
                "width": .int(800),
                "height": .int(600),
                "nested": .object(["status": .string("complete")]),
            ]),
        ]),
        phase: .complete,
        startDate: timestamp,
        endDate: timestamp.addingTimeInterval(1.2))
    let disclosure = ToolDisclosureState()
    disclosure.expand(ids: [source.id, collection.id, mcp.id])

    try assertSnapshot(
        VStack(alignment: .leading, spacing: 18) {
            ToolCardView(presentation: source)
            ToolCardView(presentation: collection)
            ToolCardView(presentation: mcp)
        }
        .environment(\.toolDisclosureState, disclosure)
        .environment(snapshotEmptyIDEStore)
        .environment(\.fileReferenceBaseURL, snapshotProjectURL)
        .environment(\.fileOpenService, snapshotFileOpenService)
        .frame(width: 720, alignment: .leading),
        name: "semantic-tool-surfaces",
        size: CGSize(width: 800, height: 1_500))
}

@MainActor
@Test func subagentActivitySnapshot() throws {
    let presentation = SubagentPresentation(
        id: "subagent",
        index: 0,
        agent: "reviewer",
        task: "Review transcript behavior",
        assignment: "Check disclosure and attribution",
        description: "Review the completed implementation against the product direction.",
        status: .running,
        sessionFile: "/tmp/reviewer.jsonl",
        parentToolCallID: "task-1",
        actualModel: "gpt-5.6-sol",
        thinkingLevel: "high",
        modelRole: "review",
        isFallback: false,
        currentTool: "read",
        recentTools: [],
        recentOutput: ["Checked transcript mapping", "Reviewing compact activity"],
        toolCount: 6,
        requests: 2,
        tokens: 1_840,
        cost: 0.03,
        durationMilliseconds: 4_200,
        result: nil)
    try assertSnapshot(
        SubagentCardView(presentation: presentation).frame(width: 720),
        name: "activity-subagent",
        size: CGSize(width: 800, height: 330))
}

@MainActor
@Test func structuredDiffSnapshot() throws {
    let longLine = "let title = \"" + String(repeating: "structured-transcript-", count: 10) + "\""
    let patch = """
    diff --git a/App/Transcript.swift b/App/Transcript.swift
    --- a/App/Transcript.swift
    +++ b/App/Transcript.swift
    @@ -1,10 +1,10 @@
     import SwiftUI
     struct Transcript {
         let id: String
         let role: String
         let model: String
         let mode: String
         let date: Date
         let state: State
    -let title = "Old transcript"
    +    \(longLine) // 10 repeated segments
    diff --git a/App/Palette.swift b/App/Palette.swift
    --- a/App/Palette.swift
    +++ b/App/Palette.swift
    @@ -4,2 +4,2 @@
    -let addition = Color.green
    +let addition = Color.cyan
     let removal = Color.red
    """
    let presentation = ToolPresentation(
        id: "diff-tool",
        name: "edit",
        arguments: .object(["path": .string("/tmp/Transcript.swift")]),
        result: .object(["details": .object(["diff": .string(patch)])]),
        phase: .complete,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: Date(timeIntervalSince1970: 1.7))
    try assertSnapshot(
        EditToolCardView(presentation: presentation)
            .environment(snapshotEmptyIDEStore)
            .frame(width: 720),
        name: "activity-structured-diff",
        size: CGSize(width: 800, height: 650))
}

@MainActor
@Test func fullTranscriptCompactWindowSnapshot() throws {
    try assertSnapshot(
        ActiveSessionView(controller: compactTranscriptController())
            .environment(snapshotEmptyIDEStore),
        name: "chat-full-900",
        size: CGSize(width: 900, height: 700))
}

@MainActor
@Test func fullTranscriptWideWindowSnapshot() throws {
    try assertSnapshot(
        ActiveSessionView(controller: wideTranscriptController())
            .environment(snapshotEmptyIDEStore),
        name: "chat-full-1440",
        size: CGSize(width: 1_440, height: 900))
}

@MainActor
@Test func activeSessionHeaderSnapshot() throws {
    let controller = SessionController(
        processManager: SessionProcessManager(),
        previewItems: [],
        runtimeState: .streaming,
        title: "Active session",
        headerMetadata: SessionHeaderMetadata(
            branch: "codex/active-session-shell",
            repo: "10x",
            worktreePath: ".worktrees/active-session-shell"))

    try assertSnapshot(
        SessionHeaderView(controller: controller),
        name: "active-session-header",
        size: CGSize(width: 900, height: 80))
}

@MainActor
@Test func collapsedRailSnapshot() throws {
    let (model, expansion) = snapshotRail(isExpanded: false)

    try assertSnapshot(
        FloatingRailView(model: model, expansion: expansion, isBrandMenuPresented: .constant(false)),
        name: "shell-rail-collapsed",
        size: CGSize(width: 64, height: 620))
}

@MainActor
@Test func expandedRailSnapshot() throws {
    let (model, expansion) = snapshotRail(isExpanded: true)

    try assertSnapshot(
        FloatingRailView(model: model, expansion: expansion, isBrandMenuPresented: .constant(false)),
        name: "shell-rail-expanded",
        size: CGSize(width: 220, height: 620))
}

@MainActor
@Test func expandedOverflowRailSnapshot() throws {
    let (model, expansion) = snapshotOverflowRail()

    try assertSnapshot(
        FloatingRailView(model: model, expansion: expansion, isBrandMenuPresented: .constant(false)),
        name: "shell-rail-overflow-expanded",
        size: CGSize(width: 220, height: 360))
}

@MainActor
@Test func archivedSessionsEmptySnapshot() throws {
    let model = AppModel()
    model.archivedSessions = []

    try assertSnapshot(
        ArchivedSessionsView(model: model),
        name: "archived-sessions-empty")
}

@MainActor
@Test func archivedSessionsPopulatedSnapshot() throws {
    let model = AppModel()
    model.archivedSessions = [
        snapshotSession(
            path: "/sessions/archived-shell.jsonl",
            cwd: "/tmp/10x",
            title: "Refine session management",
            modified: 1_787_601_600),
        snapshotSession(
            path: "/sessions/archived-untitled.jsonl",
            cwd: "/tmp/10x",
            title: "",
            modified: 1_787_515_200),
        snapshotSession(
            path: "/sessions/archived-nextstep.jsonl",
            cwd: "/tmp/NextStep",
            title: "Review course navigation",
            modified: 1_787_428_800),
    ]

    try assertSnapshot(
        ArchivedSessionsView(model: model),
        name: "archived-sessions-populated")
}

@MainActor
@Test func sessionDeletionConfirmationSnapshot() throws {
    let request = SessionDeletionRequest.session(snapshotSession(
        path: "/sessions/delete-me.jsonl",
        cwd: "/tmp/10x",
        title: "Refine session management",
        modified: 1_787_601_600))

    try assertSnapshot(
        SessionDeletionConfirmationView(
            request: request,
            onCancel: {},
            onDelete: {}),
        name: "session-deletion-confirmation")
}

@MainActor
@Test func composerFooterFastPresentSnapshot() async throws {
    let anthropic = ComposerModelInfo(
        modelID: "claude-opus-4-8",
        name: "Claude Opus 4.8",
        provider: "anthropic",
        api: "anthropic-messages",
        thinkingEfforts: ["low", "high"],
        requiresEffort: false)
    let controls = await snapshotComposerControls(
        models: [anthropic],
        selected: anthropic,
        thinkingLevel: "high",
        fastModeEnabled: true)

    try assertSnapshot(
        ComposerView(
            draft: .constant("Ship the Bauhaus composer footer."),
            presentation: .newSession(
                projectURL: URL(filePath: "/tmp/10x", directoryHint: .isDirectory),
                projectURLs: [URL(filePath: "/tmp/10x", directoryHint: .isDirectory)],
                onChooseProject: { _ in },
                onAddExistingFolder: {}),
            controls: controls,
            controlsMode: .newSession,
            onSend: {}),
        name: "composer-footer-fast-present",
        size: CGSize(width: 780, height: 140))
}

@MainActor
@Test func composerFooterFastAbsentSnapshot() async throws {
    let cursor = ComposerModelInfo(
        modelID: "gpt-5",
        name: "GPT-5",
        provider: "cursor",
        api: "cursor-agent",
        thinkingEfforts: [],
        requiresEffort: false)
    let controls = await snapshotComposerControls(
        models: [cursor],
        selected: cursor,
        thinkingLevel: "auto",
        fastModeEnabled: false)

    try assertSnapshot(
        ComposerView(
            draft: .constant("Hide Fast when the model cannot support it."),
            presentation: .active(controller: SessionController(
                processManager: SessionProcessManager(),
                previewItems: [],
                runtimeState: .idle,
                modelName: "GPT-5",
                thinkingLevel: "Auto")),
            controls: controls,
            controlsMode: .activeSession,
            onSend: {}),
        name: "composer-footer-fast-absent",
        size: CGSize(width: 780, height: 140))
}

@MainActor
private func compactTranscriptController() -> SessionController {
    let timestamp = Date(timeIntervalSince1970: 1_787_601_600)
    let user = TranscriptMessage(
        id: "compact-user",
        raw: .object([
            "role": .string("user"),
            "content": .string("Make the agent transcript compact without hiding important work."),
        ]),
        timestamp: timestamp,
        isFinal: true)
    let assistant = TranscriptMessage(
        id: "compact-assistant",
        raw: .object([
            "role": .string("assistant"),
            "content": .string("Routine work stays collapsed. Running and failed work opens automatically, and every item remains keyboard accessible."),
        ]),
        timestamp: timestamp.addingTimeInterval(8),
        attribution: TranscriptResponseAttribution(
            provider: "openai-codex",
            model: "gpt-5.6-sol",
            mode: "design",
            agent: nil,
            modelRole: nil),
        isFinal: false)
    let read = ToolPresentation(
        id: "compact-read",
        name: "read",
        arguments: .object(["path": .string("App/Sessions/TranscriptView.swift")]),
        result: snapshotTextResult("struct TranscriptView: View { … }"),
        phase: .complete,
        startDate: timestamp.addingTimeInterval(10),
        endDate: timestamp.addingTimeInterval(10.3))
    let running = ToolPresentation(
        id: "compact-running",
        name: "bash",
        arguments: .object(["command": .string("xcodebuild -scheme 10x test")]),
        result: snapshotTextResult("Building transcript tests…"),
        phase: .running,
        startDate: timestamp.addingTimeInterval(11),
        endDate: timestamp.addingTimeInterval(15.6))
    let failed = ToolPresentation(
        id: "compact-failed",
        name: "bash",
        arguments: .object(["command": .string("swift build")]),
        result: snapshotTextResult("TranscriptView.swift:42: error: invalid scroll target"),
        phase: .failed,
        startDate: timestamp.addingTimeInterval(16),
        endDate: timestamp.addingTimeInterval(16.8))
    return SessionController(
        processManager: SessionProcessManager(),
        previewItems: [
            .threadStart(id: "compact-start", date: timestamp),
            .message(user),
            .message(assistant),
            .tool(read),
            .tool(running),
            .tool(failed),
        ],
        runtimeState: .streaming,
        title: "Transcript experience")
}

@MainActor
private func wideTranscriptController() -> SessionController {
    let timestamp = Date(timeIntervalSince1970: 1_787_601_600)
    let assistant = TranscriptMessage(
        id: "wide-assistant",
        raw: .object([
            "role": .string("assistant"),
            "content": .string("## Implementation\n\nThe transcript keeps long explanations readable while preserving direct references like `App/Sessions/TranscriptView.swift:42` and [the design notes](https://example.com/design)."),
        ]),
        timestamp: timestamp.addingTimeInterval(20),
        attribution: TranscriptResponseAttribution(
            provider: "openai-codex",
            model: "gpt-5.6-sol",
            mode: "advisor",
            agent: "interface-worker",
            modelRole: "implementation"),
        isFinal: true)
    let patch = """
    diff --git a/App/Transcript.swift b/App/Transcript.swift
    --- a/App/Transcript.swift
    +++ b/App/Transcript.swift
    @@ -18,3 +18,3 @@
    -scrollToBottom()
    +if isNearBottom { scrollToBottom() }
     render(items)
    """
    let edit = ToolPresentation(
        id: "wide-edit",
        name: "edit",
        arguments: .object(["path": .string("App/Transcript.swift")]),
        result: .object(["details": .object(["diff": .string(patch)])]),
        phase: .complete,
        startDate: timestamp.addingTimeInterval(21),
        endDate: timestamp.addingTimeInterval(21.7))
    let subagent = SubagentPresentation(
        id: "wide-subagent",
        index: 0,
        agent: "reviewer",
        task: "Review transcript behavior",
        assignment: "Verify attribution, disclosure, and wrapping",
        description: "Review the integrated transcript against the product direction.",
        status: .running,
        sessionFile: "/tmp/reviewer.jsonl",
        parentToolCallID: "task-review",
        actualModel: "gpt-5.6-sol",
        thinkingLevel: "high",
        modelRole: "review",
        isFallback: false,
        currentTool: "view_image",
        recentTools: [],
        recentOutput: ["Checked compact state", "Reviewing the structured diff"],
        toolCount: 7,
        requests: 2,
        tokens: 2_140,
        cost: 0.04,
        durationMilliseconds: 6_400,
        result: nil)
    let warning = TranscriptAnnotation(
        id: "wide-warning",
        kind: .retry,
        title: "Retrying response",
        detail: "Attempt 2 of 3 · 1s",
        timestamp: timestamp.addingTimeInterval(22),
        tone: .warning)
    return SessionController(
        processManager: SessionProcessManager(),
        previewItems: [
            .threadStart(id: "wide-start", date: timestamp),
            .message(assistant),
            .annotation(warning),
            .tool(edit),
            .subagent(subagent),
        ],
        runtimeState: .streaming,
        title: "Agent transcript")
}

@MainActor
private func snapshotRail(isExpanded: Bool) -> (AppModel, RailExpansionModel) {
    let model = AppModel()
    model.sessions = [
        snapshotSession(
            path: "/sessions/selected.jsonl",
            cwd: "/tmp/10x",
            title: "Improve active session shell",
            modified: 30),
        snapshotSession(
            path: "/sessions/earlier.jsonl",
            cwd: "/tmp/10x",
            title: "Transcript experience",
            modified: 20),
        snapshotSession(
            path: "/sessions/nextstep.jsonl",
            cwd: "/tmp/NextStep",
            title: "Review navigation",
            modified: 10),
    ]
    model.route = .session("/sessions/selected.jsonl")
    let expansion = RailExpansionModel()
    if isExpanded { expansion.pointerEntered() }
    return (model, expansion)
}

@MainActor
private func snapshotOverflowRail() -> (AppModel, RailExpansionModel) {
    let model = AppModel()
    model.sessions = (1...7).map { index in
        snapshotSession(
            path: "/sessions/overflow-\(index).jsonl",
            cwd: "/tmp/10x",
            title: "Session \(index)",
            modified: TimeInterval(100 - index))
    } + [
        snapshotSession(
            path: "/sessions/nextstep-overflow.jsonl",
            cwd: "/tmp/NextStep",
            title: "Review navigation",
            modified: 10),
    ]
    model.route = .session("/sessions/overflow-1.jsonl")
    let expansion = RailExpansionModel()
    expansion.pointerEntered()
    return (model, expansion)
}

private func snapshotSession(
    path: String,
    cwd: String,
    title: String,
    modified: TimeInterval
) -> SessionMetadata {
    SessionMetadata(
        path: path,
        sessionId: path,
        cwd: cwd,
        title: title,
        created: Date(timeIntervalSince1970: modified),
        modified: Date(timeIntervalSince1970: modified),
        sizeBytes: 10,
        status: .complete)
}

private func snapshotTextResult(_ text: String) -> JSONValue {
    .object(["content": .array([
        .object(["type": .string("text"), "text": .string(text)]),
    ])])
}

private struct SnapshotConfigRunner: OmpConfigRunning {
    func run(arguments: [String]) async throws -> Data {
        if arguments == ["config", "path"] {
            return Data("/Users/example/.omp/agent\n".utf8)
        }
        return Data(#"{"autoResume":{"value":false,"default":false,"type":"boolean","description":"Automatically resume the most recent session"},"advisor.enabled":{"value":true,"default":false,"type":"boolean","description":"Pair a second model that reviews each turn"},"providers.openai-codex.codeMode":{"value":"off","default":"off","type":"enum","description":"Route compatible models through code mode"},"tools.outputMaxColumns":{"value":768,"default":512,"type":"number","description":"Per-line output width"},"approval.mode":{"value":"ask","default":"ask","type":"enum","description":"Require approval before commands"}}"#.utf8)
    }
}

private let snapshotProjectURL = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private let snapshotFileOpenService = FileOpenService(
    openDefault: { _ in },
    openInApplication: { _, _ in },
    reveal: { _ in },
    startSecurityScope: { _ in false },
    stopSecurityScope: { _ in })

@MainActor
private let snapshotEmptyIDEStore: IDEPreferenceStore = {
    let suiteName = "TenXAppTests.ReferenceSnapshots"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return IDEPreferenceStore(defaults: defaults, registry: .testing(applications: [:]))
}()

@MainActor
private func snapshotComposerControls(
    models: [ComposerModelInfo],
    selected: ComposerModelInfo,
    thinkingLevel: String,
    fastModeEnabled: Bool
) async -> ComposerControlsModel {
    let catalog = SnapshotComposerCatalog(snapshot: ComposerCatalogSnapshot(
        models: models,
        selected: selected,
        thinkingLevel: thinkingLevel,
        fastModeEnabled: fastModeEnabled,
        fastModeActive: false))
    let model = ComposerControlsModel(
        catalog: catalog,
        defaults: SnapshotComposerDefaults())
    await model.refresh(authenticatedProviderIDs: Set(models.map(\.provider)))
    return model
}

private actor SnapshotComposerCatalog: ComposerCatalogLoading {
    private let snapshot: ComposerCatalogSnapshot

    init(snapshot: ComposerCatalogSnapshot) {
        self.snapshot = snapshot
    }

    func load() async throws -> ComposerCatalogSnapshot { snapshot }

    func shutdown() async {}
}

private actor SnapshotComposerDefaults: ComposerDefaultPersisting {
    func setDefaultModel(provider: String, modelID: String) async throws {}
    func setDefaultThinkingLevel(_ level: String) async throws {}
}

private let stubComposerControlsFactory: @MainActor @Sendable (URL) -> ComposerControlsModel = { _ in
    ComposerControlsModel(
        catalog: SnapshotComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [],
            selected: nil,
            thinkingLevel: nil,
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: SnapshotComposerDefaults())
}

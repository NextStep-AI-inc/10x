import Foundation
import OmpKit
import SwiftUI
import Testing
@testable import TenXApp

@Test func sessionMapSettingsMatcherFindsItsOwnRows() {
    #expect(SessionMapSettingRows.matches(query: "writer model"))
    #expect(SessionMapSettingRows.matches(query: "unattended"))
    #expect(!SessionMapSettingRows.matches(query: "Preferred IDE"))
}

@MainActor
@Test func sessionMapSettingsOffSnapshotCandidate() throws {
    let (preferences, cleanup) = try snapshotPreferences("off")
    defer { cleanup() }
    try assertSnapshot(
        sessionMapRows(preferences: preferences),
        name: "session-map-settings-off",
        size: CGSize(width: 900, height: 300))
}

@MainActor
@Test func sessionMapSettingsUnavailableSnapshotCandidate() throws {
    let (preferences, cleanup) = try snapshotPreferences("unavailable")
    defer { cleanup() }
    preferences.writerSelection = .role("missing")
    try assertSnapshot(
        sessionMapRows(preferences: preferences),
        name: "session-map-settings-unavailable",
        size: CGSize(width: 900, height: 300))
}

@MainActor
@Test func sessionMapSettingsResolvedCheckerSnapshotCandidate() throws {
    let (preferences, cleanup) = try snapshotPreferences("resolved")
    defer { cleanup() }
    preferences.checkerSelection = .role("vision")
    try assertSnapshot(
        sessionMapRows(preferences: preferences),
        name: "session-map-settings-resolved",
        size: CGSize(width: 900, height: 300))
}

@MainActor
@Test func sessionMapCatalogLoadsOnlyWhenSettingsRowsNeedIt() async throws {
    let suite = "TenXAppTests.SessionMapSettings.Lazy.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let catalog = SessionMapSettingsCatalogStub(models: [
        ComposerModelInfo(modelID: "writer", name: "Writer", provider: "p", api: nil,
                          thinkingEfforts: [], requiresEffort: false),
    ])
    let runner = SessionMapSettingsRunner()
    let model = SettingsViewModel(
        service: OmpConfigService(runner: runner),
        sessionMapCatalog: catalog,
        sessionMapPreferences: SessionMapPreferenceStore(defaults: defaults))

    #expect(await model.load())
    #expect(await catalog.loadCount == 0)
    await model.loadSessionMapCatalog(projectURL: URL(filePath: "/tmp/project"))

    #expect(await catalog.loadCount == 1)
    #expect(model.sessionMapModels.map(\.id) == ["p/writer"])
    #expect(model.sessionMapRoles == ["smol": "p/writer"])
}

@MainActor
@Test func sessionMapCatalogReloadsAfterSettingsShutdown() async throws {
    let catalog = SessionMapSettingsCatalogStub(models: [sessionMapCatalogModel("old")])
    let model = sessionMapSettingsModel(catalog: catalog)

    await model.loadSessionMapCatalog(projectURL: nil)
    await model.shutdownSessionMapCatalog()
    await catalog.setModels([sessionMapCatalogModel("new")])
    await model.loadSessionMapCatalog(projectURL: nil)

    #expect(await catalog.loadCount == 2)
    #expect(model.sessionMapModels.map(\.id) == ["p/new"])
}

@MainActor
@Test func closingSettingsLoadCannotPublishOverReloadedCatalog() async throws {
    let catalog = SessionMapSettingsCatalogStub(models: [sessionMapCatalogModel("old")])
    let model = sessionMapSettingsModel(catalog: catalog)
    await catalog.blockNextLoad()

    let closingLoad = Task { await model.loadSessionMapCatalog(projectURL: nil) }
    await catalog.waitUntilLoadIsBlocked()
    await model.shutdownSessionMapCatalog()
    await catalog.setModels([sessionMapCatalogModel("new")])
    await model.loadSessionMapCatalog(projectURL: nil)
    await catalog.releaseBlockedLoad()
    await closingLoad.value

    #expect(await catalog.loadCount == 2)
    #expect(model.sessionMapModels.map(\.id) == ["p/new"])
}

private actor SessionMapSettingsCatalogStub: ComposerCatalogLoading {
    nonisolated let commandUpdates = AsyncStream<ComposerCommandCatalogState> { $0.finish() }
    private var models: [ComposerModelInfo]
    private(set) var loadCount = 0
    private var shouldBlockNextLoad = false
    private var blockedLoadContinuation: CheckedContinuation<Void, Never>?

    init(models: [ComposerModelInfo]) { self.models = models }

    func load(projectURL: URL?) async throws -> ComposerCatalogSnapshot {
        loadCount += 1
        let loadedModels = models
        if shouldBlockNextLoad {
            shouldBlockNextLoad = false
            await withCheckedContinuation { blockedLoadContinuation = $0 }
        }
        return ComposerCatalogSnapshot(
            models: loadedModels, selected: nil, thinkingLevel: nil,
            fastModeEnabled: false, fastModeActive: false)
    }

    func shutdown() async {}

    func setModels(_ models: [ComposerModelInfo]) {
        self.models = models
    }

    func blockNextLoad() {
        shouldBlockNextLoad = true
    }

    func waitUntilLoadIsBlocked() async {
        while blockedLoadContinuation == nil { await Task.yield() }
    }

    func releaseBlockedLoad() {
        blockedLoadContinuation?.resume()
        blockedLoadContinuation = nil
    }
}

@MainActor
private func sessionMapSettingsModel(
    catalog: SessionMapSettingsCatalogStub
) -> SettingsViewModel {
    SettingsViewModel(
        service: OmpConfigService(runner: SessionMapSettingsRunner()),
        sessionMapCatalog: catalog)
}

private func sessionMapCatalogModel(_ modelID: String) -> ComposerModelInfo {
    ComposerModelInfo(
        modelID: modelID, name: modelID.capitalized, provider: "p", api: nil,
        thinkingEfforts: [], requiresEffort: false)
}

private struct SessionMapSettingsRunner: OmpConfigRunning {
    func run(arguments: [String]) async throws -> Data {
        if arguments == ["config", "list", "--json"] {
            return Data("""
            {"modelRoles":{"value":{"smol":"p/writer"},"type":"record"}}
            """.utf8)
        }
        if arguments == ["config", "path"] { return Data("/tmp/config.json\n".utf8) }
        return Data()
    }
}

@MainActor
private func sessionMapRows(preferences: SessionMapPreferenceStore) -> some View {
    SessionMapSettingRows(
        presentation: .init(
            preferences: preferences,
            catalog: [
                ComposerModelInfo(
                    modelID: "writer", name: "Writer", provider: "fixture-text", api: nil,
                    thinkingEfforts: [], requiresEffort: false),
                ComposerModelInfo(
                    modelID: "vision", name: "Vision", provider: "fixture-image", api: nil,
                    thinkingEfforts: ["high"], requiresEffort: false, acceptsImages: true),
            ],
            roles: ["smol": "fixture-text/writer", "vision": "fixture-image/vision:high"]),
        isLoading: false,
        errorMessage: nil)
        .padding(.horizontal, 36)
        .background(TenXPalette.color(TenXPalette.canvasHex))
}

@MainActor
private func snapshotPreferences(
    _ suffix: String
) throws -> (SessionMapPreferenceStore, () -> Void) {
    let suite = "TenXAppTests.SessionMapSettingsSnapshot.\(suffix).\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    return (SessionMapPreferenceStore(defaults: defaults), {
        defaults.removePersistentDomain(forName: suite)
    })
}

@MainActor
@Test func sessionMapSettingsRestrictCheckerChoicesToImageModels() throws {
    let suite = "TenXAppTests.SessionMapSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = SessionMapPreferenceStore(defaults: defaults)
    let rows = SessionMapSettingRows.Presentation(
        preferences: preferences,
        catalog: [
            ComposerModelInfo(modelID: "text", name: "Text", provider: "p", api: nil,
                              thinkingEfforts: [], requiresEffort: false),
            ComposerModelInfo(modelID: "vision", name: "Vision", provider: "p", api: nil,
                              thinkingEfforts: [], requiresEffort: false, acceptsImages: true),
        ],
        roles: ["text-role": "p/text", "vision-role": "p/vision"])

    #expect(rows.checkerChoices.map(\.selection) == [nil, .role("vision-role"), .model(id: "p/vision", effort: nil)])
}

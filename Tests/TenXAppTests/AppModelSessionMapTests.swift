import AppKit
import Foundation
import OmpKit
import SwiftUI
import Testing
@testable import TenXApp

@MainActor
@Test func newerAppModelMapRequestWinsWhenOlderSetupResumesLast() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "app-model-map-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let locator = ReorderedSessionMapLocator()
    let writer = RecordingSessionMapWriter()
    let dependencies = sessionMapAppDependencies(root: root, locator: locator, writer: writer)
    let model = AppModel(dependencies: dependencies)
    let controller = SessionController(
        processManager: SessionProcessManager(),
        previewItems: [],
        runtimeState: .idle)
    let metadata = sessionMapMetadata(path: "/tmp/session.jsonl", cwd: root.path)
    model.installSessionMapFixture(
        [(metadata, controller, nil, .needsGeneration)],
        selectedPath: metadata.path)
    let pane = model.sessionMapPaneModel(for: controller, displayedWidth: 440)

    pane.generate(.sinceCaughtUp)
    await locator.waitUntilFirstRequestIsBlocked()
    pane.generate(.sinceCaughtUp)
    await waitForSessionMap { await writer.callCount == 1 }
    await locator.releaseFirstRequest()
    await waitForSessionMap { pane.state == .ready }

    #expect(await writer.callCount == 1)
    #expect(pane.displayedDocument?.headline == "Newest map")
}

@MainActor
@Test func appModelMigratesTemporaryMapRecordToCanonicalSessionKey() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "app-model-map-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = SessionMapStore(directory: root)
    let dependencies = sessionMapAppDependencies(
        root: root, locator: ReorderedSessionMapLocator(),
        writer: RecordingSessionMapWriter(), store: store)
    let model = AppModel(dependencies: dependencies)
    let controllerID = UUID()
    let temporaryKey = "new:\(controllerID.uuidString)"
    let canonicalKey = "/tmp/canonical-session.jsonl"
    let record = sessionMapRecordForMigration()
    try await store.save(record, sessionKey: temporaryKey)

    await model.migrateSessionMapRecordForCanonicalization(
        controllerID: controllerID,
        canonicalSessionPath: canonicalKey)

    #expect(try await store.load(sessionKey: temporaryKey) == nil)
    #expect(try await store.load(sessionKey: canonicalKey) == record)
}

@MainActor
@Test func retainedSessionMapSaveErrorChangesRenderedPane() throws {
    let document = try SessionMapFixtures.document(SessionMapFixtures.planningXML)
    let plain = SessionMapPaneModel(displayedDocument: document, state: .stale)
    let failed = SessionMapPaneModel(displayedDocument: document, state: .stale)
    failed.retainFailure(message: "The updated map could not be saved.")

    let plainImage = try renderedSessionMapPane(plain)
    let failedImage = try renderedSessionMapPane(failed)
    try failedImage.write(to: URL(filePath: "/tmp/task9-fix1-save-error.png"))

    #expect(plainImage != failedImage)
}

private actor ReorderedSessionMapLocator: OmpLocating {
    private var requestCount = 0
    private var firstContinuation: CheckedContinuation<Void, Never>?

    func locate(preferredURL: URL?) async -> OmpLocation {
        requestCount += 1
        if requestCount == 1 {
            await withCheckedContinuation { firstContinuation = $0 }
        }
        return .found(OmpInstallation(
            executableURL: URL(filePath: "/tmp/omp"), version: "test"))
    }

    func waitUntilFirstRequestIsBlocked() async {
        while firstContinuation == nil { await Task.yield() }
    }

    func releaseFirstRequest() {
        firstContinuation?.resume()
        firstContinuation = nil
    }
}

private actor RecordingSessionMapWriter {
    private(set) var callCount = 0

    func complete(
        prompt: String,
        images: [PromptImage],
        model: SessionMapResolvedModel
    ) -> String {
        callCount += 1
        return "<sessionmap headline=\"Newest map\" phase=\"planning\"><summary>Current.</summary></sessionmap>"
    }
}

@MainActor
private func sessionMapAppDependencies(
    root: URL,
    locator: ReorderedSessionMapLocator,
    writer: RecordingSessionMapWriter,
    store: SessionMapStore? = nil
) -> AppDependencies {
    AppDependencies(
        ompLocator: locator,
        sessionLibrary: SessionLibrary(root: root.appending(path: "sessions")),
        recentProjectStore: RecentProjectStore(defaults: UserDefaults()),
        makeSettingsModel: { _ in
            SettingsViewModel(
                service: OmpConfigService(runner: SessionMapConfigRunner()),
                sessionMapCatalog: SessionMapCatalog())
        },
        makeProviderModel: { _ in providerTestModel(providers: []) },
        makeComposerControls: stubAppComposerControlsFactory,
        makeUpdateChecker: stubUpdateCheckerFactory,
        sessionMapStore: store ?? SessionMapStore(directory: root.appending(path: "maps")),
        makeSessionMapGenerator: { _, _ in
            SessionMapGenerator { prompt, images, model in
                await writer.complete(prompt: prompt, images: images, model: model)
            }
        })
}

private struct SessionMapConfigRunner: OmpConfigRunning {
    func run(arguments: [String]) async throws -> Data {
        if arguments == ["config", "list", "--json"] {
            return Data(#"{"modelRoles":{"value":{"smol":"fixture/writer"},"type":"record"}}"#.utf8)
        }
        return Data("/tmp/config.json\n".utf8)
    }
}

private actor SessionMapCatalog: ComposerCatalogLoading {
    nonisolated let commandUpdates = AsyncStream<ComposerCommandCatalogState> { $0.finish() }

    func load(projectURL: URL?) async throws -> ComposerCatalogSnapshot {
        ComposerCatalogSnapshot(
            models: [ComposerModelInfo(
                modelID: "writer", name: "Writer", provider: "fixture", api: nil,
                thinkingEfforts: [], requiresEffort: false)],
            selected: nil,
            thinkingLevel: nil,
            fastModeEnabled: false,
            fastModeActive: false)
    }

    func shutdown() async {}
}

private func sessionMapMetadata(path: String, cwd: String) -> SessionMetadata {
    SessionMetadata(
        path: path,
        sessionId: path,
        cwd: cwd,
        title: "Session",
        created: .distantPast,
        modified: .distantPast,
        sizeBytes: 1,
        status: .complete)
}

private func sessionMapRecordForMigration() -> SessionMapRecord {
    let configuration = SessionMapResolvedModel(
        provider: "fixture", modelID: "writer", effort: nil, acceptsImages: false)
    return SessionMapRecord(
        xml: "<sessionmap headline=\"Saved\" phase=\"planning\"><summary>Saved.</summary></sessionmap>",
        cacheKey: "cache",
        generatedThrough: SessionMapCursor(lineage: "lineage", entryID: nil),
        sourceManifest: [:],
        caughtUpAt: nil,
        caughtUpCursor: nil,
        caughtUpGraph: nil,
        firstSeenOrder: [],
        updatedAt: Date(timeIntervalSince1970: 1),
        writerConfiguration: configuration,
        checkerConfiguration: nil,
        checkOutcome: .off,
        dismissedThrough: nil)
}

@MainActor
private func renderedSessionMapPane(_ model: SessionMapPaneModel) throws -> Data {
    let size = CGSize(width: 440, height: 640)
    let host = NSHostingView(rootView: SessionMapPaneView(model: model)
        .frame(width: size.width, height: size.height))
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        throw SessionMapAppModelTestError.renderFailed
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw SessionMapAppModelTestError.renderFailed
    }
    return data
}

private func waitForSessionMap(
    _ condition: @escaping @MainActor () async -> Bool
) async {
    for _ in 0..<200 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private enum SessionMapAppModelTestError: Error { case renderFailed }

import Foundation
import Testing
@testable import TenXApp

private let anthropicOpus = ComposerModelInfo(
    id: "claude-opus-4-8",
    name: "Claude Opus 4.8",
    provider: "anthropic",
    api: "anthropic-messages",
    thinkingEfforts: ["low", "high"],
    requiresEffort: false)

private let anthropicSonnet = ComposerModelInfo(
    id: "claude-sonnet-4-5",
    name: "Claude Sonnet 4.5",
    provider: "anthropic",
    api: "anthropic-messages",
    thinkingEfforts: [],
    requiresEffort: false)

private let cursorModel = ComposerModelInfo(
    id: "gpt-5",
    name: "GPT-5",
    provider: "cursor",
    api: "cursor-agent",
    thinkingEfforts: [],
    requiresEffort: false)

@MainActor
@Test func refreshFiltersToAuthenticatedProvidersAndSeedsSelection() async {
    let catalog = FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
        models: [anthropicOpus, anthropicSonnet, cursorModel],
        selected: anthropicOpus,
        thinkingLevel: "high",
        fastModeEnabled: true,
        fastModeActive: false))
    let model = ComposerControlsModel(catalog: catalog, defaults: FakeComposerDefaults())

    await model.refresh(authenticatedProviderIDs: ["anthropic"])

    #expect(model.models.map(\.id) == ["claude-opus-4-8", "claude-sonnet-4-5"])
    #expect(model.selectedModel?.id == "claude-opus-4-8")
    #expect(model.thinkingLevel == "high")
    #expect(model.isFastModeEnabled == true)
    #expect(model.isFastModeVisible == true)
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func refreshHidesFastModeForCursorModel() async {
    let catalog = FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
        models: [cursorModel],
        selected: cursorModel,
        thinkingLevel: "auto",
        fastModeEnabled: false,
        fastModeActive: false))
    let model = ComposerControlsModel(catalog: catalog, defaults: FakeComposerDefaults())

    await model.refresh(authenticatedProviderIDs: ["cursor"])

    #expect(model.selectedModel?.provider == "cursor")
    #expect(model.isFastModeVisible == false)
}

@MainActor
@Test func newSessionSelectModelPersistsBeforeUpdatingUI() async throws {
    let defaults = FakeComposerDefaults()
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus, anthropicSonnet],
            selected: anthropicOpus,
            thinkingLevel: "auto",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: defaults)
    await model.refresh(authenticatedProviderIDs: ["anthropic"])

    await model.selectModel(anthropicSonnet, mode: .newSession)

    let modelCalls = await defaults.modelCalls
    #expect(modelCalls.count == 1)
    #expect(modelCalls.first?.0 == "anthropic")
    #expect(modelCalls.first?.1 == "claude-sonnet-4-5")
    #expect(model.selectedModel?.id == "claude-sonnet-4-5")
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func newSessionFailedPersistLeavesSelectionUnchanged() async throws {
    let defaults = FakeComposerDefaults()
    await defaults.setShouldFail(true)
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus, anthropicSonnet],
            selected: anthropicOpus,
            thinkingLevel: "auto",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: defaults)
    await model.refresh(authenticatedProviderIDs: ["anthropic"])

    await model.selectModel(anthropicSonnet, mode: .newSession)

    #expect(model.selectedModel?.id == "claude-opus-4-8")
    #expect(model.errorMessage != nil)
    #expect(await defaults.modelCalls.count == 1)
}

@MainActor
@Test func activeSessionSelectModelCallsSessionAndDoesNotPersist() async throws {
    let defaults = FakeComposerDefaults()
    let session = FakeComposerSessionController()
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus, anthropicSonnet],
            selected: anthropicOpus,
            thinkingLevel: "auto",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: defaults)
    await model.refresh(authenticatedProviderIDs: ["anthropic"])
    model.attachActiveSession(session)

    await model.selectModel(anthropicSonnet, mode: .activeSession)

    #expect(session.setModelCalls.count == 1)
    #expect(session.setModelCalls.first?.0 == "anthropic")
    #expect(session.setModelCalls.first?.1 == "claude-sonnet-4-5")
    #expect(await defaults.modelCalls.isEmpty)
    #expect(await defaults.thinkingCalls.isEmpty)
    #expect(model.selectedModel?.id == "claude-sonnet-4-5")
}

@MainActor
@Test func newSessionSetFastModeStoresIntentOnly() async {
    let defaults = FakeComposerDefaults()
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus],
            selected: anthropicOpus,
            thinkingLevel: "auto",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: defaults)
    await model.refresh(authenticatedProviderIDs: ["anthropic"])

    await model.setFastMode(true, mode: .newSession)

    #expect(model.isFastModeEnabled == true)
    #expect(model.spawnSelection.fastModeEnabled == true)
    #expect(await defaults.modelCalls.isEmpty)
    #expect(await defaults.thinkingCalls.isEmpty)
}

@MainActor
@Test func activeSessionSetFastModeUsesLiveRPC() async {
    let session = FakeComposerSessionController()
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus],
            selected: anthropicOpus,
            thinkingLevel: "auto",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: FakeComposerDefaults())
    await model.refresh(authenticatedProviderIDs: ["anthropic"])
    model.attachActiveSession(session)

    await model.setFastMode(true, mode: .activeSession)

    #expect(session.setFastModeCalls == [true])
    #expect(model.isFastModeEnabled == true)
}

@MainActor
@Test func activeSessionSelectModelRevertsWhenSetModelThrows() async {
    let session = FakeComposerSessionController()
    session.setModelError = FakeComposerError.rpcFailed
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus, anthropicSonnet],
            selected: anthropicOpus,
            thinkingLevel: "auto",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: FakeComposerDefaults())
    await model.refresh(authenticatedProviderIDs: ["anthropic"])
    model.attachActiveSession(session)

    await model.selectModel(anthropicSonnet, mode: .activeSession)

    #expect(session.setModelCalls.count == 1)
    #expect(model.selectedModel?.id == "claude-opus-4-8")
    #expect(model.errorMessage != nil)
}

@MainActor
@Test func activeSessionSelectThinkingRevertsWhenSetThinkingThrows() async {
    let session = FakeComposerSessionController()
    session.setThinkingError = FakeComposerError.rpcFailed
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus],
            selected: anthropicOpus,
            thinkingLevel: "auto",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: FakeComposerDefaults())
    await model.refresh(authenticatedProviderIDs: ["anthropic"])
    model.attachActiveSession(session)

    await model.selectThinking("high", mode: .activeSession)

    #expect(session.setThinkingCalls == ["high"])
    #expect(model.thinkingLevel == "auto")
    #expect(model.errorMessage != nil)
}

@MainActor
@Test func activeSessionSelectModelRevertRestoresPriorFastIntent() async {
    let session = FakeComposerSessionController()
    session.setModelError = FakeComposerError.rpcFailed
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus, cursorModel],
            selected: anthropicOpus,
            thinkingLevel: "auto",
            fastModeEnabled: true,
            fastModeActive: false)),
        defaults: FakeComposerDefaults())
    await model.refresh(authenticatedProviderIDs: ["anthropic", "cursor"])
    model.attachActiveSession(session)
    #expect(model.isFastModeEnabled == true)
    #expect(model.isFastModeVisible == true)

    await model.selectModel(cursorModel, mode: .activeSession)

    #expect(model.selectedModel?.id == "claude-opus-4-8")
    #expect(model.isFastModeEnabled == true)
    #expect(model.isFastModeVisible == true)
    #expect(model.errorMessage != nil)
}

@MainActor
@Test func activeSessionUnsupportedSetFastModeHidesChip() async {
    let session = FakeComposerSessionController()
    session.setFastModeSupported = false
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus],
            selected: anthropicOpus,
            thinkingLevel: "auto",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: FakeComposerDefaults())
    await model.refresh(authenticatedProviderIDs: ["anthropic"])
    model.attachActiveSession(session)
    #expect(model.isFastModeVisible == true)

    await model.setFastMode(true, mode: .activeSession)

    #expect(session.setFastModeCalls == [true])
    #expect(model.isFastModeEnabled == false)
    #expect(model.isFastModeVisible == false)
    #expect(model.errorMessage == "Fast mode isn’t available for this model.")
}

@MainActor
@Test func activeSessionSetFastModeTransportErrorKeepsChip() async {
    let session = FakeComposerSessionController()
    session.setFastModeError = FakeComposerError.rpcFailed
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus],
            selected: anthropicOpus,
            thinkingLevel: "auto",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: FakeComposerDefaults())
    await model.refresh(authenticatedProviderIDs: ["anthropic"])
    model.attachActiveSession(session)

    await model.setFastMode(true, mode: .activeSession)

    #expect(session.setFastModeCalls == [true])
    #expect(model.isFastModeEnabled == false)
    #expect(model.isFastModeVisible == true)
    #expect(model.errorMessage != nil)
    #expect(model.errorMessage != "Fast mode isn’t available for this model.")
}

// MARK: - Fakes

private actor FakeComposerCatalog: ComposerCatalogLoading {
    private let snapshot: ComposerCatalogSnapshot

    init(snapshot: ComposerCatalogSnapshot) {
        self.snapshot = snapshot
    }

    func load() async throws -> ComposerCatalogSnapshot {
        snapshot
    }
}

private actor FakeComposerDefaults: ComposerDefaultPersisting {
    private(set) var modelCalls: [(String, String)] = []
    private(set) var thinkingCalls: [String] = []
    private var shouldFail = false

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    func setDefaultModel(provider: String, modelID: String) async throws {
        modelCalls.append((provider, modelID))
        if shouldFail { throw FakeComposerError.persistFailed }
    }

    func setDefaultThinkingLevel(_ level: String) async throws {
        thinkingCalls.append(level)
        if shouldFail { throw FakeComposerError.persistFailed }
    }
}

@MainActor
private final class FakeComposerSessionController: ComposerSessionControlling {
    private(set) var setModelCalls: [(String, String)] = []
    private(set) var setThinkingCalls: [String] = []
    private(set) var setFastModeCalls: [Bool] = []
    var setModelError: Error?
    var setThinkingError: Error?
    var setFastModeError: Error?
    var setFastModeSupported = true

    func setModel(provider: String, modelID: String) async throws {
        setModelCalls.append((provider, modelID))
        if let setModelError { throw setModelError }
    }

    func setThinkingLevel(_ level: String) async throws {
        setThinkingCalls.append(level)
        if let setThinkingError { throw setThinkingError }
    }

    func setFastMode(_ enabled: Bool) async throws -> Bool {
        setFastModeCalls.append(enabled)
        if let setFastModeError { throw setFastModeError }
        return setFastModeSupported
    }
}

private enum FakeComposerError: Error {
    case persistFailed
    case rpcFailed
}

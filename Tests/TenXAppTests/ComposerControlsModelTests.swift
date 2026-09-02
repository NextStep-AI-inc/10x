import Foundation
import Testing
@testable import TenXApp

private let anthropicOpus = ComposerModelInfo(
    modelID: "claude-opus-4-8",
    name: "Claude Opus 4.8",
    provider: "anthropic",
    api: "anthropic-messages",
    thinkingEfforts: ["low", "high"],
    requiresEffort: false)

private let anthropicSonnet = ComposerModelInfo(
    modelID: "claude-sonnet-4-5",
    name: "Claude Sonnet 4.5",
    provider: "anthropic",
    api: "anthropic-messages",
    thinkingEfforts: [],
    requiresEffort: false)

private let cursorModel = ComposerModelInfo(
    modelID: "gpt-5",
    name: "GPT-5",
    provider: "cursor",
    api: "cursor-agent",
    thinkingEfforts: [],
    requiresEffort: false)

/// Requires an effort and has no service-tier family, so Fast mode is unavailable
/// — the pair (anthropicOpus, this) discriminates which model Fast mode is
/// computed from after a switch.
private let fireworksRequiredEffort = ComposerModelInfo(
    modelID: "kimi-k2-thinking",
    name: "Kimi K2 Thinking",
    provider: "fireworks",
    api: "openai-completions",
    thinkingEfforts: ["low", "medium", "high"],
    requiresEffort: true)

private let codexRequiredEffort = ComposerModelInfo(
    modelID: "gpt-5.2-codex",
    name: "GPT-5.2 Codex",
    provider: "openai-codex",
    api: "openai-codex-responses",
    thinkingEfforts: ["low", "medium", "high"],
    requiresEffort: true)

@MainActor
private func isolatedRecents(_ name: String = #function) -> RecentModelStore {
    let defaults = UserDefaults(suiteName: "tests.\(name)")!
    defaults.removePersistentDomain(forName: "tests.\(name)")
    return RecentModelStore(defaults: defaults, key: "recent-model-keys")
}

@MainActor
@Test func refreshFiltersToAuthenticatedProvidersAndSeedsSelection() async {
    let catalog = FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
        models: [anthropicOpus, anthropicSonnet, cursorModel],
        selected: anthropicOpus,
        thinkingLevel: "high",
        fastModeEnabled: true,
        fastModeActive: false))
    let model = ComposerControlsModel(
        catalog: catalog, defaults: FakeComposerDefaults(), recents: isolatedRecents())

    await model.refresh(authenticatedProviderIDs: ["anthropic"], projectURL: nil)

    #expect(model.models.map(\.modelID) == ["claude-opus-4-8", "claude-sonnet-4-5"])
    #expect(model.selectedModel?.modelID == "claude-opus-4-8")
    #expect(model.selectedModel?.id == "anthropic/claude-opus-4-8")
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
    let model = ComposerControlsModel(
        catalog: catalog, defaults: FakeComposerDefaults(), recents: isolatedRecents())

    await model.refresh(authenticatedProviderIDs: ["cursor"], projectURL: nil)

    #expect(model.selectedModel?.provider == "cursor")
    #expect(model.isFastModeVisible == false)
}

@MainActor
@Test func staleRefreshDoesNotClearTheCurrentRefreshOrPublishAnError() async {
    let firstGate = RefreshLoadGate()
    let secondGate = RefreshLoadGate()
    let catalog = OverlappingRefreshCatalog(
        firstGate: firstGate,
        secondGate: secondGate,
        newerSnapshot: ComposerCatalogSnapshot(
            models: [anthropicSonnet],
            selected: anthropicSonnet,
            thinkingLevel: "high",
            fastModeEnabled: false,
            fastModeActive: false))
    let model = ComposerControlsModel(
        catalog: catalog, defaults: FakeComposerDefaults(), recents: isolatedRecents())

    let staleRefresh = Task {
        await model.refresh(authenticatedProviderIDs: ["anthropic"], projectURL: nil)
    }
    await firstGate.waitUntilBlocked()
    let currentRefresh = Task {
        await model.refresh(authenticatedProviderIDs: ["anthropic"], projectURL: nil)
    }
    await secondGate.waitUntilBlocked()

    await firstGate.release()
    await staleRefresh.value

    #expect(model.isLoading)
    #expect(model.models.isEmpty)
    #expect(model.errorMessage == nil)

    await secondGate.release()
    await currentRefresh.value

    #expect(model.isLoading == false)
    #expect(model.models.map(\.modelID) == ["claude-sonnet-4-5"])
    #expect(model.selectedModel?.modelID == "claude-sonnet-4-5")
    #expect(model.errorMessage == nil)
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
        defaults: defaults,
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic"], projectURL: nil)

    let outcome = await model.selectModel(anthropicSonnet, mode: .newSession)

    #expect(outcome == .success)
    let modelCalls = await defaults.modelCalls
    #expect(modelCalls.count == 1)
    #expect(modelCalls.first?.0 == "anthropic")
    #expect(modelCalls.first?.1 == "claude-sonnet-4-5")
    #expect(model.selectedModel?.modelID == "claude-sonnet-4-5")
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
        defaults: defaults,
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic"], projectURL: nil)

    let outcome = await model.selectModel(anthropicSonnet, mode: .newSession)

    #expect(outcome == .failure("Couldn’t update the default model."))
    #expect(model.selectedModel?.modelID == "claude-opus-4-8")
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
        defaults: defaults,
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic"], projectURL: nil)
    model.attachActiveSession(session)

    let outcome = await model.selectModel(anthropicSonnet, mode: .activeSession)

    #expect(outcome == .success)
    #expect(session.setModelCalls.count == 1)
    #expect(session.setModelCalls.first?.0 == "anthropic")
    #expect(session.setModelCalls.first?.1 == "claude-sonnet-4-5")
    #expect(await defaults.modelCalls.isEmpty)
    #expect(await defaults.thinkingCalls.isEmpty)
    #expect(model.selectedModel?.modelID == "claude-sonnet-4-5")
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
        defaults: defaults,
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic"], projectURL: nil)

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
        defaults: FakeComposerDefaults(),
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic"], projectURL: nil)
    model.attachActiveSession(session)

    let outcome = await model.setFastMode(true, mode: .activeSession)

    #expect(outcome == .success)
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
        defaults: FakeComposerDefaults(),
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic"], projectURL: nil)
    model.attachActiveSession(session)

    let outcome = await model.selectModel(anthropicSonnet, mode: .activeSession)

    #expect(outcome != .success)
    #expect(session.setModelCalls.count == 1)
    #expect(model.selectedModel?.modelID == "claude-opus-4-8")
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
        defaults: FakeComposerDefaults(),
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic"], projectURL: nil)
    model.attachActiveSession(session)

    let outcome = await model.selectThinking("high", mode: .activeSession)

    #expect(outcome != .success)
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
        defaults: FakeComposerDefaults(),
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic", "cursor"], projectURL: nil)
    session.liveComposerSelection = ComposerLiveSelection(
        provider: "anthropic",
        modelID: "claude-opus-4-8",
        thinkingLevel: "auto",
        fastModeEnabled: true)
    model.attachActiveSession(session)
    #expect(model.isFastModeEnabled == true)
    #expect(model.isFastModeVisible == true)

    await model.selectModel(cursorModel, mode: .activeSession)

    #expect(model.selectedModel?.modelID == "claude-opus-4-8")
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
        defaults: FakeComposerDefaults(),
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic"], projectURL: nil)
    model.attachActiveSession(session)
    #expect(model.isFastModeVisible == true)

    let outcome = await model.setFastMode(true, mode: .activeSession)

    #expect(outcome == .failure("Fast mode isn’t available for this model."))
    #expect(session.setFastModeCalls == [true])
    #expect(model.isFastModeEnabled == false)
    #expect(model.isFastModeVisible == false)
    #expect(model.errorMessage == "Fast mode isn’t available for this model.")

    let invisibleOutcome = await model.setFastMode(true, mode: .activeSession)
    #expect(invisibleOutcome == .failure("Fast mode isn’t available for this model."))
}

@MainActor
@Test func mutationOutcomesRejectMissingControllerAndRepeatedIdenticalRPCFailures() async {
    let catalog = FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
        models: [anthropicOpus, anthropicSonnet],
        selected: anthropicOpus,
        thinkingLevel: "auto",
        fastModeEnabled: false,
        fastModeActive: false))
    let controls = ComposerControlsModel(
        catalog: catalog,
        defaults: FakeComposerDefaults(),
        recents: isolatedRecents())
    await controls.refresh(authenticatedProviderIDs: ["anthropic"], projectURL: nil)

    #expect(
        await controls.selectModel(anthropicSonnet, mode: .activeSession)
            == .failure("Couldn’t update this setting."))

    let session = FakeComposerSessionController()
    session.setModelError = FakeComposerVerboseError()
    controls.attachActiveSession(session)

    let firstFailure = await controls.selectModel(anthropicSonnet, mode: .activeSession)
    let secondFailure = await controls.selectModel(anthropicSonnet, mode: .activeSession)

    #expect(firstFailure == .failure("Couldn’t update the model."))
    #expect(secondFailure == .failure("Couldn’t update the model."))
    #expect(session.setModelCalls.count == 2)
}

@MainActor
@Test func mutationOutcomesRejectInFlightMutationWithoutReportingSuccess() async {
    let gate = RefreshLoadGate()
    let controls = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus, anthropicSonnet],
            selected: anthropicOpus,
            thinkingLevel: "auto",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: FakeComposerDefaults(),
        recents: isolatedRecents())
    await controls.refresh(authenticatedProviderIDs: ["anthropic"], projectURL: nil)
    let session = BlockingComposerSessionController(gate: gate)
    controls.attachActiveSession(session)

    let activeMutation = Task {
        await controls.selectModel(anthropicSonnet, mode: .activeSession)
    }
    await gate.waitUntilBlocked()

    #expect(
        await controls.selectModel(anthropicOpus, mode: .activeSession)
            == .failure("Couldn’t update this setting."))

    await gate.release()
    #expect(await activeMutation.value == .success)
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
        defaults: FakeComposerDefaults(),
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic"], projectURL: nil)
    model.attachActiveSession(session)

    let outcome = await model.setFastMode(true, mode: .activeSession)

    #expect(outcome != .success)
    #expect(session.setFastModeCalls == [true])
    #expect(model.isFastModeEnabled == false)
    #expect(model.isFastModeVisible == true)
    #expect(model.errorMessage != nil)
    #expect(model.errorMessage != "Fast mode isn’t available for this model.")
}

@MainActor
@Test func refreshWithActiveSessionPreservesLiveSelectionNotCatalogDefaults() async {
    let catalog = FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
        models: [anthropicOpus, anthropicSonnet, cursorModel],
        selected: anthropicOpus,
        thinkingLevel: "high",
        fastModeEnabled: true,
        fastModeActive: false))
    let session = FakeComposerSessionController()
    session.liveComposerSelection = ComposerLiveSelection(
        provider: "cursor",
        modelID: "gpt-5",
        thinkingLevel: "low",
        fastModeEnabled: false)
    let model = ComposerControlsModel(
        catalog: catalog, defaults: FakeComposerDefaults(), recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic", "cursor"], projectURL: nil)
    model.attachActiveSession(session)

    #expect(model.selectedModel?.modelID == "gpt-5")
    #expect(model.thinkingLevel == "low")
    #expect(model.isFastModeEnabled == false)

    await model.refresh(authenticatedProviderIDs: ["anthropic", "cursor"], projectURL: nil)

    #expect(model.selectedModel?.modelID == "gpt-5")
    #expect(model.thinkingLevel == "low")
    #expect(model.isFastModeEnabled == false)
    #expect(model.models.map(\.modelID) == ["claude-opus-4-8", "claude-sonnet-4-5", "gpt-5"])
}

@MainActor
@Test func applyLiveSelectionSeedsModelThinkingAndFastFromSession() async {
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus, anthropicSonnet, cursorModel],
            selected: anthropicOpus,
            thinkingLevel: "auto",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: FakeComposerDefaults(),
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic", "cursor"], projectURL: nil)
    #expect(model.selectedModel?.modelID == "claude-opus-4-8")

    model.applyLiveSelection(ComposerLiveSelection(
        provider: "cursor",
        modelID: "gpt-5",
        thinkingLevel: "low",
        fastModeEnabled: true))

    #expect(model.selectedModel?.modelID == "gpt-5")
    #expect(model.thinkingLevel == "low")
    #expect(model.isFastModeVisible == false)
    #expect(model.isFastModeEnabled == false)
}

@MainActor
@Test func spawnSelectionOmitsThinkingWhenModelHasNoThinkingOptions() async {
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicSonnet],
            selected: anthropicSonnet,
            thinkingLevel: "high",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: FakeComposerDefaults(),
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic"], projectURL: nil)

    #expect(model.thinkingOptions.isEmpty)
    #expect(model.spawnSelection.thinking == nil)
    #expect(model.spawnSelection.modelID == "claude-sonnet-4-5")
}

@MainActor
@Test func composerModelInfoIdentityIncludesProvider() {
    let left = ComposerModelInfo(
        modelID: "shared",
        name: "A",
        provider: "anthropic",
        api: nil,
        thinkingEfforts: [],
        requiresEffort: false)
    let right = ComposerModelInfo(
        modelID: "shared",
        name: "B",
        provider: "cursor",
        api: nil,
        thinkingEfforts: [],
        requiresEffort: false)
    #expect(left.id == "anthropic/shared")
    #expect(right.id == "cursor/shared")
    #expect(left.id != right.id)
}

@MainActor
@Test func selectingARequiredEffortModelDropsAutoFromTheThinkingLevel() async {
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus, codexRequiredEffort],
            selected: anthropicOpus,
            thinkingLevel: "auto",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: FakeComposerDefaults(),
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic", "openai-codex"], projectURL: nil)

    await model.selectModel(codexRequiredEffort, mode: .newSession)

    #expect(model.thinkingLevel == "medium")
    #expect(model.spawnSelection.thinking == "medium")
}

@MainActor
@Test func selectingAModelKeepsAThinkingLevelItStillOffers() async {
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus, codexRequiredEffort],
            selected: anthropicOpus,
            thinkingLevel: "high",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: FakeComposerDefaults(),
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic", "openai-codex"], projectURL: nil)

    await model.selectModel(codexRequiredEffort, mode: .newSession)

    #expect(model.thinkingLevel == "high")
}

@MainActor
@Test func aFailedActiveSwitchRestoresTheThinkingLevelToo() async {
    let session = FakeComposerSessionController()
    session.setModelError = FakeComposerError.rpcFailed
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus, codexRequiredEffort],
            selected: anthropicOpus,
            thinkingLevel: "auto",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: FakeComposerDefaults(),
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic", "openai-codex"], projectURL: nil)
    model.attachActiveSession(session)

    await model.selectModel(codexRequiredEffort, mode: .activeSession)

    #expect(model.selectedModel?.modelID == "claude-opus-4-8")
    #expect(model.thinkingLevel == "auto")
    #expect(model.errorMessage != nil)
}

@MainActor
@Test func anActiveSwitchThatMovesTheThinkingLevelSendsItOnce() async {
    let defaults = FakeComposerDefaults()
    let session = FakeComposerSessionController()
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus, codexRequiredEffort],
            selected: anthropicOpus,
            thinkingLevel: "auto",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: defaults,
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic", "openai-codex"], projectURL: nil)
    model.attachActiveSession(session)

    await model.selectModel(codexRequiredEffort, mode: .activeSession)

    #expect(model.thinkingLevel == "medium")
    #expect(session.setModelCalls.count == 1)
    #expect(session.setThinkingCalls == ["medium"])
    #expect(await defaults.thinkingCalls.isEmpty)
    #expect(await defaults.modelCalls.isEmpty)
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func anActiveSwitchThatKeepsTheThinkingLevelSendsNoThinkingRPC() async {
    let defaults = FakeComposerDefaults()
    let session = FakeComposerSessionController()
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus, codexRequiredEffort],
            selected: anthropicOpus,
            thinkingLevel: "high",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: defaults,
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic", "openai-codex"], projectURL: nil)
    model.attachActiveSession(session)

    await model.selectModel(codexRequiredEffort, mode: .activeSession)

    #expect(model.thinkingLevel == "high")
    #expect(session.setModelCalls.count == 1)
    #expect(session.setThinkingCalls.isEmpty)
    #expect(await defaults.thinkingCalls.isEmpty)
    #expect(await defaults.modelCalls.isEmpty)
}

/// The two RPCs are two failure domains. Once `setModel` lands the runtime really
/// is on the new model, so reverting the chip would misname what the user is
/// talking to — only the level it failed to set may be rolled back.
@MainActor
@Test func aFailedThinkingReconciliationKeepsTheModelTheRuntimeIsRunning() async {
    let session = FakeComposerSessionController()
    // Long enough to trip the sanitizer's fallback, so the assertion below reads
    // the copy the user is actually shown.
    session.setThinkingError = FakeComposerVerboseError()
    let model = ComposerControlsModel(
        catalog: FakeComposerCatalog(snapshot: ComposerCatalogSnapshot(
            models: [anthropicOpus, fireworksRequiredEffort],
            selected: anthropicOpus,
            thinkingLevel: "auto",
            fastModeEnabled: false,
            fastModeActive: false)),
        defaults: FakeComposerDefaults(),
        recents: isolatedRecents())
    await model.refresh(authenticatedProviderIDs: ["anthropic", "fireworks"], projectURL: nil)
    model.attachActiveSession(session)
    #expect(model.isFastModeVisible == true)

    await model.selectModel(fireworksRequiredEffort, mode: .activeSession)

    #expect(session.setModelCalls.count == 1)
    #expect(session.setThinkingCalls == ["medium"])
    // The switch landed, so the chip keeps naming the model the runtime runs…
    #expect(model.selectedModel?.modelID == "kimi-k2-thinking")
    // …Fast mode stays computed from that new model, not the abandoned old one…
    #expect(model.isFastModeVisible == false)
    // …and only the level that failed to send is rolled back.
    #expect(model.thinkingLevel == "auto")
    #expect(model.errorMessage == "Couldn’t update the thinking level.")
}

// MARK: - Fakes

private actor FakeComposerCatalog: ComposerCatalogLoading {
    private let snapshot: ComposerCatalogSnapshot
    nonisolated let commandUpdates = AsyncStream<ComposerCommandCatalogState>(
        bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuation.yield(.available([]))
            continuation.finish()
        }

    init(snapshot: ComposerCatalogSnapshot) {
        self.snapshot = snapshot
    }

    func load(projectURL: URL?) async throws -> ComposerCatalogSnapshot {
        snapshot
    }

    func shutdown() async {}
}

private actor OverlappingRefreshCatalog: ComposerCatalogLoading {
    private let firstGate: RefreshLoadGate
    private let secondGate: RefreshLoadGate
    private let newerSnapshot: ComposerCatalogSnapshot
    private var loadCount = 0
    nonisolated let commandUpdates = AsyncStream<ComposerCommandCatalogState>(
        bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuation.yield(.available([]))
            continuation.finish()
        }

    init(
        firstGate: RefreshLoadGate,
        secondGate: RefreshLoadGate,
        newerSnapshot: ComposerCatalogSnapshot
    ) {
        self.firstGate = firstGate
        self.secondGate = secondGate
        self.newerSnapshot = newerSnapshot
    }

    func load(projectURL: URL?) async throws -> ComposerCatalogSnapshot {
        loadCount += 1
        if loadCount == 1 {
            await firstGate.block()
            throw CancellationError()
        }
        await secondGate.block()
        return newerSnapshot
    }

    func shutdown() async {}
}

private actor RefreshLoadGate {
    private var hasBlocked = false
    private var isReleased = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func block() async {
        hasBlocked = true
        let waiters = blockedWaiters
        blockedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilBlocked() async {
        guard !hasBlocked else { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
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
private final class BlockingComposerSessionController: ComposerSessionControlling {
    var liveComposerSelection = ComposerLiveSelection(
        provider: nil,
        modelID: nil,
        thinkingLevel: nil,
        fastModeEnabled: false)
    private let gate: RefreshLoadGate

    init(gate: RefreshLoadGate) {
        self.gate = gate
    }

    func setModel(provider: String, modelID: String) async throws {
        await gate.block()
    }

    func setThinkingLevel(_ level: String) async throws {}

    func setFastMode(_ enabled: Bool) async throws -> Bool {
        true
    }
}

@MainActor
private final class FakeComposerSessionController: ComposerSessionControlling {
    var liveComposerSelection = ComposerLiveSelection(
        provider: nil,
        modelID: nil,
        thinkingLevel: nil,
        fastModeEnabled: false)
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

/// Raw OMP failure text too long for the footer, so `sanitizedMessage` falls back
/// to the app's own copy and a test can assert which message the user is shown.
private struct FakeComposerVerboseError: LocalizedError {
    var errorDescription: String? {
        String(repeating: "omp reported a transport failure. ", count: 8)
    }
}

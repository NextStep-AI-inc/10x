import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor
@Test func openSettingsSelectsSettingsRoute() {
    let model = AppModel()

    model.openSettings()

    #expect(model.route == .settings)
}

@MainActor
@Test func openNewSessionSelectsNewSessionRoute() {
    let model = AppModel()
    model.route = .settings

    model.openNewSession()

    #expect(model.route == .newSession)
}

@MainActor
@Test func openSearchPresentsSearchWithoutChangingRoute() {
    let model = AppModel()
    model.route = .session("/tmp/session.jsonl")

    model.openSearch()

    #expect(model.isSearchPresented)
    #expect(model.route == .session("/tmp/session.jsonl"))
}

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

@MainActor
@Test func refreshProvidersIfNeededRefreshesAtFiveMinutesButNotBefore() async {
    let clock = ProviderRefreshClock(date: Date(timeIntervalSince1970: 100))
    let usageService = FakeUsageService(snapshot: .empty)
    let providerModel = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: [
            ProviderLoginProvider(
                id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
        ]),
        usageService: usageService,
        openURL: { _ in },
        now: { clock.date },
        formatTime: { _ in "4:00 PM" })
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))

    await model.bootstrap()
    await model.refreshProvidersIfNeeded()
    #expect(await usageService.loadCount == 1)

    clock.date = Date(timeIntervalSince1970: 400)
    await model.refreshProvidersIfNeeded()
    #expect(await usageService.loadCount == 2)
}

@MainActor
@Test func settingsProvidersActionOpensConnectionsWithoutChangingSettingsData() async throws {
    let providerModel = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))

    await model.bootstrap()
    let settingsModel = try #require(model.settingsModel)
    let settingsCount = settingsModel.settingCount
    model.openProviders(.connections)

    #expect(model.route == .providers(.connections))
    #expect(settingsModel.settingCount == settingsCount)
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

@MainActor
@Test func bootstrapSelectsProviderSetupWhileUsageIsStillLoading() async {
    let usageGate = LoadGate()
    let usageService = FakeUsageService(snapshot: .empty)
    await usageService.enqueueLoadGate(usageGate)
    let providerModel = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: [
            ProviderLoginProvider(
                id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
        ]),
        usageService: usageService,
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))

    let bootstrap = Task { await model.bootstrap() }
    await usageGate.waitForStart()
    for _ in 0..<20 { await Task.yield() }

    #expect(model.route == .providerSetup)
    await usageGate.release()
    await bootstrap.value
}

@MainActor
@Test func replacingProviderModelWaitsForItsShutdown() async {
    let shutdownGate = LoadGate()
    let firstService = FakeProviderService(
        providers: [ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false)],
        shutdownGate: shutdownGate)
    let firstModel = ProviderManagementViewModel(
        providerService: firstService,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    let secondModel = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    let models = ProviderModelQueue(models: [firstModel, secondModel])
    let model = AppModel(dependencies: testDependencies(
        ompLocator: SequentialOmpLocator(installations: [testInstallation, testInstallation]),
        makeProviderModel: { _ in models.next() }))
    await model.bootstrap()

    let replacement = Task { await model.useOmp(at: URL(filePath: "/tmp/replacement-omp")) }
    for _ in 0..<20 { await Task.yield() }

    #expect(model.providerModel === firstModel)
    #expect(await firstService.shutdownCount == 1)
    await shutdownGate.release()
    await replacement.value
    #expect(model.providerModel === secondModel)
}

@MainActor
@Test func failedInstallWaitsForProviderModelShutdownBeforeClearing() async {
    let shutdownGate = LoadGate()
    let providerService = FakeProviderService(
        providers: [ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false)],
        shutdownGate: shutdownGate)
    let providerModel = ProviderManagementViewModel(
        providerService: providerService,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    let model = AppModel(dependencies: testDependencies(
        ompLocator: SequentialOmpLocator(installations: [testInstallation, nil]),
        makeProviderModel: { _ in providerModel }))
    await model.bootstrap()

    let failedInstall = Task { await model.useOmp(at: URL(filePath: "/tmp/missing-omp")) }
    for _ in 0..<20 { await Task.yield() }

    #expect(model.providerModel === providerModel)
    #expect(await providerService.shutdownCount == 1)
    await shutdownGate.release()
    await failedInstall.value
    #expect(model.providerModel == nil)
    #expect(model.route == .setup)
}

private struct InstalledOmpLocator: OmpLocating {
    func locate(preferredURL: URL?) async -> OmpInstallation? {
        testInstallation
    }
}

private let testInstallation = OmpInstallation(
    executableURL: URL(filePath: "/tmp/omp"),
    version: "test")

private actor SequentialOmpLocator: OmpLocating {
    private var installations: [OmpInstallation?]

    init(installations: [OmpInstallation?]) {
        self.installations = installations
    }

    func locate(preferredURL: URL?) async -> OmpInstallation? {
        guard !installations.isEmpty else { return nil }
        return installations.removeFirst()
    }
}

@MainActor
private final class ProviderModelQueue {
    private var models: [ProviderManagementViewModel]

    init(models: [ProviderManagementViewModel]) {
        self.models = models
    }

    func next() -> ProviderManagementViewModel {
        models.removeFirst()
    }
}

@MainActor
private func testDependencies(
    providerModel: ProviderManagementViewModel
) -> AppDependencies {
    testDependencies(
        ompLocator: InstalledOmpLocator(),
        makeProviderModel: { _ in providerModel })
}

private func testDependencies<Locator: OmpLocating>(
    ompLocator: Locator,
    makeProviderModel: @escaping @MainActor @Sendable (URL) -> ProviderManagementViewModel
) -> AppDependencies {
    AppDependencies(
        ompLocator: ompLocator,
        sessionLibrary: SessionLibrary(root: URL(
            filePath: "/tmp/10x-provider-tests-empty",
            directoryHint: .isDirectory)),
        makeProviderModel: makeProviderModel)
}

private final class ProviderRefreshClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedDate: Date

    init(date: Date) {
        storedDate = date
    }

    var date: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedDate
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedDate = newValue
        }
    }
}

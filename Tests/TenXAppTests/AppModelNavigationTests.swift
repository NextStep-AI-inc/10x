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

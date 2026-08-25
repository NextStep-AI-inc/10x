import Foundation
import OmpKit
import Synchronization
import Testing
@testable import TenXApp

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

@MainActor
@Test func providerModelOpensValidatedBrowserURLAndKeepsLoginActive() async throws {
    let loginGate = LoginGate()
    let service = FakeProviderService(providers: [
        ProviderLoginProvider(id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
    ], loginGate: loginGate)
    let openedURLs = OpenURLRecorder()
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { url in
            Task { await openedURLs.append(url) }
        },
        now: { Date(timeIntervalSince1970: 100) })
    await model.load()
    let provider = try #require(model.visibleProviders.first)

    let loginTask = Task { await model.login(provider) }
    await loginGate.waitForStart()
    await service.emit(ExtensionUIRequest(
        id: "open",
        method: "open_url",
        payload: .object(["launchUrl": .string("https://example.com/login")])) )

    #expect(await openedURLs.waitForURL() == URL(string: "https://example.com/login"))
    #expect(model.activeLoginProviderID == "cursor")
    await loginGate.release()
    await loginTask.value
}

@MainActor
@Test func providerModelRoutesInputAndRespondsWithExactBody() async throws {
    let loginGate = LoginGate()
    let service = FakeProviderService(providers: [
        ProviderLoginProvider(id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
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
        id: "input",
        method: "input",
        payload: .object([
            "title": .string("Paste the code"),
            "placeholder": .string("Code"),
        ])))
    await waitForModelState { model.sheetRequest?.id == "input" }
    let request = try #require(model.sheetRequest)

    await model.respond(to: request, with: .value("confirmed-code"))

    let response = try #require(await service.responses.first)
    #expect(response.0 == "input")
    #expect(response.1 == ["value": .string("confirmed-code")])
    #expect(model.sheetRequest == nil)

    await model.cancelLogin()
    await loginGate.release()
    await login.value
}

@MainActor
@Test func providerModelSuccessfulLoginReloadsProvidersAndUsage() async throws {
    let service = FakeProviderService(providers: [
        ProviderLoginProvider(id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
    ])
    let usage = FakeUsageService(snapshot: .empty)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: usage,
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    await model.load()
    let provider = try #require(model.providers.first)

    await model.login(provider)

    #expect(await service.loginIDs == ["cursor"])
    #expect(model.hasAuthenticatedProvider)
    #expect(await usage.loadCount == 2)
}

@MainActor
@Test func providerModelLoginRefreshesBothResourcesAfterAnOverlappingRefresh() async throws {
    let loginGate = LoginGate()
    let service = FakeProviderService(providers: [
        ProviderLoginProvider(id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
    ], loginGate: loginGate)
    let usage = FakeUsageService(snapshot: .empty)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: usage,
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    await model.load()
    let provider = try #require(model.providers.first)
    let providerGate = LoadGate()
    let usageGate = LoadGate()
    await service.enqueueProviderGate(providerGate)
    await usage.enqueueLoadGate(usageGate)

    let foregroundRefresh = Task { await model.refresh() }
    await providerGate.waitForStart()
    await usageGate.waitForStart()
    let login = Task { await model.login(provider) }
    await loginGate.waitForStart()
    await loginGate.release()
    await loginGate.waitForCompletion()

    await providerGate.release()
    await usageGate.release()
    await foregroundRefresh.value
    await login.value

    #expect(await service.providerLoadCount == 3)
    #expect(await usage.loadCount == 3)
    #expect(model.hasAuthenticatedProvider)
}

@MainActor
@Test func providerModelCancelDelegatesAndClearsTransientState() async {
    let loginGate = LoginGate()
    let service = FakeProviderService(providers: [
        ProviderLoginProvider(id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
    ], loginGate: loginGate)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })

    await model.load()
    guard let provider = model.providers.first else {
        Issue.record("Expected a provider")
        return
    }
    let login = Task { await model.login(provider) }
    await loginGate.waitForStart()
    await service.emit(ExtensionUIRequest(
        id: "input",
        method: "input",
        payload: .object(["title": .string("Paste the code")])) )
    await waitForModelState { model.sheetRequest != nil }

    await model.cancelLogin()

    #expect(await service.cancelCount == 1)
    #expect(model.activeLoginProviderID == nil)
    #expect(model.sheetRequest == nil)
    #expect(model.loginMessage == nil)

    await loginGate.release()
    await login.value
}

@MainActor
@Test func providerModelAppliesLoginNotificationsAndRemoteRequestCancellation() async {
    let loginGate = LoginGate()
    let service = FakeProviderService(providers: [
        ProviderLoginProvider(id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
    ], loginGate: loginGate)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })

    await model.load()
    guard let provider = model.providers.first else {
        Issue.record("Expected a provider")
        return
    }
    let login = Task { await model.login(provider) }
    await loginGate.waitForStart()
    await service.emit(ExtensionUIRequest(
        id: "input",
        method: "input",
        payload: .object(["title": .string("Paste the code")])) )
    await waitForModelState { model.sheetRequest?.id == "input" }
    await service.emit(ExtensionUIRequest(
        id: "notice",
        method: "notify",
        payload: .object(["message": .string("Waiting for approval.")])) )
    await waitForModelState { model.loginMessage == "Connecting to Cursor." }
    await service.emit(ExtensionUIRequest(
        id: "cancel",
        method: "cancel",
        payload: .object(["targetId": .string("input")])) )
    await waitForModelState { model.sheetRequest == nil }

    #expect(model.loginMessage == "Connecting to Cursor.")
    #expect(model.loginMessageProviderID == "cursor")

    await model.cancelLogin()
    await loginGate.release()
    await login.value
}

@MainActor
@Test func providerModelRejectsStaleExtensionRequestsAfterLoginCancellation() async throws {
    let firstLoginGate = LoginGate()
    let secondLoginGate = LoginGate()
    let service = FakeProviderService(providers: [
        ProviderLoginProvider(id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
    ], loginGate: firstLoginGate)
    await service.enqueueLoginGate(secondLoginGate)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    await model.load()
    let provider = try #require(model.providers.first)

    let firstLogin = Task { await model.login(provider) }
    await firstLoginGate.waitForStart()
    await model.cancelLogin()
    await firstLoginGate.release()
    await firstLogin.value

    let secondLogin = Task { await model.login(provider) }
    await secondLoginGate.waitForStart()
    await service.emit(
        ExtensionUIRequest(
            id: "stale-input",
            method: "input",
            payload: .object(["title": .string("Stale")])
        ),
        generation: 1)
    for _ in 0..<20 { await Task.yield() }
    #expect(model.sheetRequest == nil)

    await service.emit(
        ExtensionUIRequest(
            id: "current-input",
            method: "input",
            payload: .object(["title": .string("Current")])
        ),
        generation: 3)
    await waitForModelState { model.sheetRequest?.id == "current-input" }

    await model.cancelLogin()
    await secondLoginGate.release()
    await secondLogin.value
}

@MainActor
@Test func providerModelSanitizesNotificationsAndScopesThemToTheActiveProvider() async throws {
    let loginGate = LoginGate()
    let service = FakeProviderService(providers: [
        ProviderLoginProvider(id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
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
        id: "malicious-notice",
        method: "notify",
        payload: .object(["message": .string("token=secret /tmp/omp rpc_error")])) )
    await waitForModelState { model.loginMessageProviderID == "cursor" }

    #expect(model.loginMessage == "Connecting to Cursor.")
    #expect(model.loginMessage?.contains("secret") == false)
    #expect(model.loginMessage?.contains("/tmp") == false)
    #expect(model.loginMessage?.contains("rpc_error") == false)

    await model.cancelLogin()
    await loginGate.release()
    await login.value
}

@MainActor
@Test func providerModelPreservesUsageAfterARefreshFailure() async throws {
    let usage = FakeUsageService(snapshot: try usageSnapshotFixture())
    let model = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: [
            ProviderLoginProvider(id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
        ]),
        usageService: usage,
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) },
        formatTime: { _ in "4:00 PM" })
    await model.load()
    let presentation = model.usage
    await usage.setFailing(true)

    await model.refresh()

    #expect(model.usage == presentation)
    #expect(model.usageMessage == "Usage couldn’t be refreshed. Showing data from 4:00 PM.")
}

@MainActor
@Test func providerModelKeepsExactUsagePresentationWhenConcurrentDiscoverySucceeds() async throws {
    let snapshot = try usageSnapshotFixture()
    let service = FakeProviderService(providers: [
        ProviderLoginProvider(id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    let usage = FakeUsageService(snapshot: snapshot)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: usage,
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) },
        formatTime: { _ in "4:00 PM" })
    await model.load()
    let presentation = model.usage
    let providerGate = LoadGate()
    let usageGate = LoadGate()
    await service.setProviders([
        ProviderLoginProvider(id: "cursor", name: "Cursor Updated", isAvailable: true, isAuthenticated: true),
    ])
    await service.enqueueProviderGate(providerGate)
    await usage.enqueueLoadGate(usageGate)
    await usage.setFailing(true)

    let refresh = Task { await model.refresh() }
    await providerGate.waitForStart()
    await usageGate.waitForStart()
    await providerGate.release()
    await waitForModelState { model.providers.first?.name == "Cursor Updated" }
    await usageGate.release()
    await refresh.value

    #expect(model.usage == presentation)
    #expect(model.usageMessage == "Usage couldn’t be refreshed. Showing data from 4:00 PM.")
}

@MainActor
@Test func providerModelKeepsExactUsagePresentationWhenFailingUsageCompletesBeforeDiscovery() async throws {
    let snapshot = try usageSnapshotFixture()
    let service = FakeProviderService(providers: [
        ProviderLoginProvider(id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    let usage = FakeUsageService(snapshot: snapshot)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: usage,
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) },
        formatTime: { _ in "4:00 PM" })
    await model.load()
    let presentation = model.usage
    let providerGate = LoadGate()
    let usageGate = LoadGate()
    await service.setProviders([
        ProviderLoginProvider(id: "cursor", name: "Cursor Updated", isAvailable: true, isAuthenticated: true),
    ])
    await service.enqueueProviderGate(providerGate)
    await usage.enqueueLoadGate(usageGate)
    await usage.setFailing(true)

    let refresh = Task { await model.refresh() }
    await providerGate.waitForStart()
    await usageGate.waitForStart()
    await usageGate.release()
    await waitForModelState { model.usageMessage == "Usage couldn’t be refreshed. Showing data from 4:00 PM." }
    #expect(model.usage == presentation)
    await providerGate.release()
    await refresh.value

    #expect(model.providers.first?.name == "Cursor Updated")
    #expect(model.usage == presentation)
    #expect(model.usageMessage == "Usage couldn’t be refreshed. Showing data from 4:00 PM.")
}

@MainActor
@Test func providerModelRefreshesOnlyAtTheFiveMinuteStalenessBoundary() async {
    let clock = MutableClock(date: Date(timeIntervalSince1970: 0))
    let usage = FakeUsageService(snapshot: .empty)
    let model = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: []),
        usageService: usage,
        openURL: { _ in },
        now: { clock.now() })
    await model.load()
    clock.set(Date(timeIntervalSince1970: 299))

    await model.refreshIfStale()

    #expect(await usage.loadCount == 1)
    clock.set(Date(timeIntervalSince1970: 300))
    await model.refreshIfStale()
    #expect(await usage.loadCount == 2)
}

final class MutableClock: Sendable {
    private let date: Mutex<Date>

    init(date: Date) {
        self.date = Mutex(date)
    }

    func now() -> Date {
        date.withLock { $0 }
    }

    func set(_ date: Date) {
        self.date.withLock { $0 = date }
    }
}

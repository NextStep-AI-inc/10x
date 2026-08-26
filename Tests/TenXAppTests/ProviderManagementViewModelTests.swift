import Darwin
import Foundation
import OmpKit
import Synchronization
import Testing
@testable import TenXApp

@Suite @MainActor struct ProviderManagementViewModelTests {

@Test func accountMetadataAppearsBeforeAccountUsageCompletes() async throws {
    let providerID = "openai-codex"
    let usageGate = LoadGate()
    let service = FakeProviderService(
        providers: [ProviderLoginProvider(
            id: providerID,
            name: "ChatGPT",
            isAvailable: true,
            isAuthenticated: true)],
        capabilities: [providerID: .accountRouting],
        accounts: [providerID: [
            providerAccountFixture(providerID: providerID, ref: "acct_B", label: "Work", order: 2),
            providerAccountFixture(providerID: providerID, ref: "acct_A", label: "Personal", order: 1),
        ]])
    await service.enqueueAccountUsageGate(usageGate)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })

    let load = Task { await model.load() }
    await usageGate.waitForStart()

    let provider = try #require(model.dockProviders.first)
    #expect(provider.accounts.map(\.accountRef) == ["acct_A", "acct_B"])
    #expect(provider.accounts.allSatisfy { $0.usageState == .loading })
    #expect(provider.showsAccountSelectors)
    #expect(provider.showsAccountSwitch)
    #expect(provider.showsAccountRemoval)

    await usageGate.release()
    await load.value
}

@Test func accountUsageFailurePreservesAccountsWithoutGuessingCLIIdentity() async throws {
    let providerID = "cursor"
    let service = FakeProviderService(
        providers: [ProviderLoginProvider(
            id: providerID,
            name: "Cursor",
            isAvailable: true,
            isAuthenticated: true)],
        capabilities: [providerID: .accountRouting],
        accounts: [providerID: [
            providerAccountFixture(
                providerID: providerID,
                ref: "opaque-real-ref",
                label: "same@example.com",
                order: 0),
        ]],
        accountUsageError: .accountUsageFailed)
    let cliSnapshot = try JSONDecoder().decode(OmpUsageSnapshot.self, from: Data(#"""
    {
      "generatedAt":1,
      "reports":[{
        "provider":"cursor",
        "fetchedAt":1,
        "limits":[{
          "id":"cli-only",
          "label":"CLI identity must not join",
          "scope":{"provider":"cursor"},
          "amount":{"remainingFraction":0.99,"unit":"percent"}
        }],
        "metadata":{"email":"same@example.com"}
      }],
      "accountsWithoutUsage":[],
      "disabledCredentials":[]
    }
    """#.utf8))
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: cliSnapshot),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })

    await model.load()

    let provider = try #require(model.dockProviders.first)
    let account = try #require(provider.accounts.first)
    #expect(account.accountRef == "opaque-real-ref")
    #expect(account.limits.isEmpty)
    #expect(account.usageState == .unavailable)
    #expect(account.usageStatusText == "Usage unavailable")
    #expect(provider.capability == .accountRouting)
    #expect(model.usageMessage == "Usage couldn’t be loaded.")
}

@Test func providerOnlyCapabilityUsesCLIUsageAndHidesAccountControls() async throws {
    let providerID = "cursor"
    let snapshot = try usageSnapshotFixture()
    let service = FakeProviderService(providers: [ProviderLoginProvider(
        id: providerID,
        name: "Cursor",
        isAvailable: true,
        isAuthenticated: true)])
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: snapshot),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })

    await model.load()

    let provider = try #require(model.dockProviders.first)
    #expect(provider.capability == .providerOnly)
    #expect(provider.accounts.count == 1)
    #expect(provider.ringLimits.map(\.label) == ["Cursor Models"])
    #expect(!provider.showsAccountSelectors)
    #expect(!provider.showsAccountSwitch)
    #expect(!provider.showsAccountRemoval)
    #expect(await service.accountLoadIDs.isEmpty)
    #expect(await service.accountUsageLoadIDs.isEmpty)
}

@Test func accountCapabilityFailureDoesNotEnterProviderOnlyCompatibilityMode() async throws {
    let providerID = "cursor"
    let service = FakeProviderService(
        providers: [ProviderLoginProvider(
            id: providerID,
            name: "Cursor",
            isAvailable: true,
            isAuthenticated: true)],
        accountCapabilityError: .accountCapabilityFailed)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: try usageSnapshotFixture()),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })

    await model.load()

    #expect(model.dockProviders.isEmpty)
    #expect(model.providerMessage == "Provider accounts couldn’t be loaded.")
}

@Test func successfulLoginAppendsAnAccountAndRefreshesAccountMetadataAndUsage() async throws {
    let providerID = "openai-codex"
    let first = providerAccountFixture(
        providerID: providerID,
        ref: "acct_A",
        label: "same@example.com",
        order: 0,
        detailLabel: "Personal")
    let second = providerAccountFixture(
        providerID: providerID,
        ref: "acct_B",
        label: "same@example.com",
        order: 1,
        detailLabel: "Work")
    let service = AccountManagementProviderService(
        provider: ProviderLoginProvider(
            id: providerID,
            name: "ChatGPT",
            isAvailable: true,
            isAuthenticated: true),
        accounts: [first],
        accountAddedOnLogin: second)
    let usage = FakeUsageService(snapshot: .empty)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: usage,
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    let (coordinator, defaults, suiteName) = try makeManagementCoordinator()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    model.attachAccountCoordinator(coordinator)
    await model.load()
    let provider = try #require(model.providers.first)
    await coordinator.useAccount(
        "stale-primary",
        providerID: providerID,
        scope: .allNewSessions,
        openSessionID: nil)

    await model.login(provider)

    #expect(model.connectionAccounts(providerID: providerID).map(\.accountRef) == ["acct_A", "acct_B"])
    #expect(model.connectionAccounts(providerID: providerID).map(\.displayLabel) == [
        "same@example.com", "same@example.com",
    ])
    #expect(await service.loginIDs == [providerID])
    #expect(await service.accountLoadCount == 2)
    #expect(await service.accountUsageLoadCount == 2)
    #expect(await usage.loadCount == 2)
    #expect(coordinator.primaryAccountRef(providerID: providerID) == "acct_A")
}

@Test func staleExternalRemovalRefreshesRowsAndReportsAccountUnavailable() async throws {
    let providerID = "openai-codex"
    let removed = providerAccountFixture(
        providerID: providerID,
        ref: "acct_A",
        label: "Personal",
        order: 0)
    let remaining = providerAccountFixture(
        providerID: providerID,
        ref: "acct_B",
        label: "Work",
        order: 1)
    let service = AccountManagementProviderService(
        provider: ProviderLoginProvider(
            id: providerID,
            name: "ChatGPT",
            isAvailable: true,
            isAuthenticated: true),
        accounts: [removed, remaining],
        removalReportsStale: true)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    await model.load()
    let (coordinator, defaults, suiteName) = try makeManagementCoordinator()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    model.attachAccountCoordinator(coordinator)
    await coordinator.useAccount(
        "acct_A",
        providerID: providerID,
        scope: .allNewSessions,
        openSessionID: nil)

    await model.removeAccount(removed, coordinator: coordinator)

    #expect(await service.removalRequests == [
        AccountRemovalRequest(providerID: providerID, accountRef: "acct_A"),
    ])
    #expect(model.connectionAccounts(providerID: providerID).map(\.accountRef) == ["acct_B"])
    #expect(model.removalMessage == "Account is no longer available.")
    #expect(model.pendingRemovalAccounts.isEmpty)
    #expect(coordinator.primaryAccountRef(providerID: providerID) == "acct_B")
}

@Test func failedRemovalRefreshesMetadataAndUsageThenRepairsFromAuthoritativeAccounts() async throws {
    let providerID = "openai-codex"
    let removed = providerAccountFixture(
        providerID: providerID,
        ref: "acct_A",
        label: "Personal",
        order: 0)
    let remaining = providerAccountFixture(
        providerID: providerID,
        ref: "acct_B",
        label: "Work",
        order: 1)
    let service = AccountManagementProviderService(
        provider: ProviderLoginProvider(
            id: providerID,
            name: "ChatGPT",
            isAvailable: true,
            isAuthenticated: true),
        accounts: [removed, remaining],
        removalFailureAfterMutation: true)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    let (coordinator, defaults, suiteName) = try makeManagementCoordinator()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    model.attachAccountCoordinator(coordinator)
    await model.load()
    await coordinator.useAccount(
        "acct_A",
        providerID: providerID,
        scope: .allNewSessions,
        openSessionID: nil)

    await model.removeAccount(removed, coordinator: coordinator)

    #expect(model.connectionAccounts(providerID: providerID).map(\.accountRef) == ["acct_B"])
    #expect(model.removalMessage == "Account couldn’t be removed.")
    #expect(await service.accountLoadCount == 2)
    #expect(await service.accountUsageLoadCount == 2)
    #expect(coordinator.primaryAccountRef(providerID: providerID) == "acct_B")
}

@Test func removalWithoutAnEligibleReplacementRefreshesAndShowsATruthfulError() async throws {
    let providerID = "openai-codex"
    let target = providerAccountFixture(
        providerID: providerID,
        ref: "acct_A",
        label: "Personal",
        order: 0)
    let unavailable = providerAccountFixture(
        providerID: providerID,
        ref: "acct_B",
        label: "Unavailable",
        order: 1,
        availability: .unavailable)
    let service = AccountManagementProviderService(
        provider: ProviderLoginProvider(
            id: providerID,
            name: "ChatGPT",
            isAvailable: true,
            isAuthenticated: true),
        accounts: [target, unavailable])
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    let (coordinator, defaults, suiteName) = try makeManagementCoordinator()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    model.attachAccountCoordinator(coordinator)
    await model.load()

    await model.removeAccount(target, coordinator: coordinator)

    #expect(await service.removalRequests.isEmpty)
    #expect(await service.accountLoadCount == 2)
    #expect(await service.accountUsageLoadCount == 2)
    #expect(model.removalMessage == "Account couldn’t be removed because no replacement account is available.")
    #expect(coordinator.primaryAccountRef(providerID: providerID) == "acct_A")
}

@Test func connectionFocusSelectsConnectionsAndRetainsTheProviderTarget() {
    let model = providerTestModel(providers: [])
    model.selectedSection = .usage

    model.focusConnections(providerID: "anthropic")

    #expect(model.selectedSection == .connections)
    #expect(model.focusedConnectionsProviderID == "anthropic")
}

@Test func accountConnectionCopyUsesSafeDetailPrimaryAndSessionGrammar() {
    let account = providerAccountFixture(
        providerID: "openai-codex",
        ref: "private-ref",
        label: "same@example.com",
        order: 0,
        detailLabel: "Work")

    let unused = ProviderAccountConnectionRowPresentation.make(
        account: account,
        isPrimary: false,
        sessionCount: 0,
        isPendingRemoval: false)
    let singular = ProviderAccountConnectionRowPresentation.make(
        account: account,
        isPrimary: true,
        sessionCount: 1,
        isPendingRemoval: false)
    let plural = ProviderAccountConnectionRowPresentation.make(
        account: account,
        isPrimary: true,
        sessionCount: 3,
        isPendingRemoval: false)
    let unavailableReplacement = ProviderAccountConnectionRowPresentation.make(
        account: account,
        isPrimary: true,
        sessionCount: 0,
        isPendingRemoval: false,
        canRemove: false)

    #expect(unused.label == "same@example.com")
    #expect(unused.detail == "Work")
    #expect(unused.status == nil)
    #expect(singular.status == "Primary · In use by 1 session")
    #expect(plural.status == "Primary · In use by 3 sessions")
    #expect(!plural.accessibilityLabel.contains("private-ref"))
    #expect(unavailableReplacement.status == "Primary · No available replacement")
    #expect(unavailableReplacement.actionLabel == "Remove")
    #expect(unavailableReplacement.isActionDisabled)
}

@Test func removalConfirmationCopyNamesOnlyManagedSessionsAndUsesExactLastAccountWarning() {
    let normal = ProviderAccountRemovalConfirmationPresentation(
        providerName: "ChatGPT",
        accountLabel: "work@example.com",
        accountDetailLabel: "Work",
        hasDuplicateAccountLabel: true,
        affectedSessionCount: 2,
        isLastAccount: false)
    let last = ProviderAccountRemovalConfirmationPresentation(
        providerName: "ChatGPT",
        accountLabel: "work@example.com",
        accountDetailLabel: "Work",
        hasDuplicateAccountLabel: true,
        affectedSessionCount: 2,
        isLastAccount: true)

    #expect(normal.title == "Remove work@example.com (Work)?")
    #expect(normal.message == "2 10x-managed sessions use this account. They move to another account before removal. Generating turns finish first.")
    #expect(!normal.message.localizedCaseInsensitiveContains("other apps"))
    #expect(!normal.message.localizedCaseInsensitiveContains("terminal"))
    #expect(last.title == "Remove the last account?")
    #expect(last.message == "This disconnects ChatGPT. Sessions using this provider cannot continue through it.")
}

@Test func removalModalBehaviorHidesUnderlyingContentAndRestoresKeyboardOriginFocus() {
    let behavior = ProviderAccountRemovalModalBehavior(isPresented: true)

    #expect(behavior.isUnderlyingContentDisabled)
    #expect(behavior.isUnderlyingContentAccessibilityHidden)
    #expect(behavior.restorationTarget(
        dismissalSource: .keyboard,
        accountID: "openai-codex:acct_A",
        providerID: "openai-codex",
        accountStillConnected: true
    ) == .removeAccount("openai-codex:acct_A"))
    #expect(behavior.restorationTarget(
        dismissalSource: .confirmAction,
        accountID: "openai-codex:acct_A",
        providerID: "openai-codex",
        accountStillConnected: false
    ) == .addAccount("openai-codex"))

    let hidden = ProviderAccountRemovalModalBehavior(isPresented: false)
    #expect(!hidden.isUnderlyingContentDisabled)
    #expect(!hidden.isUnderlyingContentAccessibilityHidden)
}

@Test func lateCLIFailureDoesNotOverwriteNewerAccountRPCUsage() async throws {
    let providerID = "cursor"
    let account = providerAccountFixture(
        providerID: providerID,
        ref: "acct_A",
        label: "Account",
        order: 0)
    let service = FakeProviderService(
        providers: [ProviderLoginProvider(
            id: providerID,
            name: "Cursor",
            isAvailable: true,
            isAuthenticated: true)],
        capabilities: [providerID: .accountRouting],
        accounts: [providerID: [account]],
        accountUsage: [providerID: [providerAccountUsageFixture(
            providerID: providerID,
            ref: "acct_A",
            windows: [providerAccountUsageWindowFixture(
                id: "monthly",
                label: "Monthly",
                remainingFraction: 0.25)])]])
    let cliUsage = FakeUsageService(snapshot: try usageSnapshotFixture())
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: cliUsage,
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    await model.load()
    #expect(model.dockProviders.first?.accounts.first?.limits.first?.percentage == 25)
    let lateCLIGate = LoadGate()
    await cliUsage.enqueueLoadGate(lateCLIGate)
    await cliUsage.setFailing(true)
    await service.setAccountUsage([providerID: [providerAccountUsageFixture(
        providerID: providerID,
        ref: "acct_A",
        windows: [providerAccountUsageWindowFixture(
            id: "monthly",
            label: "Monthly",
            remainingFraction: 0.8)])]])

    let refresh = Task { await model.refresh() }
    await lateCLIGate.waitForStart()
    await waitForModelState {
        model.dockProviders.first?.accounts.first?.limits.first?.percentage == 80
    }
    await lateCLIGate.release()
    await refresh.value

    let provider = try #require(model.dockProviders.first)
    #expect(provider.capability == .accountRouting)
    #expect(provider.accounts.first?.accountRef == "acct_A")
    #expect(provider.accounts.first?.limits.first?.percentage == 80)
}

@Test func disconnectedAndMissingProvidersDiscardAccountPresentationCaches() async throws {
    let providerID = "cursor"
    let authenticated = ProviderLoginProvider(
        id: providerID,
        name: "Cursor",
        isAvailable: true,
        isAuthenticated: true)
    let service = FakeProviderService(
        providers: [authenticated],
        capabilities: [providerID: .accountRouting],
        accounts: [providerID: [providerAccountFixture(
            providerID: providerID,
            ref: "acct_A",
            label: "Account",
            order: 0)]],
        accountUsage: [providerID: [providerAccountUsageFixture(
            providerID: providerID,
            ref: "acct_A",
            windows: [providerAccountUsageWindowFixture(id: "monthly", label: "Monthly")])]])
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: try usageSnapshotFixture()),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    await model.load()
    #expect(model.dockProviders.first?.capability == .accountRouting)

    await service.setProviders([ProviderLoginProvider(
        id: providerID,
        name: "Cursor",
        isAvailable: true,
        isAuthenticated: false)])
    await model.refresh()

    var fallback = try #require(model.dockProviders.first)
    #expect(fallback.capability == .providerOnly)
    #expect(fallback.accounts.allSatisfy { $0.accountRef == nil })
    #expect(!fallback.showsAccountSelectors)
    #expect(!fallback.showsAccountSwitch)
    #expect(!fallback.showsAccountRemoval)

    await service.setProviders([])
    await model.refresh()

    fallback = try #require(model.dockProviders.first)
    #expect(fallback.capability == .providerOnly)
    #expect(fallback.accounts.allSatisfy { $0.accountRef == nil })
    #expect(!fallback.showsAccountSwitch)
    #expect(!fallback.showsAccountRemoval)
}

@MainActor
@Test func providerShutdownCancelsAndAwaitsAnInflightUsageCommand() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let pidFile = fixture.root.appending(path: "usage.pid")
    let executable = try fixture.executable(
        name: "blocked-usage",
        body: "printf '%s' $$ > '\(pidFile.path)'; trap '' TERM; while :; do sleep 1; done")
    let model = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: []),
        usageService: OmpUsageService(
            runner: OmpUsageProcessRunner(executableURL: executable)),
        openURL: { _ in })
    let load = Task { await model.loadUsage() }
    let pids = try await fixture.waitForPIDs(in: pidFile, count: 1)
    let pid = try #require(pids.first)

    await model.shutdown()
    await load.value

    #expect(kill(pid, 0) == -1)
    #expect(errno == ESRCH)
}

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

}

private struct AccountRemovalRequest: Equatable, Sendable {
    let providerID: String
    let accountRef: String
}

private actor AccountManagementProviderService: ProviderManaging {
    nonisolated let events: AsyncStream<ProviderLoginEvent>

    private let eventContinuation: AsyncStream<ProviderLoginEvent>.Continuation
    private var provider: ProviderLoginProvider
    private var accounts: [ProviderAccountSummary]
    private let accountAddedOnLogin: ProviderAccountSummary?
    private let removalReportsStale: Bool
    private let removalFailureAfterMutation: Bool
    private(set) var loginIDs: [String] = []
    private(set) var removalRequests: [AccountRemovalRequest] = []
    private(set) var accountLoadCount = 0
    private(set) var accountUsageLoadCount = 0

    init(
        provider: ProviderLoginProvider,
        accounts: [ProviderAccountSummary],
        accountAddedOnLogin: ProviderAccountSummary? = nil,
        removalReportsStale: Bool = false,
        removalFailureAfterMutation: Bool = false
    ) {
        self.provider = provider
        self.accounts = accounts
        self.accountAddedOnLogin = accountAddedOnLogin
        self.removalReportsStale = removalReportsStale
        self.removalFailureAfterMutation = removalFailureAfterMutation
        (events, eventContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    func providers() async throws -> [ProviderLoginProvider] { [provider] }

    func accountCapability(providerID: String) async throws -> ProviderAccountCapability {
        .accountRouting
    }

    func accounts(providerID: String) async throws -> [ProviderAccountSummary] {
        accountLoadCount += 1
        return accounts
    }

    func accountUsage(providerID: String) async throws -> [ProviderAccountUsage] {
        accountUsageLoadCount += 1
        return []
    }

    func removeAccount(
        providerID: String,
        accountRef: String
    ) async throws -> ProviderAccountRemovalResult {
        removalRequests.append(AccountRemovalRequest(providerID: providerID, accountRef: accountRef))
        accounts.removeAll { $0.providerID == providerID && $0.accountRef == accountRef }
        if accounts.isEmpty {
            provider = ProviderLoginProvider(
                id: provider.id,
                name: provider.name,
                isAvailable: provider.isAvailable,
                isAuthenticated: false)
        }
        if removalFailureAfterMutation {
            throw AccountManagementProviderError.removalFailed
        }
        return ProviderAccountRemovalResult(
            removed: !removalReportsStale,
            accounts: accounts)
    }

    func login(providerID: String, generation: Int) async throws {
        loginIDs.append(providerID)
        if let accountAddedOnLogin, !accounts.contains(where: { $0.accountRef == accountAddedOnLogin.accountRef }) {
            accounts.append(accountAddedOnLogin)
        }
    }

    func respond(requestID: String, body: [String: JSONValue]) async throws {}

    func cancelLogin() async {}

    func shutdown() async {
        eventContinuation.finish()
    }
}

private enum AccountManagementProviderError: Error {
    case removalFailed
}

@MainActor
private func makeManagementCoordinator() throws -> (
    coordinator: ProviderAccountCoordinator,
    defaults: UserDefaults,
    suiteName: String
) {
    let suiteName = "TenXAppTests.ProviderManagementCoordinator.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return (
        ProviderAccountCoordinator(primaryStore: ProviderPrimaryPreferenceStore(defaults: defaults)),
        defaults,
        suiteName)
}

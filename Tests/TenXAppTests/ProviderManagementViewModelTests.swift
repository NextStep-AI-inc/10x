import Darwin
import Foundation
import OmpKit
import Synchronization
import Testing
@testable import TenXApp

@Suite @MainActor struct ProviderManagementViewModelTests {

/// Task 10b's read-path fix: `refreshAccountUsage` must derive accounts from
/// `ProviderAccountUsageBackend.accounts(from:providerID:)` over the usage
/// snapshot the view model already holds, not from `providerService.accounts`
/// — Task 10 deleted the RPC that backed it, so that call now hits the
/// `ProviderAccountManaging` protocol default and silently returns `[]`.
/// `FakeProviderService` deliberately has no way to hand back accounts of its
/// own any more (see `ProviderTestFixtures.swift`), so this fails today for
/// the right reason: real accounts, zero returned.
@Test func routedTierAccountsDeriveFromTheUsageSnapshotNotADeadRPC() async throws {
    let providerID = "openai-codex"
    let personal = AccountSnapshotEntry(accountID: "a1", email: "personal@example.com", orgName: "Personal")
    let work = AccountSnapshotEntry(accountID: "a2", email: "work@example.com", orgName: "Work")
    let service = FakeProviderService(providers: [ProviderLoginProvider(
        id: providerID,
        name: "ChatGPT",
        isAvailable: true,
        isAuthenticated: true)])
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: multiAccountUsageSnapshotFixture(
            providerID: providerID,
            accounts: [personal, work])),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })

    await model.load()

    #expect(model.connectionAccounts(providerID: providerID).map(\.accountRef) == [
        personal.accountRef(providerID: providerID),
        work.accountRef(providerID: providerID),
    ])
    #expect(model.connectionAccounts(providerID: providerID).map(\.displayLabel) == [
        "personal@example.com", "work@example.com",
    ])
    #expect(model.connectionAccounts(providerID: providerID).map(\.detailLabel) == ["Personal", "Work"])
    let provider = try #require(model.dockProviders.first)
    #expect(provider.showsAccountSelectors)
    #expect(provider.showsAccountSwitch)
    #expect(provider.showsAccountRemoval)
}

@Test func providerOnlyCapabilityUsesCLIUsageAndHidesAccountControls() async throws {
    let providerID = "cursor"
    // No per-account metadata: tier detection must see this as `.providerOnly`
    // even though usage (the ring limit below) is present, same as when a
    // stock CLI's usage output carries no stable per-account identity.
    let snapshot = try JSONDecoder().decode(OmpUsageSnapshot.self, from: Data(#"""
    {
      "generatedAt":1,
      "reports":[{
        "provider":"cursor",
        "fetchedAt":1,
        "limits":[
          {"id":"cursor:models","label":"Cursor Models","scope":{"provider":"cursor","windowId":"monthly"},"window":{"id":"monthly","label":"Monthly","resetsAt":1788061624000},"amount":{"usedFraction":0.499,"unit":"percent"},"status":"ok"},
          {"id":"cursor:requests","label":"Requests","scope":{"provider":"cursor"},"amount":{"used":4,"unit":"requests"}}
        ],
        "metadata":{}
      }],
      "accountsWithoutUsage":[],
      "disabledCredentials":[]
    }
    """#.utf8))
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
    #expect(model.connectionAccounts(providerID: providerID).isEmpty)
}

@Test func accountCapabilityFailureDoesNotEnterProviderOnlyCompatibilityMode() async throws {
    let providerID = "cursor"
    let service = FakeProviderService(
        providers: [ProviderLoginProvider(
            id: providerID,
            name: "Cursor",
            isAvailable: true,
            isAuthenticated: true)])
    // Tier detection reads the usage snapshot instead of probing an RPC, so a
    // failure now has to come from the usage load itself: no snapshot has
    // ever loaded successfully, so detection can't run at all.
    let usage = FakeUsageService(snapshot: .empty)
    await usage.setFailing(true)
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: usage,
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })

    await model.load()

    #expect(model.dockProviders.isEmpty)
    #expect(model.providerMessage == "Provider accounts couldn’t be loaded.")
}

@Test func accountTierReflectsDetectionFromTheUsageSnapshot() async throws {
    let providerID = "cursor"
    let service = FakeProviderService(providers: [ProviderLoginProvider(
        id: providerID,
        name: "Cursor",
        isAvailable: true,
        isAuthenticated: true)])
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: try accountRoutingUsageSnapshotFixture(providerID: providerID)),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })

    await model.load()

    // No `installTierHelloProvider` call here: `resolveExtensionHello()`
    // then reports no hello available, the same as a live app before any
    // session has attached an extension channel
    // (`AppModel.configureProviderModel`'s doc comment walks through why).
    // A snapshot with per-account identity but no hello detects as
    // `.stockOMP`, never `.extensionBacked` — see
    // `compatibleExtensionHelloUnlocksTheExtensionBackedTier` immediately
    // below for the case where a hello provider *is* installed.
    #expect(model.accountTier == .stockOMP)
}

/// Task 10b fix round 1, Finding 1: proves `.extensionBacked` is actually
/// reachable through the real wiring (`installTierHelloProvider` →
/// `resolveExtensionHello` → `ProviderAccountTier.detect`), not just that
/// `detect` itself accepts a compatible hello in isolation
/// (`ProviderAccountTierTests.compatibleHelloSelectsTheExtensionTier`
/// already proves that). Without a test at this level, `AppModel` silently
/// forgetting to call `installTierHelloProvider` — or `refreshAccountUsage`
/// silently forgetting to call `resolveExtensionHello` — would regress this
/// straight back to nil-forever with nothing to notice.
@Test func compatibleExtensionHelloUnlocksTheExtensionBackedTier() async throws {
    let providerID = "cursor"
    let service = FakeProviderService(providers: [ProviderLoginProvider(
        id: providerID,
        name: "Cursor",
        isAvailable: true,
        isAuthenticated: true)])
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: try accountRoutingUsageSnapshotFixture(providerID: providerID)),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    model.installTierHelloProvider {
        ProviderExtensionHello(contractVersion: ProviderAccountTier.contractVersion)
    }

    await model.load()

    #expect(model.accountTier == .extensionBacked)
}

/// The fail-closed counterpart to the test above, at the same wiring level:
/// an installed hello provider that answers with a version this build
/// doesn't understand must still degrade to `.stockOMP`, not hang and not
/// silently accept it.
@Test func incompatibleExtensionHelloDegradesToStockOMP() async throws {
    let providerID = "cursor"
    let service = FakeProviderService(providers: [ProviderLoginProvider(
        id: providerID,
        name: "Cursor",
        isAvailable: true,
        isAuthenticated: true)])
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: try accountRoutingUsageSnapshotFixture(providerID: providerID)),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    model.installTierHelloProvider {
        ProviderExtensionHello(contractVersion: ProviderAccountTier.contractVersion + 1)
    }

    await model.load()

    #expect(model.accountTier == .stockOMP)
}

/// `resolveExtensionHello()`'s whole reason to exist: `refreshAccountUsage`
/// runs on every `refresh()` — every login, every removal, the 5-minute
/// stale timer — so a fresh probe on every call would mean an ordinary
/// refresh potentially paying `ProviderAccountExtensionBackend.helloTimeout`
/// each time a channel is attached but slow. Proves the provider is invoked
/// once, not once per refresh, by counting calls directly rather than
/// inferring it from timing.
@Test func extensionHelloIsFetchedOnceAndCachedAcrossRefreshes() async throws {
    let providerID = "cursor"
    let service = FakeProviderService(providers: [ProviderLoginProvider(
        id: providerID,
        name: "Cursor",
        isAvailable: true,
        isAuthenticated: true)])
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: try accountRoutingUsageSnapshotFixture(providerID: providerID)),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    var helloCallCount = 0
    model.installTierHelloProvider {
        helloCallCount += 1
        return ProviderExtensionHello(contractVersion: ProviderAccountTier.contractVersion)
    }

    await model.load()
    await model.refresh()
    await model.refresh()

    #expect(helloCallCount == 1)
    #expect(model.accountTier == .extensionBacked)
}

/// Task-10b final fix, Finding 2 direction A: nothing previously re-ran
/// tier detection when a channel became available after the fact — the
/// label could sit at `.stockOMP` until the next periodic refresh
/// (`staleRefreshInterval`, 5 minutes) or explicit user action. `AppModel`
/// wires `ProviderAccountChannelRegistry.onAvailabilityChange` to
/// `redetectAccountTier()` for exactly this — this test proves the view
/// model's half of that wiring: installing a hello provider *after* the
/// first load, then calling `redetectAccountTier()` directly (standing in
/// for the registry's callback), picks it up without a full `refresh()`.
@Test func redetectAccountTierPicksUpAHelloProviderThatBecameAvailableAfterLoad() async throws {
    let providerID = "cursor"
    let service = FakeProviderService(providers: [ProviderLoginProvider(
        id: providerID,
        name: "Cursor",
        isAvailable: true,
        isAuthenticated: true)])
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: try accountRoutingUsageSnapshotFixture(providerID: providerID)),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })

    await model.load()
    #expect(model.accountTier == .stockOMP)

    model.installTierHelloProvider {
        ProviderExtensionHello(contractVersion: ProviderAccountTier.contractVersion)
    }
    await model.redetectAccountTier().value

    #expect(model.accountTier == .extensionBacked)
}

/// Task-10b final fix, Finding 2 direction B: a *successful* hello is
/// cached forever by `resolveExtensionHello` (see
/// `extensionHelloIsFetchedOnceAndCachedAcrossRefreshes` immediately
/// above), so once a channel goes away nothing previously re-asked —
/// routing would silently fall back to pin-and-restart while the label
/// kept claiming `.extensionBacked`. `redetectAccountTier()` is what
/// `ProviderAccountTieredRoutingBackend.route`'s own `.unavailable` catch
/// now calls (through the registry) the moment it discovers that; this
/// proves invalidating the cache and re-probing actually flips the label
/// back, not just that a fresh provider would have given the right answer
/// on a first probe.
@Test func redetectAccountTierInvalidatesAPreviouslyCachedSuccessfulHello() async throws {
    let providerID = "cursor"
    let service = FakeProviderService(providers: [ProviderLoginProvider(
        id: providerID,
        name: "Cursor",
        isAvailable: true,
        isAuthenticated: true)])
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: FakeUsageService(snapshot: try accountRoutingUsageSnapshotFixture(providerID: providerID)),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    var channelIsAlive = true
    model.installTierHelloProvider {
        channelIsAlive ? ProviderExtensionHello(contractVersion: ProviderAccountTier.contractVersion) : nil
    }

    await model.load()
    #expect(model.accountTier == .extensionBacked)

    // The channel died — matches what `ProviderAccountChannelRegistry
    // .anyChannel()` returns once the dead entry's session detaches, or a
    // still-attached channel that is now internally dropped.
    channelIsAlive = false
    await model.redetectAccountTier().value

    #expect(model.accountTier == .stockOMP)
}

@Test func successfulLoginAppendsAnAccountAndRefreshesAccountMetadataAndUsage() async throws {
    let providerID = "openai-codex"
    let personal = AccountSnapshotEntry(accountID: "a1", email: "same@example.com", orgName: "Personal")
    let work = AccountSnapshotEntry(accountID: "a2", email: "same@example.com", orgName: "Work")
    let service = FakeProviderService(providers: [ProviderLoginProvider(
        id: providerID,
        name: "ChatGPT",
        isAvailable: true,
        isAuthenticated: true)])
    // Account reads derive from the usage snapshot, not a per-account login
    // response — so "login adds an account" now means the NEXT usage load
    // (triggered by `login()`'s own `refresh(forceFresh: true)`) sees a
    // grown snapshot. `setSnapshot` swaps what `loadUsage()` returns from
    // here on, modeling that later load.
    let usage = FakeUsageService(snapshot: multiAccountUsageSnapshotFixture(
        providerID: providerID, accounts: [personal]))
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
    await usage.setSnapshot(multiAccountUsageSnapshotFixture(
        providerID: providerID, accounts: [personal, work]))

    await model.login(provider)
    // `login()`'s own `refresh(forceFresh: true)` races its two concurrent
    // halves (`refreshProviders`/`refreshUsage` via `async let`) —
    // `refreshAccountUsage` deliberately does not wait on the sibling usage
    // refresh once bootstrapped (see its doc comment and
    // `refreshAccountUsageDoesNotBlockOnASlowSubsequentUsagePoll`), so
    // whether that first pass derives accounts from the old or the
    // just-swapped snapshot is a coin flip. By the time `login()` returns,
    // `lastUsageSnapshot` is deterministically the new one either way
    // (`refresh` awaits both halves) — one more refresh settles the race.
    await model.refresh()

    #expect(model.connectionAccounts(providerID: providerID).map(\.accountRef) == [
        personal.accountRef(providerID: providerID),
        work.accountRef(providerID: providerID),
    ])
    #expect(model.connectionAccounts(providerID: providerID).map(\.displayLabel) == [
        "same@example.com", "same@example.com",
    ])
    #expect(await service.loginIDs == [providerID])
    #expect(coordinator.primaryAccountRef(providerID: providerID) == personal.accountRef(providerID: providerID))
}

@Test func staleExternalRemovalRefreshesRowsAndReportsAccountUnavailable() async throws {
    let providerID = "openai-codex"
    let removedEntry = AccountSnapshotEntry(accountID: "a1", email: "personal@example.com")
    let remainingEntry = AccountSnapshotEntry(accountID: "a2", email: "work@example.com")
    let removedRef = removedEntry.accountRef(providerID: providerID)
    let remainingRef = remainingEntry.accountRef(providerID: providerID)
    let usage = FakeUsageService(snapshot: multiAccountUsageSnapshotFixture(
        providerID: providerID, accounts: [removedEntry, remainingEntry]))
    let model = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: [ProviderLoginProvider(
            id: providerID, name: "ChatGPT", isAvailable: true, isAuthenticated: true)]),
        usageService: usage,
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    await model.load()
    let (coordinator, defaults, suiteName) = try makeManagementCoordinator()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    model.attachAccountCoordinator(coordinator)
    await coordinator.useAccount(
        removedRef,
        providerID: providerID,
        scope: .allNewSessions,
        openSessionID: nil)
    var removalRequests: [AccountRemovalRequest] = []
    // The extension reports the account already gone (removed by some other
    // path) — `removed: false` alongside the now-authoritative remaining
    // list. Mutating the snapshot models that same reality reaching the next
    // `omp usage --json` poll the view model's own `refresh(forceFresh:)`
    // triggers right after.
    model.installAccountRemovalTransport { requestedProviderID, requestedAccountRef in
        removalRequests.append(AccountRemovalRequest(
            providerID: requestedProviderID, accountRef: requestedAccountRef))
        await usage.setSnapshot(multiAccountUsageSnapshotFixture(
            providerID: providerID, accounts: [remainingEntry]))
        return ProviderAccountRemovalResult(
            removed: false,
            accounts: [providerAccountFixture(
                providerID: providerID, ref: remainingRef, label: "work@example.com", order: 0)])
    }
    let removed = try #require(
        model.connectionAccounts(providerID: providerID).first { $0.accountRef == removedRef })

    await model.removeAccount(removed, coordinator: coordinator)
    // No settling refresh needed here (task-10b fix round 1, "Finding 2"
    // fixed this): `removeAccount`'s own `refresh(forceFresh:)` still races
    // its two concurrent halves the same way `login()`'s does (see the
    // comment in `successfulLoginAppendsAnAccountAndRefreshesAccountMetadataAndUsage`),
    // so the snapshot swap above may or may not have landed in
    // `lastUsageSnapshot` by the time it returns — but this test hits
    // `removeAccount`'s success branch (a decoded `{removed, accounts}`
    // reply, `removed: false` or not), so `removedAccountRefsAwaitingSnapshotCatchUp`
    // now filters `removedRef` out of a stale re-derivation regardless of
    // which way that race lands. Proven by asserting immediately, with no
    // second `refresh()` to paper over either outcome.
    #expect(removalRequests == [
        AccountRemovalRequest(providerID: providerID, accountRef: removedRef),
    ])
    #expect(model.connectionAccounts(providerID: providerID).map(\.accountRef) == [remainingRef])
    #expect(model.removalMessage == "Account is no longer available.")
    #expect(model.pendingRemovalAccounts.isEmpty)
    #expect(coordinator.primaryAccountRef(providerID: providerID) == remainingRef)
}

/// Task 10b fix round 1, Finding 2: the rigorous version of the proof
/// above, forcing the exact worst-case ordering rather than trusting
/// whatever the scheduler happens to produce. `FakeUsageService`'s snapshot
/// is deliberately left un-swapped (still the pre-removal, two-account
/// snapshot) and its next `loadUsage()` is gated open, so
/// `refreshAccountUsage`'s re-derivation inside `removeAccount`'s own
/// `refresh(forceFresh: true)` is guaranteed to run against the
/// still-stale `lastUsageSnapshot` — the exact interleaving that used to
/// resurrect the removed account (see `removedAccountRefsAwaitingSnapshotCatchUp`'s
/// doc comment for the full mechanism). Asserting mid-flight, before the
/// gate is ever released, proves the fix holds on the very first pass, not
/// "eventually, once the settling refresh catches up."
@Test func removalDoesNotResurrectTheRemovedAccountEvenWhenTheUsagePollLagsBehindIt() async throws {
    let providerID = "openai-codex"
    let removedEntry = AccountSnapshotEntry(accountID: "a1", email: "personal@example.com")
    let remainingEntry = AccountSnapshotEntry(accountID: "a2", email: "work@example.com")
    let removedRef = removedEntry.accountRef(providerID: providerID)
    let remainingRef = remainingEntry.accountRef(providerID: providerID)
    let usage = FakeUsageService(snapshot: multiAccountUsageSnapshotFixture(
        providerID: providerID, accounts: [removedEntry, remainingEntry]))
    let model = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: [ProviderLoginProvider(
            id: providerID, name: "ChatGPT", isAvailable: true, isAuthenticated: true)]),
        usageService: usage,
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    await model.load()
    let (coordinator, defaults, suiteName) = try makeManagementCoordinator()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    model.attachAccountCoordinator(coordinator)
    await coordinator.useAccount(
        removedRef,
        providerID: providerID,
        scope: .allNewSessions,
        openSessionID: nil)
    model.installAccountRemovalTransport { _, _ in
        ProviderAccountRemovalResult(
            removed: true,
            accounts: [providerAccountFixture(
                providerID: providerID, ref: remainingRef, label: "work@example.com", order: 0)])
    }

    let gate = LoadGate()
    await usage.enqueueLoadGate(gate)
    let removed = try #require(
        model.connectionAccounts(providerID: providerID).first { $0.accountRef == removedRef })
    let removal = Task { await model.removeAccount(removed, coordinator: coordinator) }
    await gate.waitForStart()
    // The gate now holds the CLI-side usage poll open, so `lastUsageSnapshot`
    // cannot yet have advanced past the stale, two-account snapshot.
    // Waiting for `!isLoadingProviders` guarantees `refreshAccountUsage`'s
    // entire re-derivation already ran — and therefore already read
    // whichever snapshot `lastUsageSnapshot` holds right now — before this
    // assertion, the same synchronization
    // `refreshAccountUsageDoesNotBlockOnASlowSubsequentUsagePoll` uses.
    await waitForModelState { !model.isLoadingProviders }

    #expect(model.connectionAccounts(providerID: providerID).map(\.accountRef) == [remainingRef])

    await gate.release()
    await removal.value

    #expect(model.connectionAccounts(providerID: providerID).map(\.accountRef) == [remainingRef])
}

@Test func failedRemovalRefreshesMetadataAndUsageThenRepairsFromAuthoritativeAccounts() async throws {
    let providerID = "openai-codex"
    let removedEntry = AccountSnapshotEntry(accountID: "a1", email: "personal@example.com")
    let remainingEntry = AccountSnapshotEntry(accountID: "a2", email: "work@example.com")
    let removedRef = removedEntry.accountRef(providerID: providerID)
    let remainingRef = remainingEntry.accountRef(providerID: providerID)
    let usage = FakeUsageService(snapshot: multiAccountUsageSnapshotFixture(
        providerID: providerID, accounts: [removedEntry, remainingEntry]))
    let model = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: [ProviderLoginProvider(
            id: providerID, name: "ChatGPT", isAvailable: true, isAuthenticated: true)]),
        usageService: usage,
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    let (coordinator, defaults, suiteName) = try makeManagementCoordinator()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    model.attachAccountCoordinator(coordinator)
    await model.load()
    await coordinator.useAccount(
        removedRef,
        providerID: providerID,
        scope: .allNewSessions,
        openSessionID: nil)
    // The transport's own effect (the extension actually removed the
    // credential) lands on the snapshot before it reports failure — modeling
    // "the removal happened, but telling us about it failed" — so the
    // `refresh(forceFresh:)` inside the view model's catch-all still repairs
    // from the authoritative, now-one-account state.
    model.installAccountRemovalTransport { _, _ in
        await usage.setSnapshot(multiAccountUsageSnapshotFixture(
            providerID: providerID, accounts: [remainingEntry]))
        throw ProviderAccountChannelError.rejected("boom")
    }

    let removed = try #require(
        model.connectionAccounts(providerID: providerID).first { $0.accountRef == removedRef })
    await model.removeAccount(removed, coordinator: coordinator)
    // Still settles a real race, unlike the now-unnecessary one removed
    // from `staleExternalRemovalRefreshesRowsAndReportsAccountUnavailable`
    // (task-10b fix round 1, "Finding 2"): that fix protects re-derivation
    // only when `removeAccount` reaches its success branch and has an
    // authoritative `result.accounts` to guard with
    // (`removedAccountRefsAwaitingSnapshotCatchUp`). A thrown error, like
    // this test's, never reaches that branch — the view model has no
    // confirmation of what actually happened on the extension side, only
    // the generic catch-all below — so it has nothing to guard with either,
    // and must rely entirely on this settling refresh to discover the true
    // state via ordinary re-derivation.
    await model.refresh()

    #expect(model.connectionAccounts(providerID: providerID).map(\.accountRef) == [remainingRef])
    #expect(model.removalMessage == "Account couldn’t be removed.")
    #expect(coordinator.primaryAccountRef(providerID: providerID) == remainingRef)
}

@Test func removalWithoutAnEligibleReplacementRefreshesAndShowsATruthfulError() async throws {
    let providerID = "openai-codex"
    let target = AccountSnapshotEntry(accountID: "a1", email: "personal@example.com")
    let unavailable = AccountSnapshotEntry(accountID: "a2", email: "unavailable@example.com", isDisabled: true)
    let targetRef = target.accountRef(providerID: providerID)
    let model = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: [ProviderLoginProvider(
            id: providerID, name: "ChatGPT", isAvailable: true, isAuthenticated: true)]),
        usageService: FakeUsageService(snapshot: multiAccountUsageSnapshotFixture(
            providerID: providerID, accounts: [target, unavailable])),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    let (coordinator, defaults, suiteName) = try makeManagementCoordinator()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    model.attachAccountCoordinator(coordinator)
    await model.load()
    // No removal transport installed: the coordinator must refuse before
    // ever reaching it (the only remaining account, `unavailable`, is not an
    // eligible replacement) — reaching `performRemoval` at all would produce
    // a different message than the one asserted below, via the installed-
    // by-default "no transport" failure, so this also proves it was never
    // called without a separate call-count fake.

    let removed = try #require(
        model.connectionAccounts(providerID: providerID).first { $0.accountRef == targetRef })
    await model.removeAccount(removed, coordinator: coordinator)

    #expect(model.removalMessage == "Account couldn’t be removed because no replacement account is available.")
    #expect(coordinator.primaryAccountRef(providerID: providerID) == targetRef)
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

/// Task 10b replacement for the retired `lateCLIFailureDoesNotOverwriteNewerAccountRPCUsage`:
/// that test proved a slow/failing CLI-wide `omp usage --json` poll could
/// not block or corrupt a SEPARATE, independent per-account RPC. There is no
/// longer a separate per-account RPC to race against — both derive from the
/// same snapshot — so the invariant worth keeping is the mechanism that
/// used to protect it: `refreshAccountUsage` waits for the sibling usage
/// refresh only on a cold-start (`lastUsageSnapshot == nil`), never on a
/// later refresh, so a slow subsequent CLI poll cannot stall provider/account
/// loading behind it.
@Test func refreshAccountUsageDoesNotBlockOnASlowSubsequentUsagePoll() async throws {
    let providerID = "cursor"
    let account = AccountSnapshotEntry(accountID: "a1", email: "account@example.com", remainingFraction: 0.25)
    let usage = FakeUsageService(snapshot: multiAccountUsageSnapshotFixture(
        providerID: providerID, accounts: [account]))
    let service = FakeProviderService(providers: [ProviderLoginProvider(
        id: providerID, name: "Cursor", isAvailable: true, isAuthenticated: true)])
    let model = ProviderManagementViewModel(
        providerService: service,
        usageService: usage,
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    await model.load()
    #expect(model.dockProviders.first?.accounts.first?.limits.first?.percentage == 25)

    let lateCLIGate = LoadGate()
    await usage.enqueueLoadGate(lateCLIGate)

    let refresh = Task { await model.refresh() }
    await lateCLIGate.waitForStart()
    // The account-deriving side of the refresh must already be done — still
    // showing the OLD snapshot's values — while the CLI poll sits gated.
    await waitForModelState {
        model.isRefreshingUsage && !model.isLoadingProviders
    }
    #expect(model.dockProviders.first?.accounts.first?.limits.first?.percentage == 25)

    await lateCLIGate.release()
    await refresh.value

    let provider = try #require(model.dockProviders.first)
    #expect(provider.capability == .accountRouting)
    #expect(provider.accounts.first?.accountRef == account.accountRef(providerID: providerID))
    #expect(provider.accounts.first?.limits.first?.percentage == 25)
}

@Test func disconnectedAndMissingProvidersDiscardAccountPresentationCaches() async throws {
    let providerID = "cursor"
    let authenticated = ProviderLoginProvider(
        id: providerID,
        name: "Cursor",
        isAvailable: true,
        isAuthenticated: true)
    let service = FakeProviderService(providers: [authenticated])
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

import SwiftUI
import Testing
@testable import TenXApp

@Suite struct ProviderAccountStackTests {
@Test func foregroundAccountKeepsTheRegularWheelWhileSiblingsFanUpwardAtSmallerSize() throws {
    let geometry = ProviderAccountStackGeometry(
        accountIDs: ["account-a", "account-b", "account-c"],
        foregroundAccountID: "account-b",
        wheelDiameter: 54)

    let foreground = try #require(geometry.items.first(where: { $0.accountID == "account-b" }))
    let firstSibling = try #require(geometry.items.first(where: { $0.accountID == "account-a" }))
    let secondSibling = try #require(geometry.items.first(where: { $0.accountID == "account-c" }))

    #expect(foreground.visualDiameter == 54)
    #expect(foreground.verticalOffset == 0)
    #expect(firstSibling.visualDiameter < foreground.visualDiameter)
    #expect(firstSibling.verticalOffset > foreground.verticalOffset)
    #expect(secondSibling.verticalOffset > firstSibling.verticalOffset)
    // The fan spends height, not width: the group is exactly one wheel wide
    // regardless of account count, which is what makes `stackWidths(providers:)`
    // dead code (see ProviderUsageDockLayoutTests).
    #expect(geometry.width == 54)
    #expect(geometry.expandedHeight > 54)
}

@Test func everyAccountHasASeparateFortyFourPointSemanticTarget() {
    let geometry = ProviderAccountStackGeometry(
        accountIDs: ["account-a", "account-b", "account-c"],
        foregroundAccountID: "account-a",
        wheelDiameter: 44)

    #expect(geometry.items.count == 3)
    #expect(geometry.items.allSatisfy { $0.hitTargetDiameter >= 44 })
    #expect(Set(geometry.items.map(\.accountID)).count == 3)
}

@Test func accessibilityOrderStartsWithForegroundThenKeepsConnectionOrderStable() {
    let geometry = ProviderAccountStackGeometry(
        accountIDs: ["account-a", "account-b", "account-c", "account-d"],
        foregroundAccountID: "account-c",
        wheelDiameter: 54)

    #expect(geometry.accessibilityOrderedAccountIDs == [
        "account-c",
        "account-a",
        "account-b",
        "account-d",
    ])
}

@Test func foregroundOwnsPrimaryZOrderUntilABackgroundAccountIsHoveredOrFocused() throws {
    let geometry = ProviderAccountStackGeometry(
        accountIDs: ["account-a", "account-b"],
        foregroundAccountID: "account-a",
        wheelDiameter: 54)
    let foreground = try #require(geometry.items.first(where: { $0.accountID == "account-a" }))
    let background = try #require(geometry.items.first(where: { $0.accountID == "account-b" }))

    let idle = geometry.visualState(
        for: background,
        isRaised: false,
        isAnyItemRaised: false,
        showsFocusOutline: false,
        isGrayscale: true,
        reduceMotion: false)
    let hovered = geometry.visualState(
        for: background,
        isRaised: true,
        isAnyItemRaised: true,
        showsFocusOutline: false,
        isGrayscale: true,
        reduceMotion: false)
    let focused = geometry.visualState(
        for: background,
        isRaised: true,
        isAnyItemRaised: true,
        showsFocusOutline: true,
        isGrayscale: true,
        reduceMotion: false)

    #expect(foreground.zIndex > idle.zIndex)
    #expect(!idle.isRaised)
    #expect(idle.isGrayscale)
    #expect(hovered.isRaised)
    #expect(!hovered.isGrayscale)
    #expect(hovered.zIndex > foreground.zIndex)
    #expect(focused.isRaised)
    #expect(!focused.isGrayscale)
    #expect(focused.zIndex > foreground.zIndex)
    #expect(!hovered.showsFocusOutline)
    #expect(focused.showsFocusOutline)
}

// Regression test for the z-order guard bug: `isRaised` used to be gated by
// `!item.isForeground`, so the foreground account could never be promoted or
// colorized by hover/focus. Today the foreground already holds the highest
// base z-index, which is what masked the bug — but whichever account the
// pointer or focus ring is actually on must come to the top of the z-stack,
// foreground included.
@Test func hoveringOrFocusingTheForegroundAccountAlsoRaisesAndPromotesItToTheTopOfTheZStack() throws {
    let geometry = ProviderAccountStackGeometry(
        accountIDs: ["account-a", "account-b"],
        foregroundAccountID: "account-a",
        wheelDiameter: 54)
    let foreground = try #require(geometry.items.first(where: { $0.accountID == "account-a" }))

    let idle = geometry.visualState(
        for: foreground,
        isRaised: false,
        isAnyItemRaised: false,
        showsFocusOutline: false,
        isGrayscale: true,
        reduceMotion: false)
    let hovered = geometry.visualState(
        for: foreground,
        isRaised: true,
        isAnyItemRaised: true,
        showsFocusOutline: false,
        isGrayscale: true,
        reduceMotion: false)

    #expect(!idle.isRaised)
    #expect(idle.currentDiameter == geometry.wheelDiameter)
    #expect(hovered.isRaised)
    #expect(hovered.currentDiameter == geometry.wheelDiameter)
    #expect(!hovered.isGrayscale)
    #expect(hovered.zIndex == Double(geometry.items.count + 2))
}

// The user's own correction to the raise design: the raised account should
// become the full-size foreground, not just a slightly-emphasized version
// of its own resting size — and everything else, foreground included,
// should visibly step back to make room for it.
@Test func hoveredBackgroundAccountGrowsToFullDiameterWhileForegroundShrinksAndDims() throws {
    let geometry = ProviderAccountStackGeometry(
        accountIDs: ["account-a", "account-b"],
        foregroundAccountID: "account-a",
        wheelDiameter: 54)
    let foregroundItem = try #require(geometry.items.first(where: { $0.accountID == "account-a" }))
    let backgroundItem = try #require(geometry.items.first(where: { $0.accountID == "account-b" }))

    let raisedBackground = geometry.visualState(
        for: backgroundItem,
        isRaised: true,
        isAnyItemRaised: true,
        showsFocusOutline: false,
        isGrayscale: false,
        reduceMotion: false)
    let demotedForeground = geometry.visualState(
        for: foregroundItem,
        isRaised: false,
        isAnyItemRaised: true,
        showsFocusOutline: false,
        isGrayscale: false,
        reduceMotion: false)
    let restingForeground = geometry.visualState(
        for: foregroundItem,
        isRaised: false,
        isAnyItemRaised: false,
        showsFocusOutline: false,
        isGrayscale: false,
        reduceMotion: false)

    #expect(raisedBackground.currentDiameter == geometry.wheelDiameter)
    #expect(demotedForeground.currentDiameter == geometry.backgroundDiameter)
    #expect(demotedForeground.currentDiameter < raisedBackground.currentDiameter)
    // Dimming while a sibling is raised holds even with the global
    // grayscale flag off — "every other account... dimmed treatment while
    // the hover lasts" names no exception for whether the open chat is
    // generating.
    #expect(demotedForeground.isGrayscale)
    #expect(!restingForeground.isGrayscale)
    #expect(restingForeground.currentDiameter == geometry.wheelDiameter)
}

// The explicit constraint on how the grow-in-place must work: only size,
// color, and z-index may change. `renderedOffset` is the whole position
// contract in one formula — proves it holds for the resting diameter, the
// full raised diameter, and an arbitrary third diameter, not just the two
// values that happen to occur in practice.
@Test func growingOrShrinkingNeverMovesAWheelsCenter() throws {
    let geometry = ProviderAccountStackGeometry(
        accountIDs: ["account-a", "account-b", "account-c"],
        foregroundAccountID: "account-a",
        wheelDiameter: 54)
    let background = try #require(geometry.items.first(where: { $0.accountID == "account-b" }))
    let restingCenter = background.verticalOffset + background.visualDiameter / 2

    for candidateDiameter: CGFloat in [background.visualDiameter, geometry.wheelDiameter, 30] {
        let offset = geometry.renderedOffset(
            for: background,
            currentDiameter: candidateDiameter,
            isExpanded: true)
        #expect(offset + candidateDiameter / 2 == restingCenter)
    }

    // Collapsed (not expanded), every item sits at zero regardless of
    // diameter — the group-collapse behavior grow-in-place must not disturb.
    #expect(geometry.renderedOffset(
        for: background, currentDiameter: geometry.wheelDiameter, isExpanded: false) == 0)
}

@Test func reduceMotionRaisesAndColorizesImmediatelyWithoutAnimation() throws {
    let geometry = ProviderAccountStackGeometry(
        accountIDs: ["account-a", "account-b"],
        foregroundAccountID: "account-a",
        wheelDiameter: 54)
    let background = try #require(geometry.items.first(where: { $0.accountID == "account-b" }))

    let state = geometry.visualState(
        for: background,
        isRaised: true,
        isAnyItemRaised: true,
        showsFocusOutline: true,
        isGrayscale: true,
        reduceMotion: true)

    #expect(state.isRaised)
    #expect(!state.isGrayscale)
    #expect(state.currentDiameter == geometry.wheelDiameter)
    #expect(state.animationDuration == nil)
}

// Focusing the foreground is how a keyboard user discovers the collapsed
// siblings in the first place — it must expand the group exactly like
// hovering it would, not just show an outline in place.
@Test func focusedForegroundAccountRaisesAndShowsACustomOutline() throws {
    let geometry = ProviderAccountStackGeometry(
        accountIDs: ["account-a", "account-b"],
        foregroundAccountID: "account-a",
        wheelDiameter: 54)
    let foreground = try #require(geometry.items.first(where: {
        $0.accountID == "account-a"
    }))

    let state = geometry.visualState(
        for: foreground,
        isRaised: true,
        isAnyItemRaised: true,
        showsFocusOutline: true,
        isGrayscale: true,
        reduceMotion: false)

    #expect(state.isRaised)
    #expect(state.currentDiameter == geometry.wheelDiameter)
    #expect(state.showsFocusOutline)
}

@Test func foregroundGeometryChangesAnimateOnlyWhenReduceMotionIsOff() {
    #expect(ProviderAccountStackMotion.animationDuration(reduceMotion: false) == 0.16)
    #expect(ProviderAccountStackMotion.animationDuration(reduceMotion: true) == nil)
}

@MainActor
@Test func focusedForegroundAccountShowsInteractiveCyanOutlineSnapshot() throws {
    try assertSnapshot(
        ProviderAccountStackSnapshotHarness(visualFocusAccountID: "anthropic:personal"),
        name: "provider-account-stack-states",
        size: CGSize(width: 160, height: 170))
}

// Rest state: only the active account's wheel plus a badge naming how many
// other accounts are collapsed behind it. Single-account providers get no
// badge at all (covered by the account-count check in `showsBadge`).
@MainActor
@Test func restStateShowsACountBadgeForOtherAccountsSnapshot() throws {
    // The canvas matches the expanded snapshots' height even though only one
    // wheel is visible: the container always reserves the fully fanned-out
    // height so the hover region never resizes (see `isGroupExpanded` and
    // the comment on `ProviderAccountStackGeometry.expandedHeight`). A
    // shorter canvas would clip the reserved-but-currently-empty space above
    // the wheel and misrepresent what a real rest state looks like.
    try assertSnapshot(
        ProviderAccountStackSnapshotHarness(),
        name: "provider-account-stack-rest-badge",
        size: CGSize(width: 100, height: 170))
}

// Hovering one account (not focusing it) must raise, colorize, and front it
// without showing the keyboard focus outline — a distinct visual state from
// the focus-driven snapshot above. This needs a fixture where "work" can
// actually show color (.available, with a real limit) and a globally
// grayscaled scope (isGrayscale: true) so there is a grey state for hover
// to visibly override — the shared harness fixture fails both: "work" is
// .loading (always a neutral placeholder track, colored or not) and the
// harness's default isGrayscale is false (nothing is grey to begin with).
@MainActor
@Test func hoveringOneAccountRaisesItWithoutAFocusOutlineSnapshot() throws {
    try assertSnapshot(
        ProviderAccountStackSnapshotHarness(
            visualHoverAccountID: "anthropic:work",
            isGrayscale: true,
            provider: ProviderAccountStackSnapshotHarness.colorableProvider),
        name: "provider-account-stack-hovered-account",
        size: CGSize(width: 160, height: 170))
}

// A hidden (non-foreground) account with a nonzero generating count keeps
// the rest-state badge in the accent color, so the activity signal the
// per-account centers exist for survives collapsing the stack.
@MainActor
@Test func restBadgeGoesLiveWhenAHiddenAccountIsGeneratingSnapshot() throws {
    try assertSnapshot(
        ProviderAccountStackSnapshotHarness(
            generatingCounts: [
                ProviderAccountKey(providerID: "anthropic", accountRef: "work"): 2,
            ]),
        name: "provider-account-stack-badge-live",
        size: CGSize(width: 100, height: 170))
}
}

private struct ProviderAccountStackSnapshotHarness: View {
    var visualFocusAccountID: String?
    var visualHoverAccountID: String?
    var generatingCounts: [ProviderAccountKey: Int] = [:]
    var isGrayscale = false
    var provider = ProviderAccountStackSnapshotHarness.defaultProvider

    @FocusState private var focusedAccountID: String?

    var body: some View {
        ProviderAccountStackView(
            provider: provider,
            generatingCounts: generatingCounts,
            isGrayscale: isGrayscale,
            focusedAccountID: $focusedAccountID,
            visualFocusAccountID: visualFocusAccountID,
            visualHoverAccountID: visualHoverAccountID,
            onSelect: { _ in })
            // A nonzero generating count keeps a wheel's activity pulse
            // animating even while that wheel sits collapsed behind the
            // foreground; without this the snapshot byte-for-byte compares
            // against a rendering frozen at a different animation phase
            // than whichever one was captured for the reference image.
            // macOS exposes the public Reduce Motion key as read-only.
            .environment(\._accessibilityReduceMotion, true)
    }

    private static let defaultProvider = ProviderUsageProvider(
        id: "anthropic",
        name: "Anthropic",
        accounts: [
            account(
                id: "anthropic:personal",
                label: "Personal",
                accountRef: "personal",
                usageState: .available,
                limits: [limit(id: "five-hour", percentage: 72)]),
            account(
                id: "anthropic:work",
                label: "Work",
                accountRef: "work",
                usageState: .loading,
                limits: []),
            account(
                id: "anthropic:backup",
                label: "Backup",
                accountRef: "backup",
                usageState: .unavailable,
                limits: [limit(id: "stale", percentage: 8)]),
        ],
        capability: .accountRouting,
        foregroundAccountRef: "personal")

    // "work" has real, colorable usage (.available, 55% — standard/cyan
    // tone) unlike the default fixture's .loading placeholder, which never
    // shows color regardless of hover. Used only by the hover-colorization
    // snapshot so the other three snapshots keep their original fixture.
    static let colorableProvider = ProviderUsageProvider(
        id: "anthropic",
        name: "Anthropic",
        accounts: [
            account(
                id: "anthropic:personal",
                label: "Personal",
                accountRef: "personal",
                usageState: .available,
                limits: [limit(id: "five-hour", percentage: 72)]),
            account(
                id: "anthropic:work",
                label: "Work",
                accountRef: "work",
                usageState: .available,
                limits: [limit(id: "monthly", percentage: 55)]),
            account(
                id: "anthropic:backup",
                label: "Backup",
                accountRef: "backup",
                usageState: .unavailable,
                limits: [limit(id: "stale", percentage: 8)]),
        ],
        capability: .accountRouting,
        foregroundAccountRef: "personal")

    private static func account(
        id: String,
        label: String,
        accountRef: String,
        usageState: ProviderUsageState,
        limits: [ProviderUsageLimit]
    ) -> ProviderUsageAccount {
        ProviderUsageAccount(
            id: id,
            label: label,
            identity: .empty,
            limits: limits,
            amounts: [],
            notes: [],
            isUsageAvailable: usageState != .unavailable,
            accountRef: accountRef,
            usageState: usageState)
    }

    private static func limit(id: String, percentage: Int) -> ProviderUsageLimit {
        ProviderUsageLimit(
            id: id,
            label: "5 hour",
            percentage: percentage,
            resetWindow: "in 2 hours")
    }
}

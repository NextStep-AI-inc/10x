import SwiftUI
import Testing
@testable import TenXApp

@Suite struct ProviderAccountStackTests {
@Test func foregroundAccountKeepsTheRegularWheelWhileSiblingsCascadeRightAtSmallerSize() throws {
    let geometry = ProviderAccountStackGeometry(
        accountIDs: ["account-a", "account-b", "account-c"],
        foregroundAccountID: "account-b",
        wheelDiameter: 54)

    let foreground = try #require(geometry.items.first(where: { $0.accountID == "account-b" }))
    let firstSibling = try #require(geometry.items.first(where: { $0.accountID == "account-a" }))
    let secondSibling = try #require(geometry.items.first(where: { $0.accountID == "account-c" }))

    #expect(foreground.visualDiameter == 54)
    #expect(foreground.xOffset == 0)
    #expect(firstSibling.visualDiameter < foreground.visualDiameter)
    #expect(firstSibling.xOffset > foreground.xOffset)
    #expect(secondSibling.xOffset > firstSibling.xOffset)
    #expect(geometry.width > 54)
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
        isHovered: false,
        isFocused: false,
        isGrayscale: true,
        reduceMotion: false)
    let hovered = geometry.visualState(
        for: background,
        isHovered: true,
        isFocused: false,
        isGrayscale: true,
        reduceMotion: false)
    let focused = geometry.visualState(
        for: background,
        isHovered: false,
        isFocused: true,
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

@Test func reduceMotionRaisesAndColorizesImmediatelyWithoutAnimation() throws {
    let geometry = ProviderAccountStackGeometry(
        accountIDs: ["account-a", "account-b"],
        foregroundAccountID: "account-a",
        wheelDiameter: 54)
    let background = try #require(geometry.items.first(where: { $0.accountID == "account-b" }))

    let state = geometry.visualState(
        for: background,
        isHovered: false,
        isFocused: true,
        isGrayscale: true,
        reduceMotion: true)

    #expect(state.isRaised)
    #expect(!state.isGrayscale)
    #expect(state.elevation > 0)
    #expect(state.animationDuration == nil)
}

@Test func focusedForegroundAccountKeepsItsPositionAndShowsACustomOutline() throws {
    let geometry = ProviderAccountStackGeometry(
        accountIDs: ["account-a", "account-b"],
        foregroundAccountID: "account-a",
        wheelDiameter: 54)
    let foreground = try #require(geometry.items.first(where: {
        $0.accountID == "account-a"
    }))

    let state = geometry.visualState(
        for: foreground,
        isHovered: false,
        isFocused: true,
        isGrayscale: true,
        reduceMotion: false)

    #expect(!state.isRaised)
    #expect(state.elevation == 0)
    #expect(state.showsFocusOutline)
}

@Test func foregroundGeometryChangesAnimateOnlyWhenReduceMotionIsOff() {
    #expect(ProviderAccountStackMotion.animationDuration(reduceMotion: false) == 0.16)
    #expect(ProviderAccountStackMotion.animationDuration(reduceMotion: true) == nil)
}

@MainActor
@Test func focusedForegroundAccountShowsInteractiveCyanOutlineSnapshot() throws {
    try assertSnapshot(
        ProviderAccountStackSnapshotHarness(),
        name: "provider-account-stack-states",
        size: CGSize(width: 180, height: 100))
}
}

private struct ProviderAccountStackSnapshotHarness: View {
    @FocusState private var focusedAccountID: String?

    var body: some View {
        ProviderAccountStackView(
            provider: Self.provider,
            generatingCounts: [:],
            isGrayscale: false,
            focusedAccountID: $focusedAccountID,
            visualFocusAccountID: "anthropic:personal",
            onSelect: { _ in })
    }

    private static let provider = ProviderUsageProvider(
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

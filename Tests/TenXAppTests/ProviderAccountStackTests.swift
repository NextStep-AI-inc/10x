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
    #expect(focused == hovered)
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
}

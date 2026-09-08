import Foundation
import Testing
@testable import TenXApp

@Test @MainActor func flyerReplacementPreservesPositionAndScope() {
    let center = FlyerCenter()
    let now = Date(timeIntervalSince1970: 1_000)
    center.post(flyerFixture(id: "a", scope: .session("one")))
    center.post(flyerFixture(id: "b", scope: .global))
    center.post(flyerFixture(
        id: "a",
        scope: .session("one"),
        detail: "4 turns finished"))
    center.post(flyerFixture(id: "a", scope: .session("two")))

    #expect(center.visible(sessionKey: "one", at: now).map(\.id) == ["a", "b"])
    #expect(center.visible(sessionKey: "one", at: now).first?.detail == "4 turns finished")
    #expect(center.visible(sessionKey: "two", at: now).map(\.id) == ["b", "a"])
}

@Test @MainActor func flyerVisibilityCapsAtThreeAndRevealsOlderRows() {
    let center = FlyerCenter()
    let now = Date(timeIntervalSince1970: 1_000)

    #expect(center.visible(sessionKey: "one", at: now).isEmpty)

    center.post(flyerFixture(id: "global", scope: .global))
    #expect(center.visible(sessionKey: nil, at: now).map(\.id) == ["global"])

    center.post(flyerFixture(id: "a", scope: .session("one")))
    center.post(flyerFixture(id: "b", scope: .session("one")))
    center.post(flyerFixture(id: "c", scope: .session("one")))
    center.post(flyerFixture(id: "d", scope: .session("one")))
    #expect(center.visible(sessionKey: "one", at: now).map(\.id) == ["b", "c", "d"])

    center.remove(Flyer.Key(scope: .session("one"), id: "c"))
    #expect(center.visible(sessionKey: "one", at: now).map(\.id) == ["a", "b", "d"])

    center.post(flyerFixture(
        id: "expired",
        scope: .session("one"),
        expiresAt: Date(timeIntervalSince1970: 999)))
    #expect(center.visible(sessionKey: "one", at: now).map(\.id) == ["a", "b", "d"])

    center.post(flyerFixture(
        id: "d",
        scope: .session("one"),
        expiresAt: Date(timeIntervalSince1970: 1_000)))
    #expect(center.visible(sessionKey: "one", at: now).map(\.id) == ["global", "a", "b"])

    center.post(flyerFixture(id: "e", scope: .session("one")))
    center.expire(at: now)
    center.post(flyerFixture(id: "d", scope: .session("one")))
    #expect(center.visible(sessionKey: "one", at: now).map(\.id) == ["b", "e", "d"])
}

@Test @MainActor func flyerSessionRemovalPreservesGlobalRows() {
    let center = FlyerCenter()
    let now = Date(timeIntervalSince1970: 1_000)
    center.post(flyerFixture(id: "global", scope: .global))
    center.post(flyerFixture(id: "session", scope: .session("one")))
    center.post(flyerFixture(id: "session", scope: .session("two")))

    #expect(center.visible(sessionKey: "one", at: now).map(\.id) == ["global", "session"])
    #expect(center.visible(sessionKey: "two", at: now).map(\.id) == ["global", "session"])
    #expect(center.visible(sessionKey: nil, at: now).map(\.id) == ["global"])

    center.removeSession("one")

    #expect(center.visible(sessionKey: "one", at: now).map(\.id) == ["global"])
    #expect(center.visible(sessionKey: "two", at: now).map(\.id) == ["global", "session"])
}

private func flyerFixture(
    id: String,
    scope: Flyer.Scope,
    detail: String = "3 turns finished",
    expiresAt: Date? = nil
) -> Flyer {
    Flyer(
        id: id,
        scope: scope,
        tone: .information,
        title: "Catch up",
        detail: detail,
        actions: [Flyer.Action(id: "catch-up", title: "Catch up")],
        isDismissible: true,
        expiresAt: expiresAt)
}

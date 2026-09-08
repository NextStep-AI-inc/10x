import AppKit
import SwiftUI
import Testing
@testable import TenXApp

@MainActor
@Test func flyerRowShowsActionsBesideOverflowDescription() throws {
    let view = FlyerRowView(
        flyer: flyerSnapshotFixture(
            detail: "This intentionally long detail should overflow its narrow viewport while the action remains visible."),
        onAction: { _ in },
        onDismiss: {})
        .environment(\.flyerMarqueeElapsedOverride, 0)
        .frame(width: 460)

    let bitmap = try #require(renderSnapshotBitmap(
        view,
        size: CGSize(width: 460, height: 48)))

    #expect(hasInteractiveCyanInk(
        in: bitmap,
        xRange: Int(Double(bitmap.pixelsWide) * 0.70)..<bitmap.pixelsWide))
    #expect(hasDarkTextInk(
        in: bitmap,
        xRange: Int(Double(bitmap.pixelsWide) * 0.25)..<Int(Double(bitmap.pixelsWide) * 0.68)))
    #expect(!hasDarkTextInk(
        in: bitmap,
        xRange: Int(Double(bitmap.pixelsWide) * 0.82)..<Int(Double(bitmap.pixelsWide) * 0.93)))
}

@Test func marqueePresentationResetsOnTextOrWidthChange() {
    let body13 = Font.system(size: 13, weight: .regular)
    let original = MarqueePresentationKey(
        text: "Three turns finished",
        font: body13,
        viewportWidth: 180,
        layoutDirection: .leftToRight)

    #expect(original != MarqueePresentationKey(
        text: "Four turns finished",
        font: body13,
        viewportWidth: 180,
        layoutDirection: .leftToRight))
    #expect(original != MarqueePresentationKey(
        text: original.text,
        font: Font.system(size: 18, weight: .regular),
        viewportWidth: 180,
        layoutDirection: .leftToRight))
    #expect(original != MarqueePresentationKey(
        text: original.text,
        font: Font.system(size: 13, weight: .bold),
        viewportWidth: 180,
        layoutDirection: .leftToRight))
    #expect(original != MarqueePresentationKey(
        text: original.text,
        font: body13,
        viewportWidth: 120,
        layoutDirection: .leftToRight))
    #expect(original != MarqueePresentationKey(
        text: original.text,
        font: body13,
        viewportWidth: 180,
        layoutDirection: .rightToLeft))
    #expect(original == MarqueePresentationKey(
        text: original.text,
        font: Font.system(size: 13, weight: .regular),
        viewportWidth: 180,
        layoutDirection: .leftToRight))
}

@MainActor
@Test func flyerSnapshots() throws {
    for appearance in [SnapshotAppearance.light, .dark] {
        let suffix = appearance == .dark ? "-dark" : ""
        try assertSnapshot(
            flyerSnapshotRow(detail: "Finished three turns and prepared a concise implementation summary."),
            name: "flyer-fitting\(suffix)",
            appearance: appearance,
            size: CGSize(width: 720, height: 48))
        try assertSnapshot(
            flyerSnapshotRow(
                detail: "Finished three turns, verified the updated session map, and prepared a detailed implementation summary for review.",
                width: 560),
            name: "flyer-overflow-start\(suffix)",
            appearance: appearance,
            size: CGSize(width: 560, height: 48))
        try assertSnapshot(
            flyerSnapshotStack(),
            name: "flyer-three\(suffix)",
            appearance: appearance,
            size: CGSize(width: 720, height: 128))
        try assertSnapshot(
            flyerSnapshotRow(
                title: "3 turns finished while you were away",
                detail: "The implementation summary is ready.",
                width: 460),
            name: "flyer-long-title\(suffix)",
            appearance: appearance,
            size: CGSize(width: 460, height: 48))
    }

    try assertSnapshot(
        flyerSnapshotRow(
            detail: "Finished three turns, verified the updated session map, and prepared a detailed implementation summary for review.",
            width: 560)
            .environment(\.flyerReduceMotionOverride, true),
        name: "flyer-reduced-motion",
        size: CGSize(width: 560, height: 48))
    try assertSnapshot(
        flyerSnapshotRow(
            detail: "Finished three turns, verified the updated session map, and prepared a detailed implementation summary for review.",
            width: 560)
            .environment(\.flyerReduceTransparencyOverride, true),
        name: "flyer-reduced-transparency",
        size: CGSize(width: 560, height: 48))
}

@MainActor
private func flyerSnapshotRow(
    title: String = "3 turns finished",
    detail: String,
    width: CGFloat = 720
) -> some View {
    FlyerRowView(
        flyer: flyerSnapshotFixture(title: title, detail: detail),
        onAction: { _ in },
        onDismiss: {})
        .environment(\.flyerMarqueeElapsedOverride, 0)
        .frame(width: width)
}

@MainActor
private func flyerSnapshotStack() -> some View {
    FlyerStackView(
        flyers: [
            flyerSnapshotFixture(id: "information", detail: "The session summary is ready."),
            flyerSnapshotFixture(
                id: "attention",
                tone: .attention,
                title: "Attention needed",
                detail: "Review the pending question before continuing."),
            flyerSnapshotFixture(
                id: "error",
                tone: .error,
                title: "Provider disconnected",
                detail: "Reconnect to continue.",
                actions: [Flyer.Action(id: "reconnect", title: "Reconnect")]),
        ],
        onAction: { _, _ in },
        onDismiss: { _ in },
        onHeightChange: { _ in })
        .environment(\.flyerMarqueeElapsedOverride, 0)
        .frame(width: 720)
}

private func flyerSnapshotFixture(
    id: String = "catch-up",
    tone: Flyer.Tone = .information,
    title: String = "3 turns finished",
    detail: String,
    actions: [Flyer.Action] = [Flyer.Action(id: "catch-up", title: "Catch up")]
) -> Flyer {
    Flyer(
        id: id,
        scope: .session("/tmp/fixture"),
        tone: tone,
        title: title,
        detail: detail,
        actions: actions,
        isDismissible: true,
        expiresAt: nil)
}

private func hasInteractiveCyanInk(
    in bitmap: NSBitmapImageRep,
    xRange: Range<Int>
) -> Bool {
    xRange.contains { x in
        (0..<bitmap.pixelsHigh).contains { y in
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                return false
            }
            return color.redComponent < 0.12
                && color.greenComponent > 0.35
                && color.blueComponent > 0.4
        }
    }
}

private func hasDarkTextInk(
    in bitmap: NSBitmapImageRep,
    xRange: Range<Int>
) -> Bool {
    xRange.contains { x in
        (0..<bitmap.pixelsHigh).contains { y in
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                return false
            }
            return color.alphaComponent > 0.8
                && color.redComponent < 0.55
                && color.greenComponent < 0.55
                && color.blueComponent < 0.55
        }
    }
}

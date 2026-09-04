import CoreGraphics
import Foundation

struct ProviderUsageDockWheelHoverGeometry: Equatable {
    private static let hoveredScale: CGFloat = 1.16
    private static let hoverAnimationDuration: TimeInterval = 0.16

    let restingDiameter: CGFloat

    var hitTargetDiameter: CGFloat {
        max(ProviderAccountStackGeometry.minimumHitTarget, restingDiameter)
    }

    func visualScale(isHovered: Bool) -> CGFloat {
        isHovered ? Self.hoveredScale : 1
    }

    func animationDuration(reduceMotion: Bool) -> TimeInterval? {
        reduceMotion ? nil : Self.hoverAnimationDuration
    }
}

struct ProviderUsageDockCompactLayout: Equatable {
    static let standalone = ProviderUsageDockCompactLayout(
        wheelDiameter: ProviderUsageDockLayout.regular54,
        trailingOffset: 0,
        bottomOffset: 0)

    let wheelDiameter: CGFloat
    let trailingOffset: CGFloat
    let bottomOffset: CGFloat
}

enum ProviderUsageDockLayout {
    static let regular54: CGFloat = 54
    /// Matches the composer's 28pt send button, which the inline row sits beside.
    static let inComposer28: CGFloat = 28
    static let spacing8: CGFloat = 8

    /// Decides whether the dock fits beside the composer at the regular
    /// wheel size or must shrink and move above it.
    ///
    /// Each dock entry measures as exactly one wheel wide: `ProviderAccountStackView`
    /// collapses to the active account at rest and fans upward on hover, so
    /// an account-routing provider never spends extra horizontal width the
    /// way the old rightward cascade did. `providerCount` is therefore
    /// sufficient input — there is no per-provider width to derive from
    /// account counts anymore.
    static func compact(
        shellWidth: CGFloat,
        contentLeadingInset: CGFloat,
        providerCount: Int,
        hasComposer: Bool
    ) -> ProviderUsageDockCompactLayout {
        guard hasComposer else {
            return .standalone
        }

        let routeWidth = max(0, shellWidth - contentLeadingInset)
        let composerWidth = min(780, max(0, routeWidth - 84))
        let trailingGutter = max(0, (routeWidth - composerWidth) / 2)
        let normalizedCount = max(0, providerCount)
        let groupWidth = normalizedCount > 0
            ? CGFloat(normalizedCount) * regular54 + CGFloat(normalizedCount - 1) * spacing8
            : 0
        let requiredGutter = groupWidth + 16 + 16

        if trailingGutter >= requiredGutter {
            return ProviderUsageDockCompactLayout(
                wheelDiameter: regular54,
                trailingOffset: 0,
                bottomOffset: 28 - 16)
        }

        // No room beside the composer, so the row moves inside it: bottom-aligned
        // with the send button (28 card inset + 10 footer inset) and 4pt to its
        // left (10 footer inset + 28 button + 4 gap). The overlay already carries
        // 16pt of trailing/bottom padding, which these offsets sit on top of.
        // ponytail: hardcoded against the composer's footer metrics, as the old
        // above-the-composer offsets were. Real fix is making the row footer
        // content; that also handles the error-message row shifting the footer up
        // and a long project name underlapping the wheels at narrow widths.
        return ProviderUsageDockCompactLayout(
            wheelDiameter: inComposer28,
            trailingOffset: trailingGutter + 42 - 16,
            bottomOffset: 28 + 10 - 16)
    }
}

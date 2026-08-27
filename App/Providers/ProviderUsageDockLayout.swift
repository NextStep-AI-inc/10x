import CoreGraphics

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
    static let constrained44: CGFloat = 44
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

        return ProviderUsageDockCompactLayout(
            wheelDiameter: constrained44,
            trailingOffset: max(0, trailingGutter - 16),
            bottomOffset: 28 + 96 + 8 - 16)
    }
}

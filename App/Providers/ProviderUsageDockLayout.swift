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
    /// Matches the composer's 28pt send button, which the inline row sits beside.
    static let inComposer28: CGFloat = 28
    static let spacing8: CGFloat = 8

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
        let groupWidth = wheelGroupWidth(providerCount: providerCount)
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

    private static func wheelGroupWidth(providerCount: Int) -> CGFloat {
        let normalizedCount = max(0, providerCount)
        guard normalizedCount > 0 else {
            return 0
        }

        return CGFloat(normalizedCount) * regular54 + CGFloat(normalizedCount - 1) * spacing8
    }
}

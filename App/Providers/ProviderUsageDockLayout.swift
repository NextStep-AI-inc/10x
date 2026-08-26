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

        return ProviderUsageDockCompactLayout(
            wheelDiameter: constrained44,
            trailingOffset: max(0, trailingGutter - 16),
            bottomOffset: 28 + 96 + 8 - 16)
    }

    private static func wheelGroupWidth(providerCount: Int) -> CGFloat {
        let normalizedCount = max(0, providerCount)
        guard normalizedCount > 0 else {
            return 0
        }

        return CGFloat(normalizedCount) * regular54 + CGFloat(normalizedCount - 1) * spacing8
    }
}

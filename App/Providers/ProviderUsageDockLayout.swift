import CoreGraphics
import Foundation
import SwiftUI

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

enum ProviderUsageDockPlacement: Equatable {
    case standalone
    case outsideComposer
    case composerFooter
}

struct ProviderUsageDockCompactLayout: Equatable {
    static let standalone = ProviderUsageDockCompactLayout(
        wheelDiameter: ProviderUsageDockLayout.regular54,
        trailingOffset: 0,
        bottomOffset: 0)

    static let outsideComposer = ProviderUsageDockCompactLayout(
        wheelDiameter: ProviderUsageDockLayout.regular54,
        trailingOffset: 0,
        bottomOffset: 28 - 16)

    let wheelDiameter: CGFloat
    let trailingOffset: CGFloat
    let bottomOffset: CGFloat
}

enum ProviderUsageDockLayout {
    static let regular54: CGFloat = 54
    /// Matches the composer's 28pt send button, which the inline row sits beside.
    static let inComposer28: CGFloat = 28

    static let spacing8: CGFloat = 8

    static func placement(
        shellWidth: CGFloat,
        contentLeadingInset: CGFloat,
        providerCount: Int,
        hasComposer: Bool
    ) -> ProviderUsageDockPlacement {
        guard hasComposer else { return .standalone }

        let routeWidth = max(0, shellWidth - contentLeadingInset)
        let composerWidth = min(780, max(0, routeWidth - 84))
        let trailingGutter = max(0, (routeWidth - composerWidth) / 2)
        let normalizedCount = max(0, providerCount)
        let groupWidth = normalizedCount > 0
            ? CGFloat(normalizedCount) * regular54
                + CGFloat(normalizedCount - 1) * spacing8
            : 0
        let requiredGutter = groupWidth + 16 + 16

        return trailingGutter >= requiredGutter
            ? .outsideComposer
            : .composerFooter
    }

    static func compact(shellSize: CGSize, footerFrame: CGRect) -> ProviderUsageDockCompactLayout {
        ProviderUsageDockCompactLayout(
            wheelDiameter: inComposer28,
            trailingOffset: shellSize.width - footerFrame.maxX - 16,
            bottomOffset: shellSize.height - footerFrame.maxY - 16)
    }

    static func footerWidth(providers: [ProviderUsageProvider]) -> CGFloat {
        guard !providers.isEmpty else { return 0 }
        return providers.reduce(CGFloat.zero) { width, provider in
            width + (provider.capability == .accountRouting
                ? ProviderAccountStackGeometry(
                    accountIDs: provider.accounts.map(\.id),
                    foregroundAccountID: nil,
                    wheelDiameter: inComposer28).width
                : ProviderUsageDockWheelHoverGeometry(restingDiameter: inComposer28).hitTargetDiameter)
        } + CGFloat(providers.count - 1) * spacing8
    }
}

private struct ComposerProviderDockWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var composerProviderDockWidth: CGFloat {
        get { self[ComposerProviderDockWidthKey.self] }
        set { self[ComposerProviderDockWidthKey.self] = newValue }
    }
}

struct ComposerProviderDockAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

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

struct ProviderUsageDockCompactLayout: Equatable {
    static let standalone = ProviderUsageDockCompactLayout(
        wheelDiameter: ProviderUsageDockLayout.regular54,
        trailingOffset: 0,
        bottomOffset: 0,
        expandedBottomOffset: 0)

    let wheelDiameter: CGFloat
    let trailingOffset: CGFloat
    let bottomOffset: CGFloat
    let expandedBottomOffset: CGFloat
}

enum ProviderUsageDockLayout {
    static let regular54: CGFloat = 54
    /// Matches the composer's 28pt send button, which the inline row sits beside.
    static let inComposer28: CGFloat = 28
    static let spacing8: CGFloat = 8

    @MainActor
    static func aboveLineBottomOffset(hasAttachments: Bool) -> CGFloat {
        162 + (hasAttachments ? ComposerAttachmentsView.stripHeight : 0)
    }

    static func placement(
        availableWidth: CGFloat,
        factsMinWidth: CGFloat,
        actionsMinWidth: CGFloat,
        providerWidth: CGFloat
    ) -> ProviderUsageDockPlacement {
        guard providerWidth > 0 else { return .belowLine }
        let horizontalMargins: CGFloat = 48
        return availableWidth >= factsMinWidth + actionsMinWidth + providerWidth + horizontalMargins
            ? .belowLine : .aboveLine
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

enum ProviderUsageDockPlacement: Equatable {
    case belowLine
    case aboveLine
}

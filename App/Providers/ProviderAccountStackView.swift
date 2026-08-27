import Foundation
import SwiftUI

struct ProviderAccountStackItemGeometry: Equatable {
    let accountID: String
    let visualDiameter: CGFloat
    let hitTargetDiameter: CGFloat
    let verticalOffset: CGFloat
    let zIndex: Double
    let accessibilityPriority: Double
    let isForeground: Bool
}

struct ProviderAccountStackVisualState: Equatable {
    let isRaised: Bool
    let isGrayscale: Bool
    let showsFocusOutline: Bool
    let elevation: CGFloat
    let zIndex: Double
    let animationDuration: TimeInterval?
}

enum ProviderAccountStackMotion {
    static func animationDuration(reduceMotion: Bool) -> TimeInterval? {
        reduceMotion ? nil : 0.16
    }
}

/// Collapsed at rest to the active account's wheel; on hover or keyboard focus
/// the remaining accounts fan upward from behind it. Background wheels overlap
/// the one below by design (`fanStepScale` < 1) so the group still reads as one
/// unit — `ProviderAccountStackView` adds a canvas-colored ring per wheel so
/// overlapping discs stay legible instead of blending, the classic
/// overlapping-avatar treatment.
struct ProviderAccountStackGeometry: Equatable {
    static let minimumHitTarget: CGFloat = 44
    static let backgroundScale: CGFloat = 0.78
    /// Fraction of `wheelDiameter` each background wheel rises above the one
    /// beneath it. Must clear more than `backgroundScale` alone would
    /// suggest: because the foreground wheel is larger, a bottom-aligned
    /// background wheel's own center sits closer to the frame's bottom edge
    /// than the foreground's does (by `(1 - backgroundScale) * wheelDiameter
    /// / 2`), so a step that only matched the size difference would still
    /// leave the nearest background wheel's activity count hidden under the
    /// foreground — confirmed by rendering it: 0.58 buried the digit inside
    /// the foreground disc, and 0.7 still let the separation ring's stroke
    /// clip it. 0.75 clears the ring with roughly 6.5pt to spare at the
    /// regular wheel size and leaves about 18% of each disc overlapped —
    /// enough to read as one group without hiding any wheel's own count.
    /// (0.34, the old rightward step, hid about two thirds of every
    /// background disc.)
    static let fanStepScale: CGFloat = 0.75
    static let raisedElevation: CGFloat = 6

    let items: [ProviderAccountStackItemGeometry]
    /// Width of the widest hit target — with the cascade now vertical this is
    /// always one wheel wide, regardless of account count.
    let width: CGFloat
    /// Height needed to show every account fully fanned out, including the
    /// raise elevation. The container reserves this height even at rest so
    /// hovering never resizes the hit-testable region — see
    /// `ProviderAccountStackView`'s single hover region.
    let expandedHeight: CGFloat
    let foregroundAccountID: String?
    let accessibilityOrderedAccountIDs: [String]

    init(
        accountIDs: [String],
        foregroundAccountID: String?,
        wheelDiameter: CGFloat
    ) {
        let foregroundID = foregroundAccountID.flatMap { candidate in
            accountIDs.contains(candidate) ? candidate : nil
        } ?? accountIDs.first
        let backgroundIDs = accountIDs.filter { $0 != foregroundID }
        let maximumBaseZIndex = Double(accountIDs.count + 1)
        let backgroundDiameter = wheelDiameter * Self.backgroundScale
        let fanStep = wheelDiameter * Self.fanStepScale

        items = accountIDs.map { accountID in
            let isForeground = accountID == foregroundID
            let backgroundIndex = backgroundIDs.firstIndex(of: accountID) ?? 0
            let visualDiameter = isForeground ? wheelDiameter : backgroundDiameter
            let hitTargetDiameter = max(Self.minimumHitTarget, visualDiameter)
            let verticalOffset = isForeground ? 0 : fanStep * CGFloat(backgroundIndex + 1)
            let baseZIndex = isForeground
                ? maximumBaseZIndex
                : maximumBaseZIndex - Double(backgroundIndex + 1)
            return ProviderAccountStackItemGeometry(
                accountID: accountID,
                visualDiameter: visualDiameter,
                hitTargetDiameter: hitTargetDiameter,
                verticalOffset: verticalOffset,
                zIndex: baseZIndex,
                accessibilityPriority: baseZIndex,
                isForeground: isForeground)
        }
        width = items.map(\.hitTargetDiameter).max() ?? wheelDiameter
        let maxVerticalOffset = items.map(\.verticalOffset).max() ?? 0
        expandedHeight = max(wheelDiameter, backgroundDiameter + maxVerticalOffset)
            + Self.raisedElevation
        self.foregroundAccountID = foregroundID
        accessibilityOrderedAccountIDs = (foregroundID.map { [$0] } ?? [])
            + backgroundIDs
    }

    /// Hover or focus raises and colorizes whichever account the pointer or
    /// focus ring is actually on, foreground included — the foreground has no
    /// special exemption here. It only wins the *base* z-order below.
    func visualState(
        for item: ProviderAccountStackItemGeometry,
        isHovered: Bool,
        isFocused: Bool,
        isGrayscale: Bool,
        reduceMotion: Bool
    ) -> ProviderAccountStackVisualState {
        let isRaised = isHovered || isFocused
        return ProviderAccountStackVisualState(
            isRaised: isRaised,
            isGrayscale: isGrayscale && !isRaised,
            showsFocusOutline: isFocused,
            elevation: isRaised ? Self.raisedElevation : 0,
            zIndex: isRaised ? Double(items.count + 2) : item.zIndex,
            animationDuration: ProviderAccountStackMotion.animationDuration(
                reduceMotion: reduceMotion))
    }
}

struct ProviderAccountStackView: View {
    let provider: ProviderUsageProvider
    let generatingCounts: [ProviderAccountKey: Int]
    let isGrayscale: Bool
    let diameter: CGFloat
    /// True for the panel's inline account selector, which always has room
    /// and always wants every account visible. False (default) is the
    /// compact dock's collapsed-at-rest, hover-to-fan behavior.
    let alwaysExpanded: Bool
    let onSelect: (ProviderUsageAccount) -> Void
    @FocusState.Binding var focusedAccountID: String?
    let visualFocusAccountID: String?
    let visualHoverAccountID: String?

    @State private var hoveredAccountID: String?
    @State private var isGroupRegionHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        provider: ProviderUsageProvider,
        generatingCounts: [ProviderAccountKey: Int],
        isGrayscale: Bool,
        diameter: CGFloat = ProviderUsageRingGeometry.diameter,
        alwaysExpanded: Bool = false,
        focusedAccountID: FocusState<String?>.Binding,
        visualFocusAccountID: String? = nil,
        visualHoverAccountID: String? = nil,
        onSelect: @escaping (ProviderUsageAccount) -> Void
    ) {
        self.provider = provider
        self.generatingCounts = generatingCounts
        self.isGrayscale = isGrayscale
        self.diameter = diameter
        self.alwaysExpanded = alwaysExpanded
        self.onSelect = onSelect
        self._focusedAccountID = focusedAccountID
        self.visualFocusAccountID = visualFocusAccountID
        self.visualHoverAccountID = visualHoverAccountID
    }

    private var geometry: ProviderAccountStackGeometry {
        ProviderAccountStackGeometry(
            accountIDs: provider.accounts.map(\.id),
            foregroundAccountID: provider.accounts.first(where: {
                $0.accountRef == provider.foregroundAccountRef
            })?.id,
            wheelDiameter: diameter)
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                ForEach(provider.accounts) { account in
                    if let item = geometry.items.first(where: { $0.accountID == account.id }) {
                        accountButton(account, item: item)
                    }
                }
            }
            .animation(stackAnimation, value: geometry)
            .animation(stackAnimation, value: isGroupExpanded)
            .frame(
                width: geometry.width,
                height: geometry.expandedHeight,
                alignment: .bottom)
            // One hover region for the whole reserved footprint, sized for
            // the fully-expanded stack even at rest, so moving the pointer
            // up toward a background account never crosses a gap that would
            // collapse the group out from under the cursor.
            .contentShape(Rectangle())
            .onHover { isHovered in
                isGroupRegionHovered = isHovered
            }

            Text(provider.abbreviation)
                .font(TenXTypography.mono(size: 9, weight: .semibold))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .accessibilityHidden(true)
        }
    }

    private var isGroupExpanded: Bool {
        if alwaysExpanded { return true }
        if isGroupRegionHovered { return true }
        if let hoveredAccountID, belongsToGroup(hoveredAccountID) { return true }
        if let visualHoverAccountID, belongsToGroup(visualHoverAccountID) { return true }
        let effectiveFocusID = visualFocusAccountID ?? focusedAccountID
        if let effectiveFocusID, belongsToGroup(effectiveFocusID) { return true }
        return false
    }

    private func belongsToGroup(_ accountID: String) -> Bool {
        provider.accounts.contains { $0.id == accountID }
    }

    private func accountButton(
        _ account: ProviderUsageAccount,
        item: ProviderAccountStackItemGeometry
    ) -> some View {
        let accountProvider = providerPresentingOnly(account)
        let activeCount = generatingCount(for: account)
        let isHovered = (visualHoverAccountID ?? hoveredAccountID) == account.id
        let isFocused = (visualFocusAccountID ?? focusedAccountID) == account.id
        let visualState = geometry.visualState(
            for: item,
            isHovered: isHovered,
            isFocused: isFocused,
            isGrayscale: isGrayscale,
            reduceMotion: reduceMotion)
        let fanOffset = isGroupExpanded ? item.verticalOffset : 0
        let totalOffset = fanOffset + visualState.elevation
        let showsSeparationRing = isGroupExpanded && geometry.items.count > 1

        return Button {
            onSelect(account)
        } label: {
            ProviderUsageWheelView(
                provider: accountProvider,
                activeCount: activeCount,
                isGrayscale: visualState.isGrayscale,
                diameter: item.visualDiameter,
                showsProviderLabel: false,
                presentationMode: .account(account.usageState))
                .frame(
                    width: item.hitTargetDiameter,
                    height: item.hitTargetDiameter)
                .contentShape(Rectangle())
                .overlay {
                    if showsSeparationRing {
                        Circle()
                            .stroke(
                                TenXPalette.color(TenXPalette.canvasHex),
                                lineWidth: 2)
                            .frame(width: item.visualDiameter, height: item.visualDiameter)
                    }
                }
                .overlay {
                    if visualState.showsFocusOutline {
                        Circle()
                            .stroke(
                                TenXPalette.color(TenXPalette.interactiveCyanHex),
                                lineWidth: 2)
                            .frame(
                                width: item.hitTargetDiameter - 2,
                                height: item.hitTargetDiameter - 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if item.isForeground, showsBadge {
                        countBadge
                            .offset(x: -2, y: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .focused($focusedAccountID, equals: account.id)
        .onHover { isHovered in
            if isHovered {
                hoveredAccountID = account.id
            } else if hoveredAccountID == account.id {
                hoveredAccountID = nil
            }
        }
        .offset(y: -totalOffset)
        .zIndex(visualState.zIndex)
        .animation(
            visualState.animationDuration.map { .easeInOut(duration: $0) },
            value: visualState.isRaised)
        .accessibilityLabel("\(provider.name), \(account.label)")
        .accessibilityValue(ProviderUsageAccessibility.wheelValue(
            provider: accountProvider,
            activeCount: activeCount))
        .accessibilitySortPriority(item.accessibilityPriority)
    }

    private var otherAccountsCount: Int {
        max(0, provider.accounts.count - 1)
    }

    /// Rest-only: the fanned-out wheels already show each account's own
    /// activity once expanded, so the badge steps aside rather than doubling
    /// the signal.
    private var showsBadge: Bool {
        otherAccountsCount > 0 && !isGroupExpanded
    }

    /// Ignores `isGrayscale` on purpose, matching `ProviderUsageWheelView`'s
    /// activity core: the generating-session signal stays legible even while
    /// the open chat's own turn state greys out the decorative usage rings.
    private var isBadgeLive: Bool {
        provider.accounts.contains { account in
            account.id != geometry.foregroundAccountID && generatingCount(for: account) > 0
        }
    }

    @ViewBuilder
    private var countBadge: some View {
        Text("+\(otherAccountsCount)")
            .font(TenXTypography.mono(size: 9, weight: .semibold))
            .foregroundStyle(isBadgeLive
                ? Color.white
                : TenXPalette.color(TenXPalette.mutedTextHex))
            .padding(.horizontal, 4)
            .frame(minWidth: 15, minHeight: 15)
            .background(
                Capsule().fill(isBadgeLive
                    ? TenXPalette.color(TenXPalette.cyanHex)
                    : TenXPalette.color(TenXPalette.separatorHex)))
            .overlay(
                Capsule().stroke(TenXPalette.color(TenXPalette.canvasHex), lineWidth: 1.5))
            // Every account behind this badge is already individually
            // focusable in the accessibility order; the badge would only
            // repeat that count, not add information.
            .accessibilityHidden(true)
    }

    private var stackAnimation: Animation? {
        ProviderAccountStackMotion.animationDuration(reduceMotion: reduceMotion)
            .map { .easeInOut(duration: $0) }
    }

    private func generatingCount(for account: ProviderUsageAccount) -> Int {
        guard let accountRef = account.accountRef else { return 0 }
        return generatingCounts[ProviderAccountKey(
            providerID: provider.id,
            accountRef: accountRef)] ?? 0
    }

    private func providerPresentingOnly(
        _ account: ProviderUsageAccount
    ) -> ProviderUsageProvider {
        ProviderUsageProvider(
            id: provider.id,
            name: provider.name,
            accounts: [account],
            capability: provider.capability,
            foregroundAccountRef: account.accountRef)
    }
}

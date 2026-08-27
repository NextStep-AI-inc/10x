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
    let currentDiameter: CGFloat
    let isGrayscale: Bool
    let showsFocusOutline: Bool
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
///
/// Hover or focus is a preview of "what if this were the active account":
/// whichever account is raised takes the full foreground diameter, and every
/// other account — including the one that is normally foreground — drops to
/// background diameter and dims for as long as the raise lasts. Every wheel
/// grows or shrinks around its own fixed resting center; position and rank
/// never change, only size, color, and z-index do.
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
    /// background disc.) This constant governs rank spacing only — it is
    /// unrelated to the hover-grow sizing below.
    static let fanStepScale: CGFloat = 0.75
    /// Fraction of `wheelDiameter` for the canvas-colored separation ring's
    /// width, drawn fully OUTSIDE each disc's own edge (see
    /// `ProviderAccountStackView`'s separation-ring overlay and badge ring).
    /// A SwiftUI `.stroke` centers on its path, so a ring merely framed at
    /// the disc's own diameter only puts half its width outside the disc —
    /// the other half eats into the disc's own drawn area, leaving an
    /// effective gap of about a point that reads as a scratch, not a
    /// separation, once magnified. Chosen by rendering: 0.035 (~1.9pt at
    /// the regular wheel size) was legible but still thin against two light
    /// grey discs; 0.045 (~2.4pt) is the smallest that reads as an
    /// unmistakable, deliberate band at native size. `fanStepScale` above
    /// still clears it with roughly 5pt to spare (checked by extending the
    /// same clearance math this round, then confirmed by rendering) because
    /// the foreground's own ring, now extending outward instead of inward,
    /// covers slightly more of whatever sits behind it than the disc alone
    /// did.
    static let separationRingScale: CGFloat = 0.045

    let items: [ProviderAccountStackItemGeometry]
    /// Width of the widest hit target — with the cascade now vertical this is
    /// always one wheel wide, regardless of account count. Also always wide
    /// enough for any single item to grow to `wheelDiameter` on raise, since
    /// the foreground's own hit target already established that width.
    let width: CGFloat
    /// Height needed for whichever single account is raised to grow to full
    /// `wheelDiameter` around its own fixed resting center, at every rank.
    /// The container reserves this height even at rest so hovering never
    /// resizes the hit-testable region — see `ProviderAccountStackView`'s
    /// single hover region.
    let expandedHeight: CGFloat
    let wheelDiameter: CGFloat
    let backgroundDiameter: CGFloat
    let separationRingWidth: CGFloat
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
        let separationRingWidth = wheelDiameter * Self.separationRingScale

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
        // The separation ring renders fully outside each disc's edge (see
        // ProviderAccountStackView), so the widest and tallest a raised
        // item's disc-plus-ring can reach is `ringWidth` beyond its own
        // diameter in every radial direction — but only providers with more
        // than one account ever show a ring at all (matching
        // `showsSeparationRing`'s own condition below). Reserving space for
        // it unconditionally would grow every single-account provider's
        // column by the same amount for a ring that geometry can never draw
        // there, which is exactly what silently shifted three unrelated
        // full-shell references (single-account dock providers, narrow
        // windows) the first time this was tried unconditionally.
        let ringReserve = accountIDs.count > 1 ? separationRingWidth : 0
        width = (items.map(\.hitTargetDiameter).max() ?? wheelDiameter)
            + 2 * ringReserve
        // Whichever item has the highest resting center is the one that, if
        // raised, needs the most headroom above it — always the
        // topmost-ranked background item when one exists.
        let topRestingCenter = items
            .map { $0.verticalOffset + $0.visualDiameter / 2 }
            .max() ?? wheelDiameter / 2
        // `raiseClearance` lifts the topmost wheel by a further half growth
        // beyond what raising it in place would have needed — whether it is
        // itself the raised wheel (up by half the growth, at `wheelDiameter`)
        // or sits above one (up by all of it, at `backgroundDiameter`). Both
        // land on the same top edge, so one half-growth of headroom covers
        // every case. Gated on having something to raise for the same reason
        // `ringReserve` is: a single-account provider can never raise a wheel,
        // and reserving the headroom anyway would grow its column for a state
        // it cannot reach.
        let raiseHeadroom = accountIDs.count > 1
            ? (wheelDiameter - backgroundDiameter) / 2
            : 0
        expandedHeight = topRestingCenter + wheelDiameter / 2 + raiseHeadroom + ringReserve
        self.wheelDiameter = wheelDiameter
        self.backgroundDiameter = backgroundDiameter
        self.separationRingWidth = separationRingWidth
        self.foregroundAccountID = foregroundID
        accessibilityOrderedAccountIDs = (foregroundID.map { [$0] } ?? [])
            + backgroundIDs
    }

    /// `isRaised` and `isAnyItemRaised` are resolved by the caller (which
    /// sees every item's hover/focus state at once and picks at most one
    /// winner) rather than computed here from this item's own hover/focus
    /// booleans alone — this item's size depends on whether a *different*
    /// item is raised, which this function has no way to know on its own.
    func visualState(
        for item: ProviderAccountStackItemGeometry,
        isRaised: Bool,
        isAnyItemRaised: Bool,
        showsFocusOutline: Bool,
        isGrayscale: Bool,
        reduceMotion: Bool
    ) -> ProviderAccountStackVisualState {
        let currentDiameter: CGFloat
        if isRaised {
            currentDiameter = wheelDiameter
        } else if isAnyItemRaised {
            currentDiameter = backgroundDiameter
        } else {
            currentDiameter = item.visualDiameter
        }
        return ProviderAccountStackVisualState(
            isRaised: isRaised,
            currentDiameter: currentDiameter,
            isGrayscale: isRaised ? false : (isGrayscale || isAnyItemRaised),
            showsFocusOutline: showsFocusOutline,
            zIndex: isRaised ? Double(items.count + 2) : item.zIndex,
            animationDuration: ProviderAccountStackMotion.animationDuration(
                reduceMotion: reduceMotion))
    }

    /// How far `item` steps up so a raised wheel keeps both of its seams.
    ///
    /// Growing a wheel around its own center spends half the growth upward and
    /// half downward, so a raised wheel eats into the neighbour on each side.
    /// That collapses seams `fanStepScale` sized to about a quarter diameter
    /// down to a few points, and the sliver left of each neighbour reads as
    /// some hidden disc rather than as two wheels meeting. Instead the raised
    /// wheel grows from its own lower edge: it moves up by half the growth so
    /// that edge stays put, and the wheels ranked above it move up by all of
    /// it. The seam above is preserved because both of its wheels moved
    /// together. Below, the wheel in front dims to `backgroundDiameter` at the
    /// same moment, so holding the raised wheel's lower edge still opens that
    /// seam rather than closing it — which is the point, since at rest those
    /// two overlap by design and it is the overlap, not a gap, that turns
    /// muddy once one of them is colorized.
    ///
    /// Anchoring at the lower edge also keeps hover stable — the raised wheel
    /// only ever expands into space above the pointer, so the area under the
    /// pointer strictly grows and can never slide out from under it.
    func raiseClearance(
        for item: ProviderAccountStackItemGeometry,
        raisedAccountID: String?
    ) -> CGFloat {
        guard let raisedAccountID,
            let raised = items.first(where: { $0.accountID == raisedAccountID })
        else { return 0 }
        // Zero when the raised wheel is already the foreground: it renders at
        // `wheelDiameter` at rest, so raising it grows nothing.
        let growth = wheelDiameter - raised.visualDiameter
        if item.accountID == raisedAccountID { return growth / 2 }
        return item.verticalOffset > raised.verticalOffset ? growth : 0
    }

    /// Vertical offset from the group's bottom edge to render `item` at,
    /// given whatever diameter it currently is (resting, raised, or
    /// dimmed). This is the whole "grow in place" contract in one formula:
    /// `item`'s own resting diameter and rank fix a `restingCenter` that
    /// never changes, and the returned offset is solved so that
    /// `offset + currentDiameter / 2 == restingCenter + clearance` always —
    /// proven by `ProviderAccountStackTests`. Growing or shrinking only ever
    /// changes how far the item's edges sit from that center, never the
    /// center itself, so a raised or dimmed wheel cannot reorder. The only
    /// thing that moves a center is `raiseClearance`, which steps the wheels
    /// above a raised one out of its way and is zero for every other wheel.
    func renderedOffset(
        for item: ProviderAccountStackItemGeometry,
        currentDiameter: CGFloat,
        isExpanded: Bool,
        raisedAccountID: String? = nil
    ) -> CGFloat {
        guard isExpanded else { return 0 }
        let restingCenter = item.verticalOffset + item.visualDiameter / 2
        let clearance = raiseClearance(for: item, raisedAccountID: raisedAccountID)
        return restingCenter + clearance - currentDiameter / 2
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
    @State private var isBadgeRegionHovered = false
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

    private var effectiveHoverID: String? { visualHoverAccountID ?? hoveredAccountID }
    private var effectiveFocusID: String? { visualFocusAccountID ?? focusedAccountID }

    /// At most one account is ever "raised" at a time. Hover wins over focus
    /// when they point at two different accounts simultaneously (e.g. Tab
    /// landed on one account while the pointer sits over another) — the
    /// pointer is the more immediate signal for "what if this were active,"
    /// while focus keeps its own outline regardless of which one wins here.
    private var raisedAccountID: String? { effectiveHoverID ?? effectiveFocusID }

    private var isGroupExpanded: Bool {
        if alwaysExpanded { return true }
        if isGroupRegionHovered { return true }
        if isBadgeRegionHovered { return true }
        if let effectiveHoverID, belongsToGroup(effectiveHoverID) { return true }
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
        let isRaised = account.id == raisedAccountID
        let isAnyItemRaised = raisedAccountID != nil
        let showsFocusOutline = account.id == effectiveFocusID
        let visualState = geometry.visualState(
            for: item,
            isRaised: isRaised,
            isAnyItemRaised: isAnyItemRaised,
            showsFocusOutline: showsFocusOutline,
            isGrayscale: isGrayscale,
            reduceMotion: reduceMotion)
        let totalOffset = geometry.renderedOffset(
            for: item,
            currentDiameter: visualState.currentDiameter,
            isExpanded: isGroupExpanded,
            raisedAccountID: raisedAccountID)
        let currentHitTarget = max(
            ProviderAccountStackGeometry.minimumHitTarget,
            visualState.currentDiameter)
        let showsSeparationRing = isGroupExpanded && geometry.items.count > 1

        return Button {
            onSelect(account)
        } label: {
            ProviderUsageWheelView(
                provider: accountProvider,
                activeCount: activeCount,
                isGrayscale: visualState.isGrayscale,
                diameter: visualState.currentDiameter,
                showsProviderLabel: false,
                presentationMode: .account(account.usageState))
                .frame(
                    width: currentHitTarget,
                    height: currentHitTarget)
                // A circle, not the full square, so the badge's corner
                // (outside the inscribed circle by construction) never
                // falls inside this button's own hit-test — see
                // `badgeHoverRegion` below for what handles that corner.
                .contentShape(Circle())
                .overlay {
                    if showsSeparationRing {
                        // Framed at diameter-plus-ring-width, not at the
                        // disc's own diameter: `.stroke` centers on its
                        // path, so framing it at the disc's exact size
                        // would spend half the stroke eating into the
                        // disc's own drawn area, leaving only the other
                        // half as visible separation from whatever
                        // overlaps it. This puts the ring's inner edge
                        // exactly at the disc's boundary and its full
                        // width outside it.
                        Circle()
                            .stroke(
                                TenXPalette.color(TenXPalette.canvasHex),
                                lineWidth: geometry.separationRingWidth)
                            .frame(
                                width: visualState.currentDiameter
                                    + geometry.separationRingWidth,
                                height: visualState.currentDiameter
                                    + geometry.separationRingWidth)
                    }
                }
                .overlay {
                    if visualState.showsFocusOutline {
                        Circle()
                            .stroke(
                                TenXPalette.color(TenXPalette.interactiveCyanHex),
                                lineWidth: 2)
                            .frame(
                                width: currentHitTarget - 2,
                                height: currentHitTarget - 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if item.isForeground, otherAccountsCount > 0 {
                        badgeHoverRegion
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
            value: visualState)
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

    /// Pointing at the badge means "show me the other accounts," exactly
    /// like pointing at the wheel — it expands the group. It must NOT also
    /// promote the foreground wheel as though that one account were
    /// individually hovered, so it drives `isBadgeRegionHovered` only, never
    /// `hoveredAccountID`.
    ///
    /// This wrapper stays in the tree whenever the provider has other
    /// accounts, regardless of whether the badge is currently drawn —
    /// `showsBadge` flips to false in the very same state change that
    /// `isBadgeRegionHovered` triggers (hovering the badge expands the
    /// group, which hides the badge), so a view that only existed while
    /// `showsBadge` was true would be removed before it could ever report
    /// its own hover exiting, leaving `isBadgeRegionHovered` stuck true and
    /// the group permanently unable to collapse again.
    @ViewBuilder
    private var badgeHoverRegion: some View {
        Group {
            if showsBadge {
                countBadge
            } else {
                Color.clear.frame(minWidth: 15, minHeight: 15)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered in
            isBadgeRegionHovered = isHovered
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
            // Same canvas-colored ring treatment as the wheels get from each
            // other, and the same width — the badge overlaps the active
            // wheel exactly like an overlapping background wheel would, so
            // it needs the same separation to read as its own object rather
            // than a bite taken out of the wheel. A neutral badge's fill
            // (separatorHex) is close in value to the wheel's own track
            // grey, so this ring is the only thing establishing the edge.
            // Negative padding (not a same-size overlay) for the same
            // reason as the wheel's own ring: `.stroke` centers on its
            // path, so a same-size overlay would spend half the stroke
            // eating into the badge's own fill instead of separating it
            // from whatever is behind it.
            .overlay(
                Capsule()
                    .stroke(
                        TenXPalette.color(TenXPalette.canvasHex),
                        lineWidth: geometry.separationRingWidth)
                    .padding(-geometry.separationRingWidth / 2))
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

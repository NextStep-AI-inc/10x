import Foundation
import SwiftUI

struct ProviderAccountStackItemGeometry: Equatable {
    let accountID: String
    let visualDiameter: CGFloat
    let hitTargetDiameter: CGFloat
    let xOffset: CGFloat
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

struct ProviderAccountStackGeometry: Equatable {
    static let minimumHitTarget: CGFloat = 44
    static let backgroundScale: CGFloat = 0.78
    static let cascadeStepScale: CGFloat = 0.34
    static let raisedElevation: CGFloat = 6

    let items: [ProviderAccountStackItemGeometry]
    let width: CGFloat
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
        let cascadeStep = wheelDiameter * Self.cascadeStepScale

        items = accountIDs.map { accountID in
            let isForeground = accountID == foregroundID
            let backgroundIndex = backgroundIDs.firstIndex(of: accountID) ?? 0
            let visualDiameter = isForeground ? wheelDiameter : backgroundDiameter
            let hitTargetDiameter = max(Self.minimumHitTarget, visualDiameter)
            let xOffset = isForeground ? 0 : cascadeStep * CGFloat(backgroundIndex + 1)
            let baseZIndex = isForeground
                ? maximumBaseZIndex
                : maximumBaseZIndex - Double(backgroundIndex + 1)
            return ProviderAccountStackItemGeometry(
                accountID: accountID,
                visualDiameter: visualDiameter,
                hitTargetDiameter: hitTargetDiameter,
                xOffset: xOffset,
                zIndex: baseZIndex,
                accessibilityPriority: baseZIndex,
                isForeground: isForeground)
        }
        width = items.map { $0.xOffset + $0.hitTargetDiameter }.max() ?? 0
        accessibilityOrderedAccountIDs = (foregroundID.map { [$0] } ?? [])
            + backgroundIDs
    }

    func visualState(
        for item: ProviderAccountStackItemGeometry,
        isHovered: Bool,
        isFocused: Bool,
        isGrayscale: Bool,
        reduceMotion: Bool
    ) -> ProviderAccountStackVisualState {
        let isRaised = !item.isForeground && (isHovered || isFocused)
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
    let onSelect: (ProviderUsageAccount) -> Void
    @FocusState.Binding var focusedAccountID: String?
    let visualFocusAccountID: String?

    @State private var hoveredAccountID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        provider: ProviderUsageProvider,
        generatingCounts: [ProviderAccountKey: Int],
        isGrayscale: Bool,
        diameter: CGFloat = ProviderUsageRingGeometry.diameter,
        focusedAccountID: FocusState<String?>.Binding,
        visualFocusAccountID: String? = nil,
        onSelect: @escaping (ProviderUsageAccount) -> Void
    ) {
        self.provider = provider
        self.generatingCounts = generatingCounts
        self.isGrayscale = isGrayscale
        self.diameter = diameter
        self.onSelect = onSelect
        self._focusedAccountID = focusedAccountID
        self.visualFocusAccountID = visualFocusAccountID
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
            ZStack(alignment: .bottomLeading) {
                ForEach(provider.accounts) { account in
                    if let item = geometry.items.first(where: { $0.accountID == account.id }) {
                        accountButton(account, item: item)
                    }
                }
            }
            .animation(stackAnimation, value: geometry)
            .frame(
                width: geometry.width,
                height: diameter + ProviderAccountStackGeometry.raisedElevation,
                alignment: .bottomLeading)

            Text(provider.abbreviation)
                .font(TenXTypography.mono(size: 9, weight: .semibold))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .accessibilityHidden(true)
        }
    }

    private func accountButton(
        _ account: ProviderUsageAccount,
        item: ProviderAccountStackItemGeometry
    ) -> some View {
        let accountProvider = providerPresentingOnly(account)
        let activeCount = generatingCount(for: account)
        let visualState = geometry.visualState(
            for: item,
            isHovered: hoveredAccountID == account.id,
            isFocused: (visualFocusAccountID ?? focusedAccountID) == account.id,
            isGrayscale: isGrayscale,
            reduceMotion: reduceMotion)

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
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .focused($focusedAccountID, equals: account.id)
        .onHover { isHovered in
            hoveredAccountID = isHovered ? account.id : nil
        }
        .offset(x: item.xOffset, y: -visualState.elevation)
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

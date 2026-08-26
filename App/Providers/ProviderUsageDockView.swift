import SwiftUI

struct ProviderUsageDockView: View {
    static let compactWheelSpacing: CGFloat = 8

    let providers: [ProviderUsageProvider]
    let activeCounts: [String: Int]
    let isForegroundGenerating: Bool
    let compactLayout: ProviderUsageDockCompactLayout

    @State private var selectedProviderID: String?
    @State private var focusRestoration = ProviderUsageDockFocusRestorationCoordinator()
    @FocusState private var compactFocusedProviderID: String?
    @FocusState private var expandedFocusedProviderID: String?
    @Namespace private var expansionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        providers: [ProviderUsageProvider],
        activeCounts: [String: Int],
        isForegroundGenerating: Bool,
        compactLayout: ProviderUsageDockCompactLayout = .standalone,
        initiallySelectedProviderID: String? = nil
    ) {
        self.providers = providers
        self.activeCounts = activeCounts
        self.isForegroundGenerating = isForegroundGenerating
        self.compactLayout = compactLayout
        _selectedProviderID = State(initialValue: providers.contains(where: {
            $0.id == initiallySelectedProviderID
        }) ? initiallySelectedProviderID : nil)
    }

    var body: some View {
        Group {
            if let provider = selectedProvider {
                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: collapse)

                    expandedPanel(provider)
                        .transition(reduceMotion ? .opacity : .identity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            } else {
                collapsedDock
                    .padding(.trailing, compactLayout.trailingOffset)
                    .padding(.bottom, compactLayout.bottomOffset)
            }
        }
        .onExitCommand(perform: collapse)
    }

    private var selectedProvider: ProviderUsageProvider? {
        providers.first(where: { $0.id == selectedProviderID })
    }

    private var collapsedDock: some View {
        HStack(alignment: .bottom, spacing: Self.compactWheelSpacing) {
            ForEach(providers) { provider in
                compactProviderButton(
                    provider,
                    isGrayscale: isForegroundGenerating,
                    diameter: compactLayout.wheelDiameter)
            }
        }
        .onAppear(perform: restoreCompactFocusIfNeeded)
    }

    private func expandedPanel(_ provider: ProviderUsageProvider) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(providers) { candidate in
                    expandedProviderButton(
                        candidate,
                        isGrayscale: false,
                        diameter: ProviderUsageRingGeometry.diameter)
                }
            }

            Rectangle()
                .fill(TenXPalette.color(TenXPalette.separatorHex))
                .frame(height: 1)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(provider.name)
                    .font(TenXTypography.accent(size: 19))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                Spacer(minLength: 8)
                Text(activeSessionText(for: provider))
                    .font(TenXTypography.body(size: 12))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(provider.accounts) { account in
                        accountSection(
                            account,
                            provider: provider,
                            showsAccountLabel: provider.accounts.count > 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            Button("Close usage details", action: collapse)
                .buttonStyle(GhostActionStyle())
                .accessibilityLabel("Close usage details")
        }
        .padding(16)
        .frame(width: 360)
        .frame(maxHeight: 440, alignment: .bottom)
        .background(TenXPalette.color(TenXPalette.canvasHex))
        .overlay {
            Rectangle()
                .stroke(TenXPalette.color(TenXPalette.separatorHex), lineWidth: 1)
        }
    }

    private func providerButton(
        _ provider: ProviderUsageProvider,
        isGrayscale: Bool,
        diameter: CGFloat
    ) -> some View {
        Button {
            select(provider)
        } label: {
            providerWheel(provider, isGrayscale: isGrayscale, diameter: diameter)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .accessibilityLabel(provider.name)
        .accessibilityValue(ProviderUsageAccessibility.wheelValue(
            provider: provider,
            activeCount: activeCounts[provider.id] ?? 0))
    }

    private func compactProviderButton(
        _ provider: ProviderUsageProvider,
        isGrayscale: Bool,
        diameter: CGFloat
    ) -> some View {
        providerButton(provider, isGrayscale: isGrayscale, diameter: diameter)
            .focused($compactFocusedProviderID, equals: provider.id)
    }

    private func expandedProviderButton(
        _ provider: ProviderUsageProvider,
        isGrayscale: Bool,
        diameter: CGFloat
    ) -> some View {
        providerButton(provider, isGrayscale: isGrayscale, diameter: diameter)
            .focused($expandedFocusedProviderID, equals: provider.id)
    }

    @ViewBuilder
    private func providerWheel(
        _ provider: ProviderUsageProvider,
        isGrayscale: Bool,
        diameter: CGFloat
    ) -> some View {
        let wheel = ProviderUsageWheelView(
            provider: provider,
            activeCount: activeCounts[provider.id] ?? 0,
            isGrayscale: isGrayscale,
            diameter: diameter)

        if !reduceMotion {
            wheel.matchedGeometryEffect(
                id: "usage-wheel-\(provider.id)",
                in: expansionNamespace,
                isSource: selectedProviderID == nil || provider.id != selectedProviderID)
        } else {
            wheel
        }
    }

    private func accountSection(
        _ account: ProviderUsageAccount,
        provider: ProviderUsageProvider,
        showsAccountLabel: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsAccountLabel {
                Text(account.label)
                    .font(TenXTypography.body(size: 13, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
            }

            ForEach(account.limits) { limit in
                ProviderUsageLimitDetailView(
                    providerName: provider.name,
                    accountName: account.label,
                    limit: limit)
            }
        }
    }

    private func activeSessionText(for provider: ProviderUsageProvider) -> String {
        switch activeCounts[provider.id] ?? 0 {
        case ...0:
            "No active sessions"
        case 1:
            "1 active session"
        default:
            "\(activeCounts[provider.id] ?? 0) active sessions"
        }
    }

    private func select(_ provider: ProviderUsageProvider) {
        applySelection(provider.id)
        Task { @MainActor in
            await Task.yield()
            expandedFocusedProviderID = provider.id
        }
    }

    private func collapse() {
        guard let providerID = selectedProviderID else { return }
        focusRestoration.scheduleReturn(to: providerID)
        expandedFocusedProviderID = nil
        applySelection(nil)
    }

    private func restoreCompactFocusIfNeeded() {
        Task { @MainActor in
            await focusRestoration.restoreAfterCompactMount { providerID in
                compactFocusedProviderID = providerID
            }
        }
    }

    private func applySelection(_ providerID: String?) {
        guard reduceMotion else {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedProviderID = providerID
            }
            return
        }
        selectedProviderID = providerID
    }
}

@MainActor
final class ProviderUsageDockFocusRestorationCoordinator {
    private var pendingProviderID: String?

    func scheduleReturn(to providerID: String) {
        pendingProviderID = providerID
    }

    func restoreAfterCompactMount(_ assignCompactFocus: (String) -> Void) async {
        await Task.yield()
        guard let providerID = pendingProviderID else { return }
        pendingProviderID = nil
        assignCompactFocus(providerID)
    }
}

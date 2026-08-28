import Observation
import SwiftUI

enum ProviderUsageDockExpansionMotion: Equatable {
    case matchedGeometry
    case identity

    static func mode(reduceMotion: Bool) -> Self {
        reduceMotion ? .identity : .matchedGeometry
    }
}

struct ProviderUsageDockRoutingEligibility {
    static func canSwitch(
        _ account: ProviderUsageAccount,
        providerID: String,
        pendingRemovalAccounts: Set<ProviderAccountKey>
    ) -> Bool {
        guard account.availability != .unavailable,
              let accountRef = account.accountRef
        else { return false }
        return !pendingRemovalAccounts.contains(ProviderAccountKey(
            providerID: providerID,
            accountRef: accountRef))
    }
}

struct ProviderUsageDockPresentation {
    static func expandedProvider(
        _ provider: ProviderUsageProvider,
        inspectedAccount: ProviderUsageAccount
    ) -> ProviderUsageProvider {
        ProviderUsageProvider(
            id: provider.id,
            name: provider.name,
            accounts: provider.accounts,
            capability: provider.capability,
            foregroundAccountRef: inspectedAccount.accountRef)
    }
}

@MainActor
@Observable
final class ProviderUsageDockInteraction {
    private(set) var inspectedProviderID: String?
    private(set) var inspectedAccountID: String?
    private(set) var isShowingConfirmation: Bool
    private(set) var selectedScope: ProviderAccountScopeOption

    @ObservationIgnored private let onUseAccount: (String, ProviderAccountScope) -> Void
    @ObservationIgnored private let focusRestoration = ProviderUsageDockFocusRestorationCoordinator()

    init(
        initiallyInspectedProviderID: String? = nil,
        initiallyInspectedAccountID: String? = nil,
        initiallyShowsConfirmation: Bool = false,
        initiallySelectedScope: ProviderAccountScopeOption = .thisSession,
        onUseAccount: @escaping (String, ProviderAccountScope) -> Void
    ) {
        inspectedProviderID = initiallyInspectedProviderID
        inspectedAccountID = initiallyInspectedAccountID
        isShowingConfirmation = initiallyShowsConfirmation
            && initiallyInspectedProviderID != nil
            && initiallyInspectedAccountID != nil
        selectedScope = initiallySelectedScope
        self.onUseAccount = onUseAccount
    }

    func inspect(providerID: String, accountID: String) {
        inspectedProviderID = providerID
        inspectedAccountID = accountID
        isShowingConfirmation = false
    }

    func inspectProvider(providerID: String) {
        inspectedProviderID = providerID
        inspectedAccountID = nil
        isShowingConfirmation = false
    }

    func beginConfirmation(satisfaction: ProviderAccountScopeSatisfaction) {
        guard inspectedAccountID != nil,
              let firstUnsatisfiedScope = satisfaction.firstUnsatisfiedScope
        else { return }
        selectedScope = firstUnsatisfiedScope
        isShowingConfirmation = true
    }

    func selectScope(
        _ scope: ProviderAccountScopeOption,
        satisfaction: ProviderAccountScopeSatisfaction
    ) {
        guard !satisfaction.isSatisfied(scope) else { return }
        selectedScope = scope
    }

    func cancelConfirmation() {
        isShowingConfirmation = false
    }

    func confirm(
        accountRef: String,
        satisfaction: ProviderAccountScopeSatisfaction
    ) {
        guard isShowingConfirmation,
              !satisfaction.isSatisfied(selectedScope)
        else { return }
        onUseAccount(accountRef, selectedScope.routingScope)
        dismiss()
    }

    func dismiss() {
        guard let inspectedProviderID else { return }
        focusRestoration.scheduleReturn(to: inspectedAccountID ?? inspectedProviderID)
        clearInspection()
    }

    func openSessionDidChange() {
        clearInspection()
    }

    func restoreFocusAfterCompactMount(_ assignFocus: (String) -> Void) async {
        await focusRestoration.restoreAfterCompactMount(assignFocus)
    }

    private func clearInspection() {
        inspectedProviderID = nil
        inspectedAccountID = nil
        isShowingConfirmation = false
    }
}

struct ProviderUsageDockView: View {
    static let compactWheelSpacing: CGFloat = 8

    let providers: [ProviderUsageProvider]
    let activeCounts: [String: Int]
    let generatingCounts: [ProviderAccountKey: Int]
    let isForegroundGenerating: Bool
    let compactLayout: ProviderUsageDockCompactLayout
    let accountScopeSatisfaction: [ProviderAccountKey: ProviderAccountScopeSatisfaction]
    let pendingRemovalAccounts: Set<ProviderAccountKey>
    let requiresRestartToSwitch: Bool
    let activeSessionIdentityToken: UUID?
    let visualFocusAccountID: String?
    let onManageAccounts: (String) -> Void

    @State private var interaction: ProviderUsageDockInteraction
    @FocusState private var compactFocusedSelectorID: String?
    @FocusState private var expandedFocusedSelectorID: String?
    @Namespace private var expansionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        providers: [ProviderUsageProvider],
        activeCounts: [String: Int],
        generatingCounts: [ProviderAccountKey: Int] = [:],
        isForegroundGenerating: Bool = false,
        compactLayout: ProviderUsageDockCompactLayout = .standalone,
        accountScopeSatisfaction: [ProviderAccountKey: ProviderAccountScopeSatisfaction] = [:],
        pendingRemovalAccounts: Set<ProviderAccountKey> = [],
        requiresRestartToSwitch: Bool = false,
        activeSessionIdentityToken: UUID? = nil,
        visualFocusAccountID: String? = nil,
        initiallySelectedProviderID: String? = nil,
        initiallyInspectedAccountID: String? = nil,
        initiallyShowsConfirmation: Bool = false,
        onUseAccount: @escaping (String, ProviderAccountScope) -> Void = { _, _ in },
        onManageAccounts: @escaping (String) -> Void = { _ in }
    ) {
        self.providers = providers
        self.activeCounts = activeCounts
        self.generatingCounts = generatingCounts
        self.isForegroundGenerating = isForegroundGenerating
        self.compactLayout = compactLayout
        self.accountScopeSatisfaction = accountScopeSatisfaction
        self.pendingRemovalAccounts = pendingRemovalAccounts
        self.requiresRestartToSwitch = requiresRestartToSwitch
        self.activeSessionIdentityToken = activeSessionIdentityToken
        self.visualFocusAccountID = visualFocusAccountID
        self.onManageAccounts = onManageAccounts

        let initialProvider = initiallyInspectedAccountID.flatMap { accountID in
            providers.first(where: { provider in
                provider.accounts.contains(where: { $0.id == accountID })
            })
        } ?? providers.first(where: { $0.id == initiallySelectedProviderID })
        let initialAccount: ProviderUsageAccount? = initialProvider.flatMap { provider in
            guard provider.capability == .accountRouting else { return nil }
            return initiallyInspectedAccountID.flatMap { accountID in
                provider.accounts.first(where: { $0.id == accountID })
            } ?? Self.foregroundAccount(provider)
        }
        let initialSatisfaction = initialProvider.flatMap { provider in
            initialAccount.flatMap { account in
                Self.accountKey(provider: provider, account: account)
            }
        }.flatMap { accountScopeSatisfaction[$0] } ?? .none

        _interaction = State(initialValue: ProviderUsageDockInteraction(
            initiallyInspectedProviderID: initialProvider?.id,
            initiallyInspectedAccountID: initialAccount?.id,
            initiallyShowsConfirmation: initiallyShowsConfirmation,
            initiallySelectedScope: initialSatisfaction.firstUnsatisfiedScope ?? .thisSession,
            onUseAccount: onUseAccount))
    }

    var body: some View {
        Group {
            if let provider = inspectedProvider {
                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: collapse)

                    expandedPanel(provider: provider)
                        .transition(.identity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            } else {
                collapsedDock
                    .padding(.trailing, compactLayout.trailingOffset)
                    .padding(.bottom, compactLayout.bottomOffset)
            }
        }
        .onChange(of: activeSessionIdentityToken) { _, _ in
            interaction.openSessionDidChange()
        }
        .onExitCommand(perform: collapse)
    }

    private var inspectedProvider: ProviderUsageProvider? {
        providers.first(where: { $0.id == interaction.inspectedProviderID })
    }

    private func inspectedAccount(in provider: ProviderUsageProvider) -> ProviderUsageAccount? {
        provider.accounts.first(where: { $0.id == interaction.inspectedAccountID })
    }

    private var collapsedDock: some View {
        HStack(alignment: .bottom, spacing: Self.compactWheelSpacing) {
            ForEach(providers) { provider in
                if provider.capability == .accountRouting, !provider.accounts.isEmpty {
                    accountStack(
                        provider: provider,
                        isGrayscale: isForegroundGenerating,
                        diameter: compactLayout.wheelDiameter,
                        focus: $compactFocusedSelectorID,
                        visualFocusAccountID: visualFocusAccountID,
                        isSource: true
                    ) { account in
                        inspect(provider: provider, account: account)
                    }
                } else {
                    compactProviderButton(provider)
                }
            }
        }
        .onAppear(perform: restoreCompactFocusIfNeeded)
    }

    private func expandedPanel(provider: ProviderUsageProvider) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if provider.capability == .accountRouting,
               let account = inspectedAccount(in: provider),
               interaction.isShowingConfirmation {
                ScrollView {
                    ProviderAccountSwitchConfirmationView(
                        accountLabel: account.label,
                        satisfaction: satisfaction(provider: provider, account: account),
                        isSwitchAvailable: canSwitch(provider: provider, account: account),
                        requiresRestartToSwitch: requiresRestartToSwitch,
                        selectedScope: selectedScopeBinding(provider: provider, account: account),
                        onCancel: interaction.cancelConfirmation,
                        onConfirm: { confirm(provider: provider, account: account) })
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            } else if provider.capability == .accountRouting,
                      let account = inspectedAccount(in: provider) {
                accountDetails(provider: provider, account: account)
            } else {
                providerDetails(provider)
            }
        }
        .padding(16)
        .frame(width: 360)
        .frame(maxHeight: 440, alignment: .bottom)
        .background(TenXPalette.color(TenXPalette.canvasHex))
        .overlay {
            Rectangle()
                .stroke(TenXPalette.color(TenXPalette.separatorHex), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private func providerDetails(_ provider: ProviderUsageProvider) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(providers) { candidate in
                    expandedProviderButton(candidate)
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
                Text(providerActiveSessionText(for: provider))
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
    }

    private func accountDetails(
        provider: ProviderUsageProvider,
        account: ProviderUsageAccount
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            expandedAccountSelector(provider, inspectedAccount: account)

            Rectangle()
                .fill(TenXPalette.color(TenXPalette.separatorHex))
                .frame(height: 1)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.name)
                        .font(TenXTypography.accent(size: 19))
                        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    Text(account.label)
                        .font(TenXTypography.body(size: 12, weight: .medium))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    if let detailLabel = account.detailLabel, detailLabel != account.label {
                        Text(detailLabel)
                            .font(TenXTypography.body(size: 11))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    }
                }
                Spacer(minLength: 8)
                Text(activeSessionText(for: provider, account: account))
                    .font(TenXTypography.body(size: 12))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }

            if satisfaction(provider: provider, account: account).isThisSessionSatisfied {
                Text("In use for this session")
                    .font(TenXTypography.body(size: 12, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    accountSection(account, provider: provider)

                    HStack(spacing: 8) {
                        if provider.showsAccountSwitch {
                            Button("Use this account") {
                                interaction.beginConfirmation(
                                    satisfaction: satisfaction(provider: provider, account: account))
                            }
                            .buttonStyle(GhostActionStyle())
                            .disabled(!canSwitch(provider: provider, account: account)
                                || satisfaction(
                                    provider: provider,
                                    account: account).areAllScopesSatisfied)
                        }

                        Button("Manage accounts") {
                            interaction.openSessionDidChange()
                            onManageAccounts(provider.id)
                        }
                        .buttonStyle(GhostActionStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            Button("Close usage details", action: collapse)
                .buttonStyle(GhostActionStyle())
                .accessibilityLabel("Close usage details")
        }
    }

    @ViewBuilder
    private func expandedAccountSelector(
        _ provider: ProviderUsageProvider,
        inspectedAccount: ProviderUsageAccount
    ) -> some View {
        if provider.capability == .accountRouting, !provider.accounts.isEmpty {
            accountStack(
                provider: ProviderUsageDockPresentation.expandedProvider(
                    provider,
                    inspectedAccount: inspectedAccount),
                isGrayscale: false,
                diameter: ProviderUsageRingGeometry.diameter,
                focus: $expandedFocusedSelectorID,
                isSource: false
            ) { account in
                inspect(provider: provider, account: account)
            }
        }
    }

    private func compactProviderButton(_ provider: ProviderUsageProvider) -> some View {
        providerButton(
            provider,
            isGrayscale: isForegroundGenerating,
            diameter: compactLayout.wheelDiameter,
            focus: $compactFocusedSelectorID)
    }

    private func expandedProviderButton(_ provider: ProviderUsageProvider) -> some View {
        providerButton(
            provider,
            isGrayscale: false,
            diameter: ProviderUsageRingGeometry.diameter,
            focus: $expandedFocusedSelectorID)
    }

    private func providerButton(
        _ provider: ProviderUsageProvider,
        isGrayscale: Bool,
        diameter: CGFloat,
        focus: FocusState<String?>.Binding
    ) -> some View {
        Button {
            inspectProvider(provider)
        } label: {
            providerWheel(provider, isGrayscale: isGrayscale, diameter: diameter)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .focused(focus, equals: provider.id)
        .accessibilityLabel(provider.name)
        .accessibilityValue(ProviderUsageAccessibility.wheelValue(
            provider: provider,
            activeCount: activeCounts[provider.id] ?? 0))
    }

    @ViewBuilder
    private func accountStack(
        provider: ProviderUsageProvider,
        isGrayscale: Bool,
        diameter: CGFloat,
        focus: FocusState<String?>.Binding,
        visualFocusAccountID: String? = nil,
        isSource: Bool,
        onSelect: @escaping (ProviderUsageAccount) -> Void
    ) -> some View {
        let stack = ProviderAccountStackView(
            provider: provider,
            generatingCounts: effectiveGeneratingCounts,
            isGrayscale: isGrayscale,
            diameter: diameter,
            // The compact dock (isSource: true) collapses at rest and fans
            // on hover; the panel's inline selector (isSource: false) always
            // has room, so it always shows every account.
            alwaysExpanded: !isSource,
            focusedAccountID: focus,
            visualFocusAccountID: visualFocusAccountID,
            onSelect: onSelect)
        if ProviderUsageDockExpansionMotion.mode(reduceMotion: reduceMotion) == .matchedGeometry {
            stack.matchedGeometryEffect(
                id: expansionID(provider.id),
                in: expansionNamespace,
                isSource: isSource)
        } else {
            stack
        }
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
        if ProviderUsageDockExpansionMotion.mode(reduceMotion: reduceMotion) == .matchedGeometry {
            wheel.matchedGeometryEffect(
                id: expansionID(provider.id),
                in: expansionNamespace,
                isSource: interaction.inspectedProviderID == nil
                    || provider.id != interaction.inspectedProviderID)
        } else {
            wheel
        }
    }

    private func expansionID(_ providerID: String) -> String {
        "usage-wheel-\(providerID)"
    }

    private func accountSection(
        _ account: ProviderUsageAccount,
        provider: ProviderUsageProvider,
        showsAccountLabel: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsAccountLabel {
                Text(account.label)
                    .font(TenXTypography.body(size: 13, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
            }

            if let usageStatusText = account.usageStatusText {
                Text(usageStatusText)
                    .font(TenXTypography.body(size: 12))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }

            ForEach(account.limits) { limit in
                ProviderUsageLimitDetailView(
                    providerName: provider.name,
                    accountName: account.label,
                    limit: limit)
            }
        }
    }

    private var effectiveGeneratingCounts: [ProviderAccountKey: Int] {
        guard generatingCounts.isEmpty else { return generatingCounts }
        var counts: [ProviderAccountKey: Int] = [:]
        for provider in providers {
            guard let account = Self.foregroundAccount(provider),
                  let key = Self.accountKey(provider: provider, account: account),
                  let count = activeCounts[provider.id]
            else { continue }
            counts[key] = count
        }
        return counts
    }

    private func activeSessionText(
        for provider: ProviderUsageProvider,
        account: ProviderUsageAccount
    ) -> String {
        let count = Self.accountKey(provider: provider, account: account)
            .flatMap { effectiveGeneratingCounts[$0] } ?? 0
        return switch count {
        case ...0: "No active sessions"
        case 1: "1 active session"
        default: "\(count) active sessions"
        }
    }

    private func providerActiveSessionText(for provider: ProviderUsageProvider) -> String {
        let count = activeCounts[provider.id] ?? 0
        return switch count {
        case ...0: "No active sessions"
        case 1: "1 active session"
        default: "\(count) active sessions"
        }
    }

    private func satisfaction(
        provider: ProviderUsageProvider,
        account: ProviderUsageAccount
    ) -> ProviderAccountScopeSatisfaction {
        Self.accountKey(provider: provider, account: account)
            .flatMap { accountScopeSatisfaction[$0] } ?? .none
    }

    private func canSwitch(
        provider: ProviderUsageProvider,
        account: ProviderUsageAccount
    ) -> Bool {
        ProviderUsageDockRoutingEligibility.canSwitch(
            account,
            providerID: provider.id,
            pendingRemovalAccounts: pendingRemovalAccounts)
    }

    private func selectedScopeBinding(
        provider: ProviderUsageProvider,
        account: ProviderUsageAccount
    ) -> Binding<ProviderAccountScopeOption> {
        Binding(
            get: { interaction.selectedScope },
            set: { scope in
                interaction.selectScope(
                    scope,
                    satisfaction: satisfaction(provider: provider, account: account))
            })
    }

    private func inspect(
        provider: ProviderUsageProvider,
        account: ProviderUsageAccount
    ) {
        applyAnimation {
            interaction.inspect(providerID: provider.id, accountID: account.id)
        }
        Task { @MainActor in
            await Task.yield()
            expandedFocusedSelectorID = account.id
        }
    }

    private func inspectProvider(_ provider: ProviderUsageProvider) {
        applyAnimation {
            interaction.inspectProvider(providerID: provider.id)
        }
        Task { @MainActor in
            await Task.yield()
            expandedFocusedSelectorID = provider.id
        }
    }

    private func confirm(
        provider: ProviderUsageProvider,
        account: ProviderUsageAccount
    ) {
        guard canSwitch(provider: provider, account: account),
              let accountRef = account.accountRef
        else { return }
        interaction.confirm(
            accountRef: accountRef,
            satisfaction: satisfaction(provider: provider, account: account))
    }

    private func collapse() {
        guard interaction.inspectedProviderID != nil else { return }
        expandedFocusedSelectorID = nil
        applyAnimation(interaction.dismiss)
    }

    private func restoreCompactFocusIfNeeded() {
        Task { @MainActor in
            await interaction.restoreFocusAfterCompactMount { selectorID in
                compactFocusedSelectorID = selectorID
            }
        }
    }

    private func applyAnimation(_ update: () -> Void) {
        if reduceMotion {
            update()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                update()
            }
        }
    }

    private static func foregroundAccount(
        _ provider: ProviderUsageProvider
    ) -> ProviderUsageAccount? {
        provider.accounts.first(where: { $0.accountRef == provider.foregroundAccountRef })
            ?? provider.accounts.first
    }

    private static func accountKey(
        provider: ProviderUsageProvider,
        account: ProviderUsageAccount
    ) -> ProviderAccountKey? {
        account.accountRef.map { ProviderAccountKey(
            providerID: provider.id,
            accountRef: $0) }
    }
}

@MainActor
final class ProviderUsageDockFocusRestorationCoordinator {
    private var pendingSelectorID: String?

    func scheduleReturn(to selectorID: String) {
        pendingSelectorID = selectorID
    }

    func restoreAfterCompactMount(_ assignCompactFocus: (String) -> Void) async {
        await Task.yield()
        guard let selectorID = pendingSelectorID else { return }
        pendingSelectorID = nil
        assignCompactFocus(selectorID)
    }
}

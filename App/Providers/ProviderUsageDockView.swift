import Observation
import SwiftUI

struct ProviderUsageDockRoutingEligibility {
    static func canSelect(
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
              let scope = satisfaction.isSatisfied(selectedScope)
                ? satisfaction.firstUnsatisfiedScope
                : selectedScope
        else { return }
        onUseAccount(accountRef, scope.routingScope)
        dismiss()
    }

    func dismiss() {
        guard let inspectedAccountID else { return }
        focusRestoration.scheduleReturn(to: inspectedAccountID)
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
    let activeSessionIdentityToken: UUID?
    let visualFocusAccountID: String?
    let onManageAccounts: (String) -> Void

    @State private var interaction: ProviderUsageDockInteraction
    @FocusState private var compactFocusedAccountID: String?
    @FocusState private var expandedFocusedAccountID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        providers: [ProviderUsageProvider],
        activeCounts: [String: Int],
        generatingCounts: [ProviderAccountKey: Int] = [:],
        isForegroundGenerating: Bool,
        compactLayout: ProviderUsageDockCompactLayout = .standalone,
        accountScopeSatisfaction: [ProviderAccountKey: ProviderAccountScopeSatisfaction] = [:],
        pendingRemovalAccounts: Set<ProviderAccountKey> = [],
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
        self.activeSessionIdentityToken = activeSessionIdentityToken
        self.visualFocusAccountID = visualFocusAccountID
        self.onManageAccounts = onManageAccounts

        let initialProvider = initiallyInspectedAccountID.flatMap { accountID in
            providers.first(where: { provider in
                provider.accounts.contains(where: { $0.id == accountID })
            })
        } ?? providers.first(where: { $0.id == initiallySelectedProviderID })
        let initialAccount = initiallyInspectedAccountID.flatMap { accountID in
            initialProvider?.accounts.first(where: { $0.id == accountID })
        } ?? initialProvider.flatMap(Self.foregroundAccount)
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
            if let provider = inspectedProvider,
               let account = inspectedAccount(in: provider) {
                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: collapse)

                    expandedPanel(provider: provider, account: account)
                        .transition(reduceMotion ? .opacity : .identity)
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
                    ProviderAccountStackView(
                        provider: provider,
                        generatingCounts: effectiveGeneratingCounts,
                        isGrayscale: isForegroundGenerating,
                        diameter: compactLayout.wheelDiameter,
                        focusedAccountID: $compactFocusedAccountID,
                        visualFocusAccountID: visualFocusAccountID
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

    private func expandedPanel(
        provider: ProviderUsageProvider,
        account: ProviderUsageAccount
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if interaction.isShowingConfirmation {
                ScrollView {
                    ProviderAccountSwitchConfirmationView(
                        accountLabel: account.label,
                        satisfaction: satisfaction(provider: provider, account: account),
                        isAccountAvailable: canSelect(provider: provider, account: account),
                        selectedScope: selectedScopeBinding(provider: provider, account: account),
                        onCancel: interaction.cancelConfirmation,
                        onConfirm: { confirm(provider: provider, account: account) })
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            } else {
                accountDetails(provider: provider, account: account)
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
                            .disabled(!canSelect(provider: provider, account: account)
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
            ProviderAccountStackView(
                provider: ProviderUsageDockPresentation.expandedProvider(
                    provider,
                    inspectedAccount: inspectedAccount),
                generatingCounts: effectiveGeneratingCounts,
                isGrayscale: false,
                diameter: ProviderUsageRingGeometry.diameter,
                focusedAccountID: $expandedFocusedAccountID
            ) { account in
                inspect(provider: provider, account: account)
            }
        } else {
            providerButton(
                provider,
                focusID: Self.providerFocusID(provider.id),
                isGrayscale: false,
                diameter: ProviderUsageRingGeometry.diameter,
                focus: $expandedFocusedAccountID)
        }
    }

    private func compactProviderButton(_ provider: ProviderUsageProvider) -> some View {
        providerButton(
            provider,
            focusID: Self.providerFocusID(provider.id),
            isGrayscale: isForegroundGenerating,
            diameter: compactLayout.wheelDiameter,
            focus: $compactFocusedAccountID)
    }

    private func providerButton(
        _ provider: ProviderUsageProvider,
        focusID: String,
        isGrayscale: Bool,
        diameter: CGFloat,
        focus: FocusState<String?>.Binding
    ) -> some View {
        Button {
            guard let account = Self.foregroundAccount(provider) else { return }
            inspect(provider: provider, account: account)
        } label: {
            ProviderUsageWheelView(
                provider: provider,
                activeCount: activeCounts[provider.id] ?? 0,
                isGrayscale: isGrayscale,
                diameter: diameter)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .focused(focus, equals: focusID)
        .accessibilityLabel(provider.name)
        .accessibilityValue(ProviderUsageAccessibility.wheelValue(
            provider: provider,
            activeCount: activeCounts[provider.id] ?? 0))
    }

    private func accountSection(
        _ account: ProviderUsageAccount,
        provider: ProviderUsageProvider
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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

    private func satisfaction(
        provider: ProviderUsageProvider,
        account: ProviderUsageAccount
    ) -> ProviderAccountScopeSatisfaction {
        Self.accountKey(provider: provider, account: account)
            .flatMap { accountScopeSatisfaction[$0] } ?? .none
    }

    private func canSelect(
        provider: ProviderUsageProvider,
        account: ProviderUsageAccount
    ) -> Bool {
        ProviderUsageDockRoutingEligibility.canSelect(
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
        guard provider.capability != .accountRouting
            || canSelect(provider: provider, account: account)
        else { return }
        applyAnimation {
            interaction.inspect(providerID: provider.id, accountID: account.id)
        }
        Task { @MainActor in
            await Task.yield()
            expandedFocusedAccountID = account.id
        }
    }

    private func confirm(
        provider: ProviderUsageProvider,
        account: ProviderUsageAccount
    ) {
        guard canSelect(provider: provider, account: account),
              let accountRef = account.accountRef
        else { return }
        interaction.confirm(
            accountRef: accountRef,
            satisfaction: satisfaction(provider: provider, account: account))
    }

    private func collapse() {
        guard interaction.inspectedAccountID != nil else { return }
        expandedFocusedAccountID = nil
        applyAnimation(interaction.dismiss)
    }

    private func restoreCompactFocusIfNeeded() {
        Task { @MainActor in
            await interaction.restoreFocusAfterCompactMount { accountID in
                compactFocusedAccountID = accountID
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

    private static func providerFocusID(_ providerID: String) -> String {
        "provider:\(providerID)"
    }
}

@MainActor
final class ProviderUsageDockFocusRestorationCoordinator {
    private var pendingAccountID: String?

    func scheduleReturn(to accountID: String) {
        pendingAccountID = accountID
    }

    func restoreAfterCompactMount(_ assignCompactFocus: (String) -> Void) async {
        await Task.yield()
        guard let accountID = pendingAccountID else { return }
        pendingAccountID = nil
        assignCompactFocus(accountID)
    }
}

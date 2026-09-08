import OmpKit
import SwiftUI

enum ProviderConnectionsFocusTarget: Equatable, Sendable {
    case addAccount(String)
    case removeAccount(String)
}

struct ProviderConnectionsFocusRequest: Equatable, Identifiable, Sendable {
    let id = UUID()
    let target: ProviderConnectionsFocusTarget
}

struct ProviderConnectionsView: View {
    let providers: [ProviderLoginProvider]
    let credentialIssues: [ProviderCredentialIssue]
    let accountsByProviderID: [String: [ProviderAccountSummary]]
    let accountManagedProviderIDs: Set<String>
    let primaryAccountRefs: [String: String]
    let accountTier: ProviderAccountTier
    let sessionCounts: [ProviderAccountKey: Int]
    let pendingRemovalAccounts: Set<ProviderAccountKey>
    let focusedProviderID: String?
    let focusRequest: ProviderConnectionsFocusRequest?
    let isLoading: Bool
    let providerMessage: String?
    let loginMessage: String?
    let loginMessageIsError: Bool
    let loginMessageProviderID: String?
    let removalMessage: String?
    let removalMessageProviderID: String?
    let activeLoginProviderID: String?
    let isShowingAllProviders: Bool
    let query: Binding<String>
    let onShowAll: () -> Void
    let onConnect: (ProviderLoginProvider) -> Void
    let onRemove: (ProviderLoginProvider, ProviderAccountSummary) -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void

    @FocusState private var focusedAddAccountProviderID: String?
    @FocusState private var focusedRemoveAccountID: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let providerMessage {
                        recovery(message: providerMessage)
                    } else if isLoading && providers.isEmpty {
                        loadingRows
                    } else {
                        catalog
                    }
                }
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
            .task(id: focusedProviderID) {
                guard let focusedProviderID else { return }
                await Task.yield()
                proxy.scrollTo(focusedProviderID, anchor: .center)
                focusedAddAccountProviderID = focusedProviderID
            }
            .task(id: focusRequest?.id) {
                guard let focusRequest else { return }
                await Task.yield()
                switch focusRequest.target {
                case .addAccount(let providerID):
                    proxy.scrollTo(providerID, anchor: .center)
                    focusedAddAccountProviderID = providerID
                case .removeAccount(let accountID):
                    proxy.scrollTo(accountID, anchor: .center)
                    focusedRemoveAccountID = accountID
                }
            }
        }
    }

    @ViewBuilder
    private var catalog: some View {
        if let loginMessage, loginMessageProviderID == nil {
            Text(loginMessage)
                .font(TenXTypography.body(size: 12))
                .foregroundStyle(loginMessageIsError
                    ? TenXPalette.color(TenXPalette.signalRedHex)
                    : TenXPalette.color(TenXPalette.mutedTextHex))
                .padding(.top, 14)
        }

        if isShowingAllProviders {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                TextField("Search providers", text: query)
                    .textFieldStyle(.plain)
                    .font(TenXTypography.body(size: 14))
                    .accessibilityLabel("Search providers")
            }
            .padding(.vertical, 11)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(TenXPalette.color(TenXPalette.cyanHex))
                    .frame(height: 2)
            }
        }

        if providers.isEmpty {
            Text("No providers match this search.")
                .font(TenXTypography.body(size: 12))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .padding(.vertical, 30)
        } else {
            ForEach(providers) { provider in
                if accountManagedProviderIDs.contains(provider.id), provider.isAuthenticated {
                    accountGroup(provider)
                        .id(provider.id)
                } else {
                    ProviderConnectionRowView(
                        provider: provider,
                        credentialIssue: credentialIssues.first(where: { $0.providerID == provider.id }),
                        activeLoginProviderID: activeLoginProviderID,
                        loginMessage: loginMessageProviderID == provider.id ? loginMessage : nil,
                        loginMessageIsError: loginMessageIsError,
                        onConnect: { onConnect(provider) },
                        onCancel: onCancel)
                        .id(provider.id)
                }
            }
        }

        if !isShowingAllProviders {
            Button("Browse all providers", action: onShowAll)
                .buttonStyle(GhostActionStyle())
                .padding(.top, 9)
        }
    }

    private func accountGroup(_ provider: ProviderLoginProvider) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title + muted subtitle, scoped to this provider's header the
            // same way both account confirmation dialogs scope standing
            // context to their title (`ProviderAccountSwitchConfirmationView`,
            // `ProviderAccountRemovalConfirmationView`) — stays flush with
            // the header while the rows below indent, so it reads as
            // section-level rather than another row's metadata.
            VStack(alignment: .leading, spacing: 3) {
                Text(provider.companyName)
                    .font(TenXTypography.body(size: 14, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                if let removalUnavailableReason {
                    Text(removalUnavailableReason)
                        .font(TenXTypography.body(size: 12))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 5)

            ForEach(accountsByProviderID[provider.id] ?? []) { account in
                ProviderAccountConnectionRowView(
                    account: account,
                    isPrimary: primaryAccountRefs[provider.id] == account.accountRef,
                    sessionCount: sessionCounts[ProviderAccountKey(
                        providerID: provider.id,
                        accountRef: account.accountRef)] ?? 0,
                    isPendingRemoval: pendingRemovalAccounts.contains(ProviderAccountKey(
                        providerID: provider.id,
                        accountRef: account.accountRef)),
                    canRemove: canRemove(account, from: provider),
                    isRemovalDisabledByTier: removalUnavailableReason != nil,
                    removeButtonFocus: $focusedRemoveAccountID,
                    onRemove: { onRemove(provider, account) })
                    .padding(.leading, 16)
                    .id(account.id)
            }

            if activeLoginProviderID == provider.id {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting…")
                        .font(TenXTypography.body(size: 12))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    Button("Cancel", action: onCancel)
                        .buttonStyle(GhostActionStyle(
                            color: TenXPalette.color(TenXPalette.nearBlackHex)))
                }
                .padding(.vertical, 10)
            } else {
                Button("Add account") {
                    onConnect(provider)
                }
                .buttonStyle(GhostActionStyle())
                .disabled(activeLoginProviderID != nil)
                .focused($focusedAddAccountProviderID, equals: provider.id)
                .padding(.vertical, 10)
            }

            if let loginMessage, loginMessageProviderID == provider.id {
                Text(loginMessage)
                    .font(TenXTypography.body(size: 12))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                    .padding(.bottom, 10)
            }
            if let removalMessage, removalMessageProviderID == provider.id {
                Text(removalMessage)
                    .font(TenXTypography.body(size: 12))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                    .padding(.bottom, 10)
            }

            Rectangle()
                .fill(TenXPalette.color(TenXPalette.separatorHex))
                .frame(height: 1)
        }
    }

    private func canRemove(
        _ account: ProviderAccountSummary,
        from provider: ProviderLoginProvider
    ) -> Bool {
        let remaining = (accountsByProviderID[provider.id] ?? []).filter { $0.id != account.id }
        return remaining.isEmpty || remaining.contains(where: \.isEligiblePrimary)
    }

    /// `nil` when the active tier can remove accounts at all; otherwise the
    /// tier-wide reason, stated once under this provider's header rather
    /// than repeated on every row — the restriction applies uniformly across
    /// every account here, so per-row repetition added nothing but noise.
    /// Reuses `ProviderAccountTier.supportsRemoval` rather than re-deriving
    /// which tiers allow removal.
    ///
    /// States the fact 10x can actually verify, not a cause it cannot: an
    /// absent, incompatible, and failed-to-load extension all fail
    /// `ProviderAccountTier.detect` the same way — a nil or wrong-version
    /// hello — so 10x has no way to tell those apart, and naming "this
    /// version of OMP" as the reason (an earlier draft of this copy) would
    /// be a guess presented as fact. Same no-diagnosis reasoning that
    /// already dropped this feature's degradation banner (task-10b, "the
    /// unprovable degradation notice").
    private var removalUnavailableReason: String? {
        guard !accountTier.supportsRemoval else { return nil }
        return "Account removal requires a connected extension."
    }

    private func recovery(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(TenXTypography.body(size: 13))
                .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            Button("Try again", action: onRetry)
                .buttonStyle(GhostActionStyle())
        }
        .padding(.vertical, 26)
    }

    private var loadingRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                HStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(TenXPalette.color(TenXPalette.separatorHex))
                        .frame(width: 130, height: 12)
                    Spacer()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(TenXPalette.color(TenXPalette.separatorHex))
                        .frame(width: 60, height: 12)
                }
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(TenXPalette.color(TenXPalette.separatorHex))
                        .frame(height: 1)
                }
                .accessibilityHidden(true)
            }
        }
    }
}

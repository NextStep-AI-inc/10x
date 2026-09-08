import OmpKit
import SwiftUI

struct ProviderAccountRemovalModalBehavior: Equatable, Sendable {
    let isPresented: Bool

    var isUnderlyingContentDisabled: Bool { isPresented }
    var isUnderlyingContentAccessibilityHidden: Bool { isPresented }

    func restorationTarget(
        dismissalSource: ProviderAccountRemovalDismissalSource,
        accountID: String,
        providerID: String,
        accountStillConnected: Bool
    ) -> ProviderConnectionsFocusTarget {
        switch dismissalSource {
        case .background, .cancelAction, .keyboard, .confirmAction:
            return accountStillConnected ? .removeAccount(accountID) : .addAccount(providerID)
        }
    }
}

struct ProvidersView: View {
    let model: ProviderManagementViewModel
    let accountCoordinator: ProviderAccountCoordinator?
    let onBack: (() -> Void)?

    @State private var removalRequest: ProviderAccountRemovalRequest?
    @State private var connectionsFocusRequest: ProviderConnectionsFocusRequest?

    init(
        model: ProviderManagementViewModel,
        accountCoordinator: ProviderAccountCoordinator? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.model = model
        self.accountCoordinator = accountCoordinator
        self.onBack = onBack
    }

    var body: some View {
        ZStack {
            workspace
                .disabled(modalBehavior.isUnderlyingContentDisabled)
                .accessibilityHidden(modalBehavior.isUnderlyingContentAccessibilityHidden)

            if let removalRequest, let accountCoordinator {
                ProviderAccountRemovalConfirmationView(
                    providerName: removalRequest.provider.companyName,
                    accountLabel: removalRequest.account.displayLabel,
                    accountDetailLabel: removalRequest.account.detailLabel,
                    hasDuplicateAccountLabel: hasDuplicateAccountLabel(removalRequest),
                    affectedSessionCount: accountCoordinator.sessionCounts[removalRequest.key] ?? 0,
                    isLastAccount: model.connectionAccounts(
                        providerID: removalRequest.provider.id).count == 1,
                    isRemoving: model.pendingRemovalAccounts.contains(removalRequest.key),
                    onCancel: { source in
                        let accountStillConnected = model.connectionAccounts(
                            providerID: removalRequest.provider.id
                        ).contains { $0.id == removalRequest.account.id }
                        dismissRemoval(
                            source: source,
                            accountStillConnected: accountStillConnected)
                    },
                    onRemove: {
                        Task {
                            await model.removeAccount(
                                removalRequest.account,
                                coordinator: accountCoordinator)
                            let accountStillConnected = model.connectionAccounts(
                                providerID: removalRequest.provider.id
                            ).contains { $0.id == removalRequest.account.id }
                            dismissRemoval(
                                source: .confirmAction,
                                accountStillConnected: accountStillConnected)
                        }
                    })
            }
        }
        .sheet(item: extensionSheetBinding) { request in
            ExtensionInputSheet(
                request: request,
                onSubmit: { value in
                    Task { await model.respond(to: request, with: .value(value)) }
                },
                onCancel: {
                    Task {
                        await model.respond(
                            to: request,
                            with: .cancelled(timedOut: false))
                    }
                })
        }
        .task {
            if let accountCoordinator {
                model.attachAccountCoordinator(accountCoordinator)
            }
        }
    }

    private var workspace: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                    .fixedSize(horizontal: false, vertical: true)
                sectionSwitch
                    .fixedSize(horizontal: false, vertical: true)
                content
                    .frame(
                        width: proxy.size.width,
                        height: max(proxy.size.height - headerHeight, 0),
                        alignment: .top)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(maxWidth: 960, maxHeight: .infinity)
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                if let onBack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                                .offset(x: 1, y: 0.5)
                            Text("Back")
                        }
                    }
                    .buttonStyle(GhostActionStyle(
                        color: TenXPalette.color(TenXPalette.nearBlackHex),
                        horizontalPadding: 0))
                    .accessibilityLabel("Back")
                    .padding(.bottom, 4)
                }

                Text("Providers")
                    .font(TenXTypography.title(size: 34))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                Text(lastUpdateText)
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
            Spacer()
            Button("Refresh") {
                Task { await model.refresh() }
            }
            .buttonStyle(GhostActionStyle())
            .disabled(model.isLoadingProviders || model.isRefreshingUsage)
            .accessibilityLabel("Refresh providers and usage")
        }
        .padding(.top, 62)
        .padding(.bottom, 22)
    }

    private var headerHeight: CGFloat { onBack == nil ? 170 : 202 }

    private var sectionSwitch: some View {
        HStack(spacing: 18) {
            sectionButton("Connections", section: .connections)
            sectionButton("Usage", section: .usage)
            Spacer()
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TenXPalette.color(TenXPalette.cyanHex))
                .frame(height: 2)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.selectedSection {
        case .connections:
            ProviderConnectionsView(
                providers: model.visibleProviders,
                credentialIssues: model.usage.credentialIssues,
                accountsByProviderID: connectionAccounts,
                accountManagedProviderIDs: accountManagedProviderIDs,
                primaryAccountRefs: primaryAccountRefs,
                accountTier: model.accountTier,
                sessionCounts: accountCoordinator?.sessionCounts ?? [:],
                pendingRemovalAccounts: model.pendingRemovalAccounts.union(
                    accountCoordinator?.pendingRemovalAccounts ?? []),
                focusedProviderID: model.focusedConnectionsProviderID,
                focusRequest: connectionsFocusRequest,
                isLoading: model.isLoadingProviders,
                providerMessage: model.providerMessage,
                loginMessage: model.loginMessage,
                loginMessageIsError: model.loginMessageIsError,
                loginMessageProviderID: model.loginMessageProviderID,
                removalMessage: model.removalMessage,
                removalMessageProviderID: model.removalMessageProviderID,
                activeLoginProviderID: model.activeLoginProviderID,
                isShowingAllProviders: model.isShowingAllProviders,
                query: queryBinding,
                onShowAll: model.showAllProviders,
                onConnect: { provider in
                    Task { await model.login(provider) }
                },
                onRemove: { provider, account in
                    removalRequest = ProviderAccountRemovalRequest(
                        provider: provider,
                        account: account)
                },
                onCancel: {
                    Task { await model.cancelLogin() }
                },
                onRetry: {
                    Task { await model.refresh() }
                })
        case .usage:
            ProviderUsageDetailView(
                usage: model.usage,
                providers: model.providers,
                usageMessage: model.usageMessage,
                hasSuccessfulUsage: model.lastUsageRefresh != nil,
                onRefresh: {
                    Task { await model.refresh() }
                },
                onReconnect: { provider in
                    Task { await model.login(provider) }
                })
        }
    }

    private var connectionAccounts: [String: [ProviderAccountSummary]] {
        model.providers.reduce(into: [:]) { accounts, provider in
            accounts[provider.id] = model.connectionAccounts(providerID: provider.id)
        }
    }

    private var accountManagedProviderIDs: Set<String> {
        guard accountCoordinator != nil else { return [] }
        return Set(model.providers.compactMap { provider in
            model.supportsAccountManagement(providerID: provider.id) ? provider.id : nil
        })
    }

    private var primaryAccountRefs: [String: String] {
        guard let accountCoordinator else { return [:] }
        return model.providers.reduce(into: [:]) { primaryRefs, provider in
            primaryRefs[provider.id] = accountCoordinator.primaryAccountRef(providerID: provider.id)
        }
    }

    private var modalBehavior: ProviderAccountRemovalModalBehavior {
        ProviderAccountRemovalModalBehavior(isPresented: removalRequest != nil)
    }

    private func hasDuplicateAccountLabel(_ request: ProviderAccountRemovalRequest) -> Bool {
        let targetLabel = safeAccountLabel(request.account)
        return model.connectionAccounts(providerID: request.provider.id).filter {
            safeAccountLabel($0) == targetLabel
        }.count > 1
    }

    private func safeAccountLabel(_ account: ProviderAccountSummary) -> String {
        ProviderAccountConnectionRowPresentation.make(
            account: account,
            isPrimary: false,
            sessionCount: 0,
            isPendingRemoval: false).label
    }

    private func dismissRemoval(
        source: ProviderAccountRemovalDismissalSource,
        accountStillConnected: Bool
    ) {
        guard let removalRequest else { return }
        let target = modalBehavior.restorationTarget(
            dismissalSource: source,
            accountID: removalRequest.account.id,
            providerID: removalRequest.provider.id,
            accountStillConnected: accountStillConnected)
        self.removalRequest = nil
        connectionsFocusRequest = ProviderConnectionsFocusRequest(target: target)
    }

    private func sectionButton(_ title: String, section: ProviderWorkspaceSection) -> some View {
        Button(title) {
            model.selectedSection = section
        }
        .buttonStyle(.plain)
        .font(TenXTypography.body(size: 12, weight: model.selectedSection == section ? .semibold : .regular))
        .foregroundStyle(model.selectedSection == section
            ? TenXPalette.color(TenXPalette.nearBlackHex)
            : TenXPalette.color(TenXPalette.mutedTextHex))
        .accessibilityAddTraits(model.selectedSection == section ? .isSelected : [])
    }

    private var lastUpdateText: String {
        guard let date = model.lastUsageRefresh else { return "Usage not updated yet" }
        return "Updated \(date.formatted(date: .omitted, time: .shortened))"
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { model.query },
            set: { model.query = $0 })
    }

    private var extensionSheetBinding: Binding<ExtensionUIState?> {
        Binding(
            get: { model.sheetRequest },
            set: { state in
                guard state == nil, let request = model.sheetRequest else { return }
                Task {
                    await model.respond(
                        to: request,
                        with: .cancelled(timedOut: false))
                }
            })
    }
}

private struct ProviderAccountRemovalRequest: Identifiable {
    let provider: ProviderLoginProvider
    let account: ProviderAccountSummary

    var id: String { account.id }
    var key: ProviderAccountKey {
        ProviderAccountKey(providerID: provider.id, accountRef: account.accountRef)
    }
}

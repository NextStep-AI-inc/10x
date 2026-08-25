import SwiftUI

struct ProvidersView: View {
    let model: ProviderManagementViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            sectionSwitch
            content
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: 960, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
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
                isLoading: model.isLoadingProviders,
                providerMessage: model.providerMessage,
                loginMessage: model.loginMessage,
                activeLoginProviderID: model.activeLoginProviderID,
                isShowingAllProviders: model.isShowingAllProviders,
                query: queryBinding,
                onShowAll: model.showAllProviders,
                onConnect: { provider in
                    Task { await model.login(provider) }
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

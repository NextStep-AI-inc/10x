import SwiftUI

struct ProviderConnectionsView: View {
    let providers: [ProviderLoginProvider]
    let credentialIssues: [ProviderCredentialIssue]
    let isLoading: Bool
    let providerMessage: String?
    let loginMessage: String?
    let activeLoginProviderID: String?
    let isShowingAllProviders: Bool
    let query: Binding<String>
    let onShowAll: () -> Void
    let onConnect: (ProviderLoginProvider) -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
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
    }

    @ViewBuilder
    private var catalog: some View {
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
                ProviderConnectionRowView(
                    provider: provider,
                    credentialIssue: credentialIssues.first(where: { $0.providerID == provider.id }),
                    isConnecting: activeLoginProviderID == provider.id,
                    loginMessage: loginMessage?.contains(provider.name) == true ? loginMessage : nil,
                    onConnect: { onConnect(provider) },
                    onCancel: onCancel)
            }
        }

        if !isShowingAllProviders {
            Button("Browse all providers", action: onShowAll)
                .buttonStyle(GhostActionStyle())
                .padding(.top, 9)
        }
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

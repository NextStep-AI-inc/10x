import SwiftUI

struct ProviderConnectionRowView: View {
    let provider: ProviderLoginProvider
    let credentialIssue: ProviderCredentialIssue?
    let isConnecting: Bool
    let loginMessage: String?
    let onConnect: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(provider.name)
                    .font(TenXTypography.body(size: 14, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                status
            }
            Spacer(minLength: 16)
            action
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TenXPalette.color(TenXPalette.separatorHex))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var status: some View {
        if isConnecting {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting…")
            }
            .font(TenXTypography.body(size: 12))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Connecting \(provider.name)")
        } else if let loginMessage {
            Text(loginMessage)
                .font(TenXTypography.body(size: 12))
                .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
        } else if provider.isAuthenticated {
            Text("Connected")
                .font(TenXTypography.body(size: 12))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        } else if credentialIssue != nil {
            Text("Reconnect to update usage.")
                .font(TenXTypography.body(size: 12))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        } else if !provider.isAvailable {
            Text("Unavailable")
                .font(TenXTypography.body(size: 12))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
    }

    @ViewBuilder
    private var action: some View {
        if isConnecting {
            Button("Cancel", action: onCancel)
                .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.nearBlackHex)))
                .accessibilityLabel("Cancel \(provider.name) connection")
        } else if provider.isAuthenticated {
            Text("Connected")
                .font(TenXTypography.body(size: 12, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
        } else if credentialIssue != nil {
            Button("Reconnect", action: onConnect)
                .buttonStyle(GhostActionStyle())
                .disabled(!provider.isAvailable)
                .accessibilityLabel("Reconnect \(provider.name)")
        } else {
            Button("Connect", action: onConnect)
                .buttonStyle(GhostActionStyle())
                .disabled(!provider.isAvailable)
                .accessibilityLabel("Connect \(provider.name)")
        }
    }
}

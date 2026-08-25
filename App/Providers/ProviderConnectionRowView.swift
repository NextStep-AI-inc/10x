import SwiftUI

enum ProviderConnectionAction: Equatable, Sendable {
    case cancel
    case connected
    case unavailable
    case retry
    case reconnect
    case connect
}

struct ProviderConnectionRowPresentation: Equatable, Sendable {
    let companyName: String
    let status: String?
    let action: ProviderConnectionAction
    let isActionDisabled: Bool
    let accessibilityLabel: String

    static func make(
        provider: ProviderLoginProvider,
        hasCredentialIssue: Bool,
        activeLoginProviderID: String?,
        loginMessage: String?
    ) -> ProviderConnectionRowPresentation {
        let isConnecting = activeLoginProviderID == provider.id
        let action: ProviderConnectionAction
        if isConnecting {
            action = .cancel
        } else if !provider.isAvailable {
            action = .unavailable
        } else if provider.isAuthenticated {
            action = .connected
        } else if loginMessage != nil {
            action = .retry
        } else if hasCredentialIssue {
            action = .reconnect
        } else {
            action = .connect
        }

        let status: String?
        if !provider.isAvailable {
            status = "Unavailable"
        } else if isConnecting {
            status = "Connecting…"
        } else if let loginMessage {
            status = loginMessage
        } else if provider.isAuthenticated {
            status = "Connected"
        } else if hasCredentialIssue {
            status = "Reconnect to update usage."
        } else {
            status = nil
        }

        let isActionDisabled = activeLoginProviderID != nil
            && action != .cancel
            && action != .connected
            && action != .unavailable
        let companyName = provider.companyName
        let accessibilityLabel: String
        switch action {
        case .cancel:
            accessibilityLabel = "Cancel \(companyName) connection"
        case .retry:
            accessibilityLabel = "Retry \(companyName) connection"
        case .reconnect:
            accessibilityLabel = "Reconnect \(companyName)"
        case .connect:
            accessibilityLabel = "Connect \(companyName)"
        case .unavailable:
            accessibilityLabel = "\(companyName) unavailable"
        case .connected:
            accessibilityLabel = "\(companyName) connected"
        }
        return ProviderConnectionRowPresentation(
            companyName: companyName,
            status: status,
            action: action,
            isActionDisabled: isActionDisabled,
            accessibilityLabel: accessibilityLabel)
    }

}

struct ProviderConnectionRowView: View {
    let provider: ProviderLoginProvider
    let credentialIssue: ProviderCredentialIssue?
    let activeLoginProviderID: String?
    let loginMessage: String?
    let onConnect: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.companyName)
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
        if presentation.action == .cancel {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting…")
            }
            .font(TenXTypography.body(size: 12))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Connecting \(presentation.companyName)")
        } else if let status = presentation.status {
            Text(status)
                .font(TenXTypography.body(size: 12))
                .foregroundStyle(presentation.action == .retry
                    ? TenXPalette.color(TenXPalette.signalRedHex)
                    : TenXPalette.color(TenXPalette.mutedTextHex))
        }
    }

    @ViewBuilder
    private var action: some View {
        switch presentation.action {
        case .cancel:
            Button("Cancel", action: onCancel)
                .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.nearBlackHex)))
                .accessibilityLabel(presentation.accessibilityLabel)
        case .connected:
            Text("Connected")
                .font(TenXTypography.body(size: 12, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
        case .unavailable:
            EmptyView()
        case .retry, .reconnect, .connect:
            Button(actionTitle, action: onConnect)
                .buttonStyle(GhostActionStyle())
                .disabled(presentation.isActionDisabled)
                .accessibilityLabel(presentation.accessibilityLabel)
        }
    }

    private var presentation: ProviderConnectionRowPresentation {
        ProviderConnectionRowPresentation.make(
            provider: provider,
            hasCredentialIssue: credentialIssue != nil,
            activeLoginProviderID: activeLoginProviderID,
            loginMessage: loginMessage)
    }

    private var actionTitle: String {
        switch presentation.action {
        case .retry: "Retry"
        case .reconnect: "Reconnect"
        case .connect: "Connect"
        case .cancel, .connected, .unavailable: ""
        }
    }
}

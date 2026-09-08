import SwiftUI

struct ComputerUseMenuBarView: View {
    let client: SupervisionClient
    var onOpenSession: (Int) -> Void // only called for rows where canOpen is true
    var openableSessionIDs: Set<Int>  // daemon sessions known to be 10x's own

    var body: some View {
        let groups = MenuBarPresentation.groups(sessions: client.sessions)
        if groups.isEmpty {
            Text("No windows in use")
                .font(TenXTypography.body(size: 12))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .padding(10)
        } else {
            ForEach(groups, id: \.harness) { group in
                Section(group.harness) {
                    ForEach(group.sessions) { session in
                        sessionRow(session)
                    }
                }
            }
            Divider()
            Button("Stop All Computer Use") { client.stopAll() }
                .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                .accessibilityLabel("Stop all computer use, all apps")
        }
        if !client.isConnected {
            Divider()
            Text("Daemon not running. Starts on first use.")
                .font(TenXTypography.mono(size: 9))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: ComputerSessionState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(session.label ?? "Session \(session.id)")
                    .font(TenXTypography.body(size: 12, weight: .semibold))
                if let status = session.status, !status.isEmpty {
                    Text(status)
                        .font(TenXTypography.mono(size: 9))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .lineLimit(1)
                }
                Spacer()
                if openableSessionIDs.contains(session.id) {
                    Button("Open") { onOpenSession(session.id) }
                }
                Button("Stop") {
                    Task { await client.stopSession(session.id) }
                }
                .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            }
            ForEach(session.windows) { window in
                Text("  \(window.title.isEmpty ? window.app : "\(window.app) · \(window.title)")")
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .lineLimit(1)
            }
        }
    }
}

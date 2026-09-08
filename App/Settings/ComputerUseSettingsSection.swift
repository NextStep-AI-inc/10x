import SwiftUI

struct ComputerUseSettingsSection: View {
    let model: ComputerUseSetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            Rectangle()
                .fill(TenXPalette.color(TenXPalette.cyanHex))
                .frame(height: 2)
            installRow
            Divider()
            selfcheckRow
            Divider()
            permissionRow(
                title: "Screen Recording",
                granted: model.supervision.permissions?.screenRecording,
                action: model.openScreenRecordingSettings)
            Divider()
            permissionRow(
                title: "Accessibility",
                granted: model.supervision.permissions?.accessibility,
                action: model.openAccessibilitySettings)
            Divider()
            daemonRow
            Divider()
            stopAllRow
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text("Computer Use")
                .font(TenXTypography.accent(size: 19))
            Spacer()
        }
        .padding(.top, 26)
        .padding(.bottom, 8)
    }

    private var installRow: some View {
        settingsRow(
            title: "tenx-computer",
            detail: model.isInstalled
                ? "Installed at \(ComputerUseInstaller.installPath)"
                : "Not installed — required for computer tools in OMP sessions")
        {
            Button(model.isInstalling ? "Installing…" : (model.isInstalled ? "Reinstall" : "Install")) {
                Task { await model.installOrReinstall() }
            }
            .buttonStyle(GhostActionStyle())
            .disabled(model.isInstalling)
        } footer: {
            if !model.installLog.isEmpty {
                Text(model.installLog)
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .textSelection(.enabled)
            }
        }
    }

    private var selfcheckRow: some View {
        settingsRow(
            title: "Selfcheck",
            detail: "Probe permissions and input on this Mac")
        {
            Button(model.isRunningSelfcheck ? "Running…" : "Run selfcheck") {
                Task { await model.runSelfcheck() }
            }
            .buttonStyle(GhostActionStyle())
            .disabled(model.isRunningSelfcheck || !model.isInstalled)
        } footer: {
            if !model.selfcheckOutput.isEmpty {
                Text(model.selfcheckOutput)
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .textSelection(.enabled)
            }
        }
    }

    private func permissionRow(
        title: String,
        granted: Bool?,
        action: @escaping () -> Void
    ) -> some View {
        settingsRow(
            title: title,
            detail: permissionDetail(granted))
        {
            Button("Open System Settings") { action() }
                .buttonStyle(GhostActionStyle())
        }
    }

    private var daemonRow: some View {
        settingsRow(
            title: "Daemon",
            detail: model.supervision.isConnected
                ? "Connected — starts on first MCP use when idle"
                : "Not running — starts on first MCP use")
    }

    private var stopAllRow: some View {
        settingsRow(
            title: "Stop all computer use",
            detail: "Halts every session across every harness")
        {
            Button("Stop all") { model.supervision.stopAll() }
                .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.signalRedHex)))
        }
    }

    private func permissionDetail(_ granted: Bool?) -> String {
        switch granted {
        case true: "Granted"
        case false: "Not granted — open System Settings to allow tenx-computer"
        case nil: "Unknown until the daemon starts"
        }
    }

    private func settingsRow<Footer: View>(
        title: String,
        detail: String,
        @ViewBuilder control: () -> some View = { EmptyView() },
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(TenXTypography.body(size: 13, weight: .semibold))
                    Text(detail)
                        .font(TenXTypography.body(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                control()
                    .frame(width: 300, alignment: .trailing)
            }
            footer()
        }
        .padding(.vertical, 15)
    }
}

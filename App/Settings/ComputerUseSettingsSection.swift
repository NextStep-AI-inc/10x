import AppKit
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
            otherHarnessesRow
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
            detail: installDetail)
        {
            Button(model.isInstalling ? "Installing…" : (model.isInstalled ? "Reinstall" : "Install")) {
                Task { await model.installOrReinstall() }
            }
            .buttonStyle(GhostActionStyle())
            .disabled(model.isInstalling)
        } footer: {
            logDisclosure(text: model.installLog)
        }
    }

    private var installDetail: String {
        if let result = model.installResultDetail { return result }
        if model.isInstalled { return "Installed at \(ComputerUseInstaller.installPath)" }
        return "Not installed. Required for computer tools in agent sessions."
    }

    private var selfcheckRow: some View {
        settingsRow(
            title: "Selfcheck",
            detail: model.selfcheckResultDetail ?? "Probe permissions and input on this Mac")
        {
            Button(model.isRunningSelfcheck ? "Running…" : "Run selfcheck") {
                Task { await model.runSelfcheck() }
            }
            .buttonStyle(GhostActionStyle())
            .disabled(model.isRunningSelfcheck || !model.isInstalled)
        } footer: {
            logDisclosure(text: model.selfcheckOutput)
        }
    }

    private var otherHarnessesRow: some View {
        settingsRow(
            title: "Other harnesses",
            detail: "Copy MCP config for Cursor, Claude Code, or Codex")
        {
            EmptyView()
        } footer: {
            DisclosureGroup("Config snippets") {
                VStack(alignment: .leading, spacing: 14) {
                    harnessSnippet(
                        title: "Cursor",
                        location: "~/.cursor/mcp.json or .cursor/mcp.json in a project",
                        content: ComputerUseInstaller.cursorMCPSnippet(binaryPath: model.binaryPath))
                    harnessSnippet(
                        title: "Claude Code",
                        location: ".mcp.json in a project root",
                        content: ComputerUseInstaller.claudeCodeMCPSnippet(binaryPath: model.binaryPath))
                    harnessSnippet(
                        title: "Codex",
                        location: "~/.codex/config.toml",
                        content: ComputerUseInstaller.codexMCPSnippet(binaryPath: model.binaryPath))
                }
                .padding(.top, 8)
            }
            .font(TenXTypography.body(size: 11))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
    }

    private func harnessSnippet(title: String, location: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(TenXTypography.body(size: 12, weight: .semibold))
                Spacer()
                Button("Copy") { copy(content) }
                    .buttonStyle(GhostActionStyle())
            }
            Text(location)
                .font(TenXTypography.body(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            Text(content)
                .font(TenXTypography.mono(size: 9))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TenXPalette.color(TenXPalette.hoverNeutralHex))
                .clipShape(RoundedRectangle(cornerRadius: 4))
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
                ? "Connected. Starts on first MCP use when idle."
                : "Not running. Starts on first MCP use.")
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
        case false: "Not granted. Open System Settings to allow tenx-computer."
        case nil: "Unknown until the daemon starts"
        }
    }

    @ViewBuilder
    private func logDisclosure(text: String) -> some View {
        if !text.isEmpty {
            DisclosureGroup("Details") {
                Text(text)
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
            .font(TenXTypography.body(size: 11))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
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

import SwiftUI

struct SplashView: View {
    let state: StartupState
    let buildVersion: String
    let onRetry: () -> Void
    let onContinue: () -> Void

    @Environment(\.accessibilityAnnouncer) private var announcer
    @FocusState private var isRetryFocused: Bool
    @AccessibilityFocusState private var isRetryAccessibilityFocused: Bool
    @State private var announcedRows: [StartupStageRow] = []

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(StartupState.buildLabel(version: buildVersion))
                        .font(TenXTypography.mono(size: 10, weight: .medium))
                        .tracking(1.3)
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    Text("Preparing your workspace")
                        .font(TenXTypography.title(size: 27))
                        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StartupLedgerView(rows: state.rows)
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 10)
            .frame(height: 248)

            StartupSignalView(
                isAnimating: state.isSignalAnimating,
                isFailed: state.phase == .recovery)
                .frame(height: 48)

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
                .frame(height: 104)
        }
        .frame(width: 640, height: 400)
        .background(TenXPalette.color(TenXPalette.canvasHex))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TenXPalette.color(TenXPalette.separatorHex), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preparing your workspace")
        .onAppear {
            announcedRows = state.rows
            if state.phase == .recovery {
                focusRecoveryAction()
            }
        }
        .onChange(of: state.phase) { _, phase in
            guard phase == .recovery else { return }
            focusRecoveryAction()
            announcer.announce(
                "Startup needs attention. Retry the stopped work or continue with what is ready.")
        }
        .onChange(of: state.rows) { _, rows in
            guard state.phase != .recovery else {
                announcedRows = rows
                return
            }
            if let changed = rows.first(where: { row in
                announcedRows.first(where: { $0.id == row.id })?.status != row.status
            }) {
                announcer.announce(changed.accessibilityLabel)
            }
            announcedRows = rows
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(state.footerTitle)
                        .font(TenXTypography.mono(size: 10, weight: .semibold))
                        .foregroundStyle(footerTitleColor)
                    Text(state.footerDetail)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
                if state.phase == .recovery {
                    HStack(spacing: 8) {
                        Button("Retry", action: onRetry)
                            .font(TenXTypography.body(size: 12, weight: .medium))
                            .buttonStyle(.bordered)
                            .tint(TenXPalette.color(TenXPalette.interactiveCyanHex))
                            .controlSize(.small)
                            .focused($isRetryFocused)
                            .accessibilityFocused($isRetryAccessibilityFocused)
                        Button("Continue to workspace", action: onContinue)
                            .buttonStyle(GhostActionStyle())
                    }
                }
            }
            Spacer(minLength: 24)
            BrandWordmark(width: 38)
        }
    }

    private var footerTitleColor: Color {
        state.phase == .recovery
            ? TenXPalette.color(TenXPalette.signalRedHex)
            : TenXPalette.color(TenXPalette.cyanHex)
    }

    private func focusRecoveryAction() {
        Task { @MainActor in
            await Task.yield()
            isRetryFocused = true
            isRetryAccessibilityFocused = true
        }
    }
}

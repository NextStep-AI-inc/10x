import SwiftUI

struct SplashView: View {
    let presentation: SplashPresentation
    let buildVersion: String

    @Environment(\.accessibilityAnnouncer) private var announcer
    @FocusState private var isPrimaryFocused: Bool
    @AccessibilityFocusState private var isPrimaryAccessibilityFocused: Bool
    @State private var announcedRows: [SplashLedgerRow] = []

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(StartupState.buildLabel(version: buildVersion))
                        .font(TenXTypography.mono(size: 10, weight: .medium))
                        .tracking(1.3)
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    Text(presentation.heading)
                        .font(TenXTypography.title(size: 27))
                        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StartupLedgerView(
                    rows: presentation.rows,
                    accessibilityLabel: presentation.ledgerAccessibilityLabel)
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 10)
            .frame(height: 248)

            StartupSignalView(
                isAnimating: presentation.isSignalAnimating,
                isFailed: presentation.isSignalFailed,
                progress: presentation.signalProgress)
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
        .accessibilityLabel(presentation.accessibilityLabel)
        .onAppear {
            announcedRows = presentation.rows
            if !presentation.actions.isEmpty { focusPrimaryAction() }
        }
        .onChange(of: presentation.screenSignature) { _, _ in
            // Focus and the spoken summary follow the screen changing, not the failure
            // tone. Tone alone missed the launch offer entirely: an update offered during
            // startup is neither an appearance nor a failure, so the primary button never
            // took focus and the user had to hunt for it with the keyboard.
            announcedRows = presentation.rows
            announcer.announce(
                "\(presentation.heading). \(presentation.footerTitle). \(presentation.footerDetail)")
            if !presentation.actions.isEmpty { focusPrimaryAction() }
        }
        .onChange(of: presentation.rows) { _, rows in
            defer { announcedRows = rows }
            guard presentation.footerTone != .failed else { return }
            // A wholly different ledger is a new screen, not progress within a run. The
            // startup steps being replaced by the update steps made every row id new, so
            // a status diff announced "Downloading update, Queued" at the exact moment
            // the app was asking whether to install.
            guard Set(rows.map(\.id)) == Set(announcedRows.map(\.id)) else { return }
            if let changed = rows.first(where: { row in
                announcedRows.first(where: { $0.id == row.id })?.status != row.status
            }) {
                announcer.announce(changed.accessibilityLabel)
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(presentation.footerTitle)
                        .font(TenXTypography.mono(size: 10, weight: .semibold))
                        .foregroundStyle(footerTitleColor)
                    Text(presentation.footerDetail)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
                if !presentation.actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(presentation.actions) { action in
                            actionButton(action)
                        }
                    }
                }
            }
            Spacer(minLength: 24)
            BrandWordmark(width: 38)
        }
    }

    @ViewBuilder
    private func actionButton(_ action: SplashAction) -> some View {
        switch action.kind {
        case .primary:
            Button(action.title) { action.perform() }
                .font(TenXTypography.body(size: 12, weight: .medium))
                .buttonStyle(.bordered)
                .tint(TenXPalette.color(TenXPalette.interactiveCyanHex))
                .controlSize(.small)
                .focused($isPrimaryFocused)
                .accessibilityFocused($isPrimaryAccessibilityFocused)
        case .secondary:
            Button(action.title) { action.perform() }
                .buttonStyle(GhostActionStyle())
        }
    }

    private var footerTitleColor: Color {
        presentation.footerTone == .failed
            ? TenXPalette.color(TenXPalette.signalRedHex)
            : TenXPalette.color(TenXPalette.cyanHex)
    }

    private func focusPrimaryAction() {
        Task { @MainActor in
            await Task.yield()
            isPrimaryFocused = true
            isPrimaryAccessibilityFocused = true
        }
    }
}

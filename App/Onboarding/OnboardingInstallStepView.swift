import AppKit
import SwiftUI

struct OnboardingInstallStepView: View {
    let model: AppModel

    @State private var log: [String] = []
    @State private var isInstalling = false
    @State private var didFail = false
    @State private var installTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.installation != nil {
                installedCard
            } else {
                commandCard
                if !log.isEmpty { logView }
                if didFail {
                    Text("Install failed. The output above shows why.")
                        .font(TenXTypography.body(size: 13))
                        .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                }
            }

            HStack(spacing: 12) {
                if model.installation != nil {
                    Button("Continue") { model.gateRoute() }
                        .buttonStyle(GhostActionStyle())
                } else {
                    Button(isInstalling ? "Installing…" : "Install OMP") { install() }
                        .buttonStyle(GhostActionStyle())
                        .disabled(isInstalling)
                }
                Button("Locate OMP") { locate() }
                    .buttonStyle(GhostActionStyle(
                        color: TenXPalette.color(TenXPalette.nearBlackHex)))
                    .accessibilityHint("Choose the OMP executable on this Mac")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear { installTask?.cancel() }
    }

    private var installedCard: some View {
        CornerCard(color: TenXPalette.color(TenXPalette.cyanHex)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.installation?.version ?? "")
                    .font(TenXTypography.body(weight: .semibold))
                Text(model.installation?.executableURL.path ?? "")
                    .font(TenXTypography.mono())
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var commandCard: some View {
        CornerCard(color: TenXPalette.color(TenXPalette.cyanHex)) {
            VStack(alignment: .leading, spacing: 12) {
                if let unrunnable = model.unrunnableOmpURL {
                    Text("Found at")
                        .font(TenXTypography.body(weight: .semibold))
                    Text(unrunnable.path)
                        .font(TenXTypography.mono())
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .textSelection(.enabled)
                    Text("Run it in a terminal to see why it fails:")
                        .font(TenXTypography.body(size: 12))
                    Text("\(unrunnable.path) --version")
                        .font(TenXTypography.mono())
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .textSelection(.enabled)
                }
                Text("Runs this command:")
                    .font(TenXTypography.body(weight: .semibold))
                Text(OmpInstallRunner.command)
                    .font(TenXTypography.mono())
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .textSelection(.enabled)
                if model.unrunnableOmpURL == nil {
                    Text("Checked automatically")
                        .font(TenXTypography.body(size: 12, weight: .semibold))
                    ForEach(OmpExecutableLocator.knownPaths, id: \.self) { path in
                        Text(path)
                            .font(TenXTypography.mono())
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(log.enumerated()), id: \.offset) { entry in
                        Text(entry.element)
                            .font(TenXTypography.mono())
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.offset)
                    }
                }
            }
            .frame(height: 126)
            .onChange(of: log.count) { _, count in
                proxy.scrollTo(count - 1, anchor: .bottom)
            }
        }
    }

    private func install() {
        log = []
        didFail = false
        isInstalling = true
        installTask = Task {
            do {
                for try await line in OmpInstallRunner().run() { log.append(line) }
            } catch {
                didFail = true
            }
            isInstalling = false
            // Advance only once discovery finds a runnable executable, never on
            // the script's own success line.
            await model.useOmp()
        }
    }

    private func locate() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use OMP"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.useOmp(at: url) }
    }
}

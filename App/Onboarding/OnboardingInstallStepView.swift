import AppKit
import SwiftUI

/// Where `OnboardingInstallStepView` is in its install flow. Distinct from a
/// single `isInstalling` flag so the UI can tell "the script is running"
/// apart from "the script succeeded and OMP discovery is now confirming it
/// runs" — before this, that second phase had no visible indication that
/// anything further would happen.
enum OnboardingInstallPhase: Equatable, Sendable {
    case idle
    case installing
    case verifying

    /// Phase to enter once the install script's output stream finishes.
    static func afterScript(succeeded: Bool) -> OnboardingInstallPhase {
        succeeded ? .verifying : .idle
    }

    /// Phase to enter once discovery (`AppModel.useOmp()`) resolves. Only
    /// `.verifying` transitions here, so this is safe to call unconditionally
    /// after discovery finishes.
    func afterDiscovery() -> OnboardingInstallPhase {
        self == .verifying ? .idle : self
    }
}

struct OnboardingInstallStepView: View {
    let model: AppModel

    @State private var log: [String]
    @State private var phase: OnboardingInstallPhase
    @State private var didFail = false
    @State private var installTask: Task<Void, Never>?

    init(
        model: AppModel,
        initialLog: [String] = [],
        initialPhase: OnboardingInstallPhase = .idle
    ) {
        self.model = model
        _log = State(initialValue: initialLog)
        _phase = State(initialValue: initialPhase)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.installation != nil {
                installedCard
            } else {
                commandCard
                if !log.isEmpty { logView }
                if phase == .verifying {
                    Text("Installed. Checking that OMP runs, then continuing.")
                        .font(TenXTypography.body(size: 13))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                } else if didFail {
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
                    Button(phase == .installing ? "Installing…" : "Install OMP") { install() }
                        .buttonStyle(GhostActionStyle())
                        .disabled(phase != .idle)
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
        phase = .installing
        installTask = Task {
            var succeeded = true
            do {
                for try await line in OmpInstallRunner().run() { log.append(line) }
            } catch {
                didFail = true
                succeeded = false
            }
            phase = OnboardingInstallPhase.afterScript(succeeded: succeeded)
            // Advance only once discovery finds a runnable executable, never on
            // the script's own success line.
            await model.useOmp()
            phase = phase.afterDiscovery()
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

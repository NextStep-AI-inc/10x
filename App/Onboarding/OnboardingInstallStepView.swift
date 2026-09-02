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

enum OnboardingInstallLogDisclosure {
    static func label(reveal: ProgressiveReveal, total: Int) -> String {
        if reveal.canRevealMore(total: total) {
            return "Show \(reveal.nextPageCount(total: total)) older lines"
        }
        return "Show newest \(reveal.initialLimit) lines"
    }

    static func accessibilityLabel(reveal: ProgressiveReveal, total: Int) -> String {
        if reveal.canRevealMore(total: total) {
            return "Show \(reveal.nextPageCount(total: total)) older installer log lines"
        }
        return "Show newest \(reveal.initialLimit) installer log lines"
    }
}

@MainActor
func consumeInstallerOutput<Lines: AsyncSequence>(
    _ lines: Lines,
    into logBuffer: OnboardingInstallLogBuffer,
    isCancelled: () -> Bool,
    onCancellation: () -> Void
) async throws -> Bool where Lines.Element == String {
    for try await line in lines {
        logBuffer.append(line)
        guard !isCancelled() else {
            logBuffer.flush()
            onCancellation()
            return true
        }
    }
    return false
}

struct OnboardingInstallStepView: View {
    let model: AppModel

    @State private var logBuffer: OnboardingInstallLogBuffer
    @State private var logReveal: ProgressiveReveal
    @State private var isAtLiveTail = true
    @State private var hasPositionedLog = false
    @State private var phase: OnboardingInstallPhase
    @State private var didFail = false
    @State private var installTask: Task<Void, Never>?

    init(
        model: AppModel,
        initialLog: [String] = [],
        initialPhase: OnboardingInstallPhase = .idle,
        initialLogReveal: ProgressiveReveal? = nil
    ) {
        self.model = model
        let buffer = OnboardingInstallLogBuffer()
        for line in initialLog {
            buffer.append(line)
        }
        buffer.flush()
        _logBuffer = State(initialValue: buffer)
        _logReveal = State(initialValue: initialLogReveal ?? ProgressiveReveal(initialLimit: 200, pageSize: 200))
        _phase = State(initialValue: initialPhase)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.installation != nil {
                installedCard
            } else {
                commandCard
                if logBuffer.totalCount > 0 { logView }
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
        let lines = logBuffer.visibleTail(limit: logReveal.visibleCount(total: logBuffer.totalCount))
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 12) {
                        if logBuffer.totalCount > logReveal.initialLimit {
                            Button(OnboardingInstallLogDisclosure.label(
                                reveal: logReveal,
                                total: logBuffer.totalCount)) {
                                if logReveal.canRevealMore(total: logBuffer.totalCount) {
                                    logReveal.revealNextPage(total: logBuffer.totalCount)
                                } else {
                                    logReveal.collapse()
                                }
                            }
                            .accessibilityLabel(OnboardingInstallLogDisclosure.accessibilityLabel(
                                reveal: logReveal,
                                total: logBuffer.totalCount))
                            .buttonStyle(GhostActionStyle(horizontalPadding: 0))
                        }
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(logBuffer.completeText, forType: .string)
                        }
                        .buttonStyle(GhostActionStyle(horizontalPadding: 0))
                    }
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(TenXTypography.mono())
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
            }
            .frame(height: 126)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                TranscriptView.shouldFollowBottom(
                    contentOffset: geometry.contentOffset.y,
                    containerHeight: geometry.containerSize.height,
                    contentHeight: geometry.contentSize.height)
            } action: { _, isNearBottom in
                isAtLiveTail = isNearBottom
            }
            .onAppear {
                guard !hasPositionedLog, let lastLine = lines.last else { return }
                hasPositionedLog = true
                proxy.scrollTo(lastLine.id, anchor: .bottom)
            }
            .onChange(of: logBuffer.flushRevision) { _, _ in
                guard isAtLiveTail, let lastLine = lines.last else { return }
                hasPositionedLog = true
                proxy.scrollTo(lastLine.id, anchor: .bottom)
            }
        }
    }

    private func install() {
        logBuffer.reset()
        logReveal = ProgressiveReveal(initialLimit: 200, pageSize: 200)
        isAtLiveTail = true
        hasPositionedLog = false
        didFail = false
        phase = .installing
        installTask = Task {
            do {
                let didStop = try await consumeInstallerOutput(
                    OmpInstallRunner().run(),
                    into: logBuffer,
                    isCancelled: { Task.isCancelled },
                    onCancellation: { phase = .idle })
                guard !didStop else { return }
                guard !Task.isCancelled else {
                    logBuffer.flush()
                    phase = .idle
                    return
                }
                logBuffer.flush()
                phase = OnboardingInstallPhase.afterScript(succeeded: true)
            } catch {
                logBuffer.flush()
                guard !Task.isCancelled else {
                    phase = .idle
                    return
                }
                didFail = true
                phase = OnboardingInstallPhase.afterScript(succeeded: false)
            }
            // Advance only once discovery finds a runnable executable, never on
            // the script's own success line.
            await model.useOmp()
            guard !Task.isCancelled else { return }
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

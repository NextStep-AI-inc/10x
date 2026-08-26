import os
import SwiftUI

struct AssistantMessageContentView: View, Equatable {
    let message: TranscriptMessage

    @Environment(IDEPreferenceStore.self) private var idePreferenceStore
    @Environment(\.fileOpenService) private var fileOpenService
    @Environment(\.fileReferenceBaseURL) private var baseURL
    @Environment(\.openIDEPreferences) private var openIDEPreferences
    @Environment(\.accessibilityAnnouncer) private var accessibilityAnnouncer
    @State private var referenceError: String?
    @State private var clearErrorTask: Task<Void, Never>?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tannerpham.tenx",
        category: "InlineReferences")

    nonisolated static func == (lhs: AssistantMessageContentView, rhs: AssistantMessageContentView) -> Bool {
        lhs.message.id == rhs.message.id
            && lhs.message.document == rhs.message.document
            && lhs.message.isFinal == rhs.message.isFinal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MessageBubbleView.assistantContentSpacing) {
            ForEach(Array(message.document.blocks.enumerated()), id: \.offset) { _, block in
                MessageBlockView(block: block)
            }
            if let referenceError {
                Text(referenceError)
                    .font(TenXTypography.body(size: 10, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                    .accessibilityLabel(referenceError)
            }
        }
        .environment(\.openURL, OpenURLAction(handler: openInlineReference))
        .onDisappear { clearErrorTask?.cancel() }
    }

    private func openInlineReference(_ url: URL) -> OpenURLAction.Result {
        guard case .file(let path, let line) = TranscriptReference(inlineURL: url) else {
            return .systemAction
        }

        clearReferenceError()
        let resolved = FileReferenceResolver().resolve(
            path: path,
            line: line,
            relativeTo: baseURL)
        switch FileReferenceActivation.resolve(
            preference: idePreferenceStore.state,
            reference: resolved,
            isOptionPressed: false) {
        case .openInIDE(let application):
            open(resolved, in: application)
        case .openPreferences:
            openIDEPreferences()
        case .revealInFinder:
            if let fileURL = resolved.url {
                fileOpenService.reveal(fileURL)
            }
        case .unavailable:
            showReferenceError("File isn’t available: \(resolved.compactLabel)")
        }
        return .handled
    }

    private func open(_ reference: ResolvedFileReference, in application: IDEApplication) {
        guard let fileURL = reference.url else { return }
        Task {
            do {
                try await fileOpenService.open(fileURL, in: application)
            } catch {
                Self.logger.error(
                    "[InlineReferences:open] Could not open file — application=\(application.displayName, privacy: .public), path=\(reference.fullPathLabel, privacy: .private(mask: .hash)), error=\(String(describing: error), privacy: .private)")
                showReferenceError("Couldn’t open in \(application.displayName)")
            }
        }
    }

    private func clearReferenceError() {
        clearErrorTask?.cancel()
        referenceError = nil
    }

    private func showReferenceError(_ message: String) {
        clearReferenceError()
        referenceError = message
        accessibilityAnnouncer.announce(message)
        clearErrorTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            referenceError = nil
        }
    }
}

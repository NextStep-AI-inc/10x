import AppKit
import os
import SwiftUI

struct TranscriptReferenceView: View {
    let reference: TranscriptReference

    var body: some View {
        switch reference {
        case .file(let path, let line):
            FileTranscriptReferenceView(path: path, line: line)
        case .web(let value, let label):
            if let url = URL(string: value) {
                Link(destination: url) {
                    Label(label ?? url.host ?? value, systemImage: "arrow.up.right")
                }
                .buttonStyle(GhostActionStyle())
                .contextMenu { copyButton(value) }
                .accessibilityLabel("Web reference, \(label ?? value)")
            }
        }
    }

    private func copyButton(_ value: String) -> some View {
        Button("Copy reference") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
    }
}

private struct FileTranscriptReferenceView: View {
    let path: String
    let line: Int?

    @Environment(IDEPreferenceStore.self) private var idePreferenceStore
    @Environment(\.fileOpenService) private var fileOpenService
    @Environment(\.fileReferenceBaseURL) private var baseURL
    @Environment(\.openIDEPreferences) private var openIDEPreferences
    @Environment(\.accessibilityAnnouncer) private var accessibilityAnnouncer
    @State private var isHovering = false
    @State private var isOptionPressed = false
    @State private var errorStatus: String?
    @State private var clearErrorTask: Task<Void, Never>?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tannerpham.tenx",
        category: "FileReferences")

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            fileAction
            if let errorStatus {
                Text(errorStatus)
                    .font(TenXTypography.body(size: 10, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                    .accessibilityLabel(errorStatus)
            }
        }
        .onDisappear { clearErrorTask?.cancel() }
    }

    private var resolvedReference: ResolvedFileReference {
        FileReferenceResolver().resolve(path: path, line: line, relativeTo: baseURL)
    }

    private var fileAction: some View {
        Button(action: activateFileReference) {
            FileReferenceLabel(
                reference: resolvedReference,
                showsFullPath: isHovering && isOptionPressed)
        }
        .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.nearBlackHex)))
        .disabled(!resolvedReference.exists)
        .onHover { isHovering = $0 }
        .onModifierKeysChanged(mask: .option, initial: true) { _, modifiers in
            isOptionPressed = modifiers.contains(.option)
        }
        .contextMenu { contextMenu }
        .accessibilityLabel(fileAccessibilityLabel)
        .accessibilityHint(fileAccessibilityHint)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Open with System Default", action: openWithSystemDefault)
            .disabled(!resolvedReference.exists)
        if case .available(let application) = idePreferenceStore.state {
            Button("Open in \(application.displayName)") {
                openInIDE(application)
            }
            .disabled(!resolvedReference.exists)
        }
        Button("Reveal in Finder", action: revealInFinder)
            .disabled(!resolvedReference.exists)
        Button("Copy Reference", action: copyReference)
    }

    private var fileAccessibilityLabel: String {
        guard resolvedReference.exists else {
            return "File reference unavailable, \(resolvedReference.fullPathLabel)"
        }
        switch idePreferenceStore.state {
        case .available(let application):
            return "Open \(resolvedReference.compactLabel) in \(application.displayName), \(resolvedReference.fullPathLabel)"
        case .none, .unavailable:
            return "Choose an IDE for \(resolvedReference.fullPathLabel)"
        }
    }

    private var fileAccessibilityHint: String {
        resolvedReference.exists
            ? "Hold Option while clicking to reveal in Finder"
            : "Copy its reference from the context menu"
    }

    private func openWithSystemDefault() {
        beginInteraction()
        guard resolvedReference.exists, let url = resolvedReference.url else { return }
        do {
            try fileOpenService.openWithSystemDefault(url)
        } catch {
            Self.logger.error(
                "[FileReferences:openWithSystemDefault] Could not open file — path=\(resolvedReference.fullPathLabel, privacy: .private(mask: .hash)), error=\(String(describing: error), privacy: .private)")
            showError("Couldn’t open \(resolvedReference.compactLabel)")
        }
    }

    private func activateFileReference() {
        switch FileReferenceActivation.resolve(
            preference: idePreferenceStore.state,
            reference: resolvedReference,
            isOptionPressed: isOptionPressed
        ) {
        case .openInIDE(let application):
            openInIDE(application)
        case .openPreferences:
            beginInteraction()
            openIDEPreferences()
        case .revealInFinder:
            revealInFinder()
        case .unavailable:
            break
        }
    }

    private func openInIDE(_ application: IDEApplication) {
        beginInteraction()
        guard resolvedReference.exists, let url = resolvedReference.url else { return }
        Task {
            do {
                try await fileOpenService.open(url, in: application)
            } catch {
                Self.logger.error(
                    "[FileReferences:openInIDE] Could not open file — application=\(application.displayName, privacy: .public), path=\(resolvedReference.fullPathLabel, privacy: .private(mask: .hash)), error=\(String(describing: error), privacy: .private)")
                showError("Couldn’t open in \(application.displayName)")
            }
        }
    }

    private func revealInFinder() {
        beginInteraction()
        guard resolvedReference.exists, let url = resolvedReference.url else { return }
        fileOpenService.reveal(url)
    }

    private func copyReference() {
        beginInteraction()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resolvedReference.originalReference, forType: .string)
    }

    private func beginInteraction() {
        clearErrorTask?.cancel()
        errorStatus = nil
    }

    private func showError(_ message: String) {
        clearErrorTask?.cancel()
        errorStatus = message
        accessibilityAnnouncer.announce(message)
        clearErrorTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            errorStatus = nil
        }
    }
}

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

    private var actionHandler: FileReferenceActionHandler {
        FileReferenceActionHandler(
            fileOpenService: fileOpenService,
            openIDEPreferences: openIDEPreferences)
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
        .accessibilityRepresentation {
            Button(fileAccessibilityLabel, action: activateFileReference)
                .disabled(!resolvedReference.exists)
                .accessibilityHint(fileAccessibilityHint)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Open with System Default", action: openWithSystemDefault)
            .disabled(!resolvedReference.exists)
        if case .available(let application) = idePreferenceStore.state {
            Button("Open in \(application.displayName)") {
                perform(.openInIDE(application))
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
        perform(FileReferenceActivation.resolve(
            preference: idePreferenceStore.state,
            reference: resolvedReference,
            isOptionPressed: isOptionPressed
        ))
    }

    private func revealInFinder() {
        perform(.revealInFinder)
    }

    private func perform(_ action: FileReferenceActivation) {
        guard action != .unavailable else { return }
        beginInteraction()
        Task {
            do {
                try await actionHandler.perform(action, reference: resolvedReference)
            } catch {
                Self.logger.error(
                    "[FileReferences:perform] Could not activate file reference — action=\(String(describing: action), privacy: .private(mask: .hash)), path=\(resolvedReference.fullPathLabel, privacy: .private(mask: .hash)), error=\(String(describing: error), privacy: .private)")
                showError(errorMessage(for: action))
            }
        }
    }

    private func errorMessage(for action: FileReferenceActivation) -> String {
        if case .openInIDE(let application) = action {
            return "Couldn’t open in \(application.displayName)"
        }
        return "Couldn’t open \(resolvedReference.compactLabel)"
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

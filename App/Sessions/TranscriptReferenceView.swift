import AppKit
import os
import SwiftUI

struct FileReferenceIDEActionPresentation {
    let title: String
    let isEnabled: Bool
    let showsUnavailableSymbol: Bool
    let accessibilityLabel: String

    static func make(
        preference: IDEPreferenceState,
        reference: ResolvedFileReference
    ) -> FileReferenceIDEActionPresentation {
        switch preference {
        case .available(let application):
            let action = "Open in \(application.displayName)"
            return FileReferenceIDEActionPresentation(
                title: action,
                isEnabled: reference.exists,
                showsUnavailableSymbol: !reference.exists,
                accessibilityLabel: reference.exists
                    ? "Open \(reference.compactLabel) in \(application.displayName), \(reference.fullPathLabel)"
                    : "Open \(reference.compactLabel) in \(application.displayName), Unavailable, \(reference.fullPathLabel)")
        case .none, .unavailable:
            return FileReferenceIDEActionPresentation(
                title: "Choose IDE",
                isEnabled: true,
                showsUnavailableSymbol: false,
                accessibilityLabel: "Choose an IDE for \(reference.fullPathLabel)")
        }
    }
}

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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    fileAction
                    ideAction
                }
                VStack(alignment: .leading, spacing: 0) {
                    fileAction
                    ideAction
                }
            }
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
        Button(action: openWithSystemDefault) {
            FileReferenceLabel(
                reference: resolvedReference,
                showsFullPath: isHovering && isOptionPressed)
        }
        .buttonStyle(GhostActionStyle(color: fileColor))
        .disabled(!resolvedReference.exists)
        .onHover { isHovering = $0 }
        .onModifierKeysChanged(mask: .option, initial: true) { _, modifiers in
            isOptionPressed = modifiers.contains(.option)
        }
        .contextMenu { contextMenu }
        .accessibilityLabel("File reference, \(resolvedReference.fullPathLabel)")
        .accessibilityHint(resolvedReference.exists
            ? "Opens with the system default application"
            : "File unavailable. Copy its reference from the context menu")
    }

    private var ideAction: some View {
        Button(action: performIDEAction) {
            HStack(spacing: 4) {
                Text(ideActionPresentation.title)
                if ideActionPresentation.showsUnavailableSymbol {
                    Image(systemName: "exclamationmark.circle")
                        .accessibilityHidden(true)
                }
            }
        }
            .buttonStyle(GhostActionStyle())
            .frame(minHeight: 32)
            .disabled(!ideActionPresentation.isEnabled)
            .accessibilityLabel(ideActionPresentation.accessibilityLabel)
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

    private var fileColor: Color {
        TenXPalette.color(resolvedReference.exists
            ? TenXPalette.interactiveCyanHex
            : TenXPalette.mutedTextHex)
    }

    private var ideActionPresentation: FileReferenceIDEActionPresentation {
        FileReferenceIDEActionPresentation.make(
            preference: idePreferenceStore.state,
            reference: resolvedReference)
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

    private func performIDEAction() {
        beginInteraction()
        guard case .available(let application) = idePreferenceStore.state else {
            openIDEPreferences()
            return
        }
        openInIDE(application)
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

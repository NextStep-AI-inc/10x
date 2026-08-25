import AppKit
import SwiftUI

struct TranscriptReferenceView: View {
    let reference: TranscriptReference

    var body: some View {
        switch reference {
        case .file(let path, let line):
            Button(action: {
                if FileManager.default.fileExists(atPath: path) { openFile(path) }
            }) {
                Label(fileLabel(path: path, line: line), systemImage: "doc.text")
            }
            .buttonStyle(GhostActionStyle(color: fileColor(path)))
            .contextMenu { copyButton(path + (line.map { ":\($0)" } ?? "")) }
            .accessibilityHint(FileManager.default.fileExists(atPath: path)
                ? "Opens the referenced file"
                : "File is unavailable; use the context menu to copy its path")
        case .web(let value, let label):
            if let url = URL(string: value) {
                Link(destination: url) {
                    Label(label ?? url.host ?? value, systemImage: "arrow.up.right")
                }
                .buttonStyle(GhostActionStyle())
                .contextMenu { copyButton(value) }
            }
        }
    }

    private func fileLabel(path: String, line: Int?) -> String {
        URL(filePath: path).lastPathComponent + (line.map { ":\($0)" } ?? "")
    }

    private func fileColor(_ path: String) -> Color {
        FileManager.default.fileExists(atPath: path)
            ? TenXPalette.color(TenXPalette.cyanHex)
            : TenXPalette.color(TenXPalette.mutedTextHex)
    }

    private func openFile(_ path: String) {
        NSWorkspace.shared.open(URL(filePath: path))
    }

    private func copyButton(_ value: String) -> some View {
        Button("Copy reference") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
    }
}

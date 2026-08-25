import AppKit
import SwiftUI

struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(language?.uppercased() ?? "CODE")
                    .font(TenXTypography.mono(size: 10, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                Spacer()
                Button("Copy") { copy() }
                    .buttonStyle(GhostActionStyle())
                    .accessibilityLabel("Copy code")
            }
            ScrollView([.horizontal, .vertical]) {
                Text(code)
                    .font(TenXTypography.mono(size: 11))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.bottom, 4)
            }
        }
        .padding(10)
        .frame(height: codeHeight)
        .background(TenXPalette.color(TenXPalette.hoverNeutralHex))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var codeHeight: CGFloat {
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false).count
        return min(320, max(76, CGFloat(lines) * 15 + 50))
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }
}

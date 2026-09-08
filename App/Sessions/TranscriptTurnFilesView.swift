import SwiftUI

struct TranscriptTurnFilesView: View {
    let files: [TranscriptTurnFile]
    let onSelect: (TranscriptTurnFile) -> Void

    nonisolated static func navigationRequest(
        for file: TranscriptTurnFile
    ) -> TranscriptNavigationRequest {
        TranscriptNavigationRequest(rowID: "tool:\(file.toolID)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tool-reported files (\(files.count))")
                .font(TenXTypography.body(size: 11, weight: .semibold))
                .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))

            Text("Completed edit and write tools in this turn. Shell commands and other workspace changes are not included.")
                .font(TenXTypography.body(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(files) { file in
                    Button {
                        onSelect(file)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10))
                            Text(file.path)
                                .font(TenXTypography.mono(size: 10))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
                    .accessibilityLabel("Show tool details for \(file.path)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

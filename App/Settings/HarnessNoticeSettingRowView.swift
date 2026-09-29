import SwiftUI

struct HarnessNoticeSettingRowView: View {
    @Bindable var store: HarnessNoticePreferenceStore

    nonisolated static let title = "Show agent guidance"
    nonisolated static let supportingText =
        "Show compact advisor notes, internal instructions, and extra activity in the transcript."

    nonisolated static func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return [title, supportingText, "agent guidance", "advisor", "internal instructions"]
            .contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Self.title)
                    .font(TenXTypography.body(size: 13, weight: .semibold))
                Text(Self.supportingText)
                    .font(TenXTypography.body(size: 11))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $store.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(TenXPalette.color(TenXPalette.cyanHex))
                .accessibilityLabel(Self.title)
        }
        .padding(.vertical, 14)
    }
}

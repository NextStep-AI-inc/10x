import SwiftUI

struct HarnessNoticeSettingRowView: View {
    @Bindable var store: HarnessNoticePreferenceStore
    let availableModels: [ComposerModelInfo]

    private static let thresholds: [(value: Int, label: String)] = [
        (0, "Everything"),
        (500, "500 chars"),
        (1_000, "1 KB"),
        (4_000, "4 KB"),
    ]

    static func matches(query: String) -> Bool {
        query.isEmpty
            || "hidden harness messages".localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Hidden harness messages")
                        .font(TenXTypography.body(size: 13, weight: .semibold))
                    Text("Show a transcript notice when a harness message is kept out of the chat, with a one-line summary from a small model")
                        .font(TenXTypography.body(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: $store.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if store.isEnabled {
                HStack(spacing: 30) {
                    Text("Notice threshold")
                        .font(TenXTypography.body(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        ForEach(Self.thresholds, id: \.value) { option in
                            Button(option.label) { store.threshold = option.value }
                        }
                    } label: {
                        Text(thresholdLabel)
                            .font(TenXTypography.body(size: 12))
                            .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    }
                    .menuStyle(.borderlessButton)
                }

                HStack(spacing: 30) {
                    Text("Summary model")
                        .font(TenXTypography.body(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        Button("OMP smol role") { store.modelOverride = nil }
                        if !availableModels.isEmpty {
                            Divider()
                            ForEach(availableModels) { model in
                                Button(model.name) { store.modelOverride = model.modelID }
                            }
                        }
                    } label: {
                        Text(modelLabel)
                            .font(TenXTypography.body(size: 12))
                            .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
        .padding(.vertical, 14)
    }

    private var thresholdLabel: String {
        Self.thresholds.first(where: { $0.value == store.threshold })?.label
            ?? "\(store.threshold) chars"
    }

    private var modelLabel: String {
        guard let override = store.modelOverride else { return "OMP smol role" }
        return availableModels.first(where: { $0.modelID == override })?.name ?? override
    }
}

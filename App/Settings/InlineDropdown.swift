import SwiftUI

struct InlineDropdown: View {
    let options: [SettingOption]
    let current: String
    /// Shown when current is empty (e.g. "Add…" for list editors).
    var prompt: String? = nil
    var allowsOther = true
    var accessibilityLabelText: String? = nil
    let onSelect: (String) -> Void

    @State private var isExpanded = false
    @State private var showsOther = false
    @State private var otherDraft = ""

    private var presentation: EnumPresentation {
        EnumPresentation(options: options, currentValue: current)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(current.isEmpty ? (prompt ?? "") : presentation.displayText(for: current))
                        .font(TenXTypography.mono(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if presentation.customValue != nil {
                        Text("custom")
                            .font(TenXTypography.mono(size: 8))
                            .foregroundStyle(TenXPalette.color(TenXPalette.yellowHex))
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(TenXPalette.color(TenXPalette.nearBlackHex))
                        .frame(height: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabelText ?? prompt ?? "Value")
            .accessibilityValue(current.isEmpty ? "" : presentation.displayText(for: current))

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if let custom = presentation.customValue {
                                optionRow(value: custom, label: custom,
                                          detail: "Current value (not a known option)", selected: true)
                            }
                            ForEach(options, id: \.value) { option in
                                optionRow(value: option.value,
                                          label: option.label ?? option.value,
                                          detail: option.detail,
                                          selected: option.value == current)
                            }
                        }
                    }
                    .frame(maxHeight: 220)

                    if allowsOther {
                        Rectangle()
                            .fill(TenXPalette.color(TenXPalette.separatorHex))
                            .frame(height: 1)
                        if showsOther {
                            HStack(spacing: 4) {
                                TextField("Custom value", text: $otherDraft)
                                    .textFieldStyle(.plain)
                                    .font(TenXTypography.mono(size: 11))
                                    .onSubmit(commitOther)
                                Button("Apply", action: commitOther)
                                    .buttonStyle(GhostActionStyle())
                            }
                            .padding(8)
                        } else {
                            Button {
                                showsOther = true
                            } label: {
                                Text("Other…")
                                    .font(TenXTypography.mono(size: 10))
                                    .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .background(TenXPalette.color(TenXPalette.canvasHex))
                .overlay(Rectangle().stroke(TenXPalette.color(TenXPalette.separatorHex)))
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            guard !expanded else { return }
            showsOther = false
            otherDraft = ""
        }
    }

    private func optionRow(value: String, label: String, detail: String?, selected: Bool) -> some View {
        Button {
            onSelect(value)
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded = false }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(TenXTypography.body(size: 12, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(TenXTypography.body(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .lineLimit(2)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(FlyoutRowBackground(isSelected: selected))
        .accessibilityValue(selected ? "selected" : "")
    }

    private func commitOther() {
        let value = otherDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onSelect(value)
        otherDraft = ""
        showsOther = false
        isExpanded = false
    }
}

import SwiftUI

struct ComposerSessionControlsView: View {
    let model: ComposerControlsModel
    let mode: ComposerControlsMode

    private var menusDisabled: Bool {
        model.isLoading || model.isMutating || model.models.isEmpty
    }

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(model.models) { item in
                    Button(item.name) {
                        Task { await model.selectModel(item, mode: mode) }
                    }
                }
            } label: {
                Text(model.selectedModel?.name ?? "Model")
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.nearBlackHex)))
            .disabled(menusDisabled)
            .accessibilityLabel("Model")
            .accessibilityValue(model.selectedModel?.name ?? "None")

            if !model.thinkingOptions.isEmpty {
                Menu {
                    ForEach(model.thinkingOptions, id: \.self) { level in
                        Button(level.capitalized) {
                            Task { await model.selectThinking(level, mode: mode) }
                        }
                    }
                } label: {
                    Text(model.thinkingLevel.capitalized)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.nearBlackHex)))
                .disabled(menusDisabled)
                .accessibilityLabel("Thinking")
                .accessibilityValue(model.thinkingLevel.capitalized)
            }

            if model.isFastModeVisible {
                Button("Fast") {
                    Task { await model.setFastMode(!model.isFastModeEnabled, mode: mode) }
                }
                .buttonStyle(GhostActionStyle(
                    color: TenXPalette.color(
                        model.isFastModeEnabled
                            ? TenXPalette.cyanHex
                            : TenXPalette.nearBlackHex)))
                .disabled(model.isMutating)
                .accessibilityLabel("Fast mode")
                .accessibilityValue(model.isFastModeEnabled ? "On" : "Off")
            }
        }
    }
}

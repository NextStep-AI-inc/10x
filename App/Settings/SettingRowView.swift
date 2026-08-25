import SwiftUI

struct SettingRowView: View {
    let definition: SettingDefinition
    let model: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(definition.displayLabel)
                            .font(TenXTypography.body(size: 13, weight: .semibold))
                        if definition.requiresRestart {
                            Text("RESTART")
                                .font(TenXTypography.mono(size: 8, weight: .semibold))
                                .foregroundStyle(TenXPalette.color(TenXPalette.yellowHex))
                        }
                    }
                    if !definition.description.isEmpty {
                        Text(definition.description)
                            .font(TenXTypography.body(size: 11))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(definition.key)
                        .font(TenXTypography.mono(size: 9))
                        .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SettingControlView(definition: definition, model: model)
                    .frame(width: 300, alignment: .trailing)
            }

            if let error = model.error(for: definition.key) {
                Text(error)
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            }
        }
        .padding(.vertical, 15)
        .accessibilityElement(children: .contain)
    }
}

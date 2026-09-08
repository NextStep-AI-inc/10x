import SwiftUI

struct ComposerInteractionSettingRows: View {
    let preferences: ComposerInteractionPreferences

    var body: some View {
        preferenceRow(
            title: "Default send action",
            detail: "Action used by the primary send shortcut"
        ) {
            Menu {
                ForEach(ComposerSendAction.allCases, id: \.self) { action in
                    Button(action.title) { preferences.defaultSendAction = action }
                }
            } label: {
                Text(preferences.defaultSendAction.title)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 180, alignment: .trailing)
            .accessibilityLabel("Default send action")
            .accessibilityValue(preferences.defaultSendAction.title)
        }

        Divider()

        ForEach(ComposerReturnShortcut.allCases) { shortcut in
            preferenceRow(title: shortcut.title, detail: "Composer keyboard shortcut") {
                Menu {
                    ForEach(ComposerReturnAction.allCases, id: \.self) { action in
                        Button(preferences.title(for: action)) {
                            preferences.assign(action, to: shortcut)
                        }
                    }
                } label: {
                    Text(preferences.title(for: preferences.action(for: shortcut)))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 180, alignment: .trailing)
                .accessibilityLabel(shortcut.title)
                .accessibilityValue(preferences.title(for: preferences.action(for: shortcut)))
            }

            if shortcut != ComposerReturnShortcut.allCases.last { Divider() }
        }
    }

    private func preferenceRow<Control: View>(
        title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(TenXTypography.body(size: 13, weight: .semibold))
                Text(detail)
                    .font(TenXTypography.body(size: 11))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .padding(.vertical, 15)
        .accessibilityElement(children: .contain)
    }
}

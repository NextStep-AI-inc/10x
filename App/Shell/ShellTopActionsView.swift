import SwiftUI

struct ShellTopActionsView: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            action(
                title: "Search",
                systemImage: "magnifyingglass",
                isSelected: model.isSearchPresented,
                perform: model.openSearch)
                .keyboardShortcut("k", modifiers: .command)
            action(
                title: "New session",
                systemImage: "plus",
                isSelected: model.route == .newSession,
                perform: model.openNewSession)
        }
    }

    private func action(
        title: String,
        systemImage: String,
        isSelected: Bool,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected
                    ? TenXPalette.color(TenXPalette.cyanHex)
                    : TenXPalette.color(TenXPalette.nearBlackHex))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(title)
        .accessibilityLabel(title)
    }
}

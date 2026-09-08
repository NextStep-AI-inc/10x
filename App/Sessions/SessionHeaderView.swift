import SwiftUI

private struct RenameCurrentSessionKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable () -> Void)? = nil
}

extension EnvironmentValues {
    var renameCurrentSession: (@MainActor @Sendable () -> Void)? {
        get { self[RenameCurrentSessionKey.self] }
        set { self[RenameCurrentSessionKey.self] = newValue }
    }
}

struct SessionHeaderView: View {
    let controller: SessionController
    var isMapVisible = false
    var mapToggleFocusRequest = 0
    var onToggleMap: (() -> Void)?
    @Environment(\.renameCurrentSession) private var renameCurrentSession
    @FocusState private var isMapToggleFocused: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 4) {
                SessionTitleView(title: controller.title, isLoading: controller.isTitleLoading)
                    .font(TenXTypography.body(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        renameCurrentSession?()
                    }
                    .contextMenu {
                        if let renameCurrentSession {
                            Button("Rename Session...", systemImage: "pencil") {
                                renameCurrentSession()
                            }
                        }
                    }
                    .accessibilityAction(named: Text("Rename Session")) {
                        renameCurrentSession?()
                    }

                if !controller.headerMetadata.presentationItems.isEmpty {
                    HStack(spacing: 14) {
                        ForEach(controller.headerMetadata.presentationItems) { item in
                            HStack(spacing: 4) {
                                Image(systemName: item.systemImage)
                                    .font(.system(size: 9, weight: .medium))
                                Text(item.value)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(item.accessibilityLabel)
                            .accessibilityValue(item.value)
                        }
                    }
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: 480)
            .padding(.leading, 42)
            .padding(.trailing, 92)

            if let onToggleMap {
                HStack {
                    Spacer()
                    Button("Map", systemImage: "point.3.connected.trianglepath.dotted") {
                        onToggleMap()
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(GhostActionStyle(horizontalPadding: 8))
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .focusable()
                    .focused($isMapToggleFocused)
                    .onKeyPress(keys: [.return, .space], phases: .down) { _ in
                        onToggleMap()
                        return .handled
                    }
                    .accessibilityLabel(isMapVisible ? "Close session map" : "Open session map")
                    .accessibilityValue(isMapVisible ? "Open" : "Closed")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onToggleMap() }
                    .padding(.trailing, 16)
                }
            }
        }
        .frame(height: 54)
        .onChange(of: mapToggleFocusRequest) { _, _ in
            isMapToggleFocused = true
        }
    }
}

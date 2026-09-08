import SwiftUI

struct SessionHeaderView: View {
    let controller: SessionController

    @State private var isComputerPopoverPresented = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(controller.title)
                    .font(TenXTypography.body(size: 13, weight: .semibold))
                    .lineLimit(1)
            }

            if !controller.headerMetadata.presentationItems.isEmpty || computerItem != nil {
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

                    if let computer = computerItem {
                        Button { isComputerPopoverPresented.toggle() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "display")
                                    .font(.system(size: 9, weight: .medium))
                                Text(computer.label)
                            }
                            .foregroundStyle(computer.isControlling
                                ? TenXPalette.color(TenXPalette.cyanHex)
                                : TenXPalette.color(TenXPalette.mutedTextHex))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Computer use")
                        .accessibilityValue(computer.label)
                        .popover(isPresented: $isComputerPopoverPresented) {
                            CurrentlyViewingPopover(
                                framePNG: controller.computerUse.latestFrame,
                                windowTitle: computer.label,
                                status: controller.computerUse.status,
                                onStop: {
                                    isComputerPopoverPresented = false
                                    Task { await controller.computerUse.stopComputerUse() }
                                })
                        }
                    }
                }
                .font(TenXTypography.mono(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .lineLimit(1)
            }
        }
        .frame(maxWidth: 680)
        .frame(height: 54)
        .padding(.leading, 42)
        .padding(.trailing, 92)
    }

    private var computerItem: (label: String, isControlling: Bool)? {
        guard controller.computerUse.isEnabled else { return nil }
        let names = controller.computerUse.windowAppNames
        let label = names.first ?? "Computer"
        return (label, controller.computerUse.phase == .controlling)
    }
}

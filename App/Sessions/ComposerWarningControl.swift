import SwiftUI

struct ComposerWarningControl: View {
    let messages: [String]
    @Binding var isPresented: Bool
    var onRestoreFocus: () -> Void = {}

    @State private var anchor: FlyoutWindowAnchor?
    @State private var contentHeight: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var desiredPanelSize: CGSize {
        CGSize(width: 360, height: contentHeight ?? CGFloat(messages.count) * 44)
    }

    var body: some View {
        trigger
            .background {
                FlyoutWindowAnchorReader { nextAnchor in
                    if anchor != nextAnchor { anchor = nextAnchor }
                }
            }
            .overlay(alignment: .topLeading) {
                if isPresented {
                    flyout
                        .offset(x: panelOffsetX, y: panelOffsetY)
                        .transition(transition)
                        .zIndex(3)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isPresented)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: contentHeight)
            .frame(width: 32, height: 28)
            .opacity(messages.isEmpty ? 0 : 1)
            .allowsHitTesting(!messages.isEmpty)
            .accessibilityHidden(messages.isEmpty)
            .onChange(of: messages) { _, messages in
                if messages.isEmpty { isPresented = false }
            }
            .onExitCommand {
                guard isPresented else { return }
                closeAndRestoreFocus()
            }
    }

    private var trigger: some View {
        Button {
            if isPresented {
                closeAndRestoreFocus()
            } else {
                isPresented = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium))
                Text(messages.count.formatted())
                    .font(TenXTypography.mono(size: 10, weight: .semibold))
            }
            .frame(height: 28)
        }
        .buttonStyle(GhostActionStyle(
            color: TenXPalette.color(TenXPalette.signalRedHex),
            horizontalPadding: 5))
        .opacity(isPresented ? 0 : 1)
        .accessibilityHidden(isPresented)
        .accessibilityLabel("Composer warnings")
        .accessibilityValue(countLabel)
        .accessibilityHint("Shows warning details")
    }

    private var flyout: some View {
        ConnectedFlyoutShelf(
            panelSize: resolvedPlacement.panelFrame.size,
            triggerSize: CGSize(
                width: min(
                    anchor?.triggerFrame.width ?? 42,
                    resolvedPlacement.panelFrame.width),
                height: anchor?.triggerFrame.height ?? 28),
            triggerOffsetX: resolvedPlacement.triggerOffsetX,
            direction: resolvedPlacement.direction,
            fill: TenXPalette.color(TenXPalette.canvasHex),
            onDismiss: { isPresented = false },
            panelContent: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(messages, id: \.self) { message in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                                    .padding(.top, 2)
                                    .accessibilityHidden(true)
                                Text(message)
                                    .font(TenXTypography.body(size: 11))
                                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(FlyoutRowBackground(isSelected: false))
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: FlyoutContentHeightKey.self,
                                value: geometry.size.height)
                        }
                    }
                }
                .onPreferenceChange(FlyoutContentHeightKey.self) { height in
                    guard height > 0 else { return }
                    contentHeight = height
                }
                .frame(
                    width: resolvedPlacement.panelFrame.width,
                    height: resolvedPlacement.panelFrame.height)
            },
            triggerContent: { openTrigger })
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Composer warnings")
            .accessibilityValue(countLabel)
    }

    private var openTrigger: some View {
        Button(action: closeAndRestoreFocus) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium))
                Text(messages.count.formatted())
                    .font(TenXTypography.mono(size: 10, weight: .semibold))
            }
            .frame(height: 28)
        }
        .buttonStyle(GhostActionStyle(
            color: TenXPalette.color(TenXPalette.signalRedHex),
            horizontalPadding: 5))
        .accessibilityLabel("Composer warnings")
        .accessibilityValue(countLabel)
        .accessibilityHint("Menu open")
    }

    private var countLabel: String {
        messages.count == 1 ? "1 warning" : "\(messages.count) warnings"
    }

    private var placement: FlyoutPlacement? {
        anchor.map {
            FlyoutPlacement.resolve(
                triggerFrame: $0.triggerFrame,
                desiredPanelSize: desiredPanelSize,
                usableBounds: $0.usableBounds,
                preferredDirection: .above)
        }
    }

    private var resolvedPlacement: FlyoutPlacement {
        placement ?? FlyoutPlacement(
            direction: .above,
            panelFrame: CGRect(origin: .zero, size: desiredPanelSize),
            triggerOffsetX: 0,
            isHeightConstrained: false)
    }

    private var panelOffsetX: CGFloat {
        guard let anchor, let placement else { return 0 }
        return placement.panelFrame.minX - anchor.triggerFrame.minX
    }

    private var panelOffsetY: CGFloat {
        resolvedPlacement.direction == .above ? -resolvedPlacement.panelFrame.height : 0
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .identity }
        let offset = resolvedPlacement.direction == .above ? 8.0 : -8.0
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: offset)),
            removal: .opacity.combined(with: .offset(y: offset / 2)))
    }

    private func closeAndRestoreFocus() {
        isPresented = false
        onRestoreFocus()
    }
}

import OmpKit
import SwiftUI

struct SendActionControl: View {
    let selection: StreamingBehavior
    let onSelect: (StreamingBehavior) -> Void
    @Binding var isPresented: Bool
    var onRestoreFocus: () -> Void = {}

    @State private var anchor: FlyoutWindowAnchor?
    @State private var highlightedIndex = 0
    @FocusState private var isPanelFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let choices: [(behavior: StreamingBehavior, title: String, detail: String)] = [
        (.steer, "Steer", "Send during the current response"),
        (.followUp, "Follow up", "Queue for the next turn"),
    ]
    private static let desiredPanelSize = CGSize(width: 272, height: 104)

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
            .onChange(of: isPresented) { _, isPresented in
                guard isPresented else { return }
                highlightedIndex = selection == .followUp ? 1 : 0
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
            Text(selection == .followUp ? "Follow up" : "Steer")
                .font(TenXTypography.body(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .buttonStyle(GhostActionStyle(
            color: TenXPalette.color(TenXPalette.nearBlackHex),
            horizontalPadding: 5))
        .opacity(isPresented ? 0 : 1)
        .accessibilityHidden(isPresented)
        .accessibilityLabel("Composer send action")
        .accessibilityValue(selection == .followUp ? "Follow up" : "Steer")
        .accessibilityHint("Shows send action menu")
    }

    private var flyout: some View {
        ConnectedFlyoutShelf(
            panelSize: resolvedPlacement.panelFrame.size,
            triggerSize: CGSize(
                width: min(
                    anchor?.triggerFrame.width ?? 72,
                    resolvedPlacement.panelFrame.width),
                height: anchor?.triggerFrame.height ?? 28),
            triggerOffsetX: resolvedPlacement.triggerOffsetX,
            direction: resolvedPlacement.direction,
            fill: TenXPalette.color(TenXPalette.canvasHex),
            onDismiss: { isPresented = false },
            panelContent: { rows },
            triggerContent: { openTrigger })
            .focusable()
            .focused($isPanelFocused)
            .onKeyPress(
                keys: [.upArrow, .downArrow, .return, .escape],
                phases: .down,
                action: handleKey)
            .task {
                await Task.yield()
                isPanelFocused = true
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Composer send action")
            .accessibilityValue(selection == .followUp ? "Follow up" : "Steer")
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.choices.enumerated()), id: \.offset) { index, choice in
                Button {
                    select(choice.behavior)
                } label: {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(choice.behavior == selection
                                ? TenXPalette.color(TenXPalette.cyanHex)
                                : .clear)
                            .frame(width: 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(choice.title)
                                .font(TenXTypography.body(size: 12, weight: .semibold))
                            Text(choice.detail)
                                .font(TenXTypography.body(size: 10))
                                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        }
                        Spacer(minLength: 4)
                        if choice.behavior == selection {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 9)
                    .frame(
                        width: resolvedPlacement.panelFrame.width,
                        height: Self.desiredPanelSize.height / 2,
                        alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(FlyoutRowBackground(isSelected: index == highlightedIndex))
                .accessibilityLabel("\(choice.title), \(choice.detail)")
                .accessibilityValue(choice.behavior == selection ? "Selected" : "Not selected")
            }
        }
    }

    private var openTrigger: some View {
        Button(action: closeAndRestoreFocus) {
            Text(selection == .followUp ? "Follow up" : "Steer")
                .font(TenXTypography.body(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .buttonStyle(GhostActionStyle(
            color: TenXPalette.color(TenXPalette.nearBlackHex),
            horizontalPadding: 5))
        .accessibilityLabel("Composer send action")
        .accessibilityValue(selection == .followUp ? "Follow up" : "Steer")
        .accessibilityHint("Menu open")
    }

    private var placement: FlyoutPlacement? {
        anchor.map {
            FlyoutPlacement.resolve(
                triggerFrame: $0.triggerFrame,
                desiredPanelSize: Self.desiredPanelSize,
                usableBounds: $0.usableBounds,
                preferredDirection: .above)
        }
    }

    private var resolvedPlacement: FlyoutPlacement {
        placement ?? FlyoutPlacement(
            direction: .above,
            panelFrame: CGRect(origin: .zero, size: Self.desiredPanelSize),
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

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow:
            highlightedIndex = max(0, highlightedIndex - 1)
        case .downArrow:
            highlightedIndex = min(Self.choices.count - 1, highlightedIndex + 1)
        case .return:
            select(Self.choices[highlightedIndex].behavior)
        case .escape:
            closeAndRestoreFocus()
        default:
            return .ignored
        }
        return .handled
    }

    private func select(_ behavior: StreamingBehavior) {
        onSelect(behavior)
        closeAndRestoreFocus()
    }

    private func closeAndRestoreFocus() {
        isPresented = false
        onRestoreFocus()
    }
}

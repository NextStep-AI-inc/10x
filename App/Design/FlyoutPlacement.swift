import AppKit
import SwiftUI

enum FlyoutDirection: Equatable, Sendable {
    case above
    case below
}

struct FlyoutContentHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct FlyoutPlacement: Equatable, Sendable {
    let direction: FlyoutDirection
    let panelFrame: CGRect
    let triggerOffsetX: CGFloat
    let isHeightConstrained: Bool

    nonisolated static func resolve(
        triggerFrame: CGRect,
        desiredPanelSize: CGSize,
        usableBounds: CGRect,
        preferredDirection: FlyoutDirection,
        padding: CGFloat = 8
    ) -> FlyoutPlacement {
        let paddedBounds = usableBounds.insetBy(dx: padding, dy: padding)
        let panelWidth = min(
            max(1, desiredPanelSize.width),
            max(1, paddedBounds.width))
        let panelX = min(
            max(triggerFrame.minX, paddedBounds.minX),
            paddedBounds.maxX - panelWidth)
        let spaceAbove = max(0, triggerFrame.minY - paddedBounds.minY)
        let spaceBelow = max(0, paddedBounds.maxY - triggerFrame.maxY)
        let desiredHeight = max(1, desiredPanelSize.height)

        let direction: FlyoutDirection
        let preferredSpace = preferredDirection == .above ? spaceAbove : spaceBelow
        if preferredSpace >= desiredHeight {
            direction = preferredDirection
        } else if spaceAbove == spaceBelow {
            direction = preferredDirection
        } else {
            direction = spaceAbove > spaceBelow ? .above : .below
        }

        let availableHeight = direction == .above ? spaceAbove : spaceBelow
        let panelHeight = min(desiredHeight, availableHeight)
        let panelY = direction == .above
            ? triggerFrame.minY - panelHeight
            : triggerFrame.maxY
        let panelFrame = CGRect(
            x: panelX,
            y: panelY,
            width: panelWidth,
            height: panelHeight)

        return FlyoutPlacement(
            direction: direction,
            panelFrame: panelFrame,
            triggerOffsetX: min(
                max(0, triggerFrame.minX - panelFrame.minX),
                panelFrame.width),
            isHeightConstrained: panelHeight < desiredHeight)
    }
}

/// One connected outline for a panel and the trigger that invoked it.
struct TwoRectShelfShape: Shape {
    var topWidth: CGFloat
    var topHeight: CGFloat
    var bottomWidth: CGFloat
    var bottomHeight: CGFloat
    var triggerOffsetX: CGFloat = 0
    var direction: FlyoutDirection = .above

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(topWidth, topHeight),
                AnimatablePair(
                    AnimatablePair(bottomWidth, bottomHeight),
                    triggerOffsetX))
        }
        set {
            topWidth = newValue.first.first
            topHeight = newValue.first.second
            bottomWidth = newValue.second.first.first
            bottomHeight = newValue.second.first.second
            triggerOffsetX = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let panelWidth = min(topWidth, rect.width)
        let triggerWidth = min(bottomWidth, panelWidth)
        let triggerX = min(max(0, triggerOffsetX), max(0, panelWidth - triggerWidth))
        let panelHeight = min(topHeight, max(0, rect.height - bottomHeight))

        var path = Path()
        switch direction {
        case .above:
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: panelWidth, y: 0))
            path.addLine(to: CGPoint(x: panelWidth, y: panelHeight))
            path.addLine(to: CGPoint(x: triggerX + triggerWidth, y: panelHeight))
            path.addLine(to: CGPoint(
                x: triggerX + triggerWidth,
                y: panelHeight + bottomHeight))
            path.addLine(to: CGPoint(x: triggerX, y: panelHeight + bottomHeight))
            path.addLine(to: CGPoint(x: triggerX, y: panelHeight))
            path.addLine(to: CGPoint(x: 0, y: panelHeight))
        case .below:
            path.move(to: CGPoint(x: triggerX, y: 0))
            path.addLine(to: CGPoint(x: triggerX + triggerWidth, y: 0))
            path.addLine(to: CGPoint(x: triggerX + triggerWidth, y: bottomHeight))
            path.addLine(to: CGPoint(x: panelWidth, y: bottomHeight))
            path.addLine(to: CGPoint(x: panelWidth, y: bottomHeight + panelHeight))
            path.addLine(to: CGPoint(x: 0, y: bottomHeight + panelHeight))
            path.addLine(to: CGPoint(x: 0, y: bottomHeight))
            path.addLine(to: CGPoint(x: triggerX, y: bottomHeight))
        }
        path.closeSubpath()
        return path
    }
}

struct ConnectedFlyoutShelf<PanelContent: View, TriggerContent: View>: View {
    let panelSize: CGSize
    let triggerSize: CGSize
    let triggerOffsetX: CGFloat
    let direction: FlyoutDirection
    let fill: Color
    let onDismiss: () -> Void
    @ViewBuilder let panelContent: PanelContent
    @ViewBuilder let triggerContent: TriggerContent

    private var silhouette: TwoRectShelfShape {
        TwoRectShelfShape(
            topWidth: panelSize.width,
            topHeight: panelSize.height,
            bottomWidth: triggerSize.width,
            bottomHeight: triggerSize.height,
            triggerOffsetX: triggerOffsetX,
            direction: direction)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            panelContent
                .frame(
                    width: panelSize.width,
                    height: panelSize.height,
                    alignment: .topLeading)
                .offset(y: direction == .above ? 0 : triggerSize.height)

            triggerContent
                .frame(width: triggerSize.width, height: triggerSize.height)
                .offset(
                    x: triggerOffsetX,
                    y: direction == .above ? panelSize.height : 0)
        }
        .frame(
            width: panelSize.width,
            height: panelSize.height + triggerSize.height,
            alignment: .topLeading)
        .background { silhouette.fill(fill) }
        .overlay {
            silhouette.stroke(TenXPalette.color(TenXPalette.nearBlackHex), lineWidth: 1)
        }
        .dismissesOnOutsideInteraction(silhouette: silhouette, onDismiss: onDismiss)
    }
}

struct FlyoutWindowAnchor: Equatable {
    let usableBounds: CGRect
    let triggerFrame: CGRect
}

/// Reports the trigger and usable content rect in one top-down coordinate space.
/// AppKit coordinates are normalized here so placement code never mixes axes.
struct FlyoutWindowAnchorReader: NSViewRepresentable {
    let onChange: @MainActor (FlyoutWindowAnchor) -> Void

    func makeNSView(context: Context) -> FlyoutWindowAnchorReaderView {
        FlyoutWindowAnchorReaderView()
    }

    func updateNSView(_ view: FlyoutWindowAnchorReaderView, context: Context) {
        view.onChange = onChange
        view.reportAnchor()
    }

    static func dismantleNSView(
        _ view: FlyoutWindowAnchorReaderView,
        coordinator: ()
    ) {
        view.stopReporting()
    }
}

final class FlyoutWindowAnchorReaderView: NSView {
    var onChange: (@MainActor (FlyoutWindowAnchor) -> Void)?
    private var reportTask: Task<Void, Never>?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportAnchor()
    }

    override func layout() {
        super.layout()
        reportAnchor()
    }

    func reportAnchor() {
        guard let window else { return }
        let contentRect = window.contentLayoutRect
        let appKitFrame = convert(bounds, to: nil)
        let triggerFrame = CGRect(
            x: appKitFrame.minX - contentRect.minX,
            y: contentRect.maxY - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height)
        let anchor = FlyoutWindowAnchor(
            usableBounds: CGRect(origin: .zero, size: contentRect.size),
            triggerFrame: triggerFrame)
        reportTask?.cancel()
        reportTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.onChange?(anchor)
        }
    }

    func stopReporting() {
        reportTask?.cancel()
        reportTask = nil
    }
}

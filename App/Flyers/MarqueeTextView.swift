import SwiftUI

struct MarqueePresentationKey: Equatable {
    let text: String
    let font: Font
    let viewportWidth: CGFloat
    let layoutDirection: LayoutDirection
}

private struct FlyerMarqueeElapsedOverrideKey: EnvironmentKey {
    static let defaultValue: TimeInterval? = nil
}

private struct FlyerReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

private struct FlyerReduceTransparencyOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var flyerMarqueeElapsedOverride: TimeInterval? {
        get { self[FlyerMarqueeElapsedOverrideKey.self] }
        set { self[FlyerMarqueeElapsedOverrideKey.self] = newValue }
    }

    var flyerReduceMotionOverride: Bool? {
        get { self[FlyerReduceMotionOverrideKey.self] }
        set { self[FlyerReduceMotionOverrideKey.self] = newValue }
    }

    var flyerReduceTransparencyOverride: Bool? {
        get { self[FlyerReduceTransparencyOverrideKey.self] }
        set { self[FlyerReduceTransparencyOverrideKey.self] = newValue }
    }
}

struct MarqueeTextView: View {
    let text: String
    let isVisible: Bool
    let isPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.flyerMarqueeElapsedOverride) private var elapsedOverride
    @Environment(\.flyerReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.font) private var font
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isKeyboardFocused: Bool
    @State private var clock = MarqueeClock(at: Self.now)
    @State private var isDetailsPresented = false
    @State private var isHovering = false
    @State private var textWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    private static var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private var overflow: CGFloat {
        guard textWidth.isFinite, viewportWidth.isFinite else { return 0 }
        return max(0, textWidth - viewportWidth)
    }

    private var resolvedFont: Font {
        font ?? TenXTypography.body()
    }

    private var presentationKey: MarqueePresentationKey {
        MarqueePresentationKey(
            text: text,
            font: resolvedFont,
            viewportWidth: viewportWidth,
            layoutDirection: layoutDirection)
    }

    private var shouldPause: Bool {
        isPaused || isHovering || isKeyboardFocused || !isVisible || scenePhase != .active
    }

    private var shouldSchedule: Bool {
        elapsedOverride == nil
            && !reduceMotion
            && overflow > 0
            && isVisible
            && scenePhase == .active
    }

    var body: some View {
        Group {
            if reduceMotion || overflow <= 0 {
                staticText
            } else if let elapsedOverride {
                movingText(elapsed: elapsedOverride)
            } else if shouldSchedule {
                TimelineView(.animation(
                    minimumInterval: 1.0 / 30.0,
                    paused: shouldPause)) { _ in
                    movingText(elapsed: clock.elapsed(at: Self.now))
                }
            } else {
                movingText(elapsed: clock.elapsed(at: Self.now))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .focusable()
        .focused($isKeyboardFocused)
        .help(text)
        .contextMenu {
            Button("Show details") { isDetailsPresented = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAction(named: Text("Show details")) {
            isDetailsPresented = true
        }
        .popover(isPresented: $isDetailsPresented, arrowEdge: .top) {
            Text(text)
                .font(resolvedFont)
                .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: 360, alignment: .leading)
        }
        .onHover { isHovering = $0 }
        .onChange(of: shouldPause, initial: true) { _, isNowPaused in
            clock.setPaused(isNowPaused, at: Self.now)
        }
        .onChange(of: presentationKey) { _, _ in
            clock.reset(at: Self.now)
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            viewportWidth = width
        }
        .overlay(alignment: .leading) {
            measurementText
        }
    }

    private var staticText: some View {
        Text(text)
            .font(resolvedFont)
            .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var measurementText: some View {
        Text(text)
            .font(resolvedFont)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .hidden()
            .accessibilityHidden(true)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { width in
                textWidth = width
            }
    }

    private func movingText(elapsed: TimeInterval) -> some View {
        let frame = MarqueeMotion.frame(
            elapsed: elapsed,
            overflow: overflow,
            isRightToLeft: layoutDirection == .rightToLeft)
        return Text(text)
            .font(resolvedFont)
            .lineLimit(1)
            .truncationMode(.tail)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Text(text)
                    .font(resolvedFont)
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: frame.offset)
            }
            .mask(edgeMask(
                fadesLeading: frame.fadesLeading,
                fadesTrailing: frame.fadesTrailing))
    }

    private func edgeMask(
        fadesLeading: Bool,
        fadesTrailing: Bool
    ) -> some View {
        HStack(spacing: 0) {
            if fadesLeading {
                LinearGradient(
                    colors: layoutDirection == .leftToRight
                        ? [.clear, .black]
                        : [.black, .clear],
                    startPoint: .leading,
                    endPoint: .trailing)
                    .frame(width: 10)
            }
            Color.black
            if fadesTrailing {
                LinearGradient(
                    colors: layoutDirection == .leftToRight
                        ? [.black, .clear]
                        : [.clear, .black],
                    startPoint: .leading,
                    endPoint: .trailing)
                    .frame(width: 10)
            }
        }
    }
}

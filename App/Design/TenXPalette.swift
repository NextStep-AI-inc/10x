import AppKit
import SwiftUI

/// The app's semantic color tokens.
///
/// Every token resolves against the drawing appearance at draw time, so call
/// sites never branch on `colorScheme`: `color(_:)` hands back a dynamic color
/// and the same expression is correct in both appearances. That keeps the
/// light/dark pairing in one place — a token gains a dark value here, not a
/// conditional at each of its several hundred use sites.
enum TenXPalette {
    // Light values. These are the approved light design and do not move.
    static let canvasHex = 0xFFFFFF
    static let nearBlackHex = 0x0C0C0B
    static let cyanHex = 0x00A7C4
    static let interactiveCyanHex = 0x007C92
    static let signalRedHex = 0xFF3B24
    static let yellowHex = 0xFFC400
    static let mutedTextHex = 0x6B6B66
    static let separatorHex = 0xE5E5E1
    static let hoverNeutralHex = 0xF7F7F5

    // Dark counterparts. Neutrals keep the warm cast of the light ramp rather
    // than going grey, and the two accents move *up* in luminance: the light
    // ramp darkens them for contrast against white, which is backwards once the
    // canvas is dark. Every value here is pinned by a contrast test.
    static let darkCanvasHex = 0x141413
    static let darkNearBlackHex = 0xF2F2EF
    static let darkCyanHex = 0x22C8E4
    static let darkInteractiveCyanHex = 0x4FD8E8
    static let darkSignalRedHex = 0xFF6B57
    static let darkYellowHex = 0xFFD54A
    static let darkMutedTextHex = 0xA3A39B
    static let darkSeparatorHex = 0x2C2C2A
    static let darkHoverNeutralHex = 0x1F1F1D

    private static let darkCounterparts: [Int: Int] = [
        canvasHex: darkCanvasHex,
        nearBlackHex: darkNearBlackHex,
        cyanHex: darkCyanHex,
        interactiveCyanHex: darkInteractiveCyanHex,
        signalRedHex: darkSignalRedHex,
        yellowHex: darkYellowHex,
        mutedTextHex: darkMutedTextHex,
        separatorHex: darkSeparatorHex,
        hoverNeutralHex: darkHoverNeutralHex,
    ]

    /// The dark value paired with a light token, for tests that do their
    /// contrast math in hex space.
    static func darkHex(for lightHex: Int) -> Int? { darkCounterparts[lightHex] }

    static func color(_ value: Int) -> Color {
        guard let darkValue = darkCounterparts[value] else {
            // Not a token — a one-off hex keeps its literal value in both
            // appearances rather than silently resolving to something else.
            return Color(nsColor: nsColor(value))
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDarkAqua ? nsColor(darkValue) : nsColor(value)
        })
    }

    static let surfaceElevatedDarkHex = 0x232321
    static let onEmphasisDarkHex = nearBlackHex

    /// Surfaces that sit *above* the canvas — flyouts, menus, modal panels.
    /// Light mode separates them with a shadow and a hairline; dark mode can't
    /// (a shadow over a dark canvas reads as nothing), so it lifts them instead.
    static let surfaceElevated = pair(light: canvasHex, dark: surfaceElevatedDarkHex)

    /// Labels drawn *on* a filled emphasis or accent surface. Both of those
    /// fills invert to light colors in dark mode, so the label on top has to
    /// invert with them — holding it at white would paint white on near-white.
    static let onEmphasis = pair(light: canvasHex, dark: onEmphasisDarkHex)

    private static func pair(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDarkAqua ? nsColor(dark) : nsColor(light)
        })
    }

    private static func nsColor(_ value: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1)
    }
}

extension NSAppearance {
    var isDarkAqua: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

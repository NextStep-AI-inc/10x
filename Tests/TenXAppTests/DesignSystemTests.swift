import Foundation
import Testing
@testable import TenXApp

@Test func paletteProducesApprovedSemanticColors() {
    #expect(TenXPalette.canvasHex == 0xFFFFFF)
    #expect(TenXPalette.nearBlackHex == 0x0C0C0B)
    #expect(TenXPalette.cyanHex == 0x00A7C4)
    #expect(TenXPalette.signalRedHex == 0xFF3B24)
    #expect(TenXPalette.yellowHex == 0xFFC400)
}

@Test func interactiveCyanMeetsNormalTextContrastOnWhite() {
    #expect(contrastRatio(
        foreground: TenXPalette.interactiveCyanHex,
        background: TenXPalette.canvasHex) >= 4.5)
}

@Test func ghostActionPreservesContrastAndDisabledActionsDoNotReact() throws {
    let hovered = GhostActionVisualState(
        isEnabled: true,
        isHovering: true)
    let hoveredBackground = try #require(hovered.backgroundHex)
    let hoveredForeground = composite(
        foreground: TenXPalette.interactiveCyanHex,
        opacity: hovered.foregroundOpacity,
        background: hoveredBackground)

    #expect(contrastRatio(
        foreground: hoveredForeground,
        background: hoveredBackground) >= 4.5)

    let disabled = GhostActionVisualState(
        isEnabled: false,
        isHovering: true)
    #expect(disabled.foregroundOpacity == 1)
    #expect(disabled.usesMutedForeground)
    #expect(disabled.backgroundHex == nil)
}

private func contrastRatio(foreground: Int, background: Int) -> Double {
    let lighter = max(relativeLuminance(foreground), relativeLuminance(background))
    let darker = min(relativeLuminance(foreground), relativeLuminance(background))
    return (lighter + 0.05) / (darker + 0.05)
}

private func relativeLuminance(_ hex: Int) -> Double {
    let channels = [16, 8, 0].map { shift in
        let component = Double((hex >> shift) & 0xFF) / 255
        return component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
}

private func composite(foreground: Int, opacity: Double, background: Int) -> Int {
    [16, 8, 0].reduce(0) { result, shift in
        let foregroundChannel = Double((foreground >> shift) & 0xFF)
        let backgroundChannel = Double((background >> shift) & 0xFF)
        let channel = Int((foregroundChannel * opacity + backgroundChannel * (1 - opacity)).rounded())
        return result | (channel << shift)
    }
}

@Test func paletteProducesApprovedDarkCounterparts() {
    #expect(TenXPalette.darkCanvasHex == 0x141413)
    #expect(TenXPalette.darkNearBlackHex == 0xF2F2EF)
    #expect(TenXPalette.darkCyanHex == 0x22C8E4)
    #expect(TenXPalette.darkSignalRedHex == 0xFF6B57)
    #expect(TenXPalette.darkYellowHex == 0xFFD54A)
}

/// A token added to the light ramp without a dark value would silently keep its
/// light rendering on a dark canvas, which is the exact failure this whole
/// change removes. Enumerated rather than derived so adding a token forces a
/// deliberate choice here.
@Test func everyLightTokenHasADarkCounterpart() {
    let lightTokens = [
        TenXPalette.canvasHex,
        TenXPalette.nearBlackHex,
        TenXPalette.cyanHex,
        TenXPalette.interactiveCyanHex,
        TenXPalette.signalRedHex,
        TenXPalette.yellowHex,
        TenXPalette.mutedTextHex,
        TenXPalette.separatorHex,
        TenXPalette.hoverNeutralHex,
    ]
    for token in lightTokens {
        #expect(TenXPalette.darkHex(for: token) != nil)
    }
}

@Test func paletteReturnsStableDynamicColors() {
    let first = TenXPalette.color(TenXPalette.nearBlackHex)
    let second = TenXPalette.color(TenXPalette.nearBlackHex)

    #expect(first == second)
}

@Test func darkForegroundsMeetNormalTextContrastOnDarkCanvas() throws {
    // Every token the app draws text with, against the surface it draws on.
    for foreground in [
        TenXPalette.nearBlackHex,
        TenXPalette.mutedTextHex,
        TenXPalette.cyanHex,
        TenXPalette.interactiveCyanHex,
        TenXPalette.signalRedHex,
    ] {
        let dark = try #require(TenXPalette.darkHex(for: foreground))
        #expect(contrastRatio(
            foreground: dark,
            background: TenXPalette.darkCanvasHex) >= 4.5)
    }
}

/// The regression this pairing exists for: `nearBlack` is both a text color and
/// a *fill* (send button, selected rows, activity core). Inverting the fill to
/// near-white without inverting the label on top paints white on near-white —
/// a 1.12:1 disappearance rather than a contrast complaint.
@Test func emphasisLabelsInvertWithTheirFill() throws {
    let darkEmphasisFill = try #require(TenXPalette.darkHex(for: TenXPalette.nearBlackHex))
    let darkAccentFill = try #require(TenXPalette.darkHex(for: TenXPalette.cyanHex))

    #expect(contrastRatio(
        foreground: TenXPalette.onEmphasisDarkHex,
        background: darkEmphasisFill) >= 4.5)
    #expect(contrastRatio(
        foreground: TenXPalette.onEmphasisDarkHex,
        background: darkAccentFill) >= 4.5)

    // Holding the label at its light value is the bug, not merely a weaker choice.
    #expect(contrastRatio(
        foreground: TenXPalette.canvasHex,
        background: darkEmphasisFill) < 1.5)
}

/// Dark mode cannot lean on the drop shadow that separates a flyout from the
/// canvas in light mode, so the surface itself has to carry the elevation.
@Test func elevatedSurfaceSeparatesFromTheDarkCanvas() {
    #expect(TenXPalette.surfaceElevatedDarkHex > TenXPalette.darkCanvasHex)
    #expect(contrastRatio(
        foreground: TenXPalette.surfaceElevatedDarkHex,
        background: TenXPalette.darkCanvasHex) >= 1.05)
}

@Test func ghostActionPreservesContrastInDarkAppearance() throws {
    let hovered = GhostActionVisualState(isEnabled: true, isHovering: true)
    let hoveredBackground = try #require(
        hovered.backgroundHex.flatMap(TenXPalette.darkHex(for:)))
    let accent = try #require(TenXPalette.darkHex(for: TenXPalette.interactiveCyanHex))
    let muted = try #require(TenXPalette.darkHex(for: TenXPalette.mutedTextHex))

    let hoveredForeground = composite(
        foreground: accent,
        opacity: hovered.foregroundOpacity,
        background: hoveredBackground)
    #expect(contrastRatio(
        foreground: hoveredForeground,
        background: hoveredBackground) >= 4.5)
    // Disabled controls drop to muted, which still has to clear the hover fill.
    #expect(contrastRatio(
        foreground: muted,
        background: hoveredBackground) >= 4.5)
}

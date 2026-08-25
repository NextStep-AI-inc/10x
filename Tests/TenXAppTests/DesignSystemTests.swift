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

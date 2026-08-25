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

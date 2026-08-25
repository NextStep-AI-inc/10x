import Testing
@testable import TenXApp

@Test func paletteProducesApprovedSemanticColors() {
    #expect(TenXPalette.canvasHex == 0xFFFFFF)
    #expect(TenXPalette.nearBlackHex == 0x0C0C0B)
    #expect(TenXPalette.cyanHex == 0x00A7C4)
    #expect(TenXPalette.signalRedHex == 0xFF3B24)
    #expect(TenXPalette.yellowHex == 0xFFC400)
}

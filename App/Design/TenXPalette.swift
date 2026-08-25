import SwiftUI

enum TenXPalette {
    static let canvasHex = 0xFFFFFF
    static let nearBlackHex = 0x0C0C0B
    static let cyanHex = 0x00A7C4
    static let interactiveCyanHex = 0x007C92
    static let signalRedHex = 0xFF3B24
    static let yellowHex = 0xFFC400
    static let mutedTextHex = 0x6B6B66
    static let separatorHex = 0xE5E5E1
    static let hoverNeutralHex = 0xF7F7F5

    static func color(_ value: Int) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

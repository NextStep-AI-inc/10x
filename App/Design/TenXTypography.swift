import SwiftUI

enum TenXTypography {
    static func title(size: CGFloat) -> Font {
        .custom("Chillax-Regular", size: size)
    }

    static func accent(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom("Chillax-Medium", size: size).weight(weight)
    }

    static func body(size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

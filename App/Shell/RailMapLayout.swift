import CoreGraphics

enum RailMapLayout {
    static let minimumVerticalSpacing: CGFloat = 24

    static func height(itemCount: Int, availableHeight: CGFloat) -> CGFloat {
        let natural = CGFloat(itemCount) * RailScrollNavigation.rowHeight
        let spacing = minimumVerticalSpacing
        let maximum = max(0, availableHeight - spacing * 2)
        return min(natural, maximum)
    }
}

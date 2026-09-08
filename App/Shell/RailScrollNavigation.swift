import CoreGraphics

enum RailScrollDirection {
    case up
    case down
}

struct RailScrollNavigation: Equatable {
    static let rowHeight: CGFloat = 32
    static let rowsPerStep: CGFloat = 4

    let offset: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat

    static let zero = RailScrollNavigation(offset: 0, contentHeight: 0, viewportHeight: 0)

    var maximumOffset: CGFloat {
        max(0, contentHeight - viewportHeight)
    }

    var canScrollUp: Bool { offset > 1 }
    var canScrollDown: Bool { offset < maximumOffset - 1 }

    func target(for direction: RailScrollDirection) -> CGFloat {
        let distance = Self.rowHeight * Self.rowsPerStep
        switch direction {
        case .up:
            return max(0, offset - distance)
        case .down:
            return min(maximumOffset, offset + distance)
        }
    }
}

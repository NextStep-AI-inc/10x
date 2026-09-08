import CoreGraphics
import Foundation

struct MarqueeFrame {
    let offset: CGFloat
    let fadesLeading: Bool
    let fadesTrailing: Bool
}

enum MarqueeMotion {
    static func frame(
        elapsed: TimeInterval,
        overflow: CGFloat,
        isRightToLeft: Bool
    ) -> MarqueeFrame {
        guard elapsed.isFinite, overflow.isFinite, overflow > 0 else {
            return MarqueeFrame(
                offset: 0,
                fadesLeading: false,
                fadesTrailing: false)
        }

        let hold = 1.2
        let speed = 40.0
        let distance = Double(overflow)
        let travel = distance / speed
        let cycle = 2 * hold + 2 * travel
        let time = max(0, elapsed).truncatingRemainder(dividingBy: cycle)
        let position: Double

        if time < hold {
            position = 0
        } else if time < hold + travel {
            position = -speed * (time - hold)
        } else if time < 2 * hold + travel {
            position = -distance
        } else {
            position = -distance + speed * (time - 2 * hold - travel)
        }

        let endpointTolerance = 0.001
        let direction = isRightToLeft ? -1.0 : 1.0
        return MarqueeFrame(
            offset: CGFloat(position * direction),
            fadesLeading: position < -endpointTolerance,
            fadesTrailing: position > -distance + endpointTolerance)
    }
}

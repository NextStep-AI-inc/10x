import Foundation

struct MarqueeClock {
    private var accumulatedElapsed: TimeInterval = 0
    private var runningStart: TimeInterval?

    init(at time: TimeInterval) {
        runningStart = time
    }

    func elapsed(at time: TimeInterval) -> TimeInterval {
        guard let runningStart else { return accumulatedElapsed }
        return accumulatedElapsed + max(0, time - runningStart)
    }

    mutating func setPaused(_ isPaused: Bool, at time: TimeInterval) {
        if isPaused {
            guard let runningStart else { return }
            accumulatedElapsed += max(0, time - runningStart)
            self.runningStart = nil
        } else {
            guard runningStart == nil else { return }
            runningStart = time
        }
    }

    mutating func reset(at time: TimeInterval) {
        accumulatedElapsed = 0
        if runningStart != nil {
            runningStart = time
        }
    }
}

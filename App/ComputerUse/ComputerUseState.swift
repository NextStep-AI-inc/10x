enum ComputerUsePhase: Equatable, Sendable {
    case off
    case preparing
    case ready
    case controlling(target: String)
    case needsHandoff(target: String, reason: String)
    case unavailable(message: String, isBestEffortAvailable: Bool)
    case stopping
}

enum ComputerUseSafetyMode: Equatable, Sendable {
    case focusIsolated
    case legacyBestEffort
}

enum ComputerUseTransitionError: Error, Equatable, Sendable {
    case invalid(from: ComputerUsePhase, to: ComputerUsePhase)
}

struct ComputerUseStateMachine: Sendable {
    private(set) var phase: ComputerUsePhase = .off

    mutating func transition(to next: ComputerUsePhase) throws {
        guard Self.isAllowed(from: phase, to: next) else {
            throw ComputerUseTransitionError.invalid(from: phase, to: next)
        }

        phase = next
    }

    private static func isAllowed(from current: ComputerUsePhase, to next: ComputerUsePhase) -> Bool {
        if case .stopping = next {
            if case .off = current {
                return false
            }
            return true
        }

        switch (current, next) {
        case (.off, .preparing),
             (.preparing, .ready),
             (.ready, .controlling),
             (.controlling, .ready),
             (.controlling, .needsHandoff),
             (.needsHandoff, .controlling),
             (.needsHandoff, .ready),
             (.preparing, .needsHandoff),
             (.preparing, .unavailable),
             (.ready, .unavailable),
             (.controlling, .unavailable),
             (.stopping, .off):
            return true
        default:
            return false
        }
    }
}

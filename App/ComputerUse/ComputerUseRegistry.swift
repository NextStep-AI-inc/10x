@MainActor
protocol ComputerUseStopping: AnyObject {
    func stopComputerUse() async
}

@MainActor
final class ComputerUseRegistry {
    private weak var active: ComputerUseStopping?

    func activate(
        _ candidate: ComputerUseStopping,
        stopPrevious: @MainActor (ComputerUseStopping) async -> Void
    ) async {
        if let active, active !== candidate {
            await stopPrevious(active)
        }
        active = candidate
    }

    func release(_ candidate: ComputerUseStopping) {
        if active === candidate {
            active = nil
        }
    }
}

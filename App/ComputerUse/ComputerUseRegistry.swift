@MainActor
protocol ComputerUseStopping: AnyObject {
    func stopComputerUse() async
}

@MainActor
final class ComputerUseRegistry {
    private weak var active: ComputerUseStopping?
    private var activationGeneration = 0

    func activate(
        _ candidate: ComputerUseStopping,
        stopPrevious: @MainActor (ComputerUseStopping) async -> Void
    ) async {
        activationGeneration += 1
        let generation = activationGeneration
        if let active, active !== candidate {
            await stopPrevious(active)
        }
        guard generation == activationGeneration else {
            return
        }
        active = candidate
    }

    func release(_ candidate: ComputerUseStopping) {
        if active === candidate {
            active = nil
        }
    }
}

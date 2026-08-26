import OmpKit

@MainActor
struct AppDependencies {
    let ompLocator: any OmpLocating
    let sessionLibrary: SessionLibrary
    let computerUseRegistry: ComputerUseRegistry
    let makeProcessManager: (String) -> SessionProcessManager
    let makeSessionController: (SessionProcessManager, ComputerUseRegistry, AgentDesktopPreference) -> SessionController

    init(
        ompLocator: any OmpLocating,
        sessionLibrary: SessionLibrary,
        computerUseRegistry: ComputerUseRegistry,
        makeProcessManager: @escaping (String) -> SessionProcessManager = {
            SessionProcessManager(executable: $0)
        },
        makeSessionController: @escaping (SessionProcessManager, ComputerUseRegistry, AgentDesktopPreference) -> SessionController = {
            SessionController(processManager: $0, computerUseRegistry: $1, computerUsePreference: $2)
        }
    ) {
        self.ompLocator = ompLocator
        self.sessionLibrary = sessionLibrary
        self.computerUseRegistry = computerUseRegistry
        self.makeProcessManager = makeProcessManager
        self.makeSessionController = makeSessionController
    }

    static let live = AppDependencies(
        ompLocator: OmpExecutableLocator(),
        sessionLibrary: SessionLibrary(),
        computerUseRegistry: ComputerUseRegistry())
}

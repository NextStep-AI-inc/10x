import OmpKit

@MainActor
struct AppDependencies {
    let ompLocator: any OmpLocating
    let sessionLibrary: SessionLibrary
    let supervisionClient: SupervisionClient
    let makeProcessManager: (String) -> SessionProcessManager
    let makeSessionController: (SessionProcessManager, SupervisionClient) -> SessionController

    init(
        ompLocator: any OmpLocating,
        sessionLibrary: SessionLibrary,
        supervisionClient: SupervisionClient,
        makeProcessManager: @escaping (String) -> SessionProcessManager = {
            SessionProcessManager(executable: $0)
        },
        makeSessionController: @escaping (SessionProcessManager, SupervisionClient) -> SessionController = {
            SessionController(processManager: $0, supervision: $1)
        }
    ) {
        self.ompLocator = ompLocator
        self.sessionLibrary = sessionLibrary
        self.supervisionClient = supervisionClient
        self.makeProcessManager = makeProcessManager
        self.makeSessionController = makeSessionController
    }

    static let live = AppDependencies(
        ompLocator: OmpExecutableLocator(),
        sessionLibrary: SessionLibrary(),
        supervisionClient: SupervisionClient())
}

import OmpKit

@MainActor
struct AppDependencies {
    let ompLocator: any OmpLocating
    let sessionLibrary: SessionLibrary
    let computerUseRegistry: ComputerUseRegistry

    static let live = AppDependencies(
        ompLocator: OmpExecutableLocator(),
        sessionLibrary: SessionLibrary(),
        computerUseRegistry: ComputerUseRegistry())
}

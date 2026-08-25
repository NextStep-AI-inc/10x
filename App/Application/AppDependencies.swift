import OmpKit

struct AppDependencies: Sendable {
    let ompLocator: any OmpLocating
    let sessionLibrary: SessionLibrary

    static let live = AppDependencies(
        ompLocator: OmpExecutableLocator(),
        sessionLibrary: SessionLibrary())
}

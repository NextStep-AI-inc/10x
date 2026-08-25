struct AppDependencies: Sendable {
    let ompLocator: any OmpLocating

    static let live = AppDependencies(ompLocator: OmpExecutableLocator())
}

import Foundation

enum ProviderExtensionBundle {
    static let indexURL: URL? = Bundle.main.url(
        forResource: "index",
        withExtension: "ts",
        subdirectory: "omp-extensions/provider-accounts")

    static func spawnArguments(indexURL: URL? = ProviderExtensionBundle.indexURL) -> [String] {
        guard let indexURL else { return [] }
        return ["-e", indexURL.path]
    }
}

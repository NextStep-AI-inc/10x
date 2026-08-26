import AppKit
import OmpKit

struct AppDependencies: Sendable {
    let ompLocator: any OmpLocating
    let sessionLibrary: SessionLibrary
    let sessionSearch: SessionSearchService
    let makeProviderModel: @MainActor @Sendable (URL) -> ProviderManagementViewModel
    let makeComposerControls: @MainActor @Sendable (URL) -> ComposerControlsModel

    static let live = AppDependencies(
        ompLocator: OmpExecutableLocator(),
        sessionLibrary: SessionLibrary(),
        sessionSearch: SessionSearchService(),
        makeProviderModel: { executableURL in
            ProviderManagementViewModel(
                providerService: ProviderManagementService(executableURL: executableURL),
                usageService: OmpUsageService(
                    runner: OmpUsageProcessRunner(executableURL: executableURL)),
                openURL: { url in
                    NSWorkspace.shared.open(url)
                })
        },
        makeComposerControls: { executableURL in
            ComposerControlsModel(
                catalog: OmpModelCatalogService(executableURL: executableURL),
                defaults: OmpComposerDefaultStore(
                    config: OmpConfigService(
                        runner: OmpConfigProcessRunner(executableURL: executableURL))))
        })
}

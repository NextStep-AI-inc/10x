import AppKit
import OmpKit

struct AppDependencies: Sendable {
    let ompLocator: any OmpLocating
    let sessionLibrary: SessionLibrary
    let sessionSearch: SessionSearchService
    let recentProjectStore: RecentProjectStore
    let startupTiming: StartupTiming
    let makeProcessManager: @Sendable (String) -> SessionProcessManager
    let makeSettingsModel: @MainActor @Sendable (URL) -> SettingsViewModel
    let makeProviderModel: @MainActor @Sendable (URL) -> ProviderManagementViewModel
    let makeComposerControls: @MainActor @Sendable (URL) -> ComposerControlsModel
    let makeProviderAccountCoordinator: @MainActor @Sendable () -> ProviderAccountCoordinator

    @MainActor
    init(
        ompLocator: any OmpLocating,
        sessionLibrary: SessionLibrary,
        sessionSearch: SessionSearchService = SessionSearchService(),
        recentProjectStore: RecentProjectStore? = nil,
        startupTiming: StartupTiming = .live,
        makeProcessManager: @escaping @Sendable (String) -> SessionProcessManager = {
            SessionProcessManager(executable: $0)
        },
        makeSettingsModel: (@MainActor @Sendable (URL) -> SettingsViewModel)? = nil,
        makeProviderModel: @escaping @MainActor @Sendable (URL) -> ProviderManagementViewModel,
        makeComposerControls: @escaping @MainActor @Sendable (URL) -> ComposerControlsModel,
        makeProviderAccountCoordinator: @escaping @MainActor @Sendable () -> ProviderAccountCoordinator = {
            ProviderAccountCoordinator()
        }
    ) {
        self.ompLocator = ompLocator
        self.sessionLibrary = sessionLibrary
        self.sessionSearch = sessionSearch
        self.recentProjectStore = recentProjectStore ?? RecentProjectStore()
        self.startupTiming = startupTiming
        self.makeProcessManager = makeProcessManager
        self.makeSettingsModel = makeSettingsModel ?? { executableURL in
            SettingsViewModel(service: OmpConfigService(
                runner: OmpConfigProcessRunner(executableURL: executableURL)))
        }
        self.makeProviderModel = makeProviderModel
        self.makeComposerControls = makeComposerControls
        self.makeProviderAccountCoordinator = makeProviderAccountCoordinator
    }

    @MainActor static let live = AppDependencies(
        ompLocator: OmpExecutableLocator(),
        sessionLibrary: SessionLibrary(),
        sessionSearch: SessionSearchService(),
        recentProjectStore: RecentProjectStore(),
        startupTiming: .live,
        makeProcessManager: { executable in
            SessionProcessManager(executable: executable)
        },
        makeSettingsModel: { executableURL in
            SettingsViewModel(service: OmpConfigService(
                runner: OmpConfigProcessRunner(executableURL: executableURL)))
        },
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
        },
        makeProviderAccountCoordinator: {
            ProviderAccountCoordinator(
                primaryStore: ProviderPrimaryPreferenceStore(defaults: .standard))
        })
}

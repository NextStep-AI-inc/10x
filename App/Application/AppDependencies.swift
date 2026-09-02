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
    let makeUpdateChecker: @MainActor @Sendable (
        @escaping @MainActor () async -> Void) -> any UpdateChecking
    let makeSessionTitleGenerator: @Sendable (URL) -> OmpSessionTitleGenerator?

    @MainActor
    init(
        ompLocator: any OmpLocating,
        sessionLibrary: SessionLibrary,
        sessionSearch: SessionSearchService = SessionSearchService(),
        recentProjectStore: RecentProjectStore? = nil,
        startupTiming: StartupTiming = .live,
        makeProcessManager: @escaping @Sendable (String) -> SessionProcessManager = {
            SessionProcessManager(executable: $0, extraArguments: ProviderExtensionBundle.spawnArguments())
        },
        makeSettingsModel: (@MainActor @Sendable (URL) -> SettingsViewModel)? = nil,
        makeProviderModel: @escaping @MainActor @Sendable (URL) -> ProviderManagementViewModel,
        makeComposerControls: @escaping @MainActor @Sendable (URL) -> ComposerControlsModel,
        makeProviderAccountCoordinator: @escaping @MainActor @Sendable () -> ProviderAccountCoordinator = {
            ProviderAccountCoordinator()
        },
        makeUpdateChecker: (@MainActor @Sendable (
            @escaping @MainActor () async -> Void) -> any UpdateChecking)? = nil,
        makeSessionTitleGenerator: @escaping @Sendable (URL) -> OmpSessionTitleGenerator? = { _ in nil }
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
        self.makeUpdateChecker = makeUpdateChecker ?? { prepareForInstall in
            let controller = UpdateController(prepareForInstall: prepareForInstall)
            controller.start()
            return controller
        }
        self.makeSessionTitleGenerator = makeSessionTitleGenerator
    }

    @MainActor static let live = AppDependencies(
        ompLocator: OmpExecutableLocator(),
        sessionLibrary: SessionLibrary(),
        sessionSearch: SessionSearchService(),
        recentProjectStore: RecentProjectStore(),
        startupTiming: .live,
        makeProcessManager: { executable in
            SessionProcessManager(executable: executable, extraArguments: ProviderExtensionBundle.spawnArguments())
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
                catalog: ComposerCatalogService(executableURL: executableURL),
                defaults: OmpComposerDefaultStore(
                    config: OmpConfigService(
                        runner: OmpConfigProcessRunner(executableURL: executableURL))))
        },
        makeProviderAccountCoordinator: {
            ProviderAccountCoordinator(
                primaryStore: ProviderPrimaryPreferenceStore(defaults: .standard))
        },
        makeUpdateChecker: { prepareForInstall in
            let controller = UpdateController(prepareForInstall: prepareForInstall)
            controller.start()
            return controller
        },
        makeSessionTitleGenerator: { executableURL in
            OmpSessionTitleGenerator(executableURL: executableURL)
        })
}

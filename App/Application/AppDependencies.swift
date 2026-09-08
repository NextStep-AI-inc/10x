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
    let sessionMapStore: SessionMapStore
    let makeSessionMapGenerator: @Sendable (URL, URL) -> SessionMapGenerator

    @MainActor
    init(
        ompLocator: any OmpLocating,
        sessionLibrary: SessionLibrary,
        sessionSearch: SessionSearchService = SessionSearchService(),
        recentProjectStore: RecentProjectStore? = nil,
        startupTiming: StartupTiming = .live,
        makeProcessManager: @escaping @Sendable (String) -> SessionProcessManager = {
            SessionProcessManager(
                executable: $0,
                extraArguments: ProviderExtensionBundle.spawnArguments(),
                supportsUserInteraction: true)
        },
        makeSettingsModel: (@MainActor @Sendable (URL) -> SettingsViewModel)? = nil,
        makeProviderModel: @escaping @MainActor @Sendable (URL) -> ProviderManagementViewModel,
        makeComposerControls: @escaping @MainActor @Sendable (URL) -> ComposerControlsModel,
        makeProviderAccountCoordinator: @escaping @MainActor @Sendable () -> ProviderAccountCoordinator = {
            ProviderAccountCoordinator()
        },
        makeUpdateChecker: (@MainActor @Sendable (
            @escaping @MainActor () async -> Void) -> any UpdateChecking)? = nil,
        makeSessionTitleGenerator: @escaping @Sendable (URL) -> OmpSessionTitleGenerator? = { _ in nil },
        sessionMapStore: SessionMapStore? = nil,
        makeSessionMapGenerator: (@Sendable (URL, URL) -> SessionMapGenerator)? = nil
    ) {
        self.ompLocator = ompLocator
        self.sessionLibrary = sessionLibrary
        self.sessionSearch = sessionSearch
        self.recentProjectStore = recentProjectStore ?? RecentProjectStore()
        self.startupTiming = startupTiming
        self.makeProcessManager = makeProcessManager
        self.makeSettingsModel = makeSettingsModel ?? { executableURL in
            SettingsViewModel(
                service: OmpConfigService(
                    runner: OmpConfigProcessRunner(executableURL: executableURL)),
                sessionMapCatalog: ComposerCatalogService(executableURL: executableURL),
                sessionMapPreferences: SessionMapPreferenceStore())
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
        self.sessionMapStore = sessionMapStore ?? SessionMapStore(
            directory: Self.defaultSessionMapDirectory())
        self.makeSessionMapGenerator = makeSessionMapGenerator ?? { executableURL, projectURL in
            let rpc = SessionMapRPC(executableURL: executableURL, projectURL: projectURL)
            return SessionMapGenerator { prompt, images, model in
                try await rpc.complete(prompt: prompt, images: images, model: model)
            }
        }
    }

    @MainActor static let live = AppDependencies(
        ompLocator: OmpExecutableLocator(),
        sessionLibrary: SessionLibrary(),
        sessionSearch: SessionSearchService(),
        recentProjectStore: RecentProjectStore(),
        startupTiming: .live,
        makeProcessManager: { executable in
            SessionProcessManager(
                executable: executable,
                extraArguments: ProviderExtensionBundle.spawnArguments(),
                supportsUserInteraction: true)
        },
        makeSettingsModel: { executableURL in
            SettingsViewModel(
                service: OmpConfigService(
                    runner: OmpConfigProcessRunner(executableURL: executableURL)),
                sessionMapCatalog: ComposerCatalogService(executableURL: executableURL),
                sessionMapPreferences: SessionMapPreferenceStore())
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

    private static func defaultSessionMapDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return base
            .appending(path: "10x", directoryHint: .isDirectory)
            .appending(path: "SessionMap", directoryHint: .isDirectory)
    }
}

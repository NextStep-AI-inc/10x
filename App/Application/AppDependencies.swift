import AppKit
import OmpKit

struct AppDependencies: Sendable {
    let ompLocator: any OmpLocating
    let sessionLibrary: SessionLibrary
    let recentProjectStore: RecentProjectStore
    let startupTiming: StartupTiming
    let makeProcessManager: @Sendable (String) -> SessionProcessManager
    let makeSettingsModel: @MainActor @Sendable (URL) -> SettingsViewModel
    let makeProviderModel: @MainActor @Sendable (URL) -> ProviderManagementViewModel

    @MainActor
    init(
        ompLocator: any OmpLocating,
        sessionLibrary: SessionLibrary,
        recentProjectStore: RecentProjectStore? = nil,
        startupTiming: StartupTiming = .live,
        makeProcessManager: @escaping @Sendable (String) -> SessionProcessManager = {
            SessionProcessManager(executable: $0)
        },
        makeSettingsModel: (@MainActor @Sendable (URL) -> SettingsViewModel)? = nil,
        makeProviderModel: @escaping @MainActor @Sendable (URL) -> ProviderManagementViewModel
    ) {
        self.ompLocator = ompLocator
        self.sessionLibrary = sessionLibrary
        self.recentProjectStore = recentProjectStore ?? RecentProjectStore()
        self.startupTiming = startupTiming
        self.makeProcessManager = makeProcessManager
        self.makeSettingsModel = makeSettingsModel ?? { executableURL in
            SettingsViewModel(service: OmpConfigService(
                runner: OmpConfigProcessRunner(executableURL: executableURL)))
        }
        self.makeProviderModel = makeProviderModel
    }

    @MainActor static let live = AppDependencies(
        ompLocator: OmpExecutableLocator(),
        sessionLibrary: SessionLibrary(),
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
        })
}

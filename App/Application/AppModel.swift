import Foundation
import Observation
import OmpKit

@MainActor
@Observable
final class AppModel {
    var route: AppRoute = .setup
    var installation: OmpInstallation?
    var selectedProjectURL: URL?
    var setupError: String?
    var sessions: [SessionMetadata] = []
    var providerUsages: [ProviderUsageProvider] = []
    var isSearchPresented = false
    private(set) var processManager: SessionProcessManager?

    @ObservationIgnored private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    func bootstrap() async {
        await install(preferredURL: nil)
        await reloadSessions()
    }

    func useOmp(at url: URL) async {
        await install(preferredURL: url)
        if installation == nil {
            setupError = OmpExecutableLocator.inspectionErrorDescription(for: url)
        }
    }

    func chooseProject(_ url: URL) {
        selectedProjectURL = url.standardizedFileURL
        route = .newSession
    }

    func openSession(_ metadata: SessionMetadata) {
        if !metadata.cwd.isEmpty {
            selectedProjectURL = URL(filePath: metadata.cwd, directoryHint: .isDirectory)
                .standardizedFileURL
        }
        route = .session(metadata.path)
    }

    func reloadSessions() async {
        sessions = await dependencies.sessionLibrary.listAll()
    }

    private func install(preferredURL: URL?) async {
        guard let installation = await dependencies.ompLocator.locate(preferredURL: preferredURL) else {
            self.installation = nil
            processManager = nil
            route = .setup
            return
        }

        self.installation = installation
        processManager = SessionProcessManager(executable: installation.executableURL.path)
        setupError = nil
        route = .newSession
    }
}

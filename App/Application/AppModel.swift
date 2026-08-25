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
    private(set) var processManager: SessionProcessManager?

    @ObservationIgnored private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    func bootstrap() async {
        await install(preferredURL: nil)
    }

    func useOmp(at url: URL) async {
        await install(preferredURL: url)
        if installation == nil {
            setupError = OmpExecutableLocator.inspectionErrorDescription(for: url)
        }
    }

    func chooseProject(_ url: URL) {
        selectedProjectURL = url.standardizedFileURL
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

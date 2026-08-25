import AppKit
import Foundation
import UniformTypeIdentifiers

struct IDERegistry {
    private struct KnownIDE {
        let displayName: String
        let bundleIdentifier: String
    }

    private static let knownIDEs = [
        KnownIDE(displayName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
        KnownIDE(displayName: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92"),
        KnownIDE(displayName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode"),
        KnownIDE(displayName: "Zed", bundleIdentifier: "dev.zed.Zed"),
        KnownIDE(displayName: "Nova", bundleIdentifier: "com.panic.Nova"),
        KnownIDE(displayName: "Sublime Text", bundleIdentifier: "com.sublimetext.4"),
    ]

    private let installedApplicationsProvider: () -> [IDEApplication]
    private let chooseApplicationProvider: () -> IDEApplication?
    private let selectionProvider: (IDEApplication) throws -> IDESelection
    private let resolveProvider: (IDESelection) -> IDEApplication?

    init() {
        self.init(
            installedApplications: Self.discoverInstalledApplications,
            chooseApplication: Self.chooseCustomApplication,
            selection: Self.selection,
            resolve: Self.resolveSelection)
    }

    init(
        installedApplications: @escaping () -> [IDEApplication],
        chooseApplication: @escaping () -> IDEApplication?,
        selection: @escaping (IDEApplication) throws -> IDESelection,
        resolve: @escaping (IDESelection) -> IDEApplication?
    ) {
        installedApplicationsProvider = installedApplications
        chooseApplicationProvider = chooseApplication
        selectionProvider = selection
        resolveProvider = resolve
    }

    func installedApplications() -> [IDEApplication] {
        installedApplicationsProvider()
    }

    func chooseApplication() -> IDEApplication? {
        chooseApplicationProvider()
    }

    func selection(for application: IDEApplication) throws -> IDESelection {
        try selectionProvider(application)
    }

    func resolve(_ selection: IDESelection) -> IDEApplication? {
        resolveProvider(selection)
    }

    private static func discoverInstalledApplications() -> [IDEApplication] {
        knownIDEs.compactMap { knownIDE in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: knownIDE.bundleIdentifier) else {
                return nil
            }
            return IDEApplication(
                displayName: knownIDE.displayName,
                url: url,
                source: .known(bundleIdentifier: knownIDE.bundleIdentifier))
        }
    }

    private static func chooseCustomApplication() -> IDEApplication? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]

        guard panel.runModal() == .OK,
              let url = panel.url,
              (try? url.resourceValues(forKeys: [.isApplicationKey]).isApplication) == true
        else {
            return nil
        }

        return IDEApplication(displayName: url.deletingPathExtension().lastPathComponent, url: url, source: .custom)
    }

    private static func selection(for application: IDEApplication) throws -> IDESelection {
        switch application.source {
        case .known(let bundleIdentifier):
            return .known(bundleIdentifier: bundleIdentifier, displayName: application.displayName)
        case .custom:
            return .custom(
                bookmarkData: try application.url.bookmarkData(options: .withSecurityScope),
                displayName: application.displayName)
        }
    }

    private static func resolveSelection(_ selection: IDESelection) -> IDEApplication? {
        switch selection {
        case .known(let bundleIdentifier, let displayName):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                return nil
            }
            return IDEApplication(
                displayName: displayName,
                url: url,
                source: .known(bundleIdentifier: bundleIdentifier))
        case .custom(let bookmarkData, let displayName):
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale),
                !isStale
            else {
                return nil
            }
            return IDEApplication(displayName: displayName, url: url, source: .custom)
        }
    }
}

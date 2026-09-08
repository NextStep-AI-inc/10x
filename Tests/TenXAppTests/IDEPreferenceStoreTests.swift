import Foundation
import Testing
@testable import TenXApp

extension IDERegistry {
    static func testing(
        applications: [String: URL],
        bookmarks: [URL: Data] = [:]
    ) -> IDERegistry {
        let knownApplications = [
            "com.apple.dt.Xcode",
            "com.todesktop.230313mzl4w4u92",
            "com.microsoft.VSCode",
            "dev.zed.Zed",
            "com.panic.Nova",
            "com.sublimetext.4",
        ].compactMap { bundleIdentifier in
            applications[bundleIdentifier].map { url in
                IDEApplication(
                    displayName: Self.displayName(for: bundleIdentifier),
                    url: url,
                    source: .known(bundleIdentifier: bundleIdentifier))
            }
        }
        let bookmarksByData = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.value, $0.key) })

        return IDERegistry(
            installedApplications: { knownApplications },
            chooseApplication: { nil },
            selection: { application in
                switch application.source {
                case .known(let bundleIdentifier):
                    return .known(bundleIdentifier: bundleIdentifier, displayName: application.displayName)
                case .custom:
                    guard let bookmarkData = bookmarks[application.url] else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    return .custom(bookmarkData: bookmarkData, displayName: application.displayName)
                }
            },
            resolve: { selection in
                switch selection {
                case .known(let bundleIdentifier, let displayName):
                    guard let url = applications[bundleIdentifier] else { return nil }
                    return IDEApplication(
                        displayName: displayName,
                        url: url,
                        source: .known(bundleIdentifier: bundleIdentifier))
                case .custom(let bookmarkData, let displayName):
                    guard let url = bookmarksByData[bookmarkData] else { return nil }
                    return IDEApplication(displayName: displayName, url: url, source: .custom)
                }
            })
    }

    private static func displayName(for bundleIdentifier: String) -> String {
        switch bundleIdentifier {
        case "com.apple.dt.Xcode": "Xcode"
        case "com.todesktop.230313mzl4w4u92": "Cursor"
        case "com.microsoft.VSCode": "Visual Studio Code"
        case "dev.zed.Zed": "Zed"
        case "com.panic.Nova": "Nova"
        case "com.sublimetext.4": "Sublime Text"
        default: bundleIdentifier
        }
    }
}

@MainActor
@Test func listsOnlyInstalledKnownIDEsInFixedOrder() {
    let registry = IDERegistry.testing(applications: [
        "com.microsoft.VSCode": URL(filePath: "/Applications/Visual Studio Code.app"),
        "com.apple.dt.Xcode": URL(filePath: "/Applications/Xcode.app"),
        "dev.zed.Zed": URL(filePath: "/Applications/Zed.app"),
    ])

    #expect(registry.installedApplications().map(\.displayName) == ["Xcode", "Visual Studio Code", "Zed"])
}

@MainActor
@Test func knownIDESelectionPersistsAcrossStoreInstances() throws {
    let suiteName = "TenXAppTests.IDE.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let cursorURL = URL(filePath: "/Applications/Cursor.app")
    let registry = IDERegistry.testing(applications: [
        "com.todesktop.230313mzl4w4u92": cursorURL,
    ])
    let first = IDEPreferenceStore(defaults: defaults, registry: registry)
    let cursor = try #require(registry.installedApplications().first)

    try first.select(cursor)
    let second = IDEPreferenceStore(defaults: defaults, registry: registry)

    #expect(second.state == .available(cursor))
}

@MainActor
@Test func customIDESelectionPersistsAcrossStoreInstances() throws {
    let suiteName = "TenXAppTests.IDE.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let url = URL(filePath: "/Applications/Custom IDE.app")
    let application = IDEApplication(displayName: "Custom IDE", url: url, source: .custom)
    let registry = IDERegistry.testing(applications: [:], bookmarks: [url: Data("bookmark".utf8)])
    let first = IDEPreferenceStore(defaults: defaults, registry: registry)

    try first.select(application)
    let second = IDEPreferenceStore(defaults: defaults, registry: registry)

    #expect(second.state == .available(application))
}

@MainActor
@Test func missingSavedIDEIsUnavailableAndNeverSubstituted() throws {
    let suiteName = "TenXAppTests.IDE.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let installed = IDERegistry.testing(applications: [
        "com.apple.dt.Xcode": URL(filePath: "/Applications/Xcode.app"),
    ])
    let cursor = IDEApplication(
        displayName: "Cursor",
        url: URL(filePath: "/Applications/Cursor.app"),
        source: .known(bundleIdentifier: "com.todesktop.230313mzl4w4u92"))
    let first = IDEPreferenceStore(defaults: defaults, registry: IDERegistry.testing(
        applications: ["com.todesktop.230313mzl4w4u92": cursor.url]))
    try first.select(cursor)

    let reloaded = IDEPreferenceStore(defaults: defaults, registry: installed)

    #expect(reloaded.state == .unavailable(displayName: "Cursor"))
}

@MainActor
@Test func staleCustomBookmarkIsUnavailable() throws {
    let suiteName = "TenXAppTests.IDE.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let url = URL(filePath: "/Applications/Custom IDE.app")
    let application = IDEApplication(displayName: "Custom IDE", url: url, source: .custom)
    let first = IDEPreferenceStore(
        defaults: defaults,
        registry: IDERegistry.testing(applications: [:], bookmarks: [url: Data("bookmark".utf8)]))
    try first.select(application)

    let reloaded = IDEPreferenceStore(defaults: defaults, registry: IDERegistry.testing(applications: [:]))

    #expect(reloaded.state == .unavailable(displayName: "Custom IDE"))
}

@MainActor
@Test func clearRemovesSavedSelection() throws {
    let suiteName = "TenXAppTests.IDE.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registry = IDERegistry.testing(applications: [
        "com.apple.dt.Xcode": URL(filePath: "/Applications/Xcode.app"),
    ])
    let store = IDEPreferenceStore(defaults: defaults, registry: registry)
    let xcode = try #require(registry.installedApplications().first)

    try store.select(xcode)
    store.clear()

    #expect(store.state == .none)
    #expect(IDEPreferenceStore(defaults: defaults, registry: registry).state == .none)
}

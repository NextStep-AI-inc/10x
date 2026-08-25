# Inline File References and Preferred IDE Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add compact clickable file references that open through the macOS default or the user's persisted preferred IDE across assistant messages and Read, Edit, and Write tool headers.

**Architecture:** Resolve file references against the active session base URL in one pure model, discover and persist IDE applications in one app-owned preference subsystem, and isolate `NSWorkspace` operations behind an injectable service. The existing `TranscriptReferenceView` becomes the shared borderless surface, while Settings adds one local Preferred IDE row without changing OMP configuration.

**Tech Stack:** macOS 15+, Swift 6, SwiftUI, Observation, AppKit, UniformTypeIdentifiers, UserDefaults, Swift Testing, Xcode snapshot tests. No new dependency.

**Spec:** `docs/superpowers/specs/2026-08-25-inline-file-references-and-ide-preference-design.md`

## Global Constraints

- Execute in a fresh worktree created through `superpowers:using-git-worktrees`; never edit the main checkout or another session's worktree.
- Preserve the current white, near-black, and cyan design. Add no fill, perimeter, pill, shadow, decorative background, or gray accent surface.
- Use SF Pro for shell copy and SF Mono only for the Option-expanded path.
- Keep the primary file action and IDE action as separate keyboard controls with 32-point minimum hit targets.
- Primary selection always uses the macOS system default. Never silently substitute another IDE.
- Store the IDE preference in 10x `UserDefaults`, not OMP configuration, OmpKit, or an RPC contract.
- Support Xcode, Cursor, Visual Studio Code, Zed, Nova, Sublime Text, and a custom `.app` choice.
- Preserve the original path and optional line suffix for Copy Reference; standardize only the local URL used to open or reveal.
- Relative references require the active session project or worktree URL. Never resolve against the app process's current directory.
- Use the existing component hierarchy: evolve `TranscriptReferenceView`, then reuse it in tool headers. Do not fork message and tool variants.
- User-facing copy is limited to the approved action and status language: `Preferred IDE`, `Open file references in this application`, `Choose IDE`, `Choose application…`, `None`, `Unavailable`, `Open with System Default`, `Open in <application>`, `Reveal in Finder`, `Copy Reference`, `Couldn’t save the application`, `Couldn’t open <file name>`, and `Couldn’t open in <application>`.
- Run `ruby scripts/generate_xcodeproj.rb` after adding Swift files and before every `xcodebuild` invocation.
- Use a task-specific DerivedData directory for Release verification. Do not use port 3000.
- The repository has no Git remote, so commits are the handoff boundary and no PR can be opened until a remote exists.

## File structure

### New production files

- `App/FileReferences/ResolvedFileReference.swift`: pure absolute/relative path resolution and compact/full labels.
- `App/FileReferences/IDEApplication.swift`: known IDE definitions, persisted selection, and available/unavailable preference state.
- `App/FileReferences/IDERegistry.swift`: installed-application lookup, bookmark creation/resolution, and custom `.app` picker.
- `App/FileReferences/IDEPreferenceStore.swift`: observable UserDefaults-backed selection and stale-selection state.
- `App/FileReferences/FileOpenService.swift`: injectable system-default, preferred-application, and Finder operations.
- `App/FileReferences/FileReferenceEnvironment.swift`: SwiftUI environment values for opening actions, base URL, and the Settings route.
- `App/FileReferences/FileReferenceLabel.swift`: compact and full-path label rendering with deterministic path wrapping.
- `App/Settings/SettingsFocusTarget.swift`: the stable focus target used when `Choose IDE` routes into Settings.
- `App/Settings/PreferredIDESettingRowView.swift`: the one app-owned Settings row and its search matching.

### New test files

- `Tests/TenXAppTests/FileReferenceResolverTests.swift`: path resolution, existence, labels, and relative-path policy.
- `Tests/TenXAppTests/IDEPreferenceStoreTests.swift`: discovery, persistence, stale applications, custom bookmarks, and clearing.
- `Tests/TenXAppTests/FileOpenServiceTests.swift`: operation routing, preferred application, security-scoped access, and failure propagation.
- `Tests/TenXAppTests/PreferredIDESettingRowTests.swift`: local Settings search matching and displayed state labels.

### Existing files changed

- Parser and reference UI: `App/Sessions/TranscriptReference.swift`, `App/Sessions/TranscriptReferenceView.swift`, `Tests/TenXAppTests/TranscriptReferenceTests.swift`.
- Session base URL: `App/Sessions/SessionController.swift`, `App/Sessions/ActiveSessionView.swift`.
- Tool integration: `App/Tools/ToolCardScaffold.swift`, `App/Tools/ReadToolCardView.swift`, `App/Tools/EditToolCardView.swift`, `App/Tools/WriteToolCardView.swift`.
- App and Settings wiring: `App/Application/AppModel.swift`, `App/Shell/AppShellView.swift`, `App/Settings/SettingsView.swift`, `Tests/TenXAppTests/AppModelNavigationTests.swift`, `Tests/TenXAppTests/ViewSnapshotTests.swift`.
- Snapshot evidence: `Tests/TenXAppTests/ReferenceImages/continuous-settings.png`, `file-reference-states.png`, and `activity-file-references.png`.
- Generated project membership: `10x.xcodeproj/project.pbxproj`.

---

### Task 1: Resolve absolute and relative file references

**Files:**
- Create: `App/FileReferences/ResolvedFileReference.swift`
- Create: `Tests/TenXAppTests/FileReferenceResolverTests.swift`
- Modify: `App/Sessions/TranscriptReference.swift`
- Modify: `Tests/TenXAppTests/TranscriptReferenceTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` through `scripts/generate_xcodeproj.rb`

**Interfaces:**
- Consumes: `TranscriptReference.file(path:line:)` and an optional active project/worktree `URL`.
- Produces: `FileReferenceResolver.resolve(path:line:relativeTo:) -> ResolvedFileReference`.
- Produces: `ResolvedFileReference.originalReference`, `url`, `exists`, `compactLabel`, and `fullPathLabel`.
- Produces: relative file extraction only from Markdown destinations and backtick code references; plain whitespace-delimited relative lookalikes remain text.

- [ ] **Step 1: Write failing parser and resolver tests**

Add these cases using an injected existence closure so the tests never depend on the developer's filesystem:

```swift
import Foundation
import Testing
@testable import TenXApp

@Test func resolvesRelativeReferenceAgainstSessionBase() {
    let resolver = FileReferenceResolver(fileExists: { $0 == "/tmp/10x/App/Foo.swift" })
    let result = resolver.resolve(
        path: "App/Folder/../Foo.swift",
        line: 42,
        relativeTo: URL(filePath: "/tmp/10x", directoryHint: .isDirectory))

    #expect(result.url?.path == "/tmp/10x/App/Foo.swift")
    #expect(result.exists)
    #expect(result.compactLabel == "Foo.swift:42")
    #expect(result.fullPathLabel == "/tmp/10x/App/Foo.swift:42")
    #expect(result.originalReference == "App/Folder/../Foo.swift:42")
}

@Test func leavesRelativeReferenceUnavailableWithoutSessionBase() {
    let result = FileReferenceResolver(fileExists: { _ in true })
        .resolve(path: "App/Foo.swift", line: nil, relativeTo: nil)

    #expect(result.url == nil)
    #expect(!result.exists)
    #expect(result.fullPathLabel == "App/Foo.swift")
}

@Test func codeAndMarkdownAcceptRelativeFilesButPlainTextDoesNot() {
    #expect(TranscriptReference.extract(from: "`App/Foo.swift:8`") == [
        .file(path: "App/Foo.swift", line: 8),
    ])
    #expect(TranscriptReference.extract(from: "[Foo](App/Foo.swift)") == [
        .file(path: "App/Foo.swift", line: nil),
    ])
    #expect(TranscriptReference.extract(from: "Ignore words/with/slashes and relative/file.swift:2") == [])
}
```

Also cover an absolute path ignoring the supplied base URL, a missing absolute file, `..` standardization, a root file name, and original line-suffix preservation.

- [ ] **Step 2: Run the focused tests and verify RED**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/TranscriptReferenceTests \
  -only-testing:TenXAppTests/FileReferenceResolverTests test
```

Expected: compilation fails because `FileReferenceResolver` and `ResolvedFileReference` do not exist; the relative extraction assertions also fail after compilation reaches them.

- [ ] **Step 3: Implement the pure resolution contract**

Create these exact public-to-the-target shapes:

```swift
import Foundation

struct ResolvedFileReference: Equatable {
    let originalPath: String
    let line: Int?
    let url: URL?
    let exists: Bool

    var originalReference: String {
        originalPath + (line.map { ":\($0)" } ?? "")
    }

    var compactLabel: String {
        URL(filePath: originalPath).lastPathComponent + (line.map { ":\($0)" } ?? "")
    }

    var fullPathLabel: String {
        (url?.path ?? originalPath) + (line.map { ":\($0)" } ?? "")
    }
}

struct FileReferenceResolver {
    private let fileExists: (String) -> Bool

    init(fileExists: @escaping (String) -> Bool = FileManager.default.fileExists(atPath:)) {
        self.fileExists = fileExists
    }

    func resolve(path: String, line: Int?, relativeTo baseURL: URL?) -> ResolvedFileReference {
        let url: URL?
        if path.hasPrefix("/") {
            url = URL(filePath: path).standardizedFileURL
        } else if let baseURL {
            url = baseURL.appending(path: path).standardizedFileURL
        } else {
            url = nil
        }
        return ResolvedFileReference(
            originalPath: path,
            line: line,
            url: url,
            exists: url.map { fileExists($0.path) } ?? false)
    }
}
```

Change the parser's private function to `parse(_:label:allowsRelativeFile:)`. Pass `true` from Markdown and code parsing, and `false` from plain-reference parsing. Strip the numeric line suffix before deciding whether a local path is file-like. Accept a relative candidate only when it starts with `./` or `../`, or when it contains `/` and the suffix-free final path component has a non-empty extension. Preserve URL handling and the existing line-suffix parser.

- [ ] **Step 4: Run focused tests and verify GREEN**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/TranscriptReferenceTests \
  -only-testing:TenXAppTests/FileReferenceResolverTests test
```

Expected: the focused parser and resolver suites pass, including the existing punctuation and duplicate tests.

- [ ] **Step 5: Commit the resolution slice**

```bash
git add App/FileReferences/ResolvedFileReference.swift \
  App/Sessions/TranscriptReference.swift \
  Tests/TenXAppTests/FileReferenceResolverTests.swift \
  Tests/TenXAppTests/TranscriptReferenceTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "feat(files): resolve transcript references"
```

---

### Task 2: Discover and persist the preferred IDE

**Files:**
- Create: `App/FileReferences/IDEApplication.swift`
- Create: `App/FileReferences/IDERegistry.swift`
- Create: `App/FileReferences/IDEPreferenceStore.swift`
- Create: `Tests/TenXAppTests/IDEPreferenceStoreTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` through `scripts/generate_xcodeproj.rb`

**Interfaces:**
- Produces: `IDEApplication`, `IDESelection`, and `IDEPreferenceState`.
- Produces: `IDERegistry.installedApplications()`, `chooseApplication()`, `selection(for:)`, and `resolve(_:)`.
- Produces: observable `IDEPreferenceStore.state`, `select(_:)`, `clear()`, and `reload()`.
- Persists: encoded `IDESelection` under `tenx.preferredIDE.v1`.

- [ ] **Step 1: Write failing registry and preference tests**

Use a dedicated `UserDefaults` suite and remove its persistent domain in test cleanup. Cover the fixed known-IDE order, only returning installed apps, known selection round-trip, custom bookmark round-trip, stale known selection, stale custom bookmark, and `clear()`:

```swift
import Foundation
import Testing
@testable import TenXApp

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
```

- [ ] **Step 2: Run the focused suite and verify RED**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/IDEPreferenceStoreTests test
```

Expected: compilation fails because the IDE types and store do not exist.

- [ ] **Step 3: Implement stable IDE values and known definitions**

Use these interfaces:

```swift
import Foundation

struct IDEApplication: Identifiable, Equatable {
    enum Source: Equatable {
        case known(bundleIdentifier: String)
        case custom
    }

    let displayName: String
    let url: URL
    let source: Source

    var id: String {
        switch source {
        case .known(let bundleIdentifier): bundleIdentifier
        case .custom: url.standardizedFileURL.path
        }
    }
}

enum IDESelection: Codable, Equatable {
    case known(bundleIdentifier: String, displayName: String)
    case custom(bookmarkData: Data, displayName: String)

    var displayName: String {
        switch self {
        case .known(_, let displayName), .custom(_, let displayName): displayName
        }
    }
}

enum IDEPreferenceState: Equatable {
    case none
    case available(IDEApplication)
    case unavailable(displayName: String)
}
```

The registry's known list is ordered exactly as follows:

```swift
private struct KnownIDE {
    let displayName: String
    let bundleIdentifier: String
}

static let knownIDEs = [
    KnownIDE(displayName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
    KnownIDE(displayName: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92"),
    KnownIDE(displayName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode"),
    KnownIDE(displayName: "Zed", bundleIdentifier: "dev.zed.Zed"),
    KnownIDE(displayName: "Nova", bundleIdentifier: "com.panic.Nova"),
    KnownIDE(displayName: "Sublime Text", bundleIdentifier: "com.sublimetext.4"),
]
```

Use `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` for known apps. The custom picker is an `NSOpenPanel` with `canChooseFiles = true`, `canChooseDirectories = false`, `allowsMultipleSelection = false`, and `allowedContentTypes = [.applicationBundle]`. Validate that the returned URL is an application bundle before constructing `.custom`.

The registry exposes these exact method signatures:

```swift
func installedApplications() -> [IDEApplication]
func chooseApplication() -> IDEApplication?
func selection(for application: IDEApplication) throws -> IDESelection
func resolve(_ selection: IDESelection) -> IDEApplication?

static func testing(
    applications: [String: URL],
    bookmarks: [URL: Data] = [:]
) -> IDERegistry
```

- [ ] **Step 4: Implement bookmark-backed persistence**

`IDERegistry.selection(for:)` stores known bundle identifiers and creates a `.withSecurityScope` bookmark for custom applications. `resolve(_:)` uses bundle lookup for known apps and `URL(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:)` with `.withSecurityScope` for custom apps; stale bookmarks return `nil`.

Implement the store as a main-actor observable type:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class IDEPreferenceStore {
    private(set) var state: IDEPreferenceState = .none
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let registry: IDERegistry
    @ObservationIgnored private let key = "tenx.preferredIDE.v1"

    init(defaults: UserDefaults = .standard, registry: IDERegistry) {
        self.defaults = defaults
        self.registry = registry
        reload()
    }

    func select(_ application: IDEApplication) throws {
        let selection = try registry.selection(for: application)
        defaults.set(try JSONEncoder().encode(selection), forKey: key)
        state = .available(application)
    }

    func clear() {
        defaults.removeObject(forKey: key)
        state = .none
    }

    func reload() {
        guard let data = defaults.data(forKey: key),
              let selection = try? JSONDecoder().decode(IDESelection.self, from: data)
        else {
            state = .none
            return
        }
        state = registry.resolve(selection).map(IDEPreferenceState.available)
            ?? .unavailable(displayName: selection.displayName)
    }
}
```

Add the `IDERegistry.testing(applications:bookmarks:)` factory through an internal initializer, not a production filesystem scan. Bookmark creation looks up `URL` to `Data`; resolution uses the reversed mapping, making both directions deterministic.

- [ ] **Step 5: Run focused tests and verify GREEN**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/IDEPreferenceStoreTests test
```

Expected: registry ordering, known/custom persistence, stale states, and clearing all pass without opening a panel.

- [ ] **Step 6: Commit the preference subsystem**

```bash
git add App/FileReferences/IDEApplication.swift \
  App/FileReferences/IDERegistry.swift \
  App/FileReferences/IDEPreferenceStore.swift \
  Tests/TenXAppTests/IDEPreferenceStoreTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "feat(settings): persist preferred IDE"
```

---

### Task 3: Isolate macOS file-opening operations

**Files:**
- Create: `App/FileReferences/FileOpenService.swift`
- Create: `App/FileReferences/FileReferenceEnvironment.swift`
- Create: `Tests/TenXAppTests/FileOpenServiceTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` through `scripts/generate_xcodeproj.rb`

**Interfaces:**
- Produces: `FileOpenService.openWithSystemDefault(_:)`, `open(_:in:)`, and `reveal(_:)`.
- Produces: `EnvironmentValues.fileOpenService`, `fileReferenceBaseURL`, and `openIDEPreferences`.
- Consumes: a resolved existing file URL and an available `IDEApplication`.

- [ ] **Step 1: Write failing operation-routing tests**

Inject closures and assert exact URLs. Cover system-default success, preferred known application, custom application security-scope start/stop, failure propagation, and Finder reveal:

```swift
import Foundation
import Testing
@testable import TenXApp

@MainActor
@Test func customIDEOpenBalancesSecurityScopedAccess() async throws {
    var events: [String] = []
    let service = FileOpenService(
        openDefault: { _ in events.append("default") },
        openInApplication: { fileURL, applicationURL in
            events.append("open:\(fileURL.path):\(applicationURL.path)")
        },
        reveal: { url in events.append("reveal:\(url.path)") },
        startSecurityScope: { url in
            events.append("start:\(url.path)")
            return true
        },
        stopSecurityScope: { url in events.append("stop:\(url.path)") })
    let application = IDEApplication(
        displayName: "Custom IDE",
        url: URL(filePath: "/Applications/Custom IDE.app"),
        source: .custom)

    try await service.open(URL(filePath: "/tmp/File.swift"), in: application)

    #expect(events == [
        "start:/Applications/Custom IDE.app",
        "open:/tmp/File.swift:/Applications/Custom IDE.app",
        "stop:/Applications/Custom IDE.app",
    ])
}
```

- [ ] **Step 2: Run the focused suite and verify RED**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/FileOpenServiceTests test
```

Expected: compilation fails because `FileOpenService` does not exist.

- [ ] **Step 3: Implement the injectable service and live adapter**

Use a main-actor value with exact operation closures:

```swift
import AppKit

struct FileOpenService {
    let openDefault: @MainActor (URL) throws -> Void
    let openInApplication: @MainActor (URL, URL) async throws -> Void
    let revealOperation: @MainActor (URL) -> Void
    let startSecurityScope: @MainActor (URL) -> Bool
    let stopSecurityScope: @MainActor (URL) -> Void

    init(
        openDefault: @escaping @MainActor (URL) throws -> Void,
        openInApplication: @escaping @MainActor (URL, URL) async throws -> Void,
        reveal: @escaping @MainActor (URL) -> Void,
        startSecurityScope: @escaping @MainActor (URL) -> Bool,
        stopSecurityScope: @escaping @MainActor (URL) -> Void
    ) {
        self.openDefault = openDefault
        self.openInApplication = openInApplication
        self.revealOperation = reveal
        self.startSecurityScope = startSecurityScope
        self.stopSecurityScope = stopSecurityScope
    }

    @MainActor
    func openWithSystemDefault(_ url: URL) throws {
        try openDefault(url)
    }

    @MainActor
    func open(_ url: URL, in application: IDEApplication) async throws {
        let didAccess = application.source == .custom && startSecurityScope(application.url)
        defer {
            if didAccess { stopSecurityScope(application.url) }
        }
        try await openInApplication(url, application.url)
    }

    @MainActor
    func reveal(_ url: URL) {
        revealOperation(url)
    }
}
```

`FileOpenService.live` uses `NSWorkspace.shared.open(_:)` and throws when it returns `false`. Its application operation wraps `NSWorkspace.shared.open(_:withApplicationAt:configuration:completionHandler:)` in `withCheckedThrowingContinuation`. Finder reveal uses `activateFileViewerSelecting`. The environment's `openIDEPreferences` value is a main-actor callable wrapper with a no-op default; `fileReferenceBaseURL` defaults to `nil`; `fileOpenService` defaults to `.live`.

- [ ] **Step 4: Run focused tests and verify GREEN**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/FileOpenServiceTests test
```

Expected: all routing, error, reveal, and balanced security-scope assertions pass.

- [ ] **Step 5: Commit the macOS service boundary**

```bash
git add App/FileReferences/FileOpenService.swift \
  App/FileReferences/FileReferenceEnvironment.swift \
  Tests/TenXAppTests/FileOpenServiceTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "feat(files): add native open service"
```

---

### Task 4: Add the Preferred IDE Settings row and focus route

**Files:**
- Create: `App/Settings/SettingsFocusTarget.swift`
- Create: `App/Settings/PreferredIDESettingRowView.swift`
- Create: `Tests/TenXAppTests/PreferredIDESettingRowTests.swift`
- Modify: `App/Application/AppModel.swift`
- Modify: `App/Shell/AppShellView.swift`
- Modify: `App/Settings/SettingsView.swift`
- Modify: `Tests/TenXAppTests/AppModelNavigationTests.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Modify: `Tests/TenXAppTests/ReferenceImages/continuous-settings.png`
- Modify: `10x.xcodeproj/project.pbxproj` through `scripts/generate_xcodeproj.rb`

**Interfaces:**
- Produces: `SettingsFocusTarget.preferredIDE` and `AppModel.settingsFocusTarget`.
- Changes: `AppModel.openSettings(focus:)` accepts an optional focus target and `consumeSettingsFocus()` clears it.
- Produces: `PreferredIDESettingRowView.matches(query:applicationName:) -> Bool`.
- Consumes: `IDERegistry` and `IDEPreferenceStore` created once by `AppModel`.

- [ ] **Step 1: Write failing navigation, search, and state-label tests**

Add navigation assertions:

```swift
@MainActor
@Test func chooseIDESelectsSettingsAndRequestsPreferredIDEFocus() {
    let model = AppModel()

    model.openSettings(focus: .preferredIDE)

    #expect(model.route == .settings)
    #expect(model.settingsFocusTarget == .preferredIDE)
    model.consumeSettingsFocus()
    #expect(model.settingsFocusTarget == nil)
}
```

Add pure search cases for empty query, `preferred`, `editor`, selected application name, unrelated query, and unavailable saved name. Assert row labels for `.none`, `.available`, and `.unavailable` states are `Choose IDE`, the application name, and `<name> · Unavailable` respectively.

- [ ] **Step 2: Run focused tests and verify RED**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/AppModelNavigationTests \
  -only-testing:TenXAppTests/PreferredIDESettingRowTests test
```

Expected: compilation fails because the focus target, local Settings row, and AppModel dependencies do not exist.

- [ ] **Step 3: Wire app-lifetime dependencies and Settings focus**

Add these AppModel members and initializer inputs:

```swift
private(set) var settingsFocusTarget: SettingsFocusTarget?
let ideRegistry: IDERegistry
let idePreferenceStore: IDEPreferenceStore
let fileOpenService: FileOpenService

init(
    dependencies: AppDependencies = .live,
    ideRegistry: IDERegistry = .live,
    preferenceDefaults: UserDefaults = .standard,
    fileOpenService: FileOpenService = .live
) {
    self.dependencies = dependencies
    self.ideRegistry = ideRegistry
    self.idePreferenceStore = IDEPreferenceStore(
        defaults: preferenceDefaults,
        registry: ideRegistry)
    self.fileOpenService = fileOpenService
}

func openSettings(focus: SettingsFocusTarget? = nil) {
    settingsFocusTarget = focus
    route = .settings
    Task { await settingsModel?.load() }
}

func consumeSettingsFocus() {
    settingsFocusTarget = nil
}
```

Keep ordinary wordmark and `⌘,` navigation calling `openSettings()` with no focus target.

- [ ] **Step 4: Build the local Settings row**

`PreferredIDESettingRowView` is one borderless settings row with title `Preferred IDE`, description `Open file references in this application`, and a plain native menu. The menu lists `registry.installedApplications()`, the current available custom application when one is selected, then `Choose application…`, then `None`. Installed and custom selections call `store.select`; `None` calls `store.clear`. A failed selection shows a red inline error using `[Settings:PreferredIDESettingRowView]` only in the internal log and `Couldn’t save the application` in the row.

Its state label logic is exact:

```swift
static func valueLabel(for state: IDEPreferenceState) -> String {
    switch state {
    case .none: "Choose IDE"
    case .available(let application): application.displayName
    case .unavailable(let displayName): "\(displayName) · Unavailable"
    }
}

static func matches(query: String, applicationName: String?) -> Bool {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return true }
    return ["Preferred IDE", "Open file references in this application", applicationName]
        .compactMap { $0 }
        .contains { $0.localizedCaseInsensitiveContains(query) }
}
```

- [ ] **Step 5: Insert and focus the row in the continuous form**

Pass the registry, store, optional focus target, and focus-consumed action into `SettingsView`. Render the local row first in General when its search matcher passes, even when no OMP General keys match. Keep the top count explicitly labeled `OMP settings`; do not add this row to `SettingsCatalog` or its OMP counts.

Give the row the stable ID `SettingsFocusTarget.preferredIDE`. When the focus request becomes `.preferredIDE`, scroll to that ID, focus the menu, then call `onFocusConsumed()`. The General anchor must still scroll to the General heading rather than the row.

In `AppShellView`, construct Settings with `model.ideRegistry`, `model.idePreferenceStore`, and `model.settingsFocusTarget`. Inject the preference store, file-opening service, and an environment `openIDEPreferences` action around the route canvas:

```swift
.environment(model.idePreferenceStore)
.environment(\.fileOpenService, model.fileOpenService)
.environment(\.openIDEPreferences, OpenIDEPreferencesAction {
    model.openSettings(focus: .preferredIDE)
})
```

- [ ] **Step 6: Verify behavior and refresh the Settings snapshot**

```bash
ruby scripts/generate_xcodeproj.rb
RECORD_SNAPSHOTS=1 xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -only-testing:TenXAppTests/ViewSnapshotTests/continuousSettingsSnapshot test
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/AppModelNavigationTests \
  -only-testing:TenXAppTests/PreferredIDESettingRowTests \
  -only-testing:TenXAppTests/ViewSnapshotTests/continuousSettingsSnapshot test
```

Expected: focused tests pass; the Settings reference image shows one borderless Preferred IDE row at the start of General, retains the continuous document, and labels the header count as OMP settings.

- [ ] **Step 7: Commit the Settings integration**

```bash
git add App/Application/AppModel.swift \
  App/Shell/AppShellView.swift \
  App/Settings/SettingsFocusTarget.swift \
  App/Settings/PreferredIDESettingRowView.swift \
  App/Settings/SettingsView.swift \
  Tests/TenXAppTests/AppModelNavigationTests.swift \
  Tests/TenXAppTests/PreferredIDESettingRowTests.swift \
  Tests/TenXAppTests/ViewSnapshotTests.swift \
  Tests/TenXAppTests/ReferenceImages/continuous-settings.png \
  10x.xcodeproj/project.pbxproj
git commit -m "feat(settings): choose preferred IDE"
```

---

### Task 5: Share actionable file references across messages and tools

**Files:**
- Create: `App/FileReferences/FileReferenceLabel.swift`
- Modify: `App/Sessions/TranscriptReferenceView.swift`
- Modify: `App/Sessions/SessionController.swift`
- Modify: `App/Sessions/ActiveSessionView.swift`
- Modify: `App/Tools/ToolCardScaffold.swift`
- Modify: `App/Tools/ReadToolCardView.swift`
- Modify: `App/Tools/EditToolCardView.swift`
- Modify: `App/Tools/WriteToolCardView.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Create: `Tests/TenXAppTests/ReferenceImages/file-reference-states.png`
- Create: `Tests/TenXAppTests/ReferenceImages/activity-file-references.png`

**Interfaces:**
- Consumes: `FileReferenceResolver`, environment `fileReferenceBaseURL`, `fileOpenService`, `openIDEPreferences`, and `IDEPreferenceStore`.
- Preserves: `TranscriptReferenceView(reference:)` so existing assistant-message call sites continue to compile.
- Changes: `ToolCardScaffold` adds `fileReference: TranscriptReference? = nil`; `subtitle` remains available for non-file tools.
- Exposes: `SessionController.projectURL` as `private(set)` for the active session only.

- [ ] **Step 1: Add failing snapshots for all visible states**

Add deterministic snapshot fixtures for:

- available compact file plus `Open in Cursor`;
- no IDE plus `Choose IDE`;
- missing file with muted label and disabled open actions;
- a full-path label at transcript width using a `ResolvedFileReference` fixture;
- collapsed Read, Edit, and Write tool headers with separate disclosure, file, IDE, phase, and duration regions;
- compact width where the IDE action moves below the file action without clipping.

Use a temporary UserDefaults suite and a testing IDE registry. The snapshots must not open files or applications.

- [ ] **Step 2: Run snapshot tests and verify RED**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/ViewSnapshotTests test
```

Expected: new snapshot cases fail because the shared actions and tool-header API are absent.

- [ ] **Step 3: Implement the shared reference interaction**

Keep the web branch unchanged. For file references:

- Resolve through `FileReferenceResolver` and the environment base URL.
- Render the primary file action with `doc.text`, compact label, cyan when available, and muted text when unavailable.
- Track hover plus Option using macOS 15 `onModifierKeysChanged(mask: .option, initial: true)`; only show `fullPathLabel` when both are true.
- Use SF Mono for the full label, allow wrapping at path separators, and cap layout at the parent width.
- Render a second cyan ghost action. `.available` reads `Open in <application>`, while `.none` and `.unavailable` read `Choose IDE` and invoke the Settings environment action.
- Use `ViewThatFits(in: .horizontal)` to switch from one horizontal action row to a leading-aligned two-line arrangement when constrained.
- Disable system/IDE/reveal actions when `ResolvedFileReference.exists` is false, but keep Copy Reference enabled.
- Add the exact context-menu order from the spec.
- On open failure, show a red inline status for four seconds or until the next interaction, canceling the previous clear task before starting a new one. Announce the failure through accessibility.
- Give both actions separate 32-point hit targets and accessibility labels containing the full resolved path and application result.

Create the internal `FileReferenceLabel` in its own file so snapshots can render compact and full-path states without synthesizing pointer events. The full-path display replaces each `/` with `/` plus a zero-width space before passing the string to `Text`; the underlying `ResolvedFileReference` and copied value stay unchanged. This guarantees wrapping at path separators instead of relying on the text engine to choose a break point.

- [ ] **Step 4: Supply the active session base URL**

Change `SessionController.projectURL` from `private` to `private(set)`. In `ActiveSessionView`, add:

```swift
.environment(\.fileReferenceBaseURL, controller.projectURL)
```

This environment value covers both assistant references and tool cards inside `TranscriptView`. Preview controllers without a project URL leave relative references visibly unavailable.

- [ ] **Step 5: Split the tool header into sibling controls**

Add `fileReference: TranscriptReference? = nil` to `ToolCardScaffold`. Replace the all-in-one header button with:

```swift
HStack(alignment: .firstTextBaseline, spacing: 8) {
    Button(action: toggle) {
        HStack(spacing: 8) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            Text(title)
            if fileReference == nil, let subtitle { Text(subtitle) }
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)

    if let fileReference {
        TranscriptReferenceView(reference: fileReference)
    }

    Spacer(minLength: 8)
    Text(presentation.phase.label)
        .font(TenXTypography.body(size: 10, weight: .medium))
        .foregroundStyle(accentColor)
    Text(presentation.durationLabel)
        .font(TenXTypography.mono(size: 10))
        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
}
```

Keep disclosure accessibility on the first button only. Read, Edit, and Write pass `.file(path: content.path, line: nil)` and stop passing the path as `subtitle`. Every other tool continues using the existing subtitle behavior.

- [ ] **Step 6: Record and inspect the focused reference snapshots**

```bash
ruby scripts/generate_xcodeproj.rb
RECORD_SNAPSHOTS=1 xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -only-testing:TenXAppTests/ViewSnapshotTests/fileReferenceStatesSnapshot \
  -only-testing:TenXAppTests/ViewSnapshotTests/activityFileReferencesSnapshot test
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/ViewSnapshotTests test
```

Expected: all view snapshots pass. Manual image inspection confirms distinct controls, no nested-button behavior, no clipping at compact width, no border/fill/shadow, and no full path in the default state.

- [ ] **Step 7: Commit the shared UI slice**

```bash
git add App/Sessions/TranscriptReferenceView.swift \
  App/FileReferences/FileReferenceLabel.swift \
  App/Sessions/SessionController.swift \
  App/Sessions/ActiveSessionView.swift \
  App/Tools/ToolCardScaffold.swift \
  App/Tools/ReadToolCardView.swift \
  App/Tools/EditToolCardView.swift \
  App/Tools/WriteToolCardView.swift \
  Tests/TenXAppTests/ViewSnapshotTests.swift \
  Tests/TenXAppTests/ReferenceImages/file-reference-states.png \
  Tests/TenXAppTests/ReferenceImages/activity-file-references.png
git commit -m "feat(chat): add actionable file references"
```

---

### Task 6: Verify the complete Release experience

**Files:**
- Modify only requirement-backed defects found during verification.
- Update: `docs/superpowers/plans/2026-08-25-inline-file-references-and-ide-preference.md` checkboxes and evidence notes.
- Update: `docs/superpowers/specs/2026-08-25-inline-file-references-and-ide-preference-design.md` status after all acceptance criteria pass.

**Interfaces:**
- Verifies the complete Settings to transcript to macOS application flow.
- Produces Release-build screenshots and an evidence-backed handoff; it does not merge.

- [ ] **Step 1: Run every automated test and a Release build**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' test
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData-inline-file-references clean build
git diff --check
git status --short
```

Expected: all tests pass, the Release build succeeds, the diff has no whitespace errors, and status contains only intended plan/spec evidence updates if they have not yet been committed.

- [x] **Step 2: Launch the explicit Release bundle**

Load `launching-local-builds`, then launch:

```bash
open '.build/DerivedData-inline-file-references/Build/Products/Release/10x.app'
```

Confirm the exact bundle process remains alive and the visible 10x window belongs to this worktree's Release build before any interaction claim.

- [x] **Step 3: Drive the real system-default and preferred-IDE flow**

Use a real session whose worktree contains a harmless Swift file:

1. Open Settings through the 10x wordmark.
2. Select an installed IDE, return to the session, and confirm every visible file reference updates to `Open in <application>`.
3. Select the file name and verify macOS opens the file with the registered system default.
4. Select `Open in <application>` and verify the chosen application opens the same file.
5. Change the preference to another installed IDE and verify visible actions update without reloading the session.
6. Choose a custom `.app`, relaunch 10x, and verify the choice persists and opens the file.
7. Select `None` and verify every secondary action returns to `Choose IDE`.

- [ ] **Step 4: Drive path, tool, error, and accessibility states**

1. Verify an absolute assistant reference and a relative backtick assistant reference.
2. Verify collapsed Read, Edit, and Write headers; selecting a file action must not expand the card.
3. Hold Option over short and long references. Capture the full resolved path and verify the window does not widen.
4. Right-click and verify Open with System Default, Open in the selected IDE, Reveal in Finder, and Copy Reference in that order.
5. Verify Copy Reference retains the original relative path and line suffix.
6. Verify a missing file remains muted and copyable while open and reveal are unavailable.
7. Make the selected test application unavailable, relaunch, and verify `Choose IDE` plus `<name> · Unavailable` in Settings with no substituted IDE.
8. Force one launch rejection through the injected test build or a temporarily invalid application URL and verify the red four-second inline status plus VoiceOver announcement.
9. Traverse disclosure, file, IDE, and context actions by keyboard at minimum and normal window widths.

- [ ] **Step 5: Capture and inspect real screenshots**

Capture the actual Release app at minimum and normal window widths showing:

- Preferred IDE in Settings;
- compact assistant file reference;
- Option-expanded full path;
- compact Read/Edit/Write headers;
- missing-file state.

Inspect for horizontal clipping, layout jumps, nested focus behavior, missing focus rings, gray fills, borders, shadows, and incorrect SF Pro/SF Mono use. Fix only defects that violate the approved spec, then rerun the affected automated and live checks.

- [ ] **Step 6: Run completion verification and review**

Load `verifying-work` and `superpowers:verification-before-completion`, then run their required evidence checks. Load `superpowers:requesting-code-review` for the implementation diff; address blocking correctness, accessibility, and visual-system findings, then rerun the affected evidence. Do not add unrelated cleanup.

- [x] **Step 7: Record evidence and commit the verified state**

Mark completed plan checkboxes, change the spec status only if every acceptance criterion passed, and add the exact build/test commands plus screenshot paths under a short `## Verification evidence` section in this plan.

```bash
git add docs/superpowers/plans/2026-08-25-inline-file-references-and-ide-preference.md \
  docs/superpowers/specs/2026-08-25-inline-file-references-and-ide-preference-design.md
git commit -m "docs: verify inline file references"
```

Report the worktree path, branch, commit SHAs, verified evidence, skipped checks with reasons, and the remaining manual checks. Do not merge or clean up the worktree without Tanner's instruction.

## Verification evidence

Verified on `codex/inline-file-references` in the explicit Release bundle at
`.build/DerivedData-inline-file-references/Build/Products/Release/10x.app`.
The final binary SHA-256 was
`3347b96b25e9225f95a24baaed020a98210cdda05f8eae50eea09ec3aefa1dbe`;
PID 8252 remained alive for more than three minutes while the live checks ran.

- `ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' test` passed 121/121 tests at `93d0532`.
- The real Cursor edit result exposed a missing tool-header path. The regression was RED, then the full suite passed 122/122 after `fd4cf92`.
- The minimum-width Settings run exposed content beneath the expanded rail. The regression was RED and the production fix compiled, but two later Xcode test-host launches stalled before executing tests and were stopped. The final Release build and live minimum-width check passed at `9982764`; the post-fix full-suite checkbox remains open.
- `xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath .build/DerivedData-inline-file-references clean build` exited 0 with `CLEAN SUCCEEDED` and `BUILD SUCCEEDED`.
- `git diff --check` exited 0.
- The exact Release app discovered Xcode, Cursor, and Visual Studio Code; persisted Cursor and Visual Studio Code selections across relaunch; accepted Cursor through `Choose application…`; returned to `Choose IDE` for `None`; opened `MessageBubbleView.swift` in Xcode through the primary action and in Cursor through the preferred action.
- A live OMP session produced Read, Edit, and Write cards using ignored verification files. Relative backtick references, relative resolution, file icons, separate IDE actions, disabled missing-file actions, Edit-result path fallback, and disclosure independence were visible in the final Release UI.
- The primary context menu exposed `Open with System Default`, `Open in Cursor`, `Reveal in Finder`, and `Copy Reference` in the required order.

Release screenshots:

- `docs/superpowers/evidence/2026-08-25-inline-file-references-release/settings-preferred-ide-final.jpg`
- `docs/superpowers/evidence/2026-08-25-inline-file-references-release/settings-minimum.jpg`
- `docs/superpowers/evidence/2026-08-25-inline-file-references-release/reference-compact.jpg`
- `docs/superpowers/evidence/2026-08-25-inline-file-references-release/tool-headers-normal.jpg`
- `docs/superpowers/evidence/2026-08-25-inline-file-references-release/tool-headers-minimum.jpg`
- `docs/superpowers/evidence/2026-08-25-inline-file-references-release/missing-file.jpg`
- `docs/superpowers/evidence/2026-08-25-inline-file-references-release/transcript-normal.jpg`
- `docs/superpowers/evidence/2026-08-25-inline-file-references-release/transcript-minimum.jpg`

Not verified: an absolute assistant reference containing spaces unless Markdown/backtick-delimited, Option-held full-path rendering, clipboard contents after `Copy Reference`, an unavailable selected application in the exact Release bundle, the four-second launch-rejection/VoiceOver announcement, and complete keyboard traversal at both widths. The spec remains incomplete and its status is intentionally unchanged.

# First-Run Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Update, 2026-08-27:** Task 3 (the Git repository scanner) and the parts of
> Task 5 and Task 6 that wired it into the project step were removed after
> live testing. Crawling the user's home directory to suggest projects was
> judged wrong. The project step now suggests only folders 10x already knows
> about, the working directories of existing OMP sessions, via
> `ProjectSessionGrouper.choosableProjectURLs(from:including:)` — the same
> derivation the composer's project flyout already used. `GitRepositoryScanner`,
> `GitRepositorySuggestion`, and `GitRepositoryScannerTests.swift` no longer
> exist. This note is the record of that change; the task bodies below are
> left as originally written, as the record of what was planned and built
> before the removal.

**Goal:** Replace the two bare setup gates with one onboarding flow that installs OMP, connects a provider, and takes a project folder from a scan of the user's Git repositories. (As of 2026-08-27, the project folder step no longer scans; see the update note above.)

**Architecture:** `AppRoute.setup` and `.providerSetup` collapse into `.onboarding(OnboardingStep)`. A pure `OnboardingStep.firstUnmet(...)` decides which step is due, `AppModel.gateRoute()` applies it at all nine routing sites, and `OnboardingView` renders whichever step is current. Three new leaf types carry the new behavior: a repository scanner (removed 2026-08-27, see update note above), an install runner, and the step enum.

**Tech Stack:** Swift 6.1, SwiftUI, macOS 15+, Swift Testing (`@Test` free functions), `xcodebuild`, `xcodeproj` gem 1.27.0.

**Spec:** `docs/superpowers/specs/2026-08-26-first-run-onboarding-design.md`

## Global Constraints

- **Never hand-edit `10x.xcodeproj`.** After creating or deleting any `.swift` file under `App/` or `Tests/`, run `ruby scripts/generate_xcodeproj.rb`. Adding one file changes about 4 lines. A diff in the hundreds of lines means the wrong `xcodeproj` gem is active; stop and fix the gem rather than committing.
- **Strict Swift 6 concurrency.** No `any` erasure where a generic works, no `as!`. Types crossing a callback boundary are `Sendable`, or a `final class ... @unchecked Sendable` guarded by `NSLock`, which is the house pattern (`StderrDrainer` in `OmpKit/Sources/OmpKit/Wire/LineTransport.swift`).
- **Tests are Swift Testing free `@Test` functions.** There are no suites. A type- or file-shaped `-only-testing:` selector matches nothing and still prints `** TEST SUCCEEDED **`. Always select the function with parentheses, and always confirm the run printed `Test run with N tests`. An absent summary line means zero tests ran.
- **Any test that calls `AppModel.bootstrap()` must `await manager.closeAll()` before returning**, or it leaks file descriptors into every later suite.
- **Snapshot references are re-recorded only with the `TEST_RUNNER_` prefix.** `testmanagerd` launches the test host without the invoking shell's environment, so an unprefixed variable never arrives. Never commit a `.actual.png`. Never add an `EnvironmentVariables` entry to the scheme's `TestAction`.
- **User-facing copy** comes from the spec's copy table verbatim. No em dashes in any user-facing string.
- **Commits** are conventional and atomic, with no self-attribution lines. After each task, tick that task's box in the PR checklist on <https://github.com/NextStep-AI-inc/10x/pull/2> using `gh api repos/NextStep-AI-inc/10x/pulls/2 -X PATCH -F body=@<file>` (`gh pr edit` fails on this token for lack of the `read:project` scope).

**Full suite:**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
```

**Single test:**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/testFunctionName()"
```

---

### Task 1: One directory list, plus `~/.local/bin`

The official installer writes to `$HOME/.local/bin` unless a matching bun is already present. That directory is in none of the app's lists, so a successful install is followed by "OMP required". The same directory set is currently hardcoded three times, and the list the setup screen *displays* is a different copy from the list discovery actually *probes*.

**Files:**
- Modify: `App/Application/OmpProcessEnvironment.swift`
- Modify: `App/Setup/OmpExecutableLocator.swift`
- Test: `Tests/TenXAppTests/OmpProcessEnvironmentTests.swift`
- Test: `Tests/TenXAppTests/OmpExecutableLocatorTests.swift`

**Interfaces:**
- Produces: `OmpProcessEnvironment.toolDirectories: [String]` (unchanged name, gains one entry); `OmpProcessEnvironment.resolvedToolDirectories(homeDirectory:) -> [URL]`; `OmpExecutableLocator.knownPaths: [String]` (unchanged name, now derived).
- Consumes: nothing from other tasks.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/TenXAppTests/OmpProcessEnvironmentTests.swift`:

```swift
@Test func resolvedPathIncludesTheInstallScriptsDefaultDirectory() {
    let home = URL(filePath: "/Users/example", directoryHint: .isDirectory)
    let resolved = OmpProcessEnvironment.resolved(
        base: ["PATH": "/usr/bin"],
        homeDirectory: home)

    let entries = (resolved["PATH"] ?? "").split(separator: ":").map(String.init)
    #expect(entries.contains("/Users/example/.local/bin"))
}

@Test func resolvedToolDirectoriesExpandTildesAgainstTheGivenHome() {
    let home = URL(filePath: "/Users/example", directoryHint: .isDirectory)
    let directories = OmpProcessEnvironment
        .resolvedToolDirectories(homeDirectory: home)
        .map(\.path)

    #expect(directories.first == "/Users/example/.bun/bin")
    #expect(directories.contains("/Users/example/.local/bin"))
    #expect(directories.contains("/opt/homebrew/bin"))
}
```

Append to `Tests/TenXAppTests/OmpExecutableLocatorTests.swift`:

```swift
@Test func displayedPathsAreDerivedFromTheDirectoriesThatAreActuallyProbed() {
    #expect(OmpExecutableLocator.knownPaths
        == OmpProcessEnvironment.toolDirectories.map { "\($0)/omp" })
}

@Test func locatorFindsAnExecutableInstalledByTheOfficialScript() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }

    let directory = fixture.root.appending(path: ".local/bin", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let executable = directory.appending(path: "omp")
    try "#!/bin/sh\nprintf '18.0.4\\n'\n".write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path)

    let locator = OmpExecutableLocator(homeDirectory: fixture.root, path: "")
    let location = try await locator.locate(preferredURL: nil)

    #expect(location == .found(OmpInstallation(
        executableURL: executable.standardizedFileURL,
        version: "18.0.4")))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/locatorFindsAnExecutableInstalledByTheOfficialScript()"
```

Expected: FAIL. The first three fail to compile (`resolvedToolDirectories` does not exist); the locator test fails because `.local/bin` is not probed. Confirm the log prints a `Test run with …` line so you know the selector matched.

- [ ] **Step 3: Add the directory and the shared accessor**

In `App/Application/OmpProcessEnvironment.swift`, replace `toolDirectories` and add the accessor. Update the doc comment, since the `ponytail:` note explicitly said to revisit when an install outside those three appeared:

```swift
    /// Where `omp` and its interpreter are installed, in probe order. The
    /// official install script writes `~/.local/bin` unless a matching bun is
    /// already present, in which case it writes `~/.bun/bin`.
    ///
    /// Single source for the three things that must agree: the paths setup
    /// says it checks, the paths discovery probes, and the PATH a spawn gets.
    static let toolDirectories = [
        "~/.bun/bin",
        "~/.local/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
    ]

    /// `toolDirectories` as absolute URLs for a given home.
    static func resolvedToolDirectories(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        toolDirectories.map { URL(filePath: expand($0, homeDirectory: homeDirectory)) }
    }
```

Delete the now-stale `ponytail:` comment above `resolved(base:homeDirectory:)` that reads "Switch to it only if installs outside these three appear."

- [ ] **Step 4: Derive both locator lists from it**

In `App/Setup/OmpExecutableLocator.swift`, replace the `knownPaths` literal:

```swift
    /// Display strings for the setup screen, derived from the same directories
    /// `candidates(preferredURL:)` probes so the two cannot drift.
    static let knownPaths = OmpProcessEnvironment.toolDirectories.map { "\($0)/omp" }
```

and replace the hardcoded `known` array inside `candidates(preferredURL:)`:

```swift
        let known = OmpProcessEnvironment
            .resolvedToolDirectories(homeDirectory: homeDirectory)
            .map { $0.appending(path: "omp") }
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/locatorFindsAnExecutableInstalledByTheOfficialScript()" -only-testing:"TenXAppTests/displayedPathsAreDerivedFromTheDirectoriesThatAreActuallyProbed()" -only-testing:"TenXAppTests/resolvedPathIncludesTheInstallScriptsDefaultDirectory()" -only-testing:"TenXAppTests/resolvedToolDirectoriesExpandTildesAgainstTheGivenHome()"
```

Expected: PASS, `Test run with 4 tests`.

- [ ] **Step 6: Commit**

```bash
git add App/Application/OmpProcessEnvironment.swift App/Setup/OmpExecutableLocator.swift Tests/TenXAppTests/OmpProcessEnvironmentTests.swift Tests/TenXAppTests/OmpExecutableLocatorTests.swift
git commit -m "fix(setup): discover OMP installed by the official script"
```

Note: `SetupView` renders `knownPaths`, so the setup screen now lists four paths. Its snapshot references change in Task 6; do not re-record here.

---

### Task 2: The onboarding step and its pure resolver

**Files:**
- Create: `App/Onboarding/OnboardingStep.swift`
- Test: `Tests/TenXAppTests/OnboardingStepTests.swift`

**Interfaces:**
- Produces: `enum OnboardingStep: Equatable, Sendable, CaseIterable { case installOmp, connectProvider, chooseProject }`, `static func unmet(installation: OmpInstallation?, hasAuthenticatedProvider: Bool, selectedProjectURL: URL?) -> [OnboardingStep]`, and `static func firstUnmet(...) -> OnboardingStep?` with the same parameters.
- Consumes: `OmpInstallation` from `App/Setup/OmpInstallation.swift`.

This task deliberately does **not** touch `AppRoute`. Adding the enum case breaks compilation everywhere until the container exists, so that happens in Task 5 and this task stays independently green.

- [ ] **Step 1: Write the failing test**

Create `Tests/TenXAppTests/OnboardingStepTests.swift`:

```swift
import Foundation
import Testing
@testable import TenXApp

private let installed = OmpInstallation(
    executableURL: URL(filePath: "/Users/example/.local/bin/omp"),
    version: "18.0.4")
private let project = URL(filePath: "/Users/example/Code/app", directoryHint: .isDirectory)

@Test func requirementsAreResolvedInOrderAndStopAtTheFirstUnmetOne() {
    #expect(OnboardingStep.firstUnmet(
        installation: nil,
        hasAuthenticatedProvider: false,
        selectedProjectURL: nil) == .installOmp)

    // A missing runtime outranks everything else, even when the later
    // requirements happen to be satisfied.
    #expect(OnboardingStep.firstUnmet(
        installation: nil,
        hasAuthenticatedProvider: true,
        selectedProjectURL: project) == .installOmp)

    #expect(OnboardingStep.firstUnmet(
        installation: installed,
        hasAuthenticatedProvider: false,
        selectedProjectURL: nil) == .connectProvider)

    #expect(OnboardingStep.firstUnmet(
        installation: installed,
        hasAuthenticatedProvider: false,
        selectedProjectURL: project) == .connectProvider)

    #expect(OnboardingStep.firstUnmet(
        installation: installed,
        hasAuthenticatedProvider: true,
        selectedProjectURL: nil) == .chooseProject)
}

@Test func everyRequirementMetMeansNoOnboardingStep() {
    #expect(OnboardingStep.firstUnmet(
        installation: installed,
        hasAuthenticatedProvider: true,
        selectedProjectURL: project) == nil)
}

@Test func stepsAreOrderedInstallThenProviderThenProject() {
    #expect(OnboardingStep.allCases == [.installOmp, .connectProvider, .chooseProject])
}

@Test func theUnmetSetSkipsRequirementsThatAreAlreadySatisfied() {
    // Losing OMP mid-session: the provider model goes away with the runtime,
    // but a chosen project survives. Two steps remain, not three.
    #expect(OnboardingStep.unmet(
        installation: nil,
        hasAuthenticatedProvider: false,
        selectedProjectURL: project) == [.installOmp, .connectProvider])

    #expect(OnboardingStep.unmet(
        installation: nil,
        hasAuthenticatedProvider: false,
        selectedProjectURL: nil)
        == [.installOmp, .connectProvider, .chooseProject])

    #expect(OnboardingStep.unmet(
        installation: installed,
        hasAuthenticatedProvider: true,
        selectedProjectURL: nil) == [.chooseProject])

    #expect(OnboardingStep.unmet(
        installation: installed,
        hasAuthenticatedProvider: true,
        selectedProjectURL: project).isEmpty)
}

@Test func theFirstUnmetRequirementIsTheFirstOfTheUnmetSet() {
    for installation in [nil, installed] {
        for hasProvider in [false, true] {
            for url in [nil, project] {
                let all = OnboardingStep.unmet(
                    installation: installation,
                    hasAuthenticatedProvider: hasProvider,
                    selectedProjectURL: url)
                let first = OnboardingStep.firstUnmet(
                    installation: installation,
                    hasAuthenticatedProvider: hasProvider,
                    selectedProjectURL: url)
                #expect(first == all.first)
            }
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/everyRequirementMetMeansNoOnboardingStep()"
```

Expected: FAIL to compile, "cannot find 'OnboardingStep' in scope".

- [ ] **Step 3: Write the implementation**

Create `App/Onboarding/OnboardingStep.swift`:

```swift
import Foundation

/// A requirement onboarding collects before the workspace is usable, in the
/// order they are asked for.
enum OnboardingStep: Equatable, Sendable, CaseIterable {
    case installOmp
    case connectProvider
    case chooseProject
}

extension OnboardingStep {
    /// Every requirement these inputs do not satisfy, in order.
    ///
    /// Kept free of `AppModel` so it can be tested as a table: `providerModel`
    /// is `private(set)` and a test cannot populate it.
    ///
    /// The whole set, not just the first, because the step counter must not
    /// count a requirement that is already met. Losing OMP mid-session is the
    /// case that separates them: the provider model goes away with the
    /// runtime, but the chosen project survives.
    static func unmet(
        installation: OmpInstallation?,
        hasAuthenticatedProvider: Bool,
        selectedProjectURL: URL?
    ) -> [OnboardingStep] {
        var steps: [OnboardingStep] = []
        if installation == nil { steps.append(.installOmp) }
        if !hasAuthenticatedProvider { steps.append(.connectProvider) }
        if selectedProjectURL == nil { steps.append(.chooseProject) }
        return steps
    }

    /// The requirement to ask for now, or nil when the workspace is usable.
    static func firstUnmet(
        installation: OmpInstallation?,
        hasAuthenticatedProvider: Bool,
        selectedProjectURL: URL?
    ) -> OnboardingStep? {
        unmet(
            installation: installation,
            hasAuthenticatedProvider: hasAuthenticatedProvider,
            selectedProjectURL: selectedProjectURL).first
    }
}
```

- [ ] **Step 4: Regenerate the project and run the tests**

```bash
ruby scripts/generate_xcodeproj.rb
git diff --stat 10x.xcodeproj
```

Expected: roughly 8 changed lines (one new App file, one new test file). Then:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/requirementsAreResolvedInOrderAndStopAtTheFirstUnmetOne()" -only-testing:"TenXAppTests/everyRequirementMetMeansNoOnboardingStep()" -only-testing:"TenXAppTests/stepsAreOrderedInstallThenProviderThenProject()" -only-testing:"TenXAppTests/theUnmetSetSkipsRequirementsThatAreAlreadySatisfied()" -only-testing:"TenXAppTests/theFirstUnmetRequirementIsTheFirstOfTheUnmetSet()"
```

Expected: PASS, `Test run with 5 tests`.

- [ ] **Step 5: Commit**

```bash
git add App/Onboarding/OnboardingStep.swift Tests/TenXAppTests/OnboardingStepTests.swift 10x.xcodeproj
git commit -m "feat(onboarding): add the step enum and its requirement resolver"
```

---

### Task 3: Git repository scanner (removed 2026-08-27, historical)

> This task's output — `GitRepositoryScanner.swift` and
> `GitRepositoryScannerTests.swift` — was deleted after live testing showed
> crawling the home directory was the wrong approach. See the update note at
> the top of this document. The task body below is left as originally
> written and no longer describes what the project step does.

**Files:**
- Create: `App/Onboarding/GitRepositoryScanner.swift`
- Test: `Tests/TenXAppTests/GitRepositoryScannerTests.swift`

**Interfaces:**
- Produces: `struct GitRepositorySuggestion: Equatable, Sendable, Identifiable { var id: String; let url: URL; let modified: Date }` and `struct GitRepositoryScanner: Sendable { init(homeDirectory: URL); func scan() async throws -> [GitRepositorySuggestion] }`, plus `static let maximumResults = 12`.
- Consumes: nothing from other tasks.
- Later tasks rely on: `GitRepositoryScanner(homeDirectory:)` and `scan()`, and on `GitRepositorySuggestion.url` / `.id`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TenXAppTests/GitRepositoryScannerTests.swift`:

```swift
import Foundation
import Testing
@testable import TenXApp

private struct ScannerFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "tenx-scan-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Creates `path` under the fixture root and marks it a repository by
    /// giving it a `.git` directory.
    @discardableResult
    func repository(_ path: String, modified: Date = Date(timeIntervalSince1970: 1)) throws -> URL {
        let url = root.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: url.appending(path: ".git", directoryHint: .isDirectory),
            withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.modificationDate: modified],
            ofItemAtPath: url.path)
        return url
    }

    /// A worktree: `.git` is a file, not a directory.
    @discardableResult
    func worktree(_ path: String) throws -> URL {
        let url = root.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try "gitdir: /elsewhere/.git/worktrees/x\n".write(
            to: url.appending(path: ".git"),
            atomically: true,
            encoding: .utf8)
        return url
    }

    func directory(_ path: String) throws -> URL {
        let url = root.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@Test func scannerFindsRepositoriesAndAppliesEveryExclusionRule() async throws {
    let fixture = try ScannerFixture()
    defer { fixture.cleanup() }

    let shallow = try fixture.repository("app")
    let deep = try fixture.repository("a/b/c/deep")
    try fixture.repository("a/b/c/d/tooDeep")
    try fixture.repository("app/vendor/nested")
    try fixture.worktree("worktrees/wt")
    try fixture.repository(".hidden/dotted")
    try fixture.repository("Documents/notes")
    try fixture.repository("Library/caches")

    let found = try await GitRepositoryScanner(homeDirectory: fixture.root)
        .scan()
        .map(\.url.lastPathComponent)

    #expect(Set(found) == ["app", "deep"])
    #expect(!found.contains("tooDeep"))     // depth 5
    #expect(!found.contains("nested"))      // inside another repository
    #expect(!found.contains("wt"))          // .git is a file
    #expect(!found.contains("dotted"))      // under a dot-directory
    #expect(!found.contains("notes"))       // skip list
    #expect(!found.contains("caches"))      // skip list
}

@Test func scannerRanksMostRecentlyModifiedFirstAndCapsTheList() async throws {
    let fixture = try ScannerFixture()
    defer { fixture.cleanup() }

    for index in 0..<(GitRepositoryScanner.maximumResults + 3) {
        try fixture.repository(
            "repo-\(index)",
            modified: Date(timeIntervalSince1970: TimeInterval(index)))
    }

    let found = try await GitRepositoryScanner(homeDirectory: fixture.root).scan()

    #expect(found.count == GitRepositoryScanner.maximumResults)
    #expect(found.first?.url.lastPathComponent == "repo-14")
    #expect(found.map(\.modified) == found.map(\.modified).sorted(by: >))
}

@Test func scannerDoesNotFollowASymbolicLinkCycle() async throws {
    let fixture = try ScannerFixture()
    defer { fixture.cleanup() }

    let branch = try fixture.directory("branch")
    try fixture.repository("branch/real")
    try FileManager.default.createSymbolicLink(
        at: branch.appending(path: "loop"),
        withDestinationURL: fixture.root)

    let found = try await GitRepositoryScanner(homeDirectory: fixture.root).scan()

    #expect(found.map(\.url.lastPathComponent) == ["real"])
}

@Test func scannerStopsWhenItsTaskIsCancelled() async throws {
    let fixture = try ScannerFixture()
    defer { fixture.cleanup() }
    for index in 0..<200 { try fixture.repository("repo-\(index)") }

    let scan = Task { try await GitRepositoryScanner(homeDirectory: fixture.root).scan() }
    scan.cancel()

    await #expect(throws: CancellationError.self) { _ = try await scan.value }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/scannerFindsRepositoriesAndAppliesEveryExclusionRule()"
```

Expected: FAIL to compile, "cannot find 'GitRepositoryScanner' in scope".

- [ ] **Step 3: Write the implementation**

Create `App/Onboarding/GitRepositoryScanner.swift`:

```swift
import Foundation

/// A Git repository offered as a project suggestion during onboarding.
struct GitRepositorySuggestion: Equatable, Sendable, Identifiable {
    var id: String { url.path }
    let url: URL
    let modified: Date
}

/// Finds Git repositories under the user's home folder to suggest as projects.
///
/// Spotlight cannot answer this: it does not index dot-directories, so a query
/// for `.git` returns nothing. A bounded walk is the only option, and it is
/// cheap once `Library` is skipped and the walk stops at each repository.
struct GitRepositoryScanner: Sendable {
    /// Skipped by name below the home folder. The first four are the folders
    /// macOS gates behind a consent prompt, which onboarding must not trigger.
    /// `.Trash` is also covered by `.skipsHiddenFiles`.
    static let excludedNames: Set<String> = [
        "Library", "Desktop", "Documents", "Downloads", ".Trash",
    ]

    /// Directory levels below the home folder. Results saturate here: a
    /// development machine found 40 repositories at 3 and 55 at both 4 and 5.
    static let maximumDepth = 4
    static let maximumResults = 12

    private let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func scan() async throws -> [GitRepositorySuggestion] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: homeDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }

        var found: [GitRepositorySuggestion] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try? url.resourceValues(forKeys: Set(keys))

            // Resource values resolve symlinks, so a link to a directory reads
            // as one. Checking the link itself is what stops a cycle.
            guard values?.isDirectory == true, values?.isSymbolicLink != true else {
                enumerator.skipDescendants()
                continue
            }
            guard !Self.excludedNames.contains(url.lastPathComponent) else {
                enumerator.skipDescendants()
                continue
            }
            if Self.isRepository(url) {
                found.append(GitRepositorySuggestion(
                    url: url.standardizedFileURL,
                    modified: values?.contentModificationDate ?? .distantPast))
                // Nothing inside a repository is a separate project, and this
                // is what keeps the walk cheap.
                enumerator.skipDescendants()
                continue
            }
            if enumerator.level >= Self.maximumDepth {
                enumerator.skipDescendants()
            }
        }

        return Array(
            found.sorted { $0.modified > $1.modified }
                .prefix(Self.maximumResults))
    }

    /// A worktree's `.git` is a file, not a directory, so requiring a directory
    /// excludes worktrees without a special case.
    private static func isRepository(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let git = url.appending(path: ".git").path
        guard FileManager.default.fileExists(atPath: git, isDirectory: &isDirectory)
        else { return false }
        return isDirectory.boolValue
    }
}
```

- [ ] **Step 4: Regenerate and run the tests**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/scannerFindsRepositoriesAndAppliesEveryExclusionRule()" -only-testing:"TenXAppTests/scannerRanksMostRecentlyModifiedFirstAndCapsTheList()" -only-testing:"TenXAppTests/scannerDoesNotFollowASymbolicLinkCycle()" -only-testing:"TenXAppTests/scannerStopsWhenItsTaskIsCancelled()"
```

Expected: PASS, `Test run with 4 tests`.

If `scannerFindsRepositoriesAndAppliesEveryExclusionRule` reports `deep` missing, `enumerator.level` counts differently than assumed: level 1 is a direct child of the start URL. Print `enumerator.level` for each visited URL and adjust `maximumDepth` so a repository four levels below the home folder is found and one five levels below is not. Do not change the test's expectations.

- [ ] **Step 5: Commit**

```bash
git add App/Onboarding/GitRepositoryScanner.swift Tests/TenXAppTests/GitRepositoryScannerTests.swift 10x.xcodeproj
git commit -m "feat(onboarding): scan for Git repositories to suggest as projects"
```

---

### Task 4: Install runner

**Files:**
- Create: `App/Onboarding/OmpInstallRunner.swift`
- Test: `Tests/TenXAppTests/OmpInstallRunnerTests.swift`

**Interfaces:**
- Produces: `enum OmpInstallError: Error, Equatable, Sendable { case failed(status: Int32) }` and `struct OmpInstallRunner: Sendable { static let command: String; init(command: String); func run() -> AsyncThrowingStream<String, Error> }`.
- Consumes: `OmpProcessEnvironment.resolved()` from Task 1.
- Later tasks rely on: `OmpInstallRunner.command` for the displayed command, and `run()` yielding one output line at a time.

`OmpCommandRunner` is not reused: it collects output with `readToEnd`, so nothing is visible until the process exits, and a network install needs its progress on screen while it runs.

- [ ] **Step 1: Write the failing test**

Create `Tests/TenXAppTests/OmpInstallRunnerTests.swift`:

```swift
import Foundation
import Testing
@testable import TenXApp

private func collect(
    _ runner: OmpInstallRunner
) async throws -> [String] {
    var lines: [String] = []
    for try await line in runner.run() { lines.append(line) }
    return lines
}

@Test func installRunnerStreamsMergedOutputLineByLine() async throws {
    let runner = OmpInstallRunner(
        command: "printf 'first\\nsecond\\n'; printf 'third\\n' 1>&2")

    let lines = try await collect(runner)

    #expect(lines.contains("first"))
    #expect(lines.contains("second"))
    #expect(lines.contains("third"))
}

@Test func installRunnerReportsANonzeroExitAfterDeliveringItsOutput() async throws {
    let runner = OmpInstallRunner(command: "printf 'why it failed\\n'; exit 3")

    var lines: [String] = []
    var thrown: Error?
    do {
        for try await line in runner.run() { lines.append(line) }
    } catch {
        thrown = error
    }

    #expect(lines == ["why it failed"])
    #expect(thrown as? OmpInstallError == .failed(status: 3))
}

@Test func installRunnerEmitsAFinalLineThatHasNoTrailingNewline() async throws {
    let runner = OmpInstallRunner(command: "printf 'no trailing newline'")

    let lines = try await collect(runner)

    #expect(lines == ["no trailing newline"])
}

@Test func abandoningTheStreamTerminatesTheInstallProcess() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "tenx-install-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pidFile = directory.appending(path: "install.pid")

    let runner = OmpInstallRunner(
        command: "printf '%s\\n' $$ > '\(pidFile.path)'; while :; do sleep 1; done")

    let consumer = Task {
        for try await _ in runner.run() { break }   // take one line, then stop
    }
    _ = try? await consumer.value

    // Give the terminate a moment to land, then prove the child is gone.
    var pid: pid_t?
    for _ in 0..<50 {
        if let text = try? String(contentsOf: pidFile, encoding: .utf8),
           let parsed = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            pid = parsed
            break
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    let child = try #require(pid)
    for _ in 0..<50 where kill(child, 0) == 0 {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(kill(child, 0) == -1)
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/installRunnerStreamsMergedOutputLineByLine()"
```

Expected: FAIL to compile, "cannot find 'OmpInstallRunner' in scope".

- [ ] **Step 3: Write the implementation**

Create `App/Onboarding/OmpInstallRunner.swift`. The buffer is touched from a Foundation callback queue and from the termination handler, so it lives in a locked box, matching `StderrDrainer` in `LineTransport.swift`:

```swift
import Darwin
import Foundation

enum OmpInstallError: Error, Equatable, Sendable {
    case failed(status: Int32)
}

/// Runs the documented OMP install command and streams its merged output.
///
/// Not `OmpCommandRunner`: that collects output with `readToEnd`, so nothing
/// appears until the process exits. A network install needs to show progress.
struct OmpInstallRunner: Sendable {
    /// The command shown to the user before it runs. Not a login shell: the
    /// installer needs nothing from rc files, and sourcing them can hang on a
    /// slow profile.
    static let command = "curl -fsSL https://omp.sh/install | sh"

    private let command: String

    init(command: String = OmpInstallRunner.command) {
        self.command = command
    }

    func run() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = ["-c", command]
            process.environment = OmpProcessEnvironment.resolved()

            let output = Pipe()
            process.standardOutput = output
            process.standardError = output

            let lines = LineAccumulator()

            output.fileHandleForReading.readabilityHandler = { handle in
                for line in lines.take(handle.availableData) {
                    continuation.yield(line)
                }
            }

            process.terminationHandler = { finished in
                output.fileHandleForReading.readabilityHandler = nil
                let remainder = (try? output.fileHandleForReading.readToEnd()) ?? Data()
                for line in lines.drain(remainder) {
                    continuation.yield(line)
                }
                if finished.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(
                        throwing: OmpInstallError.failed(status: finished.terminationStatus))
                }
            }

            let handle = ProcessHandle(process)
            continuation.onTermination = { _ in handle.terminateIfRunning() }

            do {
                try process.run()
            } catch {
                output.fileHandleForReading.readabilityHandler = nil
                continuation.finish(throwing: error)
            }
        }
    }
}

/// Splits streamed bytes into lines. Written to from a Foundation callback
/// queue and from the termination handler, so it holds a lock.
private final class LineAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    /// Complete lines available in `chunk` plus anything held over.
    func take(_ chunk: Data) -> [String] {
        guard !chunk.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        buffer.append(chunk)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }

    /// Everything left, including a final line with no trailing newline.
    func drain(_ chunk: Data) -> [String] {
        var lines = take(chunk)
        lock.lock()
        defer { lock.unlock() }
        if !buffer.isEmpty {
            lines.append(String(decoding: buffer, as: UTF8.self))
            buffer.removeAll()
        }
        return lines
    }
}

/// Lets `onTermination`, which is `@Sendable`, reach a `Process`.
private final class ProcessHandle: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func terminateIfRunning() {
        guard process.isRunning else { return }
        process.terminate()
    }
}
```

- [ ] **Step 4: Regenerate and run the tests**

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/installRunnerStreamsMergedOutputLineByLine()" -only-testing:"TenXAppTests/installRunnerReportsANonzeroExitAfterDeliveringItsOutput()" -only-testing:"TenXAppTests/installRunnerEmitsAFinalLineThatHasNoTrailingNewline()" -only-testing:"TenXAppTests/abandoningTheStreamTerminatesTheInstallProcess()"
```

Expected: PASS, `Test run with 4 tests`. None of these reach the network; every command is a local shell fixture.

- [ ] **Step 5: Commit**

```bash
git add App/Onboarding/OmpInstallRunner.swift Tests/TenXAppTests/OmpInstallRunnerTests.swift 10x.xcodeproj
git commit -m "feat(onboarding): stream the OMP install command's output"
```

---

### Task 5: Route, container, and the three steps

The atomic task. Replacing the two `AppRoute` cases breaks compilation until the container and every call site are updated, so this lands as one change.

**Files:**
- Modify: `App/Application/AppRoute.swift`
- Modify: `App/Application/AppModel.swift`
- Modify: `App/Shell/AppShellView.swift`
- Create: `App/Onboarding/OnboardingView.swift`
- Create: `App/Onboarding/OnboardingInstallStepView.swift`
- Create: `App/Onboarding/OnboardingProjectStepView.swift`
- Create: `App/Onboarding/OnboardingRowView.swift`
- Modify: `App/Providers/ProviderSetupView.swift`
- Delete: `App/Setup/SetupView.swift`
- Test: `Tests/TenXAppTests/OnboardingRoutingTests.swift`

**Interfaces:**
- Consumes: `OnboardingStep.firstUnmet(...)` (Task 2), `GitRepositoryScanner` / `GitRepositorySuggestion` (Task 3), `OmpInstallRunner` / `OmpInstallError` (Task 4).
- Produces: `AppRoute.onboarding(OnboardingStep)`; `AppModel.gateRoute()`, `AppModel.unmetRequirements() -> [OnboardingStep]`, `AppModel.firstUnmetRequirement() -> OnboardingStep?`, `AppModel.recordOnboardingProject(_ url: URL)`, `AppModel.useOmp(at url: URL? = nil) async`; `OnboardingRowView`, `OnboardingSkeletonRows`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TenXAppTests/OnboardingRoutingTests.swift`:

```swift
import Foundation
import Testing
@testable import TenXApp

@MainActor
@Test func gatingSendsAFreshInstallToTheInstallStep() {
    let model = AppModel()
    model.gateRoute()
    #expect(model.route == .onboarding(.installOmp))
}

@MainActor
@Test func gatingSendsAConnectedUserWithNoProjectToTheProjectStep() {
    let model = AppModel()
    model.installation = OmpInstallation(
        executableURL: URL(filePath: "/Users/example/.local/bin/omp"),
        version: "18.0.4")
    // No provider model at all reads as no authenticated provider.
    #expect(model.firstUnmetRequirement() == .connectProvider)

    model.selectedProjectURL = URL(filePath: "/tmp/Project", directoryHint: .isDirectory)
    #expect(model.firstUnmetRequirement() == .connectProvider)
}

@MainActor
@Test func recordingAProjectDuringOnboardingDoesNotLeaveTheFlow() {
    let model = AppModel()
    model.route = .onboarding(.chooseProject)

    model.recordOnboardingProject(URL(filePath: "/tmp/First", directoryHint: .isDirectory))

    // Still on the step, so a second folder can be added. `chooseProject`
    // would have routed away on the first selection.
    #expect(model.route == .onboarding(.chooseProject))
    #expect(model.selectedProjectURL?.lastPathComponent == "First")

    model.recordOnboardingProject(URL(filePath: "/tmp/Second", directoryHint: .isDirectory))
    #expect(model.selectedProjectURL?.lastPathComponent == "Second")
}

@MainActor
@Test func leavingSettingsFromOnboardingLandsOnTheWorkspace() {
    let model = AppModel()
    model.route = .onboarding(.connectProvider)
    model.openSettings()
    #expect(model.route == .settings)

    model.leaveSettings()
    #expect(model.route == .newSession)
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/gatingSendsAFreshInstallToTheInstallStep()"
```

Expected: FAIL to compile, "type 'AppRoute' has no member 'onboarding'".

- [ ] **Step 3: Replace the route cases**

`App/Application/AppRoute.swift`:

```swift
enum AppRoute: Equatable {
    case onboarding(OnboardingStep)
    case newSession
    case session(String)
    case archivedSessions
    case settings
    case providers(ProviderWorkspaceSection)
}
```

Build now to get the compiler's list of every break. Every one is a site this task must fix:

```bash
xcodebuild build -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' 2>&1 | grep -E "error:" | sort -u
```

- [ ] **Step 4: Add the resolver and the recording helper to `AppModel`**

Add near `chooseProject`:

```swift
    /// Every requirement the workspace does not yet satisfy, in order.
    func unmetRequirements() -> [OnboardingStep] {
        OnboardingStep.unmet(
            installation: installation,
            hasAuthenticatedProvider: providerModel?.hasAuthenticatedProvider == true,
            selectedProjectURL: selectedProjectURL)
    }

    /// The requirement to ask for now.
    func firstUnmetRequirement() -> OnboardingStep? {
        unmetRequirements().first
    }

    /// Routes to the first unmet requirement, or to the workspace. Replaces
    /// eight scattered decisions and preserves their force-to-`newSession`
    /// semantics: every caller runs before the splash hands off, or inside a
    /// runtime replacement that already discarded managed sessions.
    func gateRoute() {
        route = firstUnmetRequirement().map(AppRoute.onboarding) ?? .newSession
    }

    /// Records a project chosen during onboarding.
    ///
    /// Deliberately not `chooseProject`: that ends with `route = .newSession`,
    /// so the first selection would leave onboarding and no second folder
    /// could be added. There is no active session to tear down here.
    func recordOnboardingProject(_ url: URL) {
        let project = url.standardizedFileURL
        selectedProjectURL = project
        dependencies.recentProjectStore.recordSelection(project)
    }
```

- [ ] **Step 5: Route every site through `gateRoute()`**

Nine sites. The first eight replace existing assignments; the ninth is new.

1. Runtime preparation, OMP missing: replace `route = .setup` with `gateRoute()`.
2. Runtime replacement, OMP missing: replace `route = .setup` with `gateRoute()`.
3. Runtime preparation, services constructed: replace `route = .providerSetup` with `gateRoute()`.
4. Runtime replacement, services constructed: replace `route = .providerSetup` with `gateRoute()`.
5. Runtime preparation, providers loaded: replace `route = provider.hasAuthenticatedProvider ? .newSession : .providerSetup` with `gateRoute()`.
6. Runtime replacement, providers loaded: same replacement.
7. Provider fallback load: same replacement.
8. `completeProviderSetup()`. This is the site that would otherwise defeat the feature: it currently jumps to `.newSession`, skipping the project step. The guard becomes redundant because `gateRoute()` keeps an unauthenticated user on the connect step:

```swift
    func completeProviderSetup() {
        gateRoute()
        Task { await refreshComposerControls() }
    }
```

9. New call at the end of `prepareSessionsAndRecentProjects(attemptID:stages:)`, after `selectedProjectURL` is assigned and the warm-client task group completes:

```swift
        // Startup assigns `selectedProjectURL` in this stage, after the runtime
        // stage already routed. Without re-gating, every returning user would
        // be shown the project step.
        gateRoute()
```

Also update `leaveSettings()`, whose switch names the deleted cases:

```swift
        switch destination {
        case .onboarding, .settings:
            route = .newSession
        default:
            route = destination
        }
```

And widen `useOmp` so the install step can re-run discovery with no preferred path:

```swift
    func useOmp(at url: URL? = nil) async {
```

Its body already passes `preferredURL: url`, which now accepts `nil`, and `replaceWorkspaceRuntime` ends at site 4 or 6, so gating happens on the way out.

- [ ] **Step 6: Extract the shared row chrome**

`ProviderSetupView` keeps its 42pt row and skeleton rows private, and the project step needs both. Create `App/Onboarding/OnboardingRowView.swift`:

```swift
import SwiftUI

/// The onboarding list row: a title over an optional detail line, a trailing
/// accessory, and the 1pt rule that separates rows. Shared by the provider and
/// project steps so the two lists cannot drift apart.
struct OnboardingRowView<Accessory: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TenXTypography.body(size: 14, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                if let detail {
                    Text(detail)
                        .font(TenXTypography.body(size: 12))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer(minLength: 12)
            accessory()
        }
        .frame(height: 42)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TenXPalette.color(TenXPalette.separatorHex))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Placeholder rows shown while a step's list is loading.
struct OnboardingSkeletonRows: View {
    var count = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(TenXPalette.color(TenXPalette.separatorHex))
                            .frame(width: 128, height: 12)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(TenXPalette.color(TenXPalette.separatorHex))
                            .frame(width: 96, height: 10)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(TenXPalette.color(TenXPalette.separatorHex))
                        .frame(width: 60, height: 12)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(TenXPalette.color(TenXPalette.separatorHex))
                        .frame(height: 1)
                }
                .accessibilityHidden(true)
            }
        }
    }
}
```

Then in `App/Providers/ProviderSetupView.swift`: delete `private struct ProviderSetupLoadingRows`, use `OnboardingSkeletonRows()` in its place, and rewrite `ProviderSetupRowView`'s body to wrap `OnboardingRowView(title: provider.name, detail: description) { ... }` with its existing trailing controls unchanged. Delete the view's own `BrandWordmark`, its title and subtitle `VStack`, its `.frame(width: 470, alignment: .leading)`, and its `.padding(56)`. The container supplies all of those now. Keep the `GeometryReader`, the provider list, the `Continue` button, and the `.sheet` for `ExtensionInputSheet`.

- [ ] **Step 7: Write the container**

Create `App/Onboarding/OnboardingView.swift`:

```swift
import SwiftUI

struct OnboardingView: View {
    let model: AppModel
    let step: OnboardingStep

    /// The unmet steps as of when onboarding was entered. Held so the counter
    /// does not shrink underneath the user as requirements are satisfied.
    @State private var entrySteps: [OnboardingStep] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            BrandWordmark(width: 48)

            VStack(alignment: .leading, spacing: 8) {
                if let position {
                    Text("Step \(position) of \(entrySteps.count)")
                        .font(TenXTypography.body(size: 12))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
                Text(title)
                    .font(TenXTypography.title(size: 38))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                Text(explanation)
                    .font(TenXTypography.body(size: 14))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }

            content

            if let previous {
                Button("Back") { model.route = .onboarding(previous) }
                    .buttonStyle(GhostActionStyle(
                        color: TenXPalette.color(TenXPalette.nearBlackHex)))
            }
        }
        .frame(width: 470, alignment: .leading)
        .padding(56)
        .task {
            // Captured once: the counter must not shrink underneath the user
            // as they satisfy requirements.
            guard entrySteps.isEmpty else { return }
            entrySteps = model.unmetRequirements()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .installOmp:
            OnboardingInstallStepView(model: model)
        case .connectProvider:
            if let providerModel = model.providerModel {
                ProviderSetupView(
                    model: providerModel,
                    onContinue: model.completeProviderSetup)
            }
        case .chooseProject:
            OnboardingProjectStepView(model: model)
        }
    }

    private var position: Int? {
        entrySteps.firstIndex(of: step).map { $0 + 1 }
    }

    /// The step before this one within the entry set, if any.
    private var previous: OnboardingStep? {
        guard let index = entrySteps.firstIndex(of: step), index > 0 else { return nil }
        return entrySteps[index - 1]
    }

    private var title: String {
        switch step {
        case .installOmp:
            model.installation != nil
                ? "Using OMP"
                : (model.unrunnableOmpURL == nil ? "Install OMP" : "OMP won’t run")
        case .connectProvider: "Connect a provider"
        case .chooseProject: "Choose a project"
        }
    }

    private var explanation: String {
        switch step {
        case .installOmp:
            if model.installation != nil { return "10x is ready to start sessions." }
            return model.unrunnableOmpURL == nil
                ? "10x starts and resumes agent sessions through OMP."
                : "10x found OMP but couldn’t run it. Its interpreter may be missing."
        case .connectProvider: "Choose at least one provider to start sessions."
        case .chooseProject: "Sessions run in a project folder."
        }
    }
}
```

- [ ] **Step 8: Write the install step**

Create `App/Onboarding/OnboardingInstallStepView.swift`. This replaces `App/Setup/SetupView.swift`; delete that file in Step 11.

```swift
import AppKit
import SwiftUI

struct OnboardingInstallStepView: View {
    let model: AppModel

    @State private var log: [String] = []
    @State private var isInstalling = false
    @State private var didFail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.installation != nil {
                installedCard
            } else {
                commandCard
                if !log.isEmpty { logView }
                if didFail {
                    Text("Install failed. The output above shows why.")
                        .font(TenXTypography.body(size: 13))
                        .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                }
            }

            if let setupError = model.setupError {
                Text(setupError)
                    .font(TenXTypography.mono())
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                    .textSelection(.enabled)
            }

            HStack(spacing: 12) {
                if model.installation != nil {
                    Button("Continue") { model.gateRoute() }
                        .buttonStyle(GhostActionStyle())
                } else {
                    Button(isInstalling ? "Installing…" : "Install OMP") { install() }
                        .buttonStyle(GhostActionStyle())
                        .disabled(isInstalling)
                }
                Button("Locate OMP") { locate() }
                    .buttonStyle(GhostActionStyle(
                        color: TenXPalette.color(TenXPalette.nearBlackHex)))
                    .accessibilityHint("Choose the OMP executable on this Mac")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var installedCard: some View {
        CornerCard(color: TenXPalette.color(TenXPalette.cyanHex)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.installation?.version ?? "")
                    .font(TenXTypography.body(weight: .semibold))
                Text(model.installation?.executableURL.path ?? "")
                    .font(TenXTypography.mono())
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var commandCard: some View {
        CornerCard(color: TenXPalette.color(TenXPalette.cyanHex)) {
            VStack(alignment: .leading, spacing: 12) {
                if let unrunnable = model.unrunnableOmpURL {
                    Text("Found at")
                        .font(TenXTypography.body(weight: .semibold))
                    Text(unrunnable.path)
                        .font(TenXTypography.mono())
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .textSelection(.enabled)
                } else {
                    Text("Runs this command:")
                        .font(TenXTypography.body(weight: .semibold))
                    Text(OmpInstallRunner.command)
                        .font(TenXTypography.mono())
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .textSelection(.enabled)
                    Text("Checked automatically")
                        .font(TenXTypography.body(size: 12, weight: .semibold))
                    ForEach(OmpExecutableLocator.knownPaths, id: \.self) { path in
                        Text(path)
                            .font(TenXTypography.mono())
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(log.enumerated()), id: \.offset) { entry in
                        Text(entry.element)
                            .font(TenXTypography.mono())
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.offset)
                    }
                }
            }
            .frame(height: 126)
            .onChange(of: log.count) { _, count in
                proxy.scrollTo(count - 1, anchor: .bottom)
            }
        }
    }

    private func install() {
        log = []
        didFail = false
        isInstalling = true
        Task {
            do {
                for try await line in OmpInstallRunner().run() { log.append(line) }
            } catch {
                didFail = true
            }
            isInstalling = false
            // Advance only once discovery finds a runnable executable, never on
            // the script's own success line.
            await model.useOmp()
        }
    }

    private func locate() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use OMP"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.useOmp(at: url) }
    }
}
```

- [ ] **Step 9: Write the project step**

> **Removed 2026-08-27:** the `scanner`/`GitRepositoryScanner` wiring and the
> `isScanning` skeleton state shown below no longer exist. The project step
> now reads `AppModel.sessions` through
> `ProjectSessionGrouper.choosableProjectURLs(from:)` directly, with no
> injectable dependency and no loading state. See the update note at the top
> of this document. The code below is left as originally written.

Create `App/Onboarding/OnboardingProjectStepView.swift`:

```swift
import AppKit
import SwiftUI

struct OnboardingProjectStepView: View {
    let model: AppModel
    /// Injectable so a snapshot test can point the scan at a fixture tree.
    var scanner = GitRepositoryScanner()

    @State private var suggestions: [GitRepositorySuggestion] = []
    @State private var chosen: Set<String> = []
    @State private var isScanning = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isScanning {
                OnboardingSkeletonRows()
            } else if suggestions.isEmpty {
                Text("No Git repositories found in your home folder.")
                    .font(TenXTypography.body(size: 13))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            } else {
                Text("Found in your home folder")
                    .font(TenXTypography.body(size: 12, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions) { suggestion in
                            OnboardingRowView(
                                title: suggestion.url.lastPathComponent,
                                detail: suggestion.url.path
                            ) {
                                if chosen.contains(suggestion.id) {
                                    Text("Added")
                                        .font(TenXTypography.body(size: 12))
                                        .foregroundStyle(
                                            TenXPalette.color(TenXPalette.mutedTextHex))
                                } else {
                                    Button("Add") { choose(suggestion.url) }
                                        .buttonStyle(GhostActionStyle())
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
                .frame(height: 126)
            }

            HStack(spacing: 12) {
                Button("Continue") { model.gateRoute() }
                    .buttonStyle(GhostActionStyle())
                    .disabled(model.selectedProjectURL == nil)
                Button("Choose folder…") { chooseFolder() }
                    .buttonStyle(GhostActionStyle(
                        color: TenXPalette.color(TenXPalette.nearBlackHex)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            // Cancelled automatically when the step goes away.
            suggestions = (try? await scanner.scan()) ?? []
            isScanning = false
        }
    }

    private func choose(_ url: URL) {
        model.recordOnboardingProject(url)
        chosen.insert(GitRepositorySuggestion(url: url, modified: .distantPast).id)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        choose(url)
    }
}
```

- [ ] **Step 10: Collapse the shell's two branches into one**

In `App/Shell/AppShellView.swift`, replace the two leading branches:

```swift
                if case .onboarding(let step) = model.route {
                    OnboardingView(model: model, step: step)
                } else {
```

and in `routeCanvas`, replace the `case .setup:` and `case .providerSetup:` arms with a single `case .onboarding: EmptyView()`. Update `hasComposer` if the compiler flags its switch.

- [ ] **Step 11: Delete the replaced screen, regenerate, and run the tests**

```bash
git rm App/Setup/SetupView.swift
ruby scripts/generate_xcodeproj.rb
xcodebuild build -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' 2>&1 | grep -E "error:|warning:" | sort -u
```

Expected: no errors, no new warnings. Then:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -only-testing:"TenXAppTests/gatingSendsAFreshInstallToTheInstallStep()" -only-testing:"TenXAppTests/gatingSendsAConnectedUserWithNoProjectToTheProjectStep()" -only-testing:"TenXAppTests/recordingAProjectDuringOnboardingDoesNotLeaveTheFlow()" -only-testing:"TenXAppTests/leavingSettingsFromOnboardingLandsOnTheWorkspace()"
```

Expected: PASS, `Test run with 4 tests`.

- [ ] **Step 12: Fix the existing route assertions**

`Tests/TenXAppTests/AppModelNavigationTests.swift` and `Tests/TenXAppTests/AppModelStartupTests.swift` assert `.setup` and `.providerSetup`. Update each to the matching `.onboarding(...)` case. Do **not** relax an assertion to make it pass: a test that expected `.newSession` and now sees `.onboarding(.chooseProject)` has found the new project gate, so give its fixture a `selectedProjectURL` (or a recent project in its `RecentProjectStore`) if the scenario is meant to reach the workspace.

Run the two files' tests and confirm each prints a `Test run with …` line.

- [ ] **Step 13: Commit**

```bash
git add -A
git commit -m "feat(onboarding): route install, provider, and project through one flow"
```

---

### Task 6: Snapshot migration

Seventeen reference images cover `SetupView` and `ProviderSetupView`. Both now render inside the container, so every one of them changes. This is its own task because it is review work, not code work: each changed PNG must be looked at.

**Files:**
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Modify/Delete: `Tests/TenXAppTests/ReferenceImages/*.png`

- [ ] **Step 1: Re-target the setup snapshots**

Replace the two `SetupView` tests:

```swift
@MainActor
@Test func onboardingInstallStepSnapshot() throws {
    try assertSnapshot(
        OnboardingView(model: AppModel(), step: .installOmp),
        name: "onboarding-install")
}

@MainActor
@Test func onboardingInstallStepUnrunnableSnapshot() throws {
    let model = AppModel()
    model.unrunnableOmpURL = URL(filePath: "/Users/example/.bun/bin/omp")
    try assertSnapshot(
        OnboardingView(model: model, step: .installOmp),
        name: "onboarding-install-unrunnable")
}
```

- [ ] **Step 2: Add the project step's three states**

```swift
@MainActor
@Test func onboardingProjectStepEmptySnapshot() throws {
    let model = AppModel()
    model.installation = OmpInstallation(
        executableURL: URL(filePath: "/Users/example/.local/bin/omp"),
        version: "18.0.4")
    try assertSnapshot(
        OnboardingView(model: model, step: .chooseProject),
        name: "onboarding-project-empty",
        size: CGSize(width: 760, height: 560))
}
```

~~The populated and skeleton states need the scan pointed at a fixture. `OnboardingProjectStepView` already takes an injectable `scanner`; pass one rooted at a temporary tree, following the fixture in `GitRepositoryScannerTests`. Name the references `onboarding-project-populated` and `onboarding-project-scanning`.~~

**Removed 2026-08-27:** there is no scanner and no skeleton state to snapshot. `onboarding-project-scanning` was deleted outright. The populated case now builds `AppModel.sessions` with a few `SessionMetadata` values whose `cwd` are distinct project directories, and both `onboarding-project-empty` and `onboarding-project-populated` settle synchronously — no fixture tree, no async settle loop. See the update note at the top of this document and `assertSnapshotAfterSettling`'s removal in `Tests/TenXAppTests/SnapshotHarness.swift`.

- [ ] **Step 3: Re-target the provider snapshots**

The existing `ProviderSetupView(model:onContinue:)` calls still compile, but they now render without the wordmark and title. Wrap each in the container so the snapshot covers what the user actually sees. Where a test needs a specific `ProviderManagementViewModel`, keep building it exactly as it does now and give `AppModel` that model. Keep the existing reference names so the diff shows a changed image rather than an added and a deleted one.

- [ ] **Step 4: Re-record and review**

```bash
TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
git status --short Tests/TenXAppTests/ReferenceImages
```

Open every changed PNG and confirm it is correct: spacing even, nothing clipped, no truncated text, the step counter present and correct. Recording is deterministic, so anything git reports as modified is a real visual change. Delete references orphaned by removed tests (`omp-missing.png`, `omp-unrunnable.png`).

```bash
git rm Tests/TenXAppTests/ReferenceImages/omp-missing.png Tests/TenXAppTests/ReferenceImages/omp-unrunnable.png
ls Tests/TenXAppTests/ReferenceImages/*.actual.png
```

Expected: no `.actual.png` files. A leftover one means that snapshot is still failing; never commit one.

- [ ] **Step 5: Commit**

```bash
git add Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/ReferenceImages 10x.xcodeproj
git commit -m "test(onboarding): re-record setup and provider snapshots for the flow"
```

---

### Task 7: Full verification

**Files:** none changed unless a failure is found.

- [ ] **Step 1: Build and run the whole suite**

```bash
xcodebuild build -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' 2>&1 | tail -5
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' 2>&1 | tail -20
```

Record the exact pass count from the `Test run with N tests` line. "Tests pass" is not a result; the number is.

- [ ] **Step 2: Verify the flow in the real build**

Load `superpowers:verification-before-completion` and the `launching-local-builds` skill, then launch the built app and walk each path, screenshotting each:

1. **Three steps.** Point the app at a home with no OMP (`OmpExecutableLocator(homeDirectory:)` is injectable; otherwise rename `~/.local/bin/omp` and `~/.bun/bin/omp` aside). Confirm "Step 1 of 3", the command visible before running, output streaming during the install, and automatic advance to the provider step.
2. **Failed install.** Confirm the output stays on screen, the failure line appears, and `Locate OMP` still works.
3. **Two steps.** With OMP present and no provider connected, confirm the counter reads "Step 1 of 2".
4. **Project step.** Confirm suggestions appear, that a second folder can be added without leaving the step, and that `Continue` reaches the workspace with the project selected.
5. **No onboarding.** Relaunch as a returning user and confirm the workspace opens directly, with no project step. This is the regression the ninth call site exists to prevent.
6. **Back.** From the project step, confirm `Back` reaches the provider step, and from there the install step shows "Using OMP" with the path and version.

- [ ] **Step 3: Sync the base branch and flip the PR**

```bash
git fetch origin main && git merge origin/main
```

Resolve any conflict in `10x.xcodeproj` by taking either side and re-running `ruby scripts/generate_xcodeproj.rb`, never by hand. Then rewrite the PR body into the `writing-prs` template with the real pass count and the screenshots, and flip to ready:

```bash
gh api repos/NextStep-AI-inc/10x/pulls/2 -X PATCH -F body=@<file> -F draft=false
```

Do not merge. The PR URL and the files-changed list are the deliverable.

---

## Self-Review

**Spec coverage.** Requirement resolution → Task 2 (pure resolver) and Task 5 (all nine sites, `leaveSettings`). Executable discovery, both the `~/.local/bin` gap and the three-list unification → Task 1. Install step → Task 4 (runner) and Task 5 Step 8 (view). Provider step → Task 5 Step 6. Project step, scan and selection → Task 3 and Task 5 Step 9. Views, navigation, shared chrome, copy → Task 5 Steps 6 to 10. Testing → the test steps in Tasks 1 to 4, Task 5 Step 1, Task 6, Task 7.

**Counter correctness.** The counter uses `unmetRequirements()`, not the suffix of `allCases` from the current step. The two differ on the mid-session OMP-loss path: `providerModel` is discarded with the runtime, so `connectProvider` is unmet, while a previously chosen `selectedProjectURL` survives. The suffix would say "Step 1 of 3" and then jump to the workspace after two steps.

**Types.** `GitRepositorySuggestion.id` is `url.path`, which is why `OnboardingProjectStepView.choose` rebuilds one to key `chosen`; a caller could equally store `url.standardizedFileURL.path` directly. `useOmp(at:)` becomes optional-taking and defaulted, so the existing call in `locate()` is unchanged. `OnboardingStep` is referenced by `AppRoute`, so both live in the app target, not `OmpKit`.

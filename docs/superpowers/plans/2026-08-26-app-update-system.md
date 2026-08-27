# Application Update System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship 10x as a signed, notarized Mac app from a public NextStep repository that updates itself through Sparkle 2, with the entire update experience rendered in the existing startup splash window.

**Architecture:** Sparkle 2 owns feed polling, EdDSA verification, bundle replacement, and relaunch. A custom `SPUUserDriver` translates every Sparkle callback into a `UpdateState` phase, and `SplashView` becomes a pure function of a `SplashPresentation` value that either `StartupState` or `UpdateState` produces. The launch-time check is a fifth advisory ledger row that is structurally incapable of gating handoff or causing recovery. Releases are cut by GitHub Actions on a tag, running the same `scripts/release.sh` that runs locally.

**Tech Stack:** Swift 6.0 with complete concurrency checking, SwiftUI and Observation, Sparkle 2.6+, Swift Testing, GitHub Actions on `macos-15`, `notarytool`, `xcodeproj` 1.27 Ruby gem, macOS 15+

**Spec:** `docs/superpowers/specs/2026-08-26-app-update-system-design.md`

## Global Constraints

- Target macOS 15 and later. Swift 6.0 with `SWIFT_STRICT_CONCURRENCY = complete`. No `any` escape hatches, no `as!`, no `@unchecked Sendable` added to make something compile.
- The repository is `NextStep-AI-inc/10x`, public, single repository. There is no separate releases repository.
- Bundle identifier is `com.nextstep.tenx`. Development team is `345S42BKPY`. Signing identity is `Developer ID Application: NextStep AI Inc. (345S42BKPY)`.
- Every new app source or app-test file must be followed by `ruby scripts/generate_xcodeproj.rb` before `xcodebuild`. The project file is generated, never hand-edited.
- Use the exact visible copy from the spec's copy tables. Do not paraphrase a single string.
- No em dashes in user-facing strings. No leaked framework error text on any user surface.
- Sparkle's standard user interface must never appear. `SPUStandardUpdaterController` is forbidden; only `SPUUpdater` with the custom driver is permitted.
- The advisory update stage never enters `Stopped`, never triggers recovery, and is never marked stopped by recovery.
- Project names, paths, session names, provider names, model names, prompts, and account data stay out of the splash. Version numbers are the only new content permitted there.
- `AppModel.shutdown()` must be awaited before consenting to a Sparkle install, so no OMP child survives an update relaunch.
- Reduce Motion suppresses the travelling segment and amplitude breathing but retains the determinate fill.
- The EdDSA private key is never committed, never printed, and never written outside a secret store or the developer's own keychain.
- Follow TDD for each task: focused red test, minimal implementation, focused green test, relevant full suite, atomic conventional commit. Conventional commits, no self-attribution.
- Recording snapshots through xcodebuild requires the `TEST_RUNNER_` prefix: `TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild ... test`. Without it the run reports "Missing reference image" instead of recording.
- `-only-testing:` for a top-level `@Test func` needs the parentheses, for example `-only-testing:"TenXAppTests/updateStateStartsIdle()"`. Without them the run silently executes zero tests and reports success.
- Any test that calls `await model.bootstrap()` on an `AppModel` whose locator resolves must tear the runtime down with `if let manager = model.processManager { await manager.closeAll() }`. Skipping it leaks file descriptors and produces `NSPOSIXErrorDomain Code=24` failures in unrelated suites later in the run.
- Baseline before starting: run the full app suite once and record the pass count. Every task's "full suite" step compares against it.
- Tasks 1 and 17 touch GitHub and are gated on Tanner's explicit go-ahead. Do not run them unprompted.

## File Map

### New: update domain (`App/Updates/`)

- `App/Updates/UpdateState.swift`: the observable presentation model. One phase plus the data that phase needs. Knows nothing about Sparkle.
- `App/Updates/SplashUpdateDriver.swift`: conforms to `SPUUserDriver`. Translates Sparkle callbacks into `UpdateState` phases and splash button presses into Sparkle return values. The only file that imports Sparkle types alongside `UpdateState`.
- `App/Updates/UpdateController.swift`: owns the `SPUUpdater` instance and exposes the two entry points. The only file that constructs Sparkle objects.
- `App/Updates/UpdatePresentation.swift`: builds a `SplashPresentation` from an `UpdateState`. Pure, no imports beyond SwiftUI.

### New: shared splash presentation

- `App/Startup/SplashPresentation.swift`: the value `SplashView` renders. Produced by both `StartupState` and `UpdateState`.

### Modified: startup

- `App/Startup/StartupState.swift`: add the advisory `updates` stage, `gatingCases`, the handoff latch, and the startup presentation builder.
- `App/Startup/SplashView.swift`: becomes a pure function of `SplashPresentation`.
- `App/Startup/StartupSignalView.swift`: add the optional determinate `progress`.
- `App/Startup/StartupSceneView.swift`: read the handoff latch from `StartupState`, render whichever presentation is active.

### Modified: application

- `App/Application/AppModel.swift`: own `UpdateController`, run the advisory check, hold handoff while an offer is pending.
- `App/Application/AppDependencies.swift`: inject the update controller factory so tests can substitute a fake.
- `App/TenXApp.swift`: add the `Check for Updates…` command.
- `App/Info.plist`: Sparkle keys, version build setting references.

### Modified: build and release

- `scripts/generate_xcodeproj.rb`: signing, hardened runtime, version settings, Sparkle package reference.
- `scripts/release.sh`: new. The full six-step release chain.
- `.github/workflows/release.yml`: new. Tag-triggered wrapper around `release.sh`.

### Modified: tests

- `Tests/TenXAppTests/StartupStateTests.swift`: the four-row assertion becomes five, gating assertions added.
- `Tests/TenXAppTests/StartupSplashSnapshotTests.swift`: updated for the presentation refactor.
- `Tests/TenXAppTests/UpdateStateTests.swift`: new.
- `Tests/TenXAppTests/SplashUpdateDriverTests.swift`: new.
- `Tests/TenXAppTests/UpdateSnapshotTests.swift`: new.
- `Tests/TenXAppTests/AppModelUpdateTests.swift`: new.

---

### Task 1: Create the repository and open the draft PR

**GATED.** Do not run this task without Tanner's explicit go-ahead in the current session. If he defers, skip to Task 2 and run this later; nothing in Tasks 2 through 16 requires a remote.

**Files:**
- No source files change.

**Interfaces:**
- Consumes: nothing.
- Produces: a `origin` remote on `NextStep-AI-inc/10x`, and a draft PR for this branch.

- [ ] **Step 1: Confirm the repository does not already exist**

```bash
gh repo view NextStep-AI-inc/10x 2>&1 | head -3
```

Expected: `Could not resolve to a Repository`. If it resolves, stop and ask Tanner before touching it.

- [ ] **Step 2: Read `writing-prs` before creating anything**

The PR body template and draft lifecycle live there. This plan does not restate them.

- [ ] **Step 3: Create the public repository and push `main`**

Run from the main checkout, not this worktree, because `main` lives there.

```bash
gh repo create NextStep-AI-inc/10x --public --source . --remote origin --description "10x for macOS. A native desktop client for OMP." --push
```

- [ ] **Step 4: Push this worktree's branch and open the draft PR**

```bash
git push -u origin tannerpham/app-update-system-plan-24aedf && gh pr create --draft --title "feat(updates): application update system" --body-file /dev/stdin <<'BODY'
Implements the application update system.

Spec: docs/superpowers/specs/2026-08-26-app-update-system-design.md
Plan: docs/superpowers/plans/2026-08-26-app-update-system.md
BODY
```

- [ ] **Step 5: Confirm the default branch and visibility**

```bash
gh repo view NextStep-AI-inc/10x --json visibility,defaultBranchRef --jq '{visibility: .visibility, branch: .defaultBranchRef.name}'
```

Expected: `{"visibility":"PUBLIC","branch":"main"}`

---

### Task 2: Project identity and Release signing settings

**Files:**
- Modify: `scripts/generate_xcodeproj.rb:73-84`
- Modify: `App/Info.plist:19-22`
- Test: `Tests/TenXAppTests/BundleIdentityTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: bundle identifier `com.nextstep.tenx`; `CFBundleShortVersionString` resolving from `$(MARKETING_VERSION)`; `CFBundleVersion` resolving from `$(CURRENT_PROJECT_VERSION)`; a Release configuration that signs with Developer ID and enables the hardened runtime.

- [ ] **Step 1: Write the failing test**

Create `Tests/TenXAppTests/BundleIdentityTests.swift`:

```swift
import Foundation
import Testing
@testable import TenXApp

@Test func bundleIdentifierIsOwnedByNextStep() {
    let identifier = Bundle.main.bundleIdentifier
    #expect(identifier == "com.nextstep.tenx")
}

@Test func versionKeysResolveToConcreteValues() {
    let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

    #expect(short?.isEmpty == false)
    #expect(build?.isEmpty == false)
    #expect(short?.contains("$") == false)
    #expect(build?.contains("$") == false)
}
```

The `contains("$")` assertions catch an unsubstituted build setting, which is the failure mode that would otherwise ship a literal `$(MARKETING_VERSION)` string into the app.

- [ ] **Step 2: Run the test to verify it fails**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-identity test '-only-testing:TenXAppTests/bundleIdentifierIsOwnedByNextStep()'
```

Expected: FAIL, actual identifier is `com.tannerpham.tenx`.

- [ ] **Step 3: Point the Info.plist version keys at build settings**

In `App/Info.plist`, replace the two hardcoded values:

```xml
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
```

- [ ] **Step 4: Update the app build settings in the generator**

In `scripts/generate_xcodeproj.rb`, replace the `app.build_configurations.each` block's settings hash with:

```ruby
app.build_configurations.each do |configuration|
  configuration.build_settings.merge!({
    "PRODUCT_BUNDLE_IDENTIFIER" => "com.nextstep.tenx",
    "PRODUCT_MODULE_NAME" => "TenXApp",
    "INFOPLIST_FILE" => "App/Info.plist",
    "GENERATE_INFOPLIST_FILE" => "NO",
    "MARKETING_VERSION" => "0.1.0",
    "CURRENT_PROJECT_VERSION" => "1",
    "SWIFT_VERSION" => "6.0",
    "SWIFT_STRICT_CONCURRENCY" => "complete",
    "MACOSX_DEPLOYMENT_TARGET" => "15.0",
    "ENABLE_APP_SANDBOX" => "NO",
    "ASSETCATALOG_COMPILER_APPICON_NAME" => "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME" => "",
    "DEVELOPMENT_TEAM" => "345S42BKPY",
  })

  if configuration.name == "Release"
    configuration.build_settings.merge!({
      "CODE_SIGN_STYLE" => "Manual",
      "CODE_SIGN_IDENTITY" => "Developer ID Application",
      "ENABLE_HARDENED_RUNTIME" => "YES",
    })
  else
    configuration.build_settings.merge!({
      "CODE_SIGN_STYLE" => "Manual",
      "CODE_SIGN_IDENTITY" => "-",
      "CODE_SIGNING_REQUIRED" => "YES",
      "CODE_SIGNING_ALLOWED" => "YES",
    })
  end
end
```

The `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` defaults exist so that a plain local build produces a valid app. `release.sh` overrides both on the command line.

Non-Release configurations must pin ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) explicitly. Setting `DEVELOPMENT_TEAM` while leaving `CODE_SIGN_STYLE = Automatic` makes Xcode demand an `Apple Development` certificate for that team, which this machine does not have and which nothing in this project needs. Ad-hoc signing requires no certificate and no provisioning profile, so Debug and test builds behave identically on a developer machine and a CI runner.

The tests target inherits `DEVELOPMENT_TEAM` from nothing, so add it and the same ad-hoc signing to the tests configuration block:

```ruby
    "DEVELOPMENT_TEAM" => "345S42BKPY",
    "CODE_SIGN_STYLE" => "Manual",
    "CODE_SIGN_IDENTITY" => "-",
```

- [ ] **Step 5: Update the tests target bundle identifier**

In the `tests.build_configurations.each` block, change:

```ruby
    "PRODUCT_BUNDLE_IDENTIFIER" => "com.nextstep.tenx.tests",
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-identity test '-only-testing:TenXAppTests/bundleIdentifierIsOwnedByNextStep()' '-only-testing:TenXAppTests/versionKeysResolveToConcreteValues()'
```

Expected: PASS.

- [ ] **Step 7: Verify the Release configuration signs correctly**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-release-identity build && codesign -dv --verbose=2 /private/tmp/tenx-release-identity/Build/Products/Release/10x.app 2>&1 | grep -E "Authority|flags"
```

Expected: `Authority=Developer ID Application: NextStep AI Inc. (345S42BKPY)` and `flags=0x10000(runtime)`. The `runtime` flag confirms the hardened runtime, which notarization requires.

- [ ] **Step 8: Run the full suite**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-identity-full test 2>&1 | tail -20
```

Expected: the recorded baseline pass count, plus two.

- [ ] **Step 9: Commit**

```bash
git add scripts/generate_xcodeproj.rb App/Info.plist 10x.xcodeproj Tests/TenXAppTests/BundleIdentityTests.swift && git commit -m "build: move the app to the NextStep identity and Developer ID signing"
```

---

### Task 3: Add Sparkle as a package dependency

**Files:**
- Modify: `scripts/generate_xcodeproj.rb:65-78`
- Test: `Tests/TenXAppTests/SparkleLinkageTests.swift` (create)

**Interfaces:**
- Consumes: Task 2's build settings.
- Produces: `import Sparkle` compiles in the app target, and `Sparkle.framework` is embedded in the built app bundle. `SPUUpdater` and `SPUUserDriver` are available.

- [ ] **Step 1: Write the failing test**

Create `Tests/TenXAppTests/SparkleLinkageTests.swift`:

```swift
import Foundation
import Sparkle
import Testing

@Test func sparkleIsEmbeddedAndLoadableAtRuntime() throws {
    let bundle = try #require(Bundle(for: SPUUpdater.self))

    #expect(bundle.bundleURL.lastPathComponent == "Sparkle.framework")
}
```

This checks a real failure mode rather than merely that the module compiled. A target that imports Sparkle but fails to embed the framework builds cleanly and then dies at launch with a dyld error, so asserting the class actually resolves to a loaded `Sparkle.framework` is the thing worth testing. Deriving the bundle from `SPUUpdater.self` avoids hardcoding a bundle identifier that a Sparkle release could change.

- [ ] **Step 2: Run the test to verify it fails**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-sparkle test '-only-testing:TenXAppTests/sparkleIsEmbeddedAndLoadableAtRuntime()' 2>&1 | tail -20
```

Expected: FAIL with `no such module 'Sparkle'`.

- [ ] **Step 3: Add the remote package reference to the generator**

In `scripts/generate_xcodeproj.rb`, immediately after the existing OmpKit local package block that ends with `app.frameworks_build_phase.files << build_file`, insert:

```ruby
sparkle_package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
sparkle_package.repositoryURL = "https://github.com/sparkle-project/Sparkle"
sparkle_package.requirement = {
  "kind" => "upToNextMajorVersion",
  "minimumVersion" => "2.6.0",
}
project.root_object.package_references << sparkle_package

sparkle_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
sparkle_product.package = sparkle_package
sparkle_product.product_name = "Sparkle"
app.package_product_dependencies << sparkle_product

sparkle_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
sparkle_build_file.product_ref = sparkle_product
app.frameworks_build_phase.files << sparkle_build_file
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-sparkle test '-only-testing:TenXAppTests/sparkleIsEmbeddedAndLoadableAtRuntime()' 2>&1 | tail -20
```

Expected: PASS. The first run resolves the package from the network and is slow.

- [ ] **Step 5: Confirm Sparkle is embedded and signed in a Release build**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-sparkle-release build && codesign -dv --verbose=2 /private/tmp/tenx-sparkle-release/Build/Products/Release/10x.app/Contents/Frameworks/Sparkle.framework 2>&1 | grep Authority
```

Expected: the same Developer ID authority. An unsigned or differently signed embedded framework fails notarization, so catching it here saves a full notarization round trip.

- [ ] **Step 6: Commit**

```bash
git add scripts/generate_xcodeproj.rb 10x.xcodeproj Tests/TenXAppTests/SparkleLinkageTests.swift && git commit -m "build: link Sparkle into the app target"
```

---

### Task 4: Generate the EdDSA keypair and add the Sparkle Info.plist keys

**Files:**
- Modify: `App/Info.plist`
- Test: `Tests/TenXAppTests/UpdateConfigurationTests.swift` (create)

**Interfaces:**
- Consumes: Task 3's Sparkle linkage.
- Produces: `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, and `SUAllowsAutomaticUpdates` in the app bundle.

- [ ] **Step 1: Locate Sparkle's key generation tool**

The tool ships inside the resolved package checkout.

```bash
find ~/Library/Developer/Xcode/DerivedData /private/tmp/tenx-sparkle -type f -name generate_keys -perm +111 2>/dev/null | head -1
```

If nothing is found, the artifact bundle has not been extracted yet. Run the Task 3 build once more, then retry.

- [ ] **Step 2: Generate the keypair and export the private key**

The private key goes to a file outside the repository. Never inside it.

```bash
KEYS="$(find ~/Library/Developer/Xcode/DerivedData /private/tmp/tenx-sparkle -type f -name generate_keys -perm +111 2>/dev/null | head -1)" && "$KEYS" && "$KEYS" -x ~/sparkle-10x-private-key.pem
```

Two invocations, in that order. Plain `generate_keys` creates the keypair, stores the private half in the login keychain, and prints the base64 public key. `-x` only exports a key that already exists, so calling it first fails with `No existing signing key found!`. Record the printed public key for the next step.

Never print, `cat`, or echo the `.pem`. The public key is safe to handle; the private key must go from the keychain to the GitHub secret without passing through a terminal or a file that outlives the next step.

- [ ] **Step 3: Store the private key as a repository secret and delete the export**

Only after Task 1 has created the repository. If the repository does not exist yet, keep the `.pem` and return to this step later.

```bash
gh secret set SPARKLE_ED_PRIVATE_KEY --repo NextStep-AI-inc/10x < ~/sparkle-10x-private-key.pem && rm -P ~/sparkle-10x-private-key.pem
```

The keychain copy remains and is what local `release.sh` runs use.

- [ ] **Step 4: Stop the generator from discarding the package pin**

`generate_xcodeproj.rb` begins with `FileUtils.rm_rf(project_path)`, which deletes the whole `10x.xcodeproj` directory including `project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. The pin only reappears after a build resolves packages again. A task that regenerates and then runs `git add 10x.xcodeproj` without an intervening build silently drops the Sparkle version pin from the commit.

Every remaining task in this plan regenerates the project, so fix it once here. Preserve the file across the wipe, near the top of the script:

```ruby
resolved_relative = "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
resolved_path = File.join(project_path, resolved_relative)
preserved_resolved = File.exist?(resolved_path) ? File.read(resolved_path) : nil

FileUtils.rm_rf(project_path)
```

and restore it after `project.save`:

```ruby
if preserved_resolved
  FileUtils.mkdir_p(File.dirname(resolved_path))
  File.write(resolved_path, preserved_resolved)
end
```

Verify it: `ruby scripts/generate_xcodeproj.rb && git status --short` must not report `Package.resolved` as deleted.

- [ ] **Step 5: Write the failing test**

Create `Tests/TenXAppTests/UpdateConfigurationTests.swift`:

```swift
import Foundation
import Testing
@testable import TenXApp

@Test func updateFeedPointsAtTheNextStepReleaseFeed() {
    let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String

    #expect(feed == "https://github.com/NextStep-AI-inc/10x/releases/latest/download/appcast.xml")
}

@Test func updatePublicKeyIsPresentAndDecodable() throws {
    let key = try #require(
        Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
    let decoded = try #require(Data(base64Encoded: key))

    #expect(decoded.count == 32)
}

@Test func sparkleNeverSchedulesItsOwnChecksOrInstalls() {
    let automaticChecks = Bundle.main.object(
        forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool
    let automaticInstalls = Bundle.main.object(
        forInfoDictionaryKey: "SUAllowsAutomaticUpdates") as? Bool

    #expect(automaticChecks == false)
    #expect(automaticInstalls == false)
}
```

The 32-byte assertion catches a truncated or misquoted key, which otherwise fails only at the moment a real update is verified.

- [ ] **Step 6: Run the test to verify it fails**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-updateconfig test '-only-testing:TenXAppTests/updateFeedPointsAtTheNextStepReleaseFeed()'
```

Expected: FAIL, feed is `nil`.

- [ ] **Step 7: Add the keys to Info.plist**

Insert before the closing `</dict>` in `App/Info.plist`, substituting the public key printed in Step 2:

```xml
    <key>SUFeedURL</key>
    <string>https://github.com/NextStep-AI-inc/10x/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>PASTE_THE_BASE64_PUBLIC_KEY_FROM_STEP_2</string>
    <key>SUEnableAutomaticChecks</key>
    <false/>
    <key>SUAllowsAutomaticUpdates</key>
    <false/>
```

`SUEnableAutomaticChecks` must be explicitly `false`. Leaving it absent makes Sparkle show its own permission prompt on second launch, which is a stock dialog and violates the design.

- [ ] **Step 8: Run the tests to verify they pass**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-updateconfig test '-only-testing:TenXAppTests/updateFeedPointsAtTheNextStepReleaseFeed()' '-only-testing:TenXAppTests/updatePublicKeyIsPresentAndDecodable()' '-only-testing:TenXAppTests/sparkleNeverSchedulesItsOwnChecksOrInstalls()'
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add App/Info.plist Tests/TenXAppTests/UpdateConfigurationTests.swift && git commit -m "feat(updates): configure the Sparkle feed and verification key"
```

Confirm before committing that no `.pem` file is staged: `git status --short | grep -i pem` must print nothing.

---

### Task 5: Determinate progress on the signal path

**Files:**
- Modify: `App/Startup/StartupSignalView.swift:36-46`, `:48-98`
- Test: `Tests/TenXAppTests/StartupSignalTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `StartupSignalView(isAnimating:isFailed:progress:)` where `progress` defaults to `nil`. `nil` preserves today's travelling segment. A value fills the path from the left edge to that fraction. `StartupSignalMotion.determinateTrim(_:) -> CGFloat` clamps to `0...1`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/TenXAppTests/StartupSignalTests.swift`:

```swift
@Test func determinateTrimClampsToTheUnitInterval() {
    #expect(StartupSignalMotion.determinateTrim(-0.5) == 0)
    #expect(StartupSignalMotion.determinateTrim(0) == 0)
    #expect(StartupSignalMotion.determinateTrim(0.42) == 0.42)
    #expect(StartupSignalMotion.determinateTrim(1) == 1)
    #expect(StartupSignalMotion.determinateTrim(1.5) == 1)
}

@Test func determinateTrimSurvivesNonFiniteInput() {
    #expect(StartupSignalMotion.determinateTrim(.nan) == 0)
    #expect(StartupSignalMotion.determinateTrim(.infinity) == 1)
}
```

The non-finite case matters because a download whose expected content length is zero produces `received / expected` as `nan` or `inf`, and `Path.trim` with a `nan` bound renders nothing at all rather than failing loudly.

- [ ] **Step 2: Run the test to verify it fails**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-signal test '-only-testing:TenXAppTests/determinateTrimClampsToTheUnitInterval()'
```

Expected: FAIL, `determinateTrim` does not exist.

- [ ] **Step 3: Add the clamp helper**

In `App/Startup/StartupSignalView.swift`, add to `enum StartupSignalMotion`:

```swift
    static func determinateTrim(_ progress: Double) -> CGFloat {
        guard progress.isFinite else { return progress.isNaN ? 0 : 1 }
        return CGFloat(min(max(progress, 0), 1))
    }
```

- [ ] **Step 4: Add the determinate mode to the view**

Replace the stored properties and the `body` of `StartupSignalView` with:

```swift
struct StartupSignalView: View {
    let isAnimating: Bool
    let isFailed: Bool
    var progress: Double?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.startupSignalReduceMotionOverride) private var reduceMotionOverride
    @State private var startDate = Date()
    @State private var frozenElapsed: TimeInterval = 0

    var body: some View {
        let reduceMotion = reduceMotionOverride ?? systemReduceMotion
        let isDeterminate = progress != nil
        let shouldAnimate = isAnimating && !reduceMotion && !isFailed && !isDeterminate

        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !shouldAnimate)) { context in
            let liveElapsed = context.date.timeIntervalSince(startDate)
            let elapsed = shouldAnimate ? liveElapsed : frozenElapsed
            let amplitude = StartupSignalMotion.amplitude(
                elapsed: reduceMotion ? 0 : elapsed,
                reduceMotion: reduceMotion)
            let travel = StartupSignalMotion.progress(
                elapsed: reduceMotion ? 0 : elapsed,
                reduceMotion: reduceMotion)

            ZStack {
                StartupSignalShape(amplitude: amplitude)
                    .stroke(
                        isFailed
                            ? TenXPalette.color(TenXPalette.signalRedHex)
                            : TenXPalette.color(TenXPalette.nearBlackHex),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                Group {
                    if let progress {
                        determinateFill(amplitude: amplitude, progress: progress)
                    } else {
                        travelingSegment(amplitude: amplitude, progress: travel)
                    }
                }
                .opacity(isFailed ? 0 : 1)
            }
            .animation(.easeOut(duration: 0.35), value: isFailed)
            .onChange(of: shouldAnimate, initial: true) { _, newValue in
                if reduceMotion {
                    startDate = context.date
                    frozenElapsed = 0
                } else if newValue {
                    startDate = context.date.addingTimeInterval(-frozenElapsed)
                }
            }
            .onChange(of: liveElapsed) { _, newValue in
                guard shouldAnimate else { return }
                frozenElapsed = newValue
            }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func determinateFill(amplitude: CGFloat, progress: Double) -> some View {
        StartupSignalShape(amplitude: amplitude)
            .trim(from: 0, to: StartupSignalMotion.determinateTrim(progress))
            .stroke(
                TenXPalette.color(TenXPalette.cyanHex),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .animation(.easeOut(duration: 0.25), value: progress)
    }
```

Leave `travelingSegment`, the environment key, and `StartupSignalShape` exactly as they are.

The determinate mode deliberately pauses the timeline. Reduce Motion suppresses the travelling segment and the breathing, but a determinate fill is information rather than motion, so it renders in both cases.

- [ ] **Step 5: Run the test to verify it passes**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-signal test '-only-testing:TenXAppTests/determinateTrimClampsToTheUnitInterval()' '-only-testing:TenXAppTests/determinateTrimSurvivesNonFiniteInput()'
```

Expected: PASS.

- [ ] **Step 6: Run the full suite**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-signal-full test 2>&1 | tail -20
```

Expected: baseline plus the new tests. The existing splash snapshots must still pass, because `progress` defaults to `nil`.

- [ ] **Step 7: Commit**

```bash
git add App/Startup/StartupSignalView.swift Tests/TenXAppTests/StartupSignalTests.swift && git commit -m "feat(startup): add determinate progress to the signal path"
```

---

### Task 6: Extract `SplashPresentation` and make `SplashView` pure

**Files:**
- Create: `App/Startup/SplashPresentation.swift`
- Modify: `App/Startup/StartupState.swift:39-46` (row type), `:76-94` (row and footer builders)
- Modify: `App/Startup/StartupLedgerView.swift:4`
- Modify: `App/Startup/SplashView.swift` (whole file)
- Modify: `App/Startup/StartupSceneView.swift:12-24`
- Test: `Tests/TenXAppTests/StartupStateTests.swift`, `Tests/TenXAppTests/StartupSplashSnapshotTests.swift`, `Tests/TenXAppTests/StartupSignalTests.swift`

Every construction of `SplashView` in the test suite changes signature. Find them all before starting: `grep -rn "SplashView(" App Tests`. At the time of writing there are three test call sites across two snapshot tests and one pixel-sampling test.

**Interfaces:**
- Consumes: Task 5's `StartupSignalView` signature.
- Produces:
  - `SplashLedgerRow(id: String, title: String, status: StartupStageStatus)` with `accessibilityLabel`.
  - `SplashPresentation(heading:accessibilityLabel:rows:isSignalAnimating:isSignalFailed:signalProgress:footerTitle:footerTone:footerDetail:actions:)`.
  - `SplashAction(id:title:kind:perform:)` with `kind` of `.primary` or `.secondary`.
  - `SplashPresentation.startup(state:onRetry:onContinue:) -> SplashPresentation`.
  - `SplashView(presentation:buildVersion:)`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/TenXAppTests/StartupStateTests.swift`:

```swift
@MainActor
@Test func startupPresentationCarriesTheLedgerAndFooterUnchanged() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markLoading(.runtime, attemptID: attempt)

    let presentation = SplashPresentation.startup(
        state: state, onRetry: {}, onContinue: {})

    #expect(presentation.heading == "Preparing your workspace")
    #expect(presentation.accessibilityLabel == "Preparing your workspace")
    #expect(presentation.footerTitle == "Preparing runtime")
    #expect(presentation.footerDetail == "Checking OMP and provider access")
    #expect(presentation.footerTone == .working)
    #expect(presentation.signalProgress == nil)
    #expect(presentation.isSignalAnimating)
    #expect(presentation.actions.isEmpty)
}

@MainActor
@Test func startupRecoveryPresentationOffersRetryThenContinue() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.enterRecovery(attemptID: attempt)

    let presentation = SplashPresentation.startup(
        state: state, onRetry: {}, onContinue: {})

    #expect(presentation.footerTitle == "Startup needs attention")
    #expect(presentation.footerTone == .failed)
    #expect(presentation.isSignalFailed)
    #expect(!presentation.isSignalAnimating)
    #expect(presentation.actions.map(\.title) == ["Retry", "Continue to workspace"])
    #expect(presentation.actions.map(\.kind) == [.primary, .secondary])
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-presentation test '-only-testing:TenXAppTests/startupPresentationCarriesTheLedgerAndFooterUnchanged()' 2>&1 | tail -20
```

Expected: FAIL with `cannot find 'SplashPresentation' in scope`.

- [ ] **Step 3: Create the presentation value**

Create `App/Startup/SplashPresentation.swift`:

```swift
import SwiftUI

struct SplashLedgerRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let status: StartupStageStatus

    var accessibilityLabel: String { "\(title), \(status.rawValue)" }
}

enum SplashFooterTone: Equatable, Sendable {
    case working
    case failed
}

struct SplashAction: Identifiable {
    enum Kind: Equatable, Sendable {
        case primary
        case secondary
    }

    let id: String
    let title: String
    let kind: Kind
    let perform: @MainActor () -> Void
}

struct SplashPresentation {
    let heading: String
    let accessibilityLabel: String
    let rows: [SplashLedgerRow]
    let isSignalAnimating: Bool
    let isSignalFailed: Bool
    let signalProgress: Double?
    let footerTitle: String
    let footerTone: SplashFooterTone
    let footerDetail: String
    let actions: [SplashAction]
}

extension SplashPresentation {
    @MainActor
    static func startup(
        state: StartupState,
        onRetry: @escaping @MainActor () -> Void,
        onContinue: @escaping @MainActor () -> Void
    ) -> SplashPresentation {
        let isRecovery = state.phase == .recovery
        return SplashPresentation(
            heading: "Preparing your workspace",
            accessibilityLabel: "Preparing your workspace",
            rows: state.rows,
            isSignalAnimating: state.isSignalAnimating,
            isSignalFailed: isRecovery,
            signalProgress: nil,
            footerTitle: state.footerTitle,
            footerTone: isRecovery ? .failed : .working,
            footerDetail: state.footerDetail,
            actions: isRecovery
                ? [
                    SplashAction(
                        id: "retry", title: "Retry", kind: .primary, perform: onRetry),
                    SplashAction(
                        id: "continue",
                        title: "Continue to workspace",
                        kind: .secondary,
                        perform: onContinue),
                ]
                : [])
    }
}
```

`SplashAction` is `Identifiable` but not `Equatable`, because it carries a closure. Tests compare `title` and `kind` rather than whole actions.

- [ ] **Step 4: Generalize the ledger row**

In `App/Startup/StartupState.swift`, delete the `StartupStageRow` struct entirely and change the `rows` computed property to:

```swift
    var rows: [SplashLedgerRow] {
        StartupStageID.allCases.map {
            SplashLedgerRow(
                id: $0.rawValue,
                title: $0.title,
                status: statuses[$0] ?? .queued)
        }
    }
```

In `App/Startup/StartupLedgerView.swift`, change the stored property to:

```swift
    let rows: [SplashLedgerRow]
```

Nothing else in that view changes; it already reads `title`, `status`, and `accessibilityLabel`.

- [ ] **Step 5: Rewrite `SplashView` as a pure view**

Replace the whole of `App/Startup/SplashView.swift` with:

```swift
import SwiftUI

struct SplashView: View {
    let presentation: SplashPresentation
    let buildVersion: String

    @Environment(\.accessibilityAnnouncer) private var announcer
    @FocusState private var isPrimaryFocused: Bool
    @AccessibilityFocusState private var isPrimaryAccessibilityFocused: Bool
    @State private var announcedRows: [SplashLedgerRow] = []

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(StartupState.buildLabel(version: buildVersion))
                        .font(TenXTypography.mono(size: 10, weight: .medium))
                        .tracking(1.3)
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    Text(presentation.heading)
                        .font(TenXTypography.title(size: 27))
                        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StartupLedgerView(rows: presentation.rows)
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 10)
            .frame(height: 248)

            StartupSignalView(
                isAnimating: presentation.isSignalAnimating,
                isFailed: presentation.isSignalFailed,
                progress: presentation.signalProgress)
                .frame(height: 48)

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
                .frame(height: 104)
        }
        .frame(width: 640, height: 400)
        .background(TenXPalette.color(TenXPalette.canvasHex))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TenXPalette.color(TenXPalette.separatorHex), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilityLabel)
        .onAppear {
            announcedRows = presentation.rows
            if !presentation.actions.isEmpty { focusPrimaryAction() }
        }
        .onChange(of: presentation.footerTone) { _, tone in
            guard tone == .failed else { return }
            focusPrimaryAction()
            announcer.announce("\(presentation.footerTitle). \(presentation.footerDetail)")
        }
        .onChange(of: presentation.rows) { _, rows in
            guard presentation.footerTone != .failed else {
                announcedRows = rows
                return
            }
            if let changed = rows.first(where: { row in
                announcedRows.first(where: { $0.id == row.id })?.status != row.status
            }) {
                announcer.announce(changed.accessibilityLabel)
            }
            announcedRows = rows
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(presentation.footerTitle)
                        .font(TenXTypography.mono(size: 10, weight: .semibold))
                        .foregroundStyle(footerTitleColor)
                    Text(presentation.footerDetail)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
                if !presentation.actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(presentation.actions) { action in
                            actionButton(action)
                        }
                    }
                }
            }
            Spacer(minLength: 24)
            BrandWordmark(width: 38)
        }
    }

    @ViewBuilder
    private func actionButton(_ action: SplashAction) -> some View {
        switch action.kind {
        case .primary:
            Button(action.title) { action.perform() }
                .font(TenXTypography.body(size: 12, weight: .medium))
                .buttonStyle(.bordered)
                .tint(TenXPalette.color(TenXPalette.interactiveCyanHex))
                .controlSize(.small)
                .focused($isPrimaryFocused)
                .accessibilityFocused($isPrimaryAccessibilityFocused)
        case .secondary:
            Button(action.title) { action.perform() }
                .buttonStyle(GhostActionStyle())
        }
    }

    private var footerTitleColor: Color {
        presentation.footerTone == .failed
            ? TenXPalette.color(TenXPalette.signalRedHex)
            : TenXPalette.color(TenXPalette.cyanHex)
    }

    private func focusPrimaryAction() {
        Task { @MainActor in
            await Task.yield()
            isPrimaryFocused = true
            isPrimaryAccessibilityFocused = true
        }
    }
}
```

- [ ] **Step 6: Update the scene view**

In `App/Startup/StartupSceneView.swift`, replace the `SplashView(...)` construction with:

```swift
        SplashView(
            presentation: SplashPresentation.startup(
                state: model.startupState,
                onRetry: { Task { await model.retryStartup() } },
                onContinue: { Task { await model.continueToWorkspace() } }),
            buildVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
```

Leave the `.task` and `.onChange` modifiers unchanged; Task 11 revisits them.

- [ ] **Step 7: Update the existing row assertion**

In `Tests/TenXAppTests/StartupStateTests.swift`, replace the row identity assertion inside `startupRowsUseTheApprovedOrderAndExactCopy` with:

```swift
    #expect(state.rows.map(\.id) == StartupStageID.allCases.map(\.rawValue))
```

Leave the title assertion exactly as it is.

- [ ] **Step 8: Update the existing snapshot tests**

In `Tests/TenXAppTests/StartupSplashSnapshotTests.swift`, replace both `SplashView(...)` constructions. For the loading snapshot:

```swift
        SplashView(
            presentation: SplashPresentation.startup(
                state: state, onRetry: {}, onContinue: {}),
            buildVersion: "0.1.0")
            .environment(\.startupSignalReduceMotionOverride, true),
```

Apply the identical change to the recovery snapshot. The rendered pixels must not change, so the existing reference images stay valid.

- [ ] **Step 9: Run the tests to verify they pass**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-presentation test '-only-testing:TenXAppTests/startupPresentationCarriesTheLedgerAndFooterUnchanged()' '-only-testing:TenXAppTests/startupRecoveryPresentationOffersRetryThenContinue()' '-only-testing:TenXAppTests/startupSplashLoadingSnapshot()' '-only-testing:TenXAppTests/startupSplashRecoverySnapshot()'
```

Expected: PASS, including both snapshots against the unchanged reference images. **If a snapshot fails, do not re-record it.** A pixel difference here means the refactor changed the rendering, which this task forbids. Diff the two `SplashView` versions and fix the regression.

- [ ] **Step 10: Run the full suite**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-presentation-full test 2>&1 | tail -20
```

Expected: baseline plus two.

- [ ] **Step 11: Commit**

```bash
git add App/Startup Tests/TenXAppTests/StartupStateTests.swift Tests/TenXAppTests/StartupSplashSnapshotTests.swift 10x.xcodeproj && git commit -m "refactor(startup): render the splash from a presentation value"
```

---

### Task 7: `UpdateState` and the update presentation

**Files:**
- Create: `App/Updates/UpdateState.swift`
- Create: `App/Updates/UpdatePresentation.swift`
- Test: `Tests/TenXAppTests/UpdateStateTests.swift` (create)

**Interfaces:**
- Consumes: `SplashLedgerRow`, `SplashPresentation`, `StartupStageStatus` from Task 6.
- Produces:
  - `UpdatePhase` with cases `idle`, `checking`, `upToDate(currentVersion:)`, `available(newVersion:currentVersion:)`, `downloading(receivedBytes:expectedBytes:)`, `verifying`, `installing(extractionFraction:)`, `relaunching`, `failed(UpdateFailure)`.
  - `UpdateFailure` with cases `verification`, `download`, `installation`, `unknown` and a `detail: String`.
  - `UpdateStepID` with cases `download`, `verify`, `install`, `relaunch`.
  - `UpdateState` with `phase`, `isPresentingUpdate`, `isAwaitingDecision`, `rows`, `signalProgress`, `heading`, `footerTitle`, `footerDetail`, `waitForCheckOutcome()`, `waitWhilePresenting()`, and the mutators `beginCheck`, `showAvailable`, `showUpToDate`, `beginDownload`, `setExpectedBytes`, `addReceivedBytes`, `beginVerifying`, `beginInstalling`, `setExtractionFraction`, `beginRelaunching`, `fail`, `reset`.
  - `SplashPresentation.update(state:onInstall:onDismiss:onRetry:) -> SplashPresentation`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TenXAppTests/UpdateStateTests.swift`:

```swift
import Foundation
import Testing
@testable import TenXApp

@MainActor
@Test func updateStateStartsIdleAndDoesNotPresent() {
    let state = UpdateState()

    #expect(state.phase == .idle)
    #expect(!state.isPresentingUpdate)
}

@MainActor
@Test func checkingDoesNotTakeOverTheSplash() {
    let state = UpdateState()
    state.beginCheck()

    #expect(state.phase == .checking)
    #expect(!state.isPresentingUpdate)
    #expect(state.footerTitle == "Checking for updates")
    #expect(state.footerDetail == "Looking for a newer version")
}

@MainActor
@Test func availableUpdateShowsBothVersionsAndAwaitsADecision() {
    let state = UpdateState()
    state.beginCheck()
    state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    #expect(state.isPresentingUpdate)
    #expect(state.isAwaitingDecision)
    #expect(state.heading == "Update available")
    #expect(state.footerTitle == "10x 0.2.0")
    #expect(state.footerDetail == "You have 0.1.0.")
    #expect(state.signalProgress == nil)
}

@MainActor
@Test func upToDateReportsTheCurrentVersion() {
    let state = UpdateState()
    state.beginCheck()
    state.showUpToDate(currentVersion: "0.1.0")

    #expect(state.heading == "No updates available")
    #expect(state.footerTitle == "10x 0.1.0")
    #expect(state.footerDetail == "This is the newest version.")
    #expect(!state.isAwaitingDecision)
}

@MainActor
@Test func downloadProgressOccupiesTheFirstFourFifthsOfTheSignal() {
    let state = UpdateState()
    state.beginDownload()
    state.setExpectedBytes(100)
    state.addReceivedBytes(50)

    #expect(state.signalProgress == 0.4)
    #expect(state.footerTitle == "Downloading update")
    #expect(state.footerDetail == "50 bytes of 100 bytes")
}

@MainActor
@Test func aCompletedDownloadMovesStraightToVerifying() {
    let state = UpdateState()
    state.beginDownload()
    state.setExpectedBytes(100)
    state.addReceivedBytes(100)

    #expect(state.phase == .verifying)
    #expect(state.signalProgress == 0.8)
    #expect(state.footerDetail == "Checking the signature")
}

@MainActor
@Test func anUnknownContentLengthNeverProducesNonFiniteProgress() {
    let state = UpdateState()
    state.beginDownload()
    state.addReceivedBytes(4_096)

    let progress = try? #require(state.signalProgress)
    #expect(progress == 0)
    #expect(state.footerDetail == "4 KB")
}

@MainActor
@Test func installProgressOccupiesTheFinalFifthOfTheSignal() {
    let state = UpdateState()
    state.beginInstalling()

    #expect(state.signalProgress == 0.85)

    state.setExtractionFraction(1)

    #expect(state.signalProgress == 1)
    #expect(state.footerDetail == "Replacing the application")
}

@MainActor
@Test func stepsResolveInOrderAsThePhaseAdvances() {
    let state = UpdateState()
    state.beginDownload()

    #expect(state.rows.map(\.title) == [
        "Downloading update",
        "Verifying download",
        "Installing update",
        "Relaunching 10x",
    ])
    #expect(state.rows.map(\.status) == [.loading, .queued, .queued, .queued])

    state.beginVerifying()

    #expect(state.rows.map(\.status) == [.ready, .loading, .queued, .queued])

    state.beginInstalling()

    #expect(state.rows.map(\.status) == [.ready, .ready, .loading, .queued])

    state.beginRelaunching()

    #expect(state.rows.map(\.status) == [.ready, .ready, .ready, .loading])
}

@MainActor
@Test func failureStopsTheStepThatWasRunningAndKeepsEarlierStepsReady() {
    let state = UpdateState()
    state.beginDownload()
    state.beginVerifying()
    state.fail(.verification)

    #expect(state.rows.map(\.status) == [.ready, .stopped, .queued, .queued])
    #expect(state.footerTitle == "Update failed")
    #expect(state.footerDetail == "The download could not be verified.")
    #expect(state.signalProgress == nil)
}

@MainActor
@Test func everyFailureHasFixedCopyWithNoFrameworkDetail() {
    #expect(UpdateFailure.verification.detail == "The download could not be verified.")
    #expect(UpdateFailure.download.detail == "The download did not finish. Check your connection.")
    #expect(UpdateFailure.installation.detail == "The update could not be installed.")
    #expect(UpdateFailure.unknown.detail == "The update could not be completed.")
}

@MainActor
@Test func waitingForACheckOutcomeResumesWhenTheCheckResolves() async {
    let state = UpdateState()
    state.beginCheck()

    async let wait: Void = state.waitForCheckOutcome()
    state.showUpToDate(currentVersion: "0.1.0")
    await wait

    #expect(!state.isAwaitingDecision)
}

@MainActor
@Test func waitingForACheckOutcomeReturnsImmediatelyWhenNotChecking() async {
    let state = UpdateState()

    await state.waitForCheckOutcome()

    #expect(state.phase == .idle)
}

@MainActor
@Test func waitingWhilePresentingResumesOnceTheOfferIsDeclined() async {
    let state = UpdateState()
    state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    async let wait: Void = state.waitWhilePresenting()
    state.reset()
    await wait

    #expect(state.phase == .idle)
}

@MainActor
@Test func waitingWhilePresentingSpansAFailedUpdateUntilItIsDismissed() async {
    let state = UpdateState()
    state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    async let wait: Void = state.waitWhilePresenting()
    state.beginDownload()
    await Task.yield()

    #expect(state.isPresentingUpdate)

    state.fail(.download)
    await Task.yield()

    #expect(state.isPresentingUpdate)

    state.reset()
    await wait

    #expect(state.phase == .idle)
}

@MainActor
@Test func waitingWhilePresentingReturnsImmediatelyWhenNothingIsShown() async {
    let state = UpdateState()

    await state.waitWhilePresenting()

    #expect(state.phase == .idle)
}

@MainActor
@Test func updatePresentationOffersInstallThenNotNow() {
    let state = UpdateState()
    state.beginCheck()
    state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    let presentation = SplashPresentation.update(
        state: state, onInstall: {}, onDismiss: {}, onRetry: {})

    #expect(presentation.heading == "Update available")
    #expect(presentation.actions.map(\.title) == ["Install and Relaunch", "Not now"])
    #expect(presentation.actions.map(\.kind) == [.primary, .secondary])
    #expect(presentation.footerTone == .working)
    #expect(!presentation.isSignalAnimating)
}

@MainActor
@Test func failedPresentationOffersTryAgainThenNotNow() {
    let state = UpdateState()
    state.beginDownload()
    state.fail(.download)

    let presentation = SplashPresentation.update(
        state: state, onInstall: {}, onDismiss: {}, onRetry: {})

    #expect(presentation.heading == "Installing update")
    #expect(presentation.footerTone == .failed)
    #expect(presentation.isSignalFailed)
    #expect(presentation.actions.map(\.title) == ["Try again", "Not now"])
}

@MainActor
@Test func inFlightPresentationOffersNoActions() {
    let state = UpdateState()
    state.beginDownload()

    let presentation = SplashPresentation.update(
        state: state, onInstall: {}, onDismiss: {}, onRetry: {})

    #expect(presentation.actions.isEmpty)
    #expect(presentation.heading == "Installing update")
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
mkdir -p App/Updates && ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-updatestate test '-only-testing:TenXAppTests/updateStateStartsIdleAndDoesNotPresent()' 2>&1 | tail -20
```

Expected: FAIL with `cannot find 'UpdateState' in scope`.

- [ ] **Step 3: Write `UpdateState`**

Create `App/Updates/UpdateState.swift`:

```swift
import Foundation
import Observation

enum UpdateFailure: Equatable, Sendable {
    case verification
    case download
    case installation
    case unknown

    var detail: String {
        switch self {
        case .verification: "The download could not be verified."
        case .download: "The download did not finish. Check your connection."
        case .installation: "The update could not be installed."
        case .unknown: "The update could not be completed."
        }
    }
}

enum UpdatePhase: Equatable, Sendable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case available(newVersion: String, currentVersion: String)
    case downloading(receivedBytes: UInt64, expectedBytes: UInt64)
    case verifying
    case installing(extractionFraction: Double)
    case relaunching
    case failed(UpdateFailure)
}

enum UpdateStepID: String, CaseIterable, Sendable {
    case download
    case verify
    case install
    case relaunch

    var title: String {
        switch self {
        case .download: "Downloading update"
        case .verify: "Verifying download"
        case .install: "Installing update"
        case .relaunch: "Relaunching 10x"
        }
    }
}

@MainActor
@Observable
final class UpdateState {
    private(set) var phase: UpdatePhase = .idle
    @ObservationIgnored private var lastActiveIndex: Int?
    @ObservationIgnored private var phaseWaiters: [CheckedContinuation<Void, Never>] = []

    var isPresentingUpdate: Bool {
        switch phase {
        case .idle, .checking: false
        default: true
        }
    }

    var isAwaitingDecision: Bool {
        if case .available = phase { return true }
        return false
    }

    var heading: String {
        switch phase {
        case .available: "Update available"
        case .upToDate: "No updates available"
        default: "Installing update"
        }
    }

    var footerTitle: String {
        switch phase {
        case .idle, .checking: "Checking for updates"
        case .upToDate(let current): "10x \(current)"
        case .available(let new, _): "10x \(new)"
        case .downloading: UpdateStepID.download.title
        case .verifying: UpdateStepID.verify.title
        case .installing: UpdateStepID.install.title
        case .relaunching: UpdateStepID.relaunch.title
        case .failed: "Update failed"
        }
    }

    var footerDetail: String {
        switch phase {
        case .idle, .checking: "Looking for a newer version"
        case .upToDate: "This is the newest version."
        case .available(_, let current): "You have \(current)."
        case .downloading(let received, let expected):
            Self.byteProgress(received: received, expected: expected)
        case .verifying: "Checking the signature"
        case .installing: "Replacing the application"
        case .relaunching: "Reopening with the new version"
        case .failed(let failure): failure.detail
        }
    }

    var signalProgress: Double? {
        // Every case returns explicitly. A switch in a computed property only gets
        // implicit-return treatment when EVERY case is a single bare expression, and
        // the guard in `.downloading` demotes the whole switch to a statement.
        switch phase {
        case .downloading(let received, let expected):
            guard expected > 0 else { return 0 }
            return 0.8 * min(1, Double(received) / Double(expected))
        case .verifying: return 0.8
        case .installing(let fraction): return 0.85 + 0.15 * min(max(fraction, 0), 1)
        case .relaunching: return 1
        default: return nil
        }
    }

    var rows: [SplashLedgerRow] {
        UpdateStepID.allCases.enumerated().map { index, step in
            SplashLedgerRow(id: step.rawValue, title: step.title, status: status(at: index))
        }
    }

    static func byteProgress(received: UInt64, expected: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let receivedText = formatter.string(fromByteCount: Int64(clamping: received))
        guard expected > 0 else { return receivedText }
        return "\(receivedText) of \(formatter.string(fromByteCount: Int64(clamping: expected)))"
    }

    func beginCheck() {
        lastActiveIndex = nil
        setPhase(.checking)
    }

    func showAvailable(newVersion: String, currentVersion: String) {
        setPhase(.available(newVersion: newVersion, currentVersion: currentVersion))
    }

    func showUpToDate(currentVersion: String) {
        setPhase(.upToDate(currentVersion: currentVersion))
    }

    func beginDownload() {
        lastActiveIndex = 0
        setPhase(.downloading(receivedBytes: 0, expectedBytes: 0))
    }

    func setExpectedBytes(_ bytes: UInt64) {
        guard case .downloading(let received, _) = phase else { return }
        setPhase(.downloading(receivedBytes: received, expectedBytes: bytes))
    }

    func addReceivedBytes(_ bytes: UInt64) {
        guard case .downloading(let received, let expected) = phase else { return }
        let total = received &+ bytes
        if expected > 0, total >= expected {
            beginVerifying()
        } else {
            setPhase(.downloading(receivedBytes: total, expectedBytes: expected))
        }
    }

    func beginVerifying() {
        lastActiveIndex = 1
        setPhase(.verifying)
    }

    func beginInstalling() {
        lastActiveIndex = 2
        setPhase(.installing(extractionFraction: 0))
    }

    func setExtractionFraction(_ fraction: Double) {
        guard case .installing = phase else { return }
        setPhase(.installing(extractionFraction: fraction.isFinite ? fraction : 0))
    }

    func beginRelaunching() {
        lastActiveIndex = 3
        setPhase(.relaunching)
    }

    func fail(_ failure: UpdateFailure) {
        setPhase(.failed(failure))
    }

    func reset() {
        lastActiveIndex = nil
        setPhase(.idle)
    }

    /// Resolves as soon as an in-flight check produces any outcome. Returns immediately
    /// when no check is running, so the launch gate can await it unconditionally.
    func waitForCheckOutcome() async {
        while case .checking = phase { await nextPhaseChange() }
    }

    /// Resolves once the splash has no update content left to show. Returns immediately
    /// when nothing is presented, so the handoff gate can await it unconditionally.
    ///
    /// This is a loop rather than a single wait because an update can move through
    /// several presented phases before it is finished with the window: offered,
    /// downloading, failed, then dismissed. Handoff must wait for the end of that
    /// sequence, not the end of the first step, or a failed update strands the splash
    /// with no workspace and no recovery.
    func waitWhilePresenting() async {
        while isPresentingUpdate { await nextPhaseChange() }
    }

    private func setPhase(_ newPhase: UpdatePhase) {
        phase = newPhase
        let waiters = phaseWaiters
        phaseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func nextPhaseChange() async {
        await withCheckedContinuation { phaseWaiters.append($0) }
    }

    private var activeIndex: Int? {
        switch phase {
        case .downloading: 0
        case .verifying: 1
        case .installing: 2
        case .relaunching: 3
        default: nil
        }
    }

    private func status(at index: Int) -> StartupStageStatus {
        if case .failed = phase {
            guard let failedIndex = lastActiveIndex else { return .queued }
            if index < failedIndex { return .ready }
            return index == failedIndex ? .stopped : .queued
        }
        guard let active = activeIndex else { return .queued }
        if index < active { return .ready }
        return index == active ? .loading : .queued
    }
}
```

`lastActiveIndex` and `phaseWaiters` are marked `@ObservationIgnored` because they are bookkeeping, not rendered state. Observing them would invalidate views for no visible change.

- [ ] **Step 4: Write the update presentation**

Create `App/Updates/UpdatePresentation.swift`:

```swift
import SwiftUI

extension SplashPresentation {
    @MainActor
    static func update(
        state: UpdateState,
        onInstall: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void,
        onRetry: @escaping @MainActor () -> Void
    ) -> SplashPresentation {
        var isFailed = false
        if case .failed = state.phase { isFailed = true }

        let actions: [SplashAction]
        switch state.phase {
        case .available:
            actions = [
                SplashAction(
                    id: "install",
                    title: "Install and Relaunch",
                    kind: .primary,
                    perform: onInstall),
                SplashAction(
                    id: "dismiss", title: "Not now", kind: .secondary, perform: onDismiss),
            ]
        case .failed:
            actions = [
                SplashAction(id: "retry", title: "Try again", kind: .primary, perform: onRetry),
                SplashAction(
                    id: "dismiss", title: "Not now", kind: .secondary, perform: onDismiss),
            ]
        case .upToDate:
            actions = [
                SplashAction(id: "close", title: "Close", kind: .primary, perform: onDismiss),
            ]
        default:
            actions = []
        }

        return SplashPresentation(
            heading: state.heading,
            accessibilityLabel: state.heading,
            rows: state.rows,
            isSignalAnimating: false,
            isSignalFailed: isFailed,
            signalProgress: state.signalProgress,
            footerTitle: state.footerTitle,
            footerTone: isFailed ? .failed : .working,
            footerDetail: state.footerDetail,
            actions: actions)
    }
}
```

`isSignalAnimating` is always `false` in update mode. The path is either determinate or, at the offer and failure states, static.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-updatestate test '-only-testing:TenXAppTests/UpdateStateTests' 2>&1 | tail -25
```

Since these are top-level `@Test func` declarations rather than a suite, list them individually with parentheses if the suite-style filter matches nothing. Confirm the run reports a nonzero test count; a zero-count run that reports success means the filter did not match.

Expected: all nineteen pass.

- [ ] **Step 6: Run the full suite**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-updatestate-full test 2>&1 | tail -20
```

- [ ] **Step 7: Commit**

```bash
git add App/Updates Tests/TenXAppTests/UpdateStateTests.swift 10x.xcodeproj && git commit -m "feat(updates): model the update lifecycle and its splash presentation"
```

---

### Task 8: `SplashUpdateDriver`

**Files:**
- Create: `App/Updates/SplashUpdateDriver.swift`
- Test: `Tests/TenXAppTests/SplashUpdateDriverTests.swift` (create)

**Interfaces:**
- Consumes: `UpdateState` from Task 7, `Sparkle` from Task 3.
- Produces: `SplashUpdateDriver(state:currentVersion:prepareForInstall:)` conforming to `SPUUserDriver`, plus `isUserInitiated`, `acceptUpdate()`, `dismissUpdate()`, `cancelCheck()`, and `static func failure(for:) -> UpdateFailure`.

- [ ] **Step 1: Confirm the protocol's isolation and the error case names**

Before writing anything, read the resolved Sparkle module. Two things must be checked, not assumed:

```bash
find ~/Library/Developer/Xcode/DerivedData /private/tmp/tenx-sparkle -name "SPUUserDriver.h" 2>/dev/null | head -1 | xargs grep -n "MAIN_ACTOR\|UI_ACTOR\|@protocol" | head
find ~/Library/Developer/Xcode/DerivedData /private/tmp/tenx-sparkle -name "SUErrors.h" 2>/dev/null | head -1 | xargs grep -n "= 40\|Error =" | head -30
```

- If `SPUUserDriver` carries `NS_SWIFT_UI_ACTOR`, a `@MainActor` class conforms directly. Use the code in Step 3 as written.
- If it does not, the conformance will not compile under `SWIFT_STRICT_CONCURRENCY = complete`. Declare the class `nonisolated` and wrap each method body in `MainActor.assumeIsolated { … }`. Sparkle documents that user driver methods are delivered on the main thread, so the assumption holds. Do not silence the error by weakening a type.
- The `SUError` case names in Step 3 are the ones to verify against `SUErrors.h`. If a name differs, use the real one. Do not guess and do not fall back to a raw integer literal.

Record which branch was taken in the commit message body.

- [ ] **Step 2: Write the failing test**

Create `Tests/TenXAppTests/SplashUpdateDriverTests.swift`:

```swift
import Foundation
import Sparkle
import Testing
@testable import TenXApp

@MainActor
private func makeDriver(
    _ state: UpdateState,
    prepareForInstall: @escaping @MainActor () async -> Void = {}
) -> SplashUpdateDriver {
    SplashUpdateDriver(
        state: state, currentVersion: "0.1.0", prepareForInstall: prepareForInstall)
}

@MainActor
@Test func aUserInitiatedCheckEntersTheCheckingPhase() {
    let state = UpdateState()
    let driver = makeDriver(state)

    driver.showUserInitiatedUpdateCheck(cancellation: {})

    #expect(state.phase == .checking)
}

@MainActor
@Test func downloadCallbacksAccumulateIntoDownloadProgress() {
    let state = UpdateState()
    let driver = makeDriver(state)

    driver.showDownloadInitiated(cancellation: {})
    driver.showDownloadDidReceiveExpectedContentLength(200)
    driver.showDownloadDidReceiveData(ofLength: 50)

    #expect(state.phase == .downloading(receivedBytes: 50, expectedBytes: 200))
}

@MainActor
@Test func extractionCallbacksDriveTheInstallStep() {
    let state = UpdateState()
    let driver = makeDriver(state)

    driver.showDownloadInitiated(cancellation: {})
    driver.showDownloadDidStartExtractingUpdate()
    driver.showExtractionReceivedProgress(0.5)

    #expect(state.phase == .installing(extractionFraction: 0.5))
}

@MainActor
@Test func installingCallbackEntersRelaunching() {
    let state = UpdateState()
    let driver = makeDriver(state)

    driver.showInstallingUpdate(
        withApplicationTerminated: false, retryTerminatingApplication: {})

    #expect(state.phase == .relaunching)
}

@MainActor
@Test func dismissingAnInstallationReturnsToIdle() {
    let state = UpdateState()
    let driver = makeDriver(state)
    driver.showDownloadInitiated(cancellation: {})

    driver.dismissUpdateInstallation()

    #expect(state.phase == .idle)
}

@MainActor
@Test func consentingToInstallShutsTheRuntimeDownFirst() async {
    let state = UpdateState()
    let didPrepare = Preparation()
    let driver = makeDriver(state, prepareForInstall: { await didPrepare.record() })

    let choice = await driver.showReadyToInstallAndRelaunch()

    #expect(choice == .install)
    #expect(await didPrepare.count == 1)
}

@MainActor
@Test func aMenuCheckThatFindsNothingReportsUpToDate() async {
    let state = UpdateState()
    let driver = makeDriver(state)
    driver.isUserInitiated = true
    state.beginCheck()

    await driver.showUpdateNotFoundWithError(SplashUpdateDriverTestError.none)

    #expect(state.phase == .upToDate(currentVersion: "0.1.0"))
}

@MainActor
@Test func aLaunchCheckThatFindsNothingStaysSilent() async {
    let state = UpdateState()
    let driver = makeDriver(state)
    driver.isUserInitiated = false
    state.beginCheck()

    await driver.showUpdateNotFoundWithError(SplashUpdateDriverTestError.none)

    #expect(state.phase == .idle)
    #expect(!state.isPresentingUpdate)
}

@MainActor
@Test func splashButtonsResolveThePendingSparkleDecision() async {
    let state = UpdateState()
    let driver = makeDriver(state)

    async let choice = driver.awaitDecisionForTesting()
    while !driver.hasPendingDecisionForTesting { await Task.yield() }
    driver.acceptUpdate()

    #expect(await choice == .install)
}

@MainActor
@Test func notNowDismissesRatherThanSkippingTheVersionPermanently() async {
    let state = UpdateState()
    let driver = makeDriver(state)

    async let choice = driver.awaitDecisionForTesting()
    while !driver.hasPendingDecisionForTesting { await Task.yield() }
    driver.dismissUpdate()

    #expect(await choice == .dismiss)
}

@MainActor
@Test func aLaunchCheckThatErrorsNeverPaintsAFailureOnTheSplash() async {
    let state = UpdateState()
    let driver = makeDriver(state)
    driver.isUserInitiated = false
    state.beginCheck()

    await driver.showUpdaterError(SplashUpdateDriverTestError.none)

    #expect(state.phase == .idle)
    #expect(!state.isPresentingUpdate)
}

@MainActor
@Test func anErrorDuringAnInFlightUpdateIsShownToTheUser() async {
    let state = UpdateState()
    let driver = makeDriver(state)
    driver.isUserInitiated = false
    driver.showDownloadInitiated(cancellation: {})

    await driver.showUpdaterError(SplashUpdateDriverTestError.none)

    #expect(state.phase == .failed(.unknown))
    #expect(state.isPresentingUpdate)
}

@MainActor
@Test func cancellingACheckInvokesSparklesOwnHandlerAndClearsTheState() async {
    let state = UpdateState()
    let driver = makeDriver(state)
    let cancelled = Preparation()
    driver.showUserInitiatedUpdateCheck(cancellation: {
        Task { await cancelled.record() }
    })

    async let choice = driver.awaitDecisionForTesting()
    while !driver.hasPendingDecisionForTesting { await Task.yield() }
    driver.cancelCheck()

    #expect(await choice == .dismiss)
    #expect(state.phase == .idle)
    await Task.yield()
    #expect(await cancelled.count == 1)
}

@MainActor
@Test func sparkleErrorsMapToFixedUserFacingFailures() {
    let unrelated = NSError(domain: "com.example.other", code: 1)

    #expect(SplashUpdateDriver.failure(for: unrelated) == .unknown)
}

actor Preparation {
    private(set) var count = 0
    func record() { count += 1 }
}

enum SplashUpdateDriverTestError: Error {
    case none
}
```

`notNowDismissesRatherThanSkippingTheVersionPermanently` exists because `.skip` and `.dismiss` look interchangeable and are not. `.skip` makes Sparkle never offer that version again, which would silently strand a user on an old build.

The three tests that start an `async let` awaiter and then call `acceptUpdate()`, `dismissUpdate()`, or `cancelCheck()` in the same scope loop on `driver.hasPendingDecisionForTesting` before triggering. This is not cosmetic: on a serial `@MainActor` executor the `async let` child task cannot preempt the parent's next synchronous line, so the trigger would otherwise always fire before `awaitDecision()` has registered its continuation, resolving nothing and hanging the test forever. The loop makes registration a precondition instead of a hope; if a real bug ever stops the continuation from registering, the test still hangs — same failure mode as an un-guarded race, which is acceptable, since a passing-by-luck ordering is not. `hasPendingDecisionForTesting` is a read-only test hook (`decision != nil`); nothing in the driver's production code reads it.

- [ ] **Step 3: Write the driver**

Create `App/Updates/SplashUpdateDriver.swift`:

```swift
import Foundation
import Sparkle

@MainActor
final class SplashUpdateDriver: NSObject, SPUUserDriver {
    /// Set before each check. Controls whether an up-to-date result is shown or stays silent.
    var isUserInitiated = false

    private let state: UpdateState
    private let currentVersion: String
    private let prepareForInstall: @MainActor () async -> Void
    private var decision: CheckedContinuation<SPUUserUpdateChoice, Never>?
    private var checkCancellation: (() -> Void)?

    /// Guards `showDownloadDidReceiveExpectedContentLength` against Sparkle invoking it
    /// more than once for the same download (for example across a redirect). Only the
    /// first value is applied; see that method for why.
    private var hasReceivedExpectedContentLength = false

    init(
        state: UpdateState,
        currentVersion: String,
        prepareForInstall: @escaping @MainActor () async -> Void
    ) {
        self.state = state
        self.currentVersion = currentVersion
        self.prepareForInstall = prepareForInstall
        super.init()
    }

    // MARK: Splash actions

    func acceptUpdate() { resume(.install) }

    /// `Not now` dismisses this check. It deliberately does not use `.skip`, which
    /// would make Sparkle refuse to offer this version ever again.
    func dismissUpdate() { resume(.dismiss) }

    // MARK: SPUUserDriver

    func show(
        _ request: SPUUpdatePermissionRequest
    ) async -> SUUpdatePermissionResponse {
        SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        checkCancellation = cancellation
        state.beginCheck()
    }

    /// Called when the launch gate gives up at its deadline. Cancelling through Sparkle's
    /// own handler is what prevents a late `showUpdateFound` from stranding a decision
    /// continuation with no window left to resolve it.
    func cancelCheck() {
        let cancellation = checkCancellation
        checkCancellation = nil
        cancellation?()
        resume(.dismiss)
        state.reset()
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state updateState: SPUUserUpdateState
    ) async -> SPUUserUpdateChoice {
        checkCancellation = nil
        state.showAvailable(
            newVersion: appcastItem.displayVersionString,
            currentVersion: currentVersion)
        return await awaitDecision()
    }

    func showUpdateNotFoundWithError(_ error: any Error) async {
        checkCancellation = nil
        if isUserInitiated {
            state.showUpToDate(currentVersion: currentVersion)
        } else {
            state.reset()
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        hasReceivedExpectedContentLength = false
        state.beginDownload()
    }

    /// Sparkle's header for this method notes it "may be called more than once for the
    /// same download in rare scenarios" (e.g. a redirect). `UpdateState.setExpectedBytes`
    /// overwrites the expected total unconditionally, so a later, larger value would make
    /// the progress fraction jump backward for bytes already received. Only the first
    /// value seen for a given download is applied; later calls are ignored.
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        guard !hasReceivedExpectedContentLength else { return }
        hasReceivedExpectedContentLength = true
        state.setExpectedBytes(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        state.addReceivedBytes(length)
    }

    func showDownloadDidStartExtractingUpdate() {
        state.beginInstalling()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        state.setExtractionFraction(progress)
    }

    /// The user already consented at the offer. Prompting again would be a second gate
    /// on a decision they have made, so this returns `.install` after the runtime is torn
    /// down. Awaiting `prepareForInstall` is what guarantees no OMP child survives.
    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        await prepareForInstall()
        return .install
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        state.beginRelaunching()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
        state.reset()
    }

    /// A launch check that errors before it produced anything must say nothing at all.
    /// Painting `Update failed` across a cold launch because DNS was slow is exactly the
    /// failure surface the advisory rules exist to prevent. Once the user has asked for
    /// an update, or once one is in flight, the failure is theirs to see.
    func showUpdaterError(_ error: any Error) async {
        resume(.dismiss)
        checkCancellation = nil
        if !isUserInitiated, case .checking = state.phase {
            state.reset()
        } else {
            state.fail(Self.failure(for: error))
        }
    }

    func dismissUpdateInstallation() {
        resume(.dismiss)
        state.reset()
    }

    // MARK: Failure mapping

    static func failure(for error: any Error) -> UpdateFailure {
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain else { return .unknown }
        switch nsError.code {
        case Int(SUError.signatureError.rawValue):
            return .verification
        case Int(SUError.downloadError.rawValue),
             Int(SUError.temporaryDirectoryError.rawValue):
            return .download
        case Int(SUError.installationError.rawValue),
             Int(SUError.relaunchError.rawValue):
            return .installation
        default:
            return .unknown
        }
    }

    // MARK: Decision plumbing

    func awaitDecisionForTesting() async -> SPUUserUpdateChoice {
        await awaitDecision()
    }

    /// Read-only test hook: true once `awaitDecision()`'s continuation is registered.
    /// Production code never reads this. Tests that trigger a decision via `acceptUpdate()`,
    /// `dismissUpdate()`, or `cancelCheck()` after starting an `async let` awaiter poll this
    /// instead of assuming the child task has already registered — on a serial actor it has
    /// not necessarily done so yet, so triggering too early would resolve nothing.
    var hasPendingDecisionForTesting: Bool { decision != nil }

    private func awaitDecision() async -> SPUUserUpdateChoice {
        await withCheckedContinuation { continuation in
            decision?.resume(returning: .dismiss)
            decision = continuation
        }
    }

    private func resume(_ choice: SPUUserUpdateChoice) {
        guard let decision else { return }
        self.decision = nil
        decision.resume(returning: choice)
    }
}
```

`showUpdaterError` and `dismissUpdateInstallation` both call `resume(.dismiss)` first. A pending continuation that is never resumed leaks the task forever, and Sparkle can reach either method while an offer is still on screen.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-driver test '-only-testing:TenXAppTests/aUserInitiatedCheckEntersTheCheckingPhase()' '-only-testing:TenXAppTests/downloadCallbacksAccumulateIntoDownloadProgress()' '-only-testing:TenXAppTests/extractionCallbacksDriveTheInstallStep()' '-only-testing:TenXAppTests/installingCallbackEntersRelaunching()' '-only-testing:TenXAppTests/dismissingAnInstallationReturnsToIdle()' '-only-testing:TenXAppTests/consentingToInstallShutsTheRuntimeDownFirst()' '-only-testing:TenXAppTests/aMenuCheckThatFindsNothingReportsUpToDate()' '-only-testing:TenXAppTests/aLaunchCheckThatFindsNothingStaysSilent()' '-only-testing:TenXAppTests/splashButtonsResolveThePendingSparkleDecision()' '-only-testing:TenXAppTests/notNowDismissesRatherThanSkippingTheVersionPermanently()' '-only-testing:TenXAppTests/aLaunchCheckThatErrorsNeverPaintsAFailureOnTheSplash()' '-only-testing:TenXAppTests/anErrorDuringAnInFlightUpdateIsShownToTheUser()' '-only-testing:TenXAppTests/cancellingACheckInvokesSparklesOwnHandlerAndClearsTheState()' '-only-testing:TenXAppTests/sparkleErrorsMapToFixedUserFacingFailures()'
```

Expected: all fourteen pass.

- [ ] **Step 5: Run the full suite**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-driver-full test 2>&1 | tail -20
```

- [ ] **Step 6: Commit**

```bash
git add App/Updates/SplashUpdateDriver.swift Tests/TenXAppTests/SplashUpdateDriverTests.swift 10x.xcodeproj && git commit -m "feat(updates): drive Sparkle through the splash instead of its own interface"
```

---

### Task 9: `UpdateController`

**Files:**
- Create: `App/Updates/UpdateController.swift`
- Test: `Tests/TenXAppTests/UpdateControllerTests.swift` (create)

**Interfaces:**
- Consumes: `SplashUpdateDriver`, `UpdateState`.
- Produces: `UpdateChecking` protocol with `state: UpdateState`, `check(isUserInitiated:)`, `cancelCheck()`, `accept()`, `dismiss()`, and the `checkAtLaunch(deadline:sleep:)` extension. `UpdateController` is the live conformance; `AppModel` depends on the protocol so tests never construct an `SPUUpdater`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TenXAppTests/UpdateControllerTests.swift`:

```swift
import Foundation
import Testing
@testable import TenXApp

@MainActor
final class StubUpdateChecker: UpdateChecking {
    let state = UpdateState()
    private(set) var checkCount = 0
    private(set) var lastCheckWasUserInitiated: Bool?
    var onCheck: (@MainActor (UpdateState) -> Void)?

    private(set) var cancelCount = 0

    func check(isUserInitiated: Bool) {
        checkCount += 1
        lastCheckWasUserInitiated = isUserInitiated
        state.beginCheck()
        onCheck?(state)
    }

    func cancelCheck() {
        cancelCount += 1
        state.reset()
    }

    func accept() {}
    func dismiss() { state.reset() }
}

@MainActor
@Test func theLaunchCheckReturnsAsSoonAsSparkleAnswers() async {
    let checker = StubUpdateChecker()
    checker.onCheck = { $0.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0") }

    await checker.checkAtLaunch(deadline: .seconds(3), sleep: { _ in
        Issue.record("The deadline must not be awaited once the check has answered")
    })

    #expect(checker.checkCount == 1)
    #expect(checker.lastCheckWasUserInitiated == false)
    #expect(checker.cancelCount == 0)
    #expect(checker.state.isAwaitingDecision)
}

@MainActor
@Test func theLaunchCheckGivesUpAtTheDeadlineWithoutFailing() async {
    let checker = StubUpdateChecker()

    await checker.checkAtLaunch(deadline: .milliseconds(1), sleep: { _ in })

    #expect(checker.cancelCount == 1)
    #expect(checker.state.phase == .idle)
    #expect(!checker.state.isPresentingUpdate)
}
```

The second test is the safety property in miniature: a check that never answers must leave the launch free to proceed, and must not produce a failure surface.

- [ ] **Step 2: Run the test to verify it fails**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-controller test '-only-testing:TenXAppTests/theLaunchCheckReturnsAsSoonAsSparkleAnswers()' 2>&1 | tail -20
```

Expected: FAIL with `cannot find type 'UpdateChecking' in scope`.

- [ ] **Step 3: Write the protocol, the launch gate, and the live controller**

Create `App/Updates/UpdateController.swift`:

```swift
import Foundation
import Sparkle

@MainActor
protocol UpdateChecking: AnyObject {
    var state: UpdateState { get }
    func check(isUserInitiated: Bool)
    func cancelCheck()
    func accept()
    func dismiss()
}

extension UpdateChecking {
    /// Runs the advisory launch check. Returns when the check answers or when `deadline`
    /// elapses, whichever comes first. It never throws, never fails, and never reports a
    /// problem to the user, because a launch must not depend on network health.
    ///
    /// A check that misses the deadline is cancelled rather than left running. An
    /// abandoned check that answered later would strand a decision continuation with no
    /// window left to resolve it.
    func checkAtLaunch(
        deadline: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) async {
        check(isUserInitiated: false)
        let didAnswer = await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor [state] in
                await state.waitForCheckOutcome()
                return true
            }
            group.addTask {
                try? await sleep(deadline)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        if !didAnswer { cancelCheck() }
    }
}

@MainActor
final class UpdateController: UpdateChecking {
    let state: UpdateState
    private let updater: SPUUpdater
    private let driver: SplashUpdateDriver

    init(
        state: UpdateState = UpdateState(),
        currentVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        prepareForInstall: @escaping @MainActor () async -> Void
    ) {
        self.state = state
        let driver = SplashUpdateDriver(
            state: state,
            currentVersion: currentVersion,
            prepareForInstall: prepareForInstall)
        self.driver = driver
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: driver,
            delegate: nil)
    }

    /// Must be called once before any check. A failure here means the bundle is missing
    /// its feed or key, which is a build defect rather than a user-facing condition.
    func start() {
        do {
            try updater.start()
        } catch {
            state.fail(.unknown)
        }
    }

    /// Both paths use `checkForUpdates()` rather than `checkForUpdatesInBackground()`.
    /// The background variant is governed by Sparkle's own scheduling permission, which
    /// `SUEnableAutomaticChecks = NO` disables, so it would silently do nothing.
    func check(isUserInitiated: Bool) {
        driver.isUserInitiated = isUserInitiated
        updater.checkForUpdates()
    }

    func cancelCheck() { driver.cancelCheck() }

    func accept() { driver.acceptUpdate() }

    func dismiss() { driver.dismissUpdate() }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-controller test '-only-testing:TenXAppTests/theLaunchCheckReturnsAsSoonAsSparkleAnswers()' '-only-testing:TenXAppTests/theLaunchCheckGivesUpAtTheDeadlineWithoutFailing()'
```

Expected: PASS.

- [ ] **Step 5: Verify a real check against a local feed**

This proves Sparkle is wired correctly before any UI exists. Build a Release app, then point it at a handwritten local appcast using Sparkle's user-default override.

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-feedcheck build
```

Write a minimal feed to the scratch directory advertising a version above the built one, then launch with the override:

```bash
/private/tmp/tenx-feedcheck/Build/Products/Release/10x.app/Contents/MacOS/10x -SUFeedURL "file:///private/tmp/tenx-feedcheck/appcast.xml"
```

Expected in Console: Sparkle resolves the feed and reports a newer version. There is no visible update interface yet; that is Tasks 10 through 14. If Sparkle reports a signature failure here, the `SUPublicEDKey` from Task 4 does not match the key the feed was signed with.

- [ ] **Step 6: Commit**

```bash
git add App/Updates/UpdateController.swift Tests/TenXAppTests/UpdateControllerTests.swift 10x.xcodeproj && git commit -m "feat(updates): own the Sparkle updater behind a testable protocol"
```

---

### Task 10: The advisory update stage

**Files:**
- Modify: `App/Startup/StartupState.swift:1-30` (stage enum), `:95-140` (gating loops)
- Test: `Tests/TenXAppTests/StartupStateTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `StartupStageID.updates`, `StartupStageID.gatingCases`, and the guarantee that `markStopped(.updates, …)` and `enterRecovery` never stop the advisory row.

- [ ] **Step 1: Write the failing test**

Append to `Tests/TenXAppTests/StartupStateTests.swift`:

```swift
@MainActor
@Test func theLedgerEndsWithTheAdvisoryUpdateRow() {
    let state = StartupState()

    #expect(state.rows.map(\.title) == [
        "Preparing runtime",
        "Loading sessions",
        "Loading settings",
        "Preparing recent projects",
        "Checking for updates",
    ])
    #expect(StartupStageID.updates.detail == "Looking for a newer version")
}

@MainActor
@Test func onlyTheFourWorkStagesGateTheLaunch() {
    #expect(StartupStageID.gatingCases == [
        .runtime, .sessions, .settings, .recentProjects,
    ])
    #expect(!StartupStageID.gatingCases.contains(.updates))
}

@MainActor
@Test func recoveryNeverStopsTheAdvisoryUpdateRow() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markLoading(.updates, attemptID: attempt)
    state.markLoading(.sessions, attemptID: attempt)

    state.enterRecovery(attemptID: attempt)

    #expect(state.status(of: .sessions) == .stopped)
    #expect(state.status(of: .updates) != .stopped)
}

@MainActor
@Test func theAdvisoryRowCannotBeStoppedDirectly() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markLoading(.updates, attemptID: attempt)

    state.markStopped(.updates, attemptID: attempt)

    #expect(state.status(of: .updates) == .loading)
}

@MainActor
@Test func retryNeverReRunsTheAdvisoryRow() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markReady(.runtime, attemptID: attempt)
    state.enterRecovery(attemptID: attempt)

    let retried = state.beginRetry(id: UUID())

    #expect(!retried.contains(.updates))
    #expect(retried == [.sessions, .settings, .recentProjects])
}
```

`theAdvisoryRowCannotBeStoppedDirectly` is the load-bearing test. It is the structural guarantee that a network failure cannot put the splash into recovery, expressed as something a future change cannot silently break.

- [ ] **Step 2: Run the test to verify it fails**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-advisory test '-only-testing:TenXAppTests/theLedgerEndsWithTheAdvisoryUpdateRow()' 2>&1 | tail -20
```

Expected: FAIL, four rows instead of five.

- [ ] **Step 3: Add the stage case and its copy**

In `App/Startup/StartupState.swift`, add `case updates` as the **last** case of `StartupStageID`, since `allCases` follows declaration order and the advisory row must render last. Then extend both switches:

```swift
    var title: String {
        switch self {
        case .runtime: "Preparing runtime"
        case .sessions: "Loading sessions"
        case .settings: "Loading settings"
        case .recentProjects: "Preparing recent projects"
        case .updates: "Checking for updates"
        }
    }

    var detail: String {
        switch self {
        case .runtime: "Checking OMP and provider access"
        case .sessions: "Indexing active and archived sessions"
        case .settings: "Preparing your configuration"
        case .recentProjects: "Starting recent workspaces"
        case .updates: "Looking for a newer version"
        }
    }
```

Add the gating collection to the same enum:

```swift
    /// The stages that gate handoff and may enter recovery. `updates` is advisory and
    /// is deliberately absent: a check that fails must never stop a launch.
    static let gatingCases: [StartupStageID] = [
        .runtime, .sessions, .settings, .recentProjects,
    ]
```

- [ ] **Step 4: Exclude the advisory row from every gating loop**

Three changes in `StartupState`:

```swift
    func beginRetry(id: UUID) -> Set<StartupStageID> {
        let stages = Set(StartupStageID.gatingCases.filter { status(of: $0) != .ready })
        attemptID = id
        phase = .preparing
        for stage in stages { statuses[stage] = .queued }
        return stages
    }

    func markStopped(_ stage: StartupStageID, attemptID: UUID) {
        guard stage != .updates else { return }
        guard self.attemptID == attemptID, phase == .preparing else { return }
        statuses[stage] = .stopped
    }

    func enterRecovery(attemptID: UUID) {
        guard self.attemptID == attemptID, phase != .handoff else { return }
        for stage in StartupStageID.gatingCases where status(of: stage) != .ready {
            statuses[stage] = .stopped
        }
        phase = .recovery
    }
```

Leave `beginAttempt` iterating `allCases`, so a fresh attempt resets the advisory row too.

- [ ] **Step 5: Keep the footer describing work rather than the check**

`currentStage` already picks the first `loading` stage in `allCases` order. Because `updates` is last, the footer names it only once every gating stage is finished, which is the intended behavior. No change is needed. Confirm by reading the property rather than assuming.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-advisory test '-only-testing:TenXAppTests/theLedgerEndsWithTheAdvisoryUpdateRow()' '-only-testing:TenXAppTests/onlyTheFourWorkStagesGateTheLaunch()' '-only-testing:TenXAppTests/recoveryNeverStopsTheAdvisoryUpdateRow()' '-only-testing:TenXAppTests/theAdvisoryRowCannotBeStoppedDirectly()' '-only-testing:TenXAppTests/retryNeverReRunsTheAdvisoryRow()'
```

Expected: PASS.

- [ ] **Step 7: Re-record the two startup splash snapshots**

The ledger now has five rows, so the reference images are legitimately stale. This is the one place in this plan where re-recording is correct.

```bash
TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-advisory-record test '-only-testing:TenXAppTests/startupSplashLoadingSnapshot()' '-only-testing:TenXAppTests/startupSplashRecoverySnapshot()'
```

Then open both PNGs under `Tests/TenXAppTests/ReferenceImages/` and confirm the fifth row reads `Checking for updates` with the correct status, that nothing is clipped by the fixed 248 point upper field, and that row spacing is even. A recorded image is not verified until it has been looked at.

- [ ] **Step 8: Run the full suite**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-advisory-full test 2>&1 | tail -20
```

- [ ] **Step 9: Commit**

```bash
git add App/Startup/StartupState.swift Tests/TenXAppTests 10x.xcodeproj && git commit -m "feat(startup): add the advisory update row to the ledger"
```

---

### Task 11: Move the handoff latch into `StartupState`

**Files:**
- Modify: `App/Startup/StartupState.swift`
- Modify: `App/Startup/StartupSceneView.swift:11`, `:20-30`
- Test: `Tests/TenXAppTests/StartupStateTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `StartupState.consumeWorkspaceOpenRequest() -> Bool`, which returns `true` exactly once per handoff.

This fixes an existing defect. `handledHandoffGeneration` lives in the scene view's local `@State`, so reopening the startup window after handoff recreates the view with a counter of zero, the `onChange(initial: true)` comparison against a non-zero `handoffGeneration` succeeds, and a second workspace window opens.

- [ ] **Step 1: Write the failing test**

Append to `Tests/TenXAppTests/StartupStateTests.swift`:

```swift
@MainActor
@Test func aHandoffOpensTheWorkspaceExactlyOnce() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)

    #expect(!state.consumeWorkspaceOpenRequest())

    state.requestHandoff(attemptID: attempt)

    #expect(state.consumeWorkspaceOpenRequest())
    #expect(!state.consumeWorkspaceOpenRequest())
    #expect(!state.consumeWorkspaceOpenRequest())
}
```

The repeated calls model the startup window being reopened later in update mode. Every one of them after the first must refuse.

- [ ] **Step 2: Run the test to verify it fails**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-latch test '-only-testing:TenXAppTests/aHandoffOpensTheWorkspaceExactlyOnce()' 2>&1 | tail -20
```

Expected: FAIL, method does not exist.

- [ ] **Step 3: Add the latch**

In `App/Startup/StartupState.swift`, add the stored property beside `handoffGeneration` and the method:

```swift
    private var openedWorkspaceGeneration = 0

    /// Returns `true` at most once per handoff. The latch lives here rather than in the
    /// scene view because the startup window is recreated when it is reopened in update
    /// mode, which resets any view-local counter and would open a duplicate workspace.
    func consumeWorkspaceOpenRequest() -> Bool {
        guard handoffGeneration > openedWorkspaceGeneration else { return false }
        openedWorkspaceGeneration = handoffGeneration
        return true
    }
```

- [ ] **Step 4: Use it from the scene view**

In `App/Startup/StartupSceneView.swift`, delete `@State private var handledHandoffGeneration = 0` and replace the `onChange` with:

```swift
        .onChange(of: model.startupState.handoffGeneration, initial: true) { _, _ in
            guard model.startupState.consumeWorkspaceOpenRequest() else { return }
            Task { @MainActor in
                openWindow(id: AppWindowID.workspace)
            }
        }
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-latch test '-only-testing:TenXAppTests/aHandoffOpensTheWorkspaceExactlyOnce()'
```

Expected: PASS.

- [ ] **Step 6: Run the full suite**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-latch-full test 2>&1 | tail -20
```

- [ ] **Step 7: Commit**

```bash
git add App/Startup Tests/TenXAppTests/StartupStateTests.swift && git commit -m "fix(startup): keep the workspace handoff latch across window recreation"
```

---

### Task 12: Wire the update check into the launch

**Files:**
- Modify: `App/Startup/StartupState.swift` (`StartupTiming`)
- Modify: `App/Application/AppDependencies.swift`
- Modify: `App/Application/AppModel.swift:109-141` (bootstrap), `:728-812` (attempt and preparation)
- Test: `Tests/TenXAppTests/AppModelUpdateTests.swift` (create)

**Interfaces:**
- Consumes: `UpdateChecking` from Task 9, `StartupStageID.updates` from Task 10.
- Produces: `StartupTiming.updateCheckDeadline`, `AppDependencies.makeUpdateChecker`, `AppModel.updateState`, `AppModel.checkForUpdatesFromMenu()`, `AppModel.acceptUpdate()`, `AppModel.dismissUpdate()`, `AppModel.retryUpdate()`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TenXAppTests/AppModelUpdateTests.swift`. It reuses `StubUpdateChecker` from Task 9 and the existing `StartupFixture` from `StartupTestFixtures.swift`, which is how every other startup suite builds an `AppModel`.

```swift
import Foundation
import Testing
@testable import TenXApp

private let updateTestTiming = StartupTiming(
    minimumVisibility: .zero,
    timeout: .seconds(10),
    updateCheckDeadline: .milliseconds(50),
    sleep: { _ in })

@MainActor
@Test func aLaunchWithNoUpdateHandsOffNormally() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let checker = StubUpdateChecker()
    // What the real driver does at launch when the feed has nothing newer.
    checker.onCheck = { $0.reset() }
    let model = fixture.model(timing: updateTestTiming, updateChecker: checker)

    await model.bootstrap()

    #expect(model.startupState.phase == .handoff)
    #expect(model.startupState.status(of: .updates) == .ready)
    if let manager = model.processManager { await manager.closeAll() }
}

@MainActor
@Test func aFailedUpdateStillReachesTheWorkspaceOnceDismissed() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let checker = StubUpdateChecker()
    checker.onCheck = { $0.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0") }
    let model = fixture.model(timing: updateTestTiming, updateChecker: checker)

    let bootstrap = Task { await model.bootstrap() }
    while !model.updateState.isAwaitingDecision { await Task.yield() }
    model.updateState.beginDownload()
    model.updateState.fail(.download)
    await Task.yield()

    #expect(model.startupState.phase != .handoff)

    model.dismissUpdate()
    await bootstrap.value

    #expect(model.startupState.phase == .handoff)
    if let manager = model.processManager { await manager.closeAll() }
}

@MainActor
@Test func aStalledCheckIsCancelledAndTheLaunchProceeds() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let checker = StubUpdateChecker()

    let model = fixture.model(timing: updateTestTiming, updateChecker: checker)
    await model.bootstrap()

    #expect(checker.cancelCount == 1)
    #expect(model.startupState.phase == .handoff)
    #expect(model.startupState.status(of: .updates) == .ready)
    if let manager = model.processManager { await manager.closeAll() }
}

@MainActor
@Test func anAvailableUpdateHoldsTheWorkspaceUntilTheUserAnswers() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let checker = StubUpdateChecker()
    checker.onCheck = { $0.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0") }
    let model = fixture.model(timing: updateTestTiming, updateChecker: checker)

    let bootstrap = Task { await model.bootstrap() }
    while !model.updateState.isAwaitingDecision { await Task.yield() }

    #expect(model.startupState.phase != .handoff)

    model.dismissUpdate()
    await bootstrap.value

    #expect(model.startupState.phase == .handoff)
    if let manager = model.processManager { await manager.closeAll() }
}

@MainActor
@Test func acceptingAnUpdateNeverOpensTheWorkspace() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let checker = StubUpdateChecker()
    checker.onCheck = { $0.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0") }
    let model = fixture.model(timing: updateTestTiming, updateChecker: checker)

    let bootstrap = Task { await model.bootstrap() }
    while !model.updateState.isAwaitingDecision { await Task.yield() }
    model.updateState.beginDownload()
    for _ in 0..<10 { await Task.yield() }

    // A real install terminates the process here. Nothing may reach the workspace first.
    #expect(model.startupState.phase != .handoff)
    #expect(!model.startupState.consumeWorkspaceOpenRequest())

    // Release the gate so the test does not leak a suspended bootstrap task.
    model.updateState.reset()
    await bootstrap.value
    if let manager = model.processManager { await manager.closeAll() }
}

@MainActor
@Test func aMenuCheckIsUserInitiatedAndIgnoredWhileOneIsOnScreen() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let checker = StubUpdateChecker()
    let model = fixture.model(timing: updateTestTiming, updateChecker: checker)

    model.checkForUpdatesFromMenu()

    #expect(checker.checkCount == 1)
    #expect(checker.lastCheckWasUserInitiated == true)

    model.updateState.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")
    model.checkForUpdatesFromMenu()

    #expect(checker.checkCount == 1)
    if let manager = model.processManager { await manager.closeAll() }
}
```

`acceptingAnUpdateNeverOpensTheWorkspace` is the one that matters most: an update that is installing must never race a workspace window onto the screen moments before Sparkle terminates the process. `aStalledCheckIsCancelledAndTheLaunchProceeds` is its companion on the other side, proving a check that never answers is cancelled rather than left holding a continuation. `aFailedUpdateStillReachesTheWorkspaceOnceDismissed` guards the dead end: before the gate became a loop, a failed download left the splash frozen with no workspace and no recovery.

Every one of these bootstraps a model whose locator resolves, so every one ends with `closeAll()`. Omitting it leaks file descriptors into unrelated suites later in the run.

- [ ] **Step 2: Run the test to verify it fails**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-appmodel-update test '-only-testing:TenXAppTests/aLaunchWithNoUpdateHandsOffNormally()' 2>&1 | tail -20
```

Expected: FAIL, `StartupFixture.model` has no `updateChecker` parameter.

- [ ] **Step 3: Add the check deadline to `StartupTiming`**

In `App/Startup/StartupState.swift`:

```swift
struct StartupTiming: Sendable {
    let minimumVisibility: Duration
    let timeout: Duration
    let updateCheckDeadline: Duration
    let sleep: @Sendable (Duration) async throws -> Void

    static let live = StartupTiming(
        minimumVisibility: .milliseconds(1_200),
        timeout: .seconds(10),
        updateCheckDeadline: .seconds(3),
        sleep: { duration in try await ContinuousClock().sleep(for: duration) })
}
```

Every existing `StartupTiming(...)` construction in the test fixtures needs the new argument. Find them with:

```bash
grep -rn "StartupTiming(" App Tests
```

- [ ] **Step 4: Inject the checker factory**

In `App/Application/AppDependencies.swift`, add the stored property, the init parameter with a default, and the `live` value:

```swift
    let makeUpdateChecker: @MainActor @Sendable (
        @escaping @MainActor () async -> Void) -> any UpdateChecking
```

```swift
        makeUpdateChecker: (@MainActor @Sendable (
            @escaping @MainActor () async -> Void) -> any UpdateChecking)? = nil,
```

```swift
        self.makeUpdateChecker = makeUpdateChecker ?? { prepareForInstall in
            let controller = UpdateController(prepareForInstall: prepareForInstall)
            controller.start()
            return controller
        }
```

Add the same closure to the `live` static so it stays explicit rather than relying on the default.

- [ ] **Step 5: Own the checker from `AppModel`**

In `App/Application/AppModel.swift`, add near the other stored properties:

```swift
    @ObservationIgnored private lazy var updateChecker: any UpdateChecking =
        dependencies.makeUpdateChecker { [weak self] in
            await self?.shutdown()
        }

    var updateState: UpdateState { updateChecker.state }

    func checkForUpdatesFromMenu() {
        guard !isShuttingDown, !updateState.isPresentingUpdate else { return }
        updateChecker.check(isUserInitiated: true)
    }

    func acceptUpdate() { updateChecker.accept() }

    func dismissUpdate() { updateChecker.dismiss() }

    func retryUpdate() {
        updateChecker.dismiss()
        updateChecker.check(isUserInitiated: true)
    }
```

`lazy var` is what makes the `[weak self]` capture legal: it is evaluated after initialization completes. `@ObservationIgnored` keeps the Observation macro from trying to track a lazily initialized property.

Awaiting `shutdown()` inside `prepareForInstall` is the mechanism that satisfies the no-orphan guarantee. It does not depend on Sparkle's termination path reaching `AppTerminationDelegate`.

- [ ] **Step 6: Run the advisory check as part of preparation**

In `prepareStartup(attemptID:stages:)`, add one task to the existing group, alongside the settings and sessions tasks:

```swift
            if stages.contains(.updates) {
                group.addTask { await self.prepareUpdates(attemptID: attemptID) }
            }
```

The runtime branch returns before this group, so also resolve the advisory row on the missing-OMP path, or it hands off still reading `Queued`:

```swift
        if stages.contains(.runtime) {
            let hasRuntime = try await prepareRuntime(attemptID: attemptID)
            if !hasRuntime {
                startupState.markReady(.updates, attemptID: attemptID)
                return .missingOmp
            }
        }
```

No check runs on that path. An app with no OMP is going straight to setup, and offering it an update first would be noise.

Add the method beside `prepareRuntime`:

```swift
    /// Advisory. Deliberately non-throwing and deliberately incapable of marking the row
    /// stopped, so a network failure or a slow feed can never put the splash into
    /// recovery or extend the launch beyond the deadline.
    private func prepareUpdates(attemptID: UUID) async {
        startupState.markLoading(.updates, attemptID: attemptID)
        await updateChecker.checkAtLaunch(
            deadline: dependencies.startupTiming.updateCheckDeadline,
            sleep: dependencies.startupTiming.sleep)
        startupState.markReady(.updates, attemptID: attemptID)
    }
```

`bootstrap()` already passes `Set(StartupStageID.allCases)`, so the advisory stage is included on a cold launch and, per Task 10, excluded from every retry.

- [ ] **Step 7: Hold handoff while an offer is pending**

In `runStartupAttempt(id:stages:)`, replace the switch after the visibility floor:

```swift
            switch preparation {
            case .ready, .missingOmp:
                await updateChecker.state.waitWhilePresenting()
                startupState.requestHandoff(attemptID: id)
            }
```

`waitWhilePresenting()` returns immediately when nothing is on screen, so the common path is unchanged.

It must be a loop, not a single check followed by an early return. An update walks through several presented phases before it is done with the window: offered, downloading, failed, dismissed. Returning at the first one strands the splash with no workspace and no recovery if the download later fails, which is unrecoverable without force-quitting. Waiting for the whole sequence handles every branch with one line:

- Accepted and successful: Sparkle terminates the process inside the loop, and handoff is never reached because there is no longer a process to reach it.
- Accepted then failed then dismissed: the phase returns to `idle`, the loop exits, and the workspace opens.
- `Try again`: the phase drops to `checking`, the loop exits, the workspace opens, and any offer that follows arrives through the workspace reopen path from Task 13.

- [ ] **Step 8: Extend the existing fixtures rather than adding new doubles**

Two edits in `Tests/TenXAppTests/StartupTestFixtures.swift`.

Add the parameter to `makeStartupDependencies`, after `makeProcessManager`:

```swift
    makeUpdateChecker: @escaping @MainActor @Sendable (
        @escaping @MainActor () async -> Void) -> any UpdateChecking,
```

and pass it through to the `AppDependencies` initializer.

Add the matching parameter to `StartupFixture.model(...)`, after `providerFactory`:

```swift
        updateChecker: (any UpdateChecking)? = nil
```

and inside the method, before building the dependencies:

```swift
        let checker = updateChecker ?? StubUpdateChecker()
```

then pass `makeUpdateChecker: { _ in checker }` into `makeStartupDependencies`. The default keeps every existing startup test compiling and running unchanged, with a checker that does nothing until its `onCheck` is set.

`StubUpdateChecker` is declared in `UpdateControllerTests.swift` and is visible here because both files belong to the same test target.

- [ ] **Step 9: Run the tests to verify they pass**

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-appmodel-update test '-only-testing:TenXAppTests/aLaunchWithNoUpdateHandsOffNormally()' '-only-testing:TenXAppTests/aFailedUpdateStillReachesTheWorkspaceOnceDismissed()' '-only-testing:TenXAppTests/aStalledCheckIsCancelledAndTheLaunchProceeds()' '-only-testing:TenXAppTests/anAvailableUpdateHoldsTheWorkspaceUntilTheUserAnswers()' '-only-testing:TenXAppTests/acceptingAnUpdateNeverOpensTheWorkspace()' '-only-testing:TenXAppTests/aMenuCheckIsUserInitiatedAndIgnoredWhileOneIsOnScreen()'
```

Expected: PASS.

- [ ] **Step 10: Run the full suite**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-appmodel-update-full test 2>&1 | tail -20
```

If unrelated suites now fail with `NSPOSIXErrorDomain Code=24 "Too many open files"`, a new test is bootstrapping a model without tearing the runtime down. Add the `closeAll()` teardown to it.

- [ ] **Step 11: Commit**

```bash
git add App Tests 10x.xcodeproj && git commit -m "feat(updates): check for updates during launch without gating it"
```

---

### Task 13: Render update mode and re-enter it from the workspace

**Files:**
- Modify: `App/Startup/StartupSceneView.swift`
- Modify: `App/TenXApp.swift:23-40`
- Test: `Tests/TenXAppTests/UpdateSnapshotTests.swift` (create, extended in Task 14)

**Interfaces:**
- Consumes: `SplashPresentation.update(...)` from Task 7, `AppModel.updateState` and friends from Task 12.
- Produces: the startup window renders update mode whenever `updateState.isPresentingUpdate`; `Check for Updates…` in the application menu.

- [ ] **Step 1: Render whichever presentation is active**

Replace the body of `StartupSceneView` in `App/Startup/StartupSceneView.swift`:

```swift
struct StartupSceneView: View {
    let model: AppModel

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        SplashView(
            presentation: presentation,
            buildVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        .task { await model.bootstrap() }
        .onChange(of: model.startupState.handoffGeneration, initial: true) { _, _ in
            guard model.startupState.consumeWorkspaceOpenRequest() else { return }
            Task { @MainActor in
                openWindow(id: AppWindowID.workspace)
            }
        }
        .onChange(of: model.updateState.isPresentingUpdate) { _, isPresenting in
            guard !isPresenting, model.startupState.phase == .handoff else { return }
            dismissWindow(id: AppWindowID.startup)
        }
    }

    @MainActor
    private var presentation: SplashPresentation {
        guard model.updateState.isPresentingUpdate else {
            return SplashPresentation.startup(
                state: model.startupState,
                onRetry: { Task { await model.retryStartup() } },
                onContinue: { Task { await model.continueToWorkspace() } })
        }
        return SplashPresentation.update(
            state: model.updateState,
            onInstall: { model.acceptUpdate() },
            onDismiss: { model.dismissUpdate() },
            onRetry: { model.retryUpdate() })
    }
}
```

The dismissal branch fires only once the workspace has already been handed off, so a launch-time `Not now` does not close the window before the workspace appears.

- [ ] **Step 2: Reopen the window from the workspace**

In `App/TenXApp.swift`, add the environment value and the observation to `WorkspaceSceneView`:

```swift
    @Environment(\.openWindow) private var openWindow
```

and, on the `AppShellView`, alongside the existing `onChange`:

```swift
            .onChange(of: model.updateState.isPresentingUpdate) { _, isPresenting in
                guard isPresenting else { return }
                openWindow(id: AppWindowID.startup)
            }
```

- [ ] **Step 3: Add the menu command**

In `App/TenXApp.swift`, attach to the workspace `WindowGroup` scene, after `.windowStyle(.hiddenTitleBar)`:

```swift
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    model.checkForUpdatesFromMenu()
                }
            }
        }
```

`CommandGroup(after: .appInfo)` places the item directly under `About 10x`, which is the conventional macOS position. The ellipsis is correct because the action opens a window.

- [ ] **Step 4: Verify in a real build**

Load `launching-local-builds` before this step.

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-update-ui build && open /private/tmp/tenx-update-ui/Build/Products/Release/10x.app
```

With no update published yet, the feed returns nothing, so confirm the launch path only:

- The splash shows five rows and the fifth reads `Checking for updates`.
- The launch is not visibly slower than before this branch.
- The workspace opens once, and exactly one workspace window exists.
- `10x ▸ Check for Updates…` exists and sits directly under `About 10x`.

Screenshot the splash and the menu. Real update behavior is verified in Task 17.

- [ ] **Step 5: Commit**

```bash
git add App 10x.xcodeproj && git commit -m "feat(updates): present updates in the splash and reach them from the menu"
```

---

### Task 14: Update snapshots and accessibility coverage

**Files:**
- Create: `Tests/TenXAppTests/UpdateSnapshotTests.swift`
- Modify: `Tests/TenXAppTests/AccessibilityLabelTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 6 through 13.
- Produces: three reference images and the accessibility assertions for update mode.

- [ ] **Step 1: Write the snapshot tests**

Create `Tests/TenXAppTests/UpdateSnapshotTests.swift`:

```swift
import SwiftUI
import Testing
@testable import TenXApp

@MainActor
private func updateSplash(_ state: UpdateState) -> some View {
    SplashView(
        presentation: SplashPresentation.update(
            state: state, onInstall: {}, onDismiss: {}, onRetry: {}),
        buildVersion: "0.1.0")
        .environment(\.startupSignalReduceMotionOverride, true)
}

@MainActor
@Test func updateAvailableSnapshot() throws {
    let state = UpdateState()
    state.beginCheck()
    state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    try assertSnapshot(
        updateSplash(state),
        name: "update-available",
        size: CGSize(width: 640, height: 400))
}

@MainActor
@Test func updateDownloadingSnapshot() throws {
    let state = UpdateState()
    state.beginDownload()
    state.setExpectedBytes(61_800_000)
    state.addReceivedBytes(18_200_000)

    try assertSnapshot(
        updateSplash(state),
        name: "update-downloading",
        size: CGSize(width: 640, height: 400))
}

@MainActor
@Test func updateFailedSnapshot() throws {
    let state = UpdateState()
    state.beginDownload()
    state.beginVerifying()
    state.fail(.verification)

    try assertSnapshot(
        updateSplash(state),
        name: "update-failed",
        size: CGSize(width: 640, height: 400))
}
```

- [ ] **Step 2: Record the reference images**

```bash
ruby scripts/generate_xcodeproj.rb && TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-update-snap test '-only-testing:TenXAppTests/updateAvailableSnapshot()' '-only-testing:TenXAppTests/updateDownloadingSnapshot()' '-only-testing:TenXAppTests/updateFailedSnapshot()'
```

- [ ] **Step 3: Look at all three images before trusting them**

Load `visual-ui` and `writing-ui` before this step. Open each PNG under `Tests/TenXAppTests/ReferenceImages/` and check:

- `update-available`: heading `Update available`, footer title `10x 0.2.0`, detail `You have 0.1.0.`, buttons `Install and Relaunch` and `Not now`. The two buttons must match the recovery composition's construction exactly, bordered cyan followed by ghost. The signal path is flat black with no cyan fill.
- `update-downloading`: four update rows with the first `Loading` and the rest `Queued`, footer detail reading `18.2 MB of 61.8 MB`, and the cyan fill covering roughly 24 percent of the path. Confirm the fill starts at the left edge and follows the sine section's geometry rather than cutting across it.
- `update-failed`: `Downloading update` is `Ready`, `Verifying download` is `Stopped` in signal red, footer title `Update failed` in signal red, detail `The download could not be verified.`, buttons `Try again` and `Not now`, and the signal path red with no cyan.

Anything clipped, colliding, or off the existing 8 point spacing rhythm is a defect to fix in the view, not to accept into a reference image.

- [ ] **Step 4: Verify the snapshots pass without recording**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-update-snap test '-only-testing:TenXAppTests/updateAvailableSnapshot()' '-only-testing:TenXAppTests/updateDownloadingSnapshot()' '-only-testing:TenXAppTests/updateFailedSnapshot()'
```

Expected: PASS.

- [ ] **Step 5: Add the accessibility assertions**

Append to `Tests/TenXAppTests/AccessibilityLabelTests.swift`:

```swift
@MainActor
@Test func updateRowsAnnounceTheirTitleAndStatus() {
    let state = UpdateState()
    state.beginDownload()

    #expect(state.rows.map(\.accessibilityLabel) == [
        "Downloading update, Loading",
        "Verifying download, Queued",
        "Installing update, Queued",
        "Relaunching 10x, Queued",
    ])
}

@MainActor
@Test func updateModeRelabelsTheWindowForVoiceOver() {
    let state = UpdateState()
    state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    let presentation = SplashPresentation.update(
        state: state, onInstall: {}, onDismiss: {}, onRetry: {})

    #expect(presentation.accessibilityLabel == "Update available")
}

@MainActor
@Test func theInstallActionIsFirstInFocusOrder() {
    let state = UpdateState()
    state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    let presentation = SplashPresentation.update(
        state: state, onInstall: {}, onDismiss: {}, onRetry: {})

    #expect(presentation.actions.first?.kind == .primary)
    #expect(presentation.actions.first?.title == "Install and Relaunch")
}
```

- [ ] **Step 6: Run the full suite**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-update-snap-full test 2>&1 | tail -20
```

- [ ] **Step 7: Commit**

```bash
git add Tests 10x.xcodeproj && git commit -m "test(updates): cover the update compositions and their accessibility"
```

---

### Task 15: The release script

**Files:**
- Create: `scripts/release.sh`
- Create: `scripts/ExportOptions.plist`

**Interfaces:**
- Consumes: the Release signing settings from Task 2, the Sparkle keys from Task 4.
- Produces: `scripts/release.sh <version> [--no-publish]`, which emits `dist/10x-<version>.zip` and `dist/appcast.xml`, and publishes a GitHub release unless `--no-publish` is passed.

This task has no unit test. Its verification is a real signed, notarized artifact, which Step 5 produces.

- [ ] **Step 1: Write the export options**

Create `scripts/ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>345S42BKPY</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
```

- [ ] **Step 2: Write the script**

Create `scripts/release.sh`:

```bash
#!/usr/bin/env bash
# Builds, signs, notarizes, staples, and publishes a 10x release.
#
#   scripts/release.sh 0.2.0              build and publish
#   scripts/release.sh 0.2.0 --no-publish build only, leave dist/ on disk
#
# Requires: APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID.
# The Sparkle private key comes from SPARKLE_ED_PRIVATE_KEY_FILE if set,
# otherwise from the login keychain, which is the local-developer path.
set -euo pipefail

VERSION="${1:?usage: release.sh <version> [--no-publish]}"
PUBLISH="${2:-publish}"
SPARKLE_VERSION="2.9.6"   # must match Package.resolved; the tools and the framework are a pair
REPO="NextStep-AI-inc/10x"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD_NUMBER="$(git rev-list --count HEAD)"
if [ "$BUILD_NUMBER" -le 1 ]; then
  echo "error: git rev-list --count HEAD returned $BUILD_NUMBER." >&2
  echo "The checkout is shallow. Sparkle compares CFBundleVersion, so every" >&2
  echo "release would claim to be build 1. Fetch full history and retry." >&2
  exit 1
fi

DIST="$ROOT/dist"
BUILD="$ROOT/.release-build"
rm -rf "$DIST" "$BUILD"
mkdir -p "$DIST" "$BUILD"

echo "==> Generating the project"
ruby scripts/generate_xcodeproj.rb

echo "==> Archiving $VERSION (build $BUILD_NUMBER)"
xcodebuild archive \
  -project 10x.xcodeproj \
  -scheme 10x \
  -configuration Release \
  -destination 'platform=macOS' \
  -archivePath "$BUILD/10x.xcarchive" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive \
  -archivePath "$BUILD/10x.xcarchive" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$BUILD/export"

APP="$BUILD/export/10x.app"
[ -d "$APP" ] || { echo "error: export produced no app at $APP" >&2; exit 1; }

echo "==> Notarizing"
ditto -c -k --keepParent "$APP" "$BUILD/notarize.zip"
xcrun notarytool submit "$BUILD/notarize.zip" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

echo "==> Stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# The ticket is written into the bundle, so the notarized zip is stale.
# Everything downstream must sign and measure this second archive, not that one.
ZIP="$DIST/10x-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Fetching Sparkle $SPARKLE_VERSION tools"
# Keep this pinned to the version in Package.resolved. Signing an archive with tools
# from a different Sparkle release than the framework the app embeds is a silent way
# to produce an appcast the shipped app refuses.
curl -fsSL -o "$BUILD/sparkle.tar.xz" \
  "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
mkdir -p "$BUILD/sparkle"
tar -xJf "$BUILD/sparkle.tar.xz" -C "$BUILD/sparkle"

echo "==> Generating the appcast"
GENERATE_APPCAST="$BUILD/sparkle/bin/generate_appcast"
KEY_ARGS=()
if [ -n "${SPARKLE_ED_PRIVATE_KEY_FILE:-}" ]; then
  KEY_ARGS=(--ed-key-file "$SPARKLE_ED_PRIVATE_KEY_FILE")
fi
"$GENERATE_APPCAST" \
  "${KEY_ARGS[@]}" \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  "$DIST"

grep -q 'sparkle:edSignature' "$DIST/appcast.xml" || {
  echo "error: the appcast carries no EdDSA signature. Sparkle will reject it." >&2
  exit 1
}

if [ "$PUBLISH" = "--no-publish" ]; then
  echo "==> Built $ZIP and $DIST/appcast.xml. Not publishing."
  exit 0
fi

echo "==> Publishing v$VERSION"
gh release create "v$VERSION" \
  "$ZIP" "$DIST/appcast.xml" \
  --repo "$REPO" \
  --title "10x $VERSION" \
  --generate-notes
```

The `BUILD_NUMBER` guard is not decoration. On a default `actions/checkout` the count is `1`, every release would claim the same `CFBundleVersion`, and Sparkle would never recognise any build as newer. Failing loudly beats shipping a permanently un-updatable app.

The `grep` for `sparkle:edSignature` catches a missing or unreadable key, which otherwise produces a valid-looking appcast that every client refuses.

- [ ] **Step 3: Make it executable and add it to the generator's file list if needed**

```bash
chmod +x scripts/release.sh
```

`scripts/` is not part of any build target, so no project regeneration is required.

- [ ] **Step 4: Confirm the Apple secrets are reachable**

Before the first workflow run, confirm whether the five `APPLE_*` secrets are organization-level or repository-level on `NextStep-Workspace`. This account cannot list organization secrets, so ask Tanner to check, or check from an account with the scope.

```bash
gh secret list --repo NextStep-AI-inc/10x
```

If the Apple secrets are absent from this repository and are not organization-level, they must be added here before Task 16's workflow can run.

- [ ] **Step 5: Check the script without running it**

Tanner's decision: the local notarization dry run is skipped, and the first real signing and notarization happens in the Task 17 workflow run. That means this script's first execution is in CI, so the cheap static checks matter more than usual.

```bash
bash -n scripts/release.sh && shellcheck scripts/release.sh 2>/dev/null || bash -n scripts/release.sh
```

Expected: no syntax errors. `shellcheck` is not required; `bash -n` is the floor.

Then confirm the archive and export halves work, which need no Apple credentials beyond the Developer ID already in the keychain:

```bash
ruby scripts/generate_xcodeproj.rb && xcodebuild archive -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -archivePath /private/tmp/tenx-archive-check/10x.xcarchive MARKETING_VERSION=0.1.0 CURRENT_PROJECT_VERSION=99 && xcodebuild -exportArchive -archivePath /private/tmp/tenx-archive-check/10x.xcarchive -exportOptionsPlist scripts/ExportOptions.plist -exportPath /private/tmp/tenx-archive-check/export && codesign -dv --verbose=2 /private/tmp/tenx-archive-check/export/10x.app 2>&1 | grep -E "Authority|flags"
```

Expected: the export succeeds and reports `Authority=Developer ID Application: NextStep AI Inc. (345S42BKPY)` with `flags=0x10000(runtime)`. This proves everything up to the notarization call. Only the `notarytool` submission and the Sparkle signing remain unproven until Task 17.

Record in the ledger that notarization is unverified until the first workflow run.

- [ ] **Step 6: Commit**

```bash
git add scripts/release.sh scripts/ExportOptions.plist && git commit -m "build: add the signed and notarized release script"
```

Add `dist/` and `.release-build/` to `.gitignore` in the same commit.

---

### Task 16: The release workflow

**Files:**
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `scripts/release.sh` from Task 15.
- Produces: a tag push matching `v*` publishes a signed, notarized release with an appcast.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - "v*"

permissions:
  contents: write

jobs:
  release:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
        with:
          # Sparkle compares CFBundleVersion, which release.sh derives from the
          # commit count. A shallow checkout makes every release claim build 1.
          fetch-depth: 0

      - name: Import the Developer ID certificate
        env:
          APPLE_CSC_LINK: ${{ secrets.APPLE_CSC_LINK }}
          APPLE_CSC_KEY_PASSWORD: ${{ secrets.APPLE_CSC_KEY_PASSWORD }}
        run: |
          set -euo pipefail
          [ -n "$APPLE_CSC_LINK" ] || { echo "::error::APPLE_CSC_LINK is not set"; exit 1; }
          KEYCHAIN="$RUNNER_TEMP/build.keychain"
          KEYCHAIN_PASSWORD="$(uuidgen)"
          echo "$APPLE_CSC_LINK" | base64 --decode > "$RUNNER_TEMP/certificate.p12"
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
          security set-keychain-settings -lut 21600 "$KEYCHAIN"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
          security import "$RUNNER_TEMP/certificate.p12" \
            -k "$KEYCHAIN" -P "$APPLE_CSC_KEY_PASSWORD" \
            -T /usr/bin/codesign -T /usr/bin/security
          security set-key-partition-list -S apple-tool:,apple:,codesign: \
            -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
          security list-keychain -d user -s "$KEYCHAIN" login.keychain
          rm -P "$RUNNER_TEMP/certificate.p12"
          security find-identity -v -p codesigning "$KEYCHAIN"

      - name: Write the Sparkle signing key
        env:
          SPARKLE_ED_PRIVATE_KEY: ${{ secrets.SPARKLE_ED_PRIVATE_KEY }}
        run: |
          set -euo pipefail
          [ -n "$SPARKLE_ED_PRIVATE_KEY" ] || { echo "::error::SPARKLE_ED_PRIVATE_KEY is not set"; exit 1; }
          printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$RUNNER_TEMP/sparkle_key"
          chmod 600 "$RUNNER_TEMP/sparkle_key"

      - name: Build, notarize, and publish
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          SPARKLE_ED_PRIVATE_KEY_FILE: ${{ runner.temp }}/sparkle_key
          GH_TOKEN: ${{ github.token }}
        run: scripts/release.sh "${GITHUB_REF_NAME#v}"

      - name: Remove the signing key
        if: always()
        run: rm -Pf "$RUNNER_TEMP/sparkle_key"
```

The final step runs with `if: always()` so a failed build does not leave the private key on the runner's disk.

- [ ] **Step 2: Confirm the push will be accepted**

Workflow files are rejected over HTTPS when the token lacks the `workflow` scope. This checkout uses SSH (`gh auth status` reports `Git operations protocol: ssh`), so the push succeeds. If a push is ever rejected with a workflow-scope error, the fix is:

```bash
gh auth refresh -h github.com -s workflow
```

- [ ] **Step 3: Validate the YAML before pushing**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('valid')"
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml && git commit -m "ci: publish signed releases on a version tag"
```

---

### Task 17: Publish and verify a real upgrade

**GATED.** Publishing is outward facing and permanent. Do not run any step here without Tanner's explicit go-ahead. Do not merge the branch without his instruction.

**Files:**
- No source files change.

**Interfaces:**
- Consumes: everything.
- Produces: published `v0.1.0` and `v0.1.1` releases, and evidence that a real installed copy upgrades itself.

- [ ] **Step 1: Flip the PR to ready and run the review**

Load `writing-prs` and `reviewing-code`. The PR body needs the evidence gathered across Tasks 2 through 16, including the three update snapshots.

- [ ] **Step 2: Publish `v0.1.0`**

```bash
git tag v0.1.0 && git push origin v0.1.0
```

Watch the run:

```bash
gh run watch --repo NextStep-AI-inc/10x
```

- [ ] **Step 3: Confirm the feed resolves**

```bash
curl -fsSL "https://github.com/NextStep-AI-inc/10x/releases/latest/download/appcast.xml" | head -40
```

Expected: an item for `0.1.0` whose enclosure URL points at `releases/download/v0.1.0/` and which carries a `sparkle:edSignature`. A URL pointing at `latest/download/` instead means `--download-url-prefix` was wrong and every future update would download the wrong archive.

- [ ] **Step 4: Install `0.1.0` the way a user would**

Download the zip from the release page in a browser, expand it, and drag `10x.app` to `/Applications`. Do not use the locally built copy; the quarantine attribute a browser download carries is part of what is being tested.

Launch it. Expected: no Gatekeeper warning, the splash shows `BUILD 0.1.0` and five rows, and the fifth row resolves without offering anything.

- [ ] **Step 5: Publish `v0.1.1`**

Bump nothing in source; the tag drives the version.

```bash
git tag v0.1.1 && git push origin v0.1.1 && gh run watch --repo NextStep-AI-inc/10x
```

- [ ] **Step 6: Verify the upgrade end to end**

Load `verifying-work` before this step. Quit and relaunch the `/Applications` copy of `0.1.0`. Record the screen for the whole sequence. Confirm every one of these:

- The splash holds instead of opening the workspace.
- The heading reads `Update available`, the footer reads `10x 0.1.1` and `You have 0.1.0.`
- `Install and Relaunch` starts the progress composition, the four update rows resolve in order, and the cyan fill advances along the path rather than jumping.
- The app relaunches and the splash reads `BUILD 0.1.1`.
- No OMP child survived the relaunch:

```bash
pgrep -fl omp
```

Expected: no processes belonging to the previous instance.

- [ ] **Step 7: Verify the paths that must not break**

- Relaunch `0.1.1` with Wi-Fi disabled. Expected: the workspace opens normally, the advisory row reads `Ready`, and no error appears.
- `10x ▸ Check for Updates…` on `0.1.1`. Expected: the splash reopens over the workspace reading `No updates available` and `10x 0.1.1`, `Close` dismisses it, and exactly one workspace window remains.
- Enable Reduce Motion, install `0.1.0` again, and repeat the upgrade. Expected: the cyan fill still advances, and the travelling segment and breathing are absent.
- Enable VoiceOver and repeat the offer. Expected: the window announces `Update available`, focus lands on `Install and Relaunch`, and the update rows announce title and status.
- Install `0.1.0` again, accept the update, and quit the app mid-download with Command-Q. Expected: the app quits, no partial install is left behind, and relaunching offers the update again from the beginning. Sparkle installs only after a complete extraction, so a mid-download quit must never produce a damaged bundle. Confirm the app still launches and reports `BUILD 0.1.0`.

- [ ] **Step 8: Report**

Report in the shape Tanner expects: Verified with evidence, Not verified and why, and For him to test. Attach the screen recording and the snapshot images. Do not merge without his instruction.

---

## Notes for the implementer

**Where this plan is most likely to be wrong.** Three places depend on details of a dependency this plan could not run:

1. `SPUUserDriver`'s actor isolation. Task 8 Step 1 tells you how to check and what to do either way.
2. The `SUError` case names in `SplashUpdateDriver.failure(for:)`. Verify them against the resolved header; do not substitute integer literals.
3. `generate_appcast`'s exact flags for Sparkle 2.9.6, the version SPM resolved. If `--ed-key-file` or `--download-url-prefix` differ, run it with `--help` and use the real names. Do not work around a flag mismatch by hand-writing the appcast; a hand-written signature is the one thing that silently breaks every future update.

**What must never be weakened to make something compile.** Strict concurrency, the advisory row's inability to enter `Stopped`, awaiting `shutdown()` before consenting to install, and `.dismiss` rather than `.skip` for `Not now`.

**Snapshots.** Re-record only in Task 10 Step 7 and Task 14 Step 2. A snapshot failure anywhere else is a regression to fix, not an image to refresh.

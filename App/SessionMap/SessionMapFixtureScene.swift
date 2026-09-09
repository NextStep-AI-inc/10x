import AppKit
import Foundation
import OmpKit
import SwiftUI

struct SessionMapFixtureScene: View {
    struct Configuration {
        let model: AppModel
        let route: UIFixtureRoute
        let title: String
        let colorScheme: ColorScheme?
        let reduceMotionOverride: Bool?
        let reduceTransparencyOverride: Bool?
        let marqueeMetricsObserver: (@MainActor (CGFloat, CGFloat) -> Void)?
    }

    let configuration: Configuration

    var body: some View {
        AppShellView(model: configuration.model)
            .frame(minWidth: 760, minHeight: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preferredColorScheme(configuration.colorScheme)
            .environment(
                \.sessionMapReduceMotionOverride,
                configuration.reduceMotionOverride)
            .environment(
                \.flyerReduceMotionOverride,
                configuration.reduceMotionOverride)
            .environment(
                \.flyerReduceTransparencyOverride,
                configuration.reduceTransparencyOverride)
            .environment(
                \.flyerMarqueeMetricsObserver,
                configuration.marqueeMetricsObserver)
    }

    @MainActor
    static func make(
        route: UIFixtureRoute,
        environment: [String: String],
        isolatedRootOverride: URL? = nil
    ) throws -> Configuration {
        guard let buildSHA = environment["TENX_UI_FIXTURE_SHA"], !buildSHA.isEmpty else {
            throw SessionMapFixtureStartupError.missingBuildSHA
        }
        let appearance = try fixtureAppearance(environment["TENX_UI_FIXTURE_APPEARANCE"])
        let reduceMotionOverride = try fixtureReduceMotion(
            environment["TENX_UI_FIXTURE_REDUCE_MOTION"])
        let reduceTransparencyOverride = try fixtureReduceTransparency(
            environment["TENX_UI_FIXTURE_REDUCE_TRANSPARENCY"])
        let root = try isolatedRootOverride
            ?? isolatedRoot(route: route, buildSHA: buildSHA)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = try isolatedDefaults(route: route, buildSHA: buildSHA)
        let model = fixtureModel(
            root: root,
            defaults: defaults,
            usesLiveMapWriter: route.usesLiveMapWriter,
            sourceSHA: buildSHA)
        if route == .settingsMap {
            let sessions = try fixtureSessions(route: route, root: root, model: model)
            model.installSessionMapFixture(sessions, selectedPath: sessions[0].metadata.path)
            model.installSessionMapSettingsFixture(projectURL: root)
            return Configuration(
                model: model,
                route: route,
                title: "10x | \(route.rawValue) | \(String(buildSHA.prefix(12)))",
                colorScheme: appearance,
                reduceMotionOverride: reduceMotionOverride,
                reduceTransparencyOverride: reduceTransparencyOverride,
                marqueeMetricsObserver: nil)
        }
        let sessions = try fixtureSessions(route: route, root: root, model: model)
        model.installSessionMapFixture(sessions, selectedPath: sessions[0].metadata.path)
        let metricsObserver = route.isFlyer
            ? FlyerFixtureScene.install(
                route: route,
                model: model,
                selectedPath: sessions[0].metadata.path,
                defaults: defaults)
            : nil
        if route == .mapPlanning {
            model.sessionMapPaneModel(
                for: sessions[0].controller,
                displayedWidth: model.requestedSessionMapPaneWidth
            ).activity = SessionMapActivity(
                activeNodeIDs: ["writer"],
                unmappedDescriptions: [])
        }
        return Configuration(
            model: model,
            route: route,
            title: "10x | \(route.rawValue) | \(String(buildSHA.prefix(12)))",
            colorScheme: appearance,
            reduceMotionOverride: reduceMotionOverride,
            reduceTransparencyOverride: reduceTransparencyOverride,
            marqueeMetricsObserver: metricsObserver)
    }

    @MainActor
    static func inertModelForStartupFailure() -> AppModel {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "10x-session-map-fixture-startup-failure", directoryHint: .isDirectory)
        let defaults = UserDefaults(suiteName: "com.nextstep.tenx.sessionmap.fixture.failure")
            ?? UserDefaults.standard
        return fixtureModel(
            root: root,
            defaults: defaults,
            usesLiveMapWriter: false,
            sourceSHA: "startup-failure")
    }

    @MainActor
    private static func fixtureModel(
        root: URL,
        defaults: UserDefaults,
        usesLiveMapWriter: Bool,
        sourceSHA: String
    ) -> AppModel {
        let callRecorder = SessionMapFixtureCallRecorder(
            url: root.appending(path: "session-map-writer-calls.txt"),
            sourceSHA: sourceSHA)
        let dependencies = AppDependencies(
            ompLocator: usesLiveMapWriter
                ? OmpExecutableLocator()
                : SessionMapFixtureLocator(),
            sessionLibrary: SessionLibrary(
                root: root.appending(path: "sessions", directoryHint: .isDirectory),
                archiveRoot: root.appending(path: "archived-sessions", directoryHint: .isDirectory)),
            sessionSearch: SessionSearchService(
                databaseURL: root.appending(path: "search.sqlite")),
            recentProjectStore: RecentProjectStore(defaults: defaults),
            makeProcessManager: { _ in SessionProcessManager() },
            makeSettingsModel: { executableURL in
                if usesLiveMapWriter {
                    return SettingsViewModel(
                        service: OmpConfigService(
                            runner: OmpConfigProcessRunner(executableURL: executableURL)),
                        sessionMapCatalog: ComposerCatalogService(executableURL: executableURL),
                        sessionMapPreferences: SessionMapPreferenceStore(defaults: defaults))
                }
                return SettingsViewModel(
                    service: OmpConfigService(runner: SessionMapFixtureConfigRunner()),
                    sessionMapCatalog: SessionMapFixtureCatalog(),
                    sessionMapPreferences: SessionMapPreferenceStore(defaults: defaults))
            },
            makeProviderModel: { _ in
                preconditionFailure("UI fixture does not load provider accounts")
            },
            makeComposerControls: { _ in
                preconditionFailure("UI fixture does not load the model catalog")
            },
            makeProviderAccountCoordinator: {
                ProviderAccountCoordinator(
                    primaryStore: ProviderPrimaryPreferenceStore(defaults: defaults))
            },
            makeUpdateChecker: { _ in InertFixtureUpdateChecker() },
            sessionMapStore: SessionMapStore(
                directory: root.appending(path: "SessionMap", directoryHint: .isDirectory)),
            makeSessionMapGenerator: { executableURL, projectURL in
                guard usesLiveMapWriter else {
                    return SessionMapGenerator { _, _, _ in
                        throw SessionMapFixtureWriterError.disabled
                    }
                }
                let rpc = SessionMapRPC(executableURL: executableURL, projectURL: projectURL)
                return SessionMapGenerator { prompt, images, model in
                    await callRecorder.recordCall(hasImage: !images.isEmpty)
                    return try await rpc.complete(prompt: prompt, images: images, model: model)
                }
            })
        return AppModel(
            dependencies: dependencies,
            preferenceDefaults: defaults,
            fileOpenService: FileOpenService(
                openDefault: { _ in },
                openInApplication: { _, _ in },
                reveal: { _ in },
                startSecurityScope: { _ in false },
                stopSecurityScope: { _ in }))
    }

    @MainActor
    private static func fixtureSessions(
        route: UIFixtureRoute,
        root: URL,
        model: AppModel
    ) throws -> [(
        metadata: SessionMetadata,
        controller: SessionController,
        document: SessionMapDocument?,
        state: SessionMapPaneState
    )] {
        let projectA = root.appending(path: "SessionMapApp", directoryHint: .isDirectory)
        let projectB = root.appending(path: "SessionMapSupport", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectB, withIntermediateDirectories: true)
        try Data("struct FixtureWriter {}\n".utf8).write(
            to: projectA.appending(path: "Writer.swift"), options: .atomic)
        try Data("struct FixtureRenderer {}\n".utf8).write(
            to: projectB.appending(path: "Renderer.swift"), options: .atomic)
        let first = try fixtureDocument(route: route, isSecondary: false)
        let second = try fixtureDocument(route: route, isSecondary: true)
        let controllerA = fixtureController(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000601")!,
            title: "Plan the native session map",
            project: projectA,
            draft: "Keep the map open while I review the transcript.",
            attachmentName: "map-layout.png",
            transcriptSeed: "planning",
            route: route,
            model: model)
        let controllerB = fixtureController(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000602")!,
            title: "Implement the map renderer",
            project: projectB,
            draft: "Check the drawer behavior at the minimum window size.",
            attachmentName: "drawer-check.png",
            transcriptSeed: "implementing",
            route: route,
            model: model)
        return [
            fixtureEntry(
                controller: controllerA,
                project: projectA,
                path: root.appending(path: "planning.jsonl").path,
                document: first.document,
                state: first.state,
                modified: 200),
            fixtureEntry(
                controller: controllerB,
                project: projectB,
                path: root.appending(path: "implementing.jsonl").path,
                document: second.document,
                state: second.state,
                modified: 100),
        ]
    }

    @MainActor
    private static func fixtureController(
        id: UUID,
        title: String,
        project: URL,
        draft: String,
        attachmentName: String,
        transcriptSeed: String,
        route: UIFixtureRoute,
        model: AppModel
    ) -> SessionController {
        let timestamp = Date(timeIntervalSince1970: 1_788_800_000)
        let user = TranscriptMessage(
            id: "\(transcriptSeed)-user",
            raw: .object([
                "role": .string("user"),
                "content": .string("Show the session architecture beside the real transcript."),
            ]),
            timestamp: timestamp,
            isFinal: true)
        let assistantDetail = route.isFlyer
            ? "The selected session keeps its full latest response reachable while measured system notices sit above a multiline composer with an attachment. This deliberately long final assistant message verifies that scrolling to the bottom leaves the response visible instead of hiding it beneath the notice glass."
            : "The native map keeps the architecture visible while the composer remains ready."
        let assistant = TranscriptMessage(
            id: "\(transcriptSeed)-assistant",
            raw: .object([
                "role": .string("assistant"),
                "content": .string(assistantDetail),
            ]),
            timestamp: timestamp.addingTimeInterval(20),
            attribution: TranscriptResponseAttribution(
                provider: "fixture",
                model: "synthetic",
                mode: transcriptSeed,
                agent: nil,
                modelRole: nil),
            isFinal: true)
        var previewItems: [TranscriptItem] = [
            .threadStart(id: "\(transcriptSeed)-start", date: timestamp),
            .message(user),
            .message(assistant),
        ]
        if route.isFlyer {
            previewItems.append(.extensionUI(.select(
                id: "\(transcriptSeed)-fixture-question",
                title: "Which fixture state should remain visible during this layout check?",
                options: [
                    ExtensionSelectOption(
                        label: "Keep the current state",
                        detail: "This is synthetic component-only fixture data."),
                    ExtensionSelectOption(
                        label: "Continue inspecting",
                        detail: nil),
                ],
                timeout: nil)))
        }
        let controller = SessionController(
            processManager: SessionProcessManager(),
            previewItems: previewItems,
            runtimeState: .idle,
            title: title,
            headerMetadata: SessionHeaderMetadata(
                branch: "codex/session-map-plans",
                repo: project.lastPathComponent,
                worktreePath: project.path),
            id: id,
            activityRegistry: model.sessionActivityRegistry)
        controller.draft = route.isFlyer
            ? "Verify the measured overlay above this multiline composer.\nKeep the attachment and recovery controls reachable."
            : draft
        controller.attachments = [fixtureAttachment(name: attachmentName)]
        return controller
    }

    private static func fixtureEntry(
        controller: SessionController,
        project: URL,
        path: String,
        document: SessionMapDocument?,
        state: SessionMapPaneState,
        modified: TimeInterval
    ) -> (
        metadata: SessionMetadata,
        controller: SessionController,
        document: SessionMapDocument?,
        state: SessionMapPaneState
    ) {
        let date = Date(timeIntervalSince1970: 1_788_800_000 + modified)
        return (SessionMetadata(
            path: path,
            sessionId: controller.id.uuidString,
            cwd: project.path,
            title: controller.title,
            created: date,
            modified: date,
            sizeBytes: 2_048,
            status: .complete), controller, document, state)
    }

    private static func fixtureDocument(
        route: UIFixtureRoute,
        isSecondary: Bool
    ) throws -> (document: SessionMapDocument?, state: SessionMapPaneState) {
        if !isSecondary && route == .mapEmpty {
            return (nil, .empty)
        }
        if !isSecondary && route == .mapInvalid {
            let malformed = Data("<sessionmap><map><node></map></sessionmap>".utf8)
            let rejection = SessionMapDocumentParser.parse(
                malformed,
                context: SessionMapFixtures.context)
            guard rejection.document == nil, !rejection.fatal.isEmpty else {
                throw SessionMapFixtureStartupError.invalidFixtureWasAccepted
            }
            return (nil, .failed(message: "The fixture document was rejected."))
        }
        if !isSecondary && route == .mapWriterLive {
            return (nil, .needsGeneration)
        }
        let xml: String = switch (route, isSecondary) {
        case (.mapPlanning, false): SessionMapFixtures.planningXML
        case (.mapImplementing, false): SessionMapFixtures.implementingXML
        case (.mapDense, false): SessionMapFixtures.denseXML
        case (.mapEmpty, false), (.mapInvalid, false): SessionMapFixtures.emptyXML
        case (.mapDense, true), (.mapInvalid, true): SessionMapFixtures.layoutStressXML
        case (.settingsMap, _): SessionMapFixtures.emptyXML
        case (.mapWriterLive, false): SessionMapFixtures.emptyXML
        case (.mapWriterLive, true): SessionMapFixtures.graphStatesXML
        case (.flyerFitting, false), (.flyerOverflow, false),
             (.flyerStack, false), (.flyerRecovery, false): SessionMapFixtures.planningXML
        case (_, true): SessionMapFixtures.graphStatesXML
        }
        return (try SessionMapFixtures.document(xml), .ready)
    }

    @MainActor
    private static func fixtureAttachment(name: String) -> ComposerAttachment {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 32,
            pixelsHigh: 32,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        NSColor(red: 0, green: 0.65, blue: 0.77, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        NSGraphicsContext.restoreGraphicsState()
        return ComposerAttachment(
            name: name,
            data: representation.representation(using: .png, properties: [:]) ?? Data(),
            mimeType: "image/png",
            pixelWidth: 32,
            pixelHeight: 32)
    }

    private static func isolatedRoot(route: UIFixtureRoute, buildSHA: String) throws -> URL {
        let component = buildSHA.filter { $0.isLetter || $0.isNumber }
        let root = FileManager.default.temporaryDirectory
            .appending(path: "10x-session-map-fixture", directoryHint: .isDirectory)
            .appending(path: component, directoryHint: .isDirectory)
            .appending(path: route.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func isolatedDefaults(
        route: UIFixtureRoute,
        buildSHA: String
    ) throws -> UserDefaults {
        let component = buildSHA.filter { $0.isLetter || $0.isNumber }
        let suite = "com.nextstep.tenx.sessionmap.fixture.\(component).\(route.rawValue)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw SessionMapFixtureStartupError.defaultsUnavailable
        }
        return defaults
    }

    private static func fixtureAppearance(_ value: String?) throws -> ColorScheme? {
        switch value {
        case nil, "system": nil
        case "light": .light
        case "dark": .dark
        case .some(let value): throw SessionMapFixtureStartupError.invalidAppearance(value)
        }
    }

    private static func fixtureReduceMotion(_ value: String?) throws -> Bool? {
        switch value {
        case nil, "system": nil
        case "on": true
        case "off": false
        case .some(let value): throw SessionMapFixtureStartupError.invalidReduceMotion(value)
        }
    }

    private static func fixtureReduceTransparency(_ value: String?) throws -> Bool? {
        switch value {
        case nil, "system": nil
        case "on": true
        case "off": false
        case .some(let value): throw SessionMapFixtureStartupError.invalidReduceTransparency(value)
        }
    }

}

private actor SessionMapFixtureCallRecorder {
    let url: URL
    let sourceSHA: String
    private var count = 0
    private var writerCount = 0
    private var checkerCount = 0

    init(url: URL, sourceSHA: String) {
        self.url = url
        self.sourceSHA = sourceSHA
    }

    func recordCall(hasImage: Bool) {
        count += 1
        if hasImage { checkerCount += 1 } else { writerCount += 1 }
        let evidence = "sourceSHA=\(sourceSHA)\ncalls=\(count)\ntotalCalls=\(count)\nwriterCalls=\(writerCount)\ncheckerCalls=\(checkerCount)\n"
        try? Data(evidence.utf8).write(to: url, options: .atomic)
    }
}

private enum SessionMapFixtureWriterError: Error { case disabled }

private struct SessionMapFixtureLocator: OmpLocating {
    func locate(preferredURL: URL?) async throws -> OmpLocation {
        .found(OmpInstallation(
            executableURL: URL(filePath: "/tmp/session-map-fixture-omp"),
            version: "fixture"))
    }
}

private actor SessionMapFixtureCatalog: ComposerCatalogLoading {
    nonisolated let commandUpdates = AsyncStream<ComposerCommandCatalogState> { $0.finish() }

    func load(projectURL: URL?) async throws -> ComposerCatalogSnapshot {
        ComposerCatalogSnapshot(
            models: [
                ComposerModelInfo(
                    modelID: "writer-text",
                    name: "Fixture Writer",
                    provider: "fixture-text",
                    api: nil,
                    thinkingEfforts: [],
                    requiresEffort: false),
                ComposerModelInfo(
                    modelID: "map-vision",
                    name: "Fixture Vision",
                    provider: "fixture-image",
                    api: nil,
                    thinkingEfforts: ["low", "high"],
                    requiresEffort: false,
                    acceptsImages: true),
            ],
            selected: nil,
            thinkingLevel: nil,
            fastModeEnabled: false,
            fastModeActive: false)
    }

    func shutdown() async {}
}

private struct SessionMapFixtureConfigRunner: OmpConfigRunning {
    func run(arguments: [String]) async throws -> Data {
        switch arguments {
        case ["config", "list", "--json"]:
            Data("""
            {"modelRoles":{"value":{"smol":"fixture-image/map-vision:high","vision":"fixture-image/map-vision:low"},"type":"record","description":"Model roles"}}
            """.utf8)
        case ["config", "path"]:
            Data("/tmp/session-map-fixture-config.json\n".utf8)
        default:
            Data()
        }
    }
}

@MainActor
private final class InertFixtureUpdateChecker: UpdateChecking {
    let state = UpdateState()
    func check(isUserInitiated: Bool) {}
    func cancelCheck() {}
    func accept() {}
    func dismiss() {}
}

private enum SessionMapFixtureStartupError: LocalizedError {
    case missingBuildSHA
    case defaultsUnavailable
    case invalidAppearance(String)
    case invalidReduceMotion(String)
    case invalidReduceTransparency(String)
    case invalidFixtureWasAccepted

    var errorDescription: String? {
        switch self {
        case .missingBuildSHA:
            "TENX_UI_FIXTURE_SHA is required for fixture provenance."
        case .defaultsUnavailable:
            "The isolated fixture preferences could not be created."
        case .invalidAppearance(let value):
            "TENX_UI_FIXTURE_APPEARANCE must be system, light, or dark. Received \(value)."
        case .invalidReduceMotion(let value):
            "TENX_UI_FIXTURE_REDUCE_MOTION must be system, on, or off. Received \(value)."
        case .invalidReduceTransparency(let value):
            "TENX_UI_FIXTURE_REDUCE_TRANSPARENCY must be system, on, or off. Received \(value)."
        case .invalidFixtureWasAccepted:
            "The malformed UI fixture document was unexpectedly accepted."
        }
    }
}

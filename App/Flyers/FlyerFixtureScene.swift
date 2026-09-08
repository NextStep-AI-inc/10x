import Foundation
import OmpKit
import SwiftUI

struct FlyerFixtureScene: View {
    let configuration: SessionMapFixtureScene.Configuration

    var body: some View {
        AppShellView(model: configuration.model)
            .frame(minWidth: 760, minHeight: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preferredColorScheme(configuration.colorScheme)
            .environment(\.sessionMapReduceMotionOverride, configuration.reduceMotionOverride)
            .environment(\.flyerReduceMotionOverride, configuration.reduceMotionOverride)
            .environment(
                \.flyerReduceTransparencyOverride,
                configuration.reduceTransparencyOverride)
            .environment(\.flyerMarqueeMetricsObserver, configuration.marqueeMetricsObserver)
    }

    @MainActor
    static func install(
        route: UIFixtureRoute,
        model: AppModel,
        selectedPath: String,
        defaults: UserDefaults
    ) -> (@MainActor (CGFloat, CGFloat) -> Void)? {
        let center = model.flyerCenter
        seed(route: route, center: center, sessionPath: selectedPath)
        installComposerData(model: model, defaults: defaults)
        model.installFlyerFixtureHandlers(
            onAction: { [weak model, weak center] key, actionID in
                guard let model, let center else { return }
                handle(key: key, actionID: actionID, model: model, center: center)
            })
        if route == .flyerRecovery {
            model.activeSession?.handleUnexpectedExit(
                code: 9,
                stderrTail: "Synthetic fixture runtime stopped before the final response.")
        }
        let reporter = FlyerFixtureMetricsReporter(route: route)
        return { textWidth, viewportWidth in
            reporter.report(textWidth: textWidth, viewportWidth: viewportWidth)
        }
    }

    @MainActor
    private static func installComposerData(model: AppModel, defaults: UserDefaults) {
        let selected = ComposerModelInfo(
            modelID: "fixture-fast",
            name: "Fixture Fast",
            provider: "fixture",
            api: nil,
            thinkingEfforts: ["low", "high"],
            requiresEffort: false)
        let catalog = InertFlyerCatalog(
            snapshot: ComposerCatalogSnapshot(
                models: [selected],
                selected: selected,
                thinkingLevel: "high",
                fastModeEnabled: false,
                fastModeActive: false,
                commandCatalog: .available([
                    AvailableSlashCommand(
                        name: "fixture-check",
                        description: "Inspect synthetic fixture controls",
                        source: .builtin),
                    AvailableSlashCommand(
                        name: "fixture-summary",
                        description: "Prepare a component-only summary",
                        source: .custom),
                ])))
        let controls = ComposerControlsModel(
            catalog: catalog,
            defaults: InertFlyerDefaults(),
            recents: RecentModelStore(defaults: defaults),
            favorites: FavoriteModelStore(defaults: defaults))
        let commands = ComposerCommandModel(
            catalog: catalog,
            controls: controls,
            onStartNewSession: { _, _ in })
        model.installFlyerComposerFixture(controls: controls, commands: commands)
        Task {
            await model.prepareFlyerComposerFixture()
        }
    }

    @MainActor
    private static func seed(
        route: UIFixtureRoute,
        center: FlyerCenter,
        sessionPath: String
    ) {
        switch route {
        case .flyerFitting:
            center.post(flyer(
                id: "fitting",
                scope: .session(sessionPath),
                detail: "The session summary is ready.",
                actions: [Flyer.Action(id: "open-map", title: "Open Map")]))
        case .flyerOverflow:
            center.post(flyer(
                id: "overflow",
                scope: .session(sessionPath),
                detail: "Three background turns finished and the concise session summary is ready to inspect.",
                actions: [Flyer.Action(id: "open-map", title: "Open Map")]))
        case .flyerStack, .flyerRecovery:
            center.post(flyer(
                id: "global",
                scope: .global,
                tone: .information,
                title: "Component check",
                detail: "Global fixture notice.",
                actions: [Flyer.Action(id: "replace-global", title: "Replace fixture")]))
            center.post(flyer(
                id: "session-attention",
                scope: .session(sessionPath),
                tone: .attention,
                title: "Component check",
                detail: "Session replacement and dismissal use the real row controls.",
                actions: [Flyer.Action(id: "replace-session", title: "Replace fixture")]))
            center.post(flyer(
                id: "session-expiry",
                scope: .session(sessionPath),
                tone: .error,
                title: "Component check",
                detail: "Expiry is synthetic and component-only in this fixture.",
                actions: [Flyer.Action(id: "expire-fixture", title: "Expire fixture")]))
        default:
            break
        }
    }

    @MainActor
    private static func handle(
        key: Flyer.Key,
        actionID: String,
        model: AppModel,
        center: FlyerCenter
    ) {
        switch actionID {
        case "open-map":
            if !model.isSessionMapVisible { model.toggleSessionMap() }
            center.remove(key)
        case "replace-global":
            center.post(flyer(
                id: key.id,
                scope: key.scope,
                tone: .information,
                title: "Component check",
                detail: "The global fixture notice was replaced in place.",
                actions: []))
        case "replace-session":
            center.post(flyer(
                id: key.id,
                scope: key.scope,
                tone: .attention,
                title: "Component check",
                detail: "The session fixture notice was replaced in place.",
                actions: []))
        case "expire-fixture":
            center.post(flyer(
                id: "expired-result",
                scope: .global,
                tone: .attention,
                title: "Component check",
                detail: "This synthetic expiry clears automatically after two seconds.",
                actions: [],
                expiresAt: Date().addingTimeInterval(2)))
            center.remove(key)
        default:
            break
        }
    }

    private static func flyer(
        id: String,
        scope: Flyer.Scope,
        tone: Flyer.Tone = .information,
        title: String = "Catch up",
        detail: String,
        actions: [Flyer.Action],
        expiresAt: Date? = nil
    ) -> Flyer {
        Flyer(
            id: id,
            scope: scope,
            tone: tone,
            title: title,
            detail: detail,
            actions: actions,
            isDismissible: true,
            expiresAt: expiresAt)
    }
}

private actor InertFlyerCatalog: ComposerCatalogLoading {
    nonisolated let commandUpdates: AsyncStream<ComposerCommandCatalogState>
    private let snapshot: ComposerCatalogSnapshot

    init(snapshot: ComposerCatalogSnapshot) {
        self.snapshot = snapshot
        let updates = AsyncStream<ComposerCommandCatalogState>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        commandUpdates = updates.stream
        updates.continuation.yield(snapshot.commandCatalog)
        updates.continuation.finish()
    }

    func load(projectURL: URL?) async throws -> ComposerCatalogSnapshot {
        snapshot
    }

    func shutdown() async {}
}

private actor InertFlyerDefaults: ComposerDefaultPersisting {
    func setDefaultModel(provider: String, modelID: String) async throws {}
    func setDefaultThinkingLevel(_ level: String) async throws {}
}

@MainActor
private final class FlyerFixtureMetricsReporter {
    private let route: UIFixtureRoute
    private var lastTextWidth: CGFloat?
    private var lastViewportWidth: CGFloat?

    init(route: UIFixtureRoute) {
        self.route = route
    }

    func report(textWidth: CGFloat, viewportWidth: CGFloat) {
        guard textWidth > 0, viewportWidth > 0,
              textWidth != lastTextWidth || viewportWidth != lastViewportWidth else { return }
        lastTextWidth = textWidth
        lastViewportWidth = viewportWidth
        let overflow = max(0, textWidth - viewportWidth)
        let twoCycleDuration = 2 * (2.4 + 2 * Double(overflow) / 40)
        print(String(
            format: "TENX_FLYER_METRICS route=%@ text=%.2f viewport=%.2f overflow=%.2f twoCycles=%.2f",
            route.rawValue,
            textWidth,
            viewportWidth,
            overflow,
            twoCycleDuration))
    }
}

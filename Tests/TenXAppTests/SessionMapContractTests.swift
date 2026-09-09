import Foundation
import OmpKit
import Testing
@testable import TenXApp

private let isSessionMapLiveContractEnabled = {
    let environment = ProcessInfo.processInfo.environment
    return environment["TEST_RUNNER_TENX_SESSION_MAP_LIVE_CONTRACT"] == "1"
        || environment["TENX_SESSION_MAP_LIVE_CONTRACT"] == "1"
}()

@MainActor
@Test(.enabled(
    if: isSessionMapLiveContractEnabled,
    "Set TENX_SESSION_MAP_LIVE_CONTRACT=1 and an explicit evidence directory."))
func sessionMapConfiguredWriterContractCorpus() async throws {
    let environment = ProcessInfo.processInfo.environment
    let evidencePath = try #require(
        environment["TEST_RUNNER_TENX_SESSION_MAP_EVIDENCE_DIR"]
            ?? environment["TENX_SESSION_MAP_EVIDENCE_DIR"])
    let sourceSHA = try #require(
        environment["TEST_RUNNER_TENX_SESSION_MAP_SOURCE_SHA"]
            ?? environment["TENX_SESSION_MAP_SOURCE_SHA"])
    let projectURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let location = try await OmpExecutableLocator().locate(preferredURL: nil)
    let executableURL = try #require(location.installation?.executableURL)
    let settings = SettingsViewModel(
        service: OmpConfigService(runner: OmpConfigProcessRunner(executableURL: executableURL)),
        sessionMapCatalog: ComposerCatalogService(executableURL: executableURL),
        sessionMapPreferences: SessionMapPreferenceStore())
    try #require(await settings.load())
    try #require(await settings.loadSessionMapCatalog(projectURL: projectURL))
    let writer = try #require(SessionMapModelResolver.resolve(
        selection: settings.sessionMapPreferences.writerSelection,
        catalog: settings.sessionMapModels,
        roles: settings.sessionMapRoles))
    let checkerSelection = settings.sessionMapPreferences.checkerSelection
    let checker = checkerSelection.flatMap {
        SessionMapModelResolver.resolve(
            selection: $0,
            catalog: settings.sessionMapModels,
            roles: settings.sessionMapRoles)
    }
    let runDirectory = URL(filePath: evidencePath, directoryHint: .isDirectory)
        .appending(path: "session-map-contract-\(sourceSHA.prefix(12))", directoryHint: .isDirectory)
    guard !FileManager.default.fileExists(atPath: runDirectory.path) else {
        Issue.record("Evidence directory already exists; refusing to overwrite a prior bounded run.")
        return
    }
    try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

    let rpc = SessionMapRPC(executableURL: executableURL, projectURL: projectURL)
    let completion: SessionMapWriterCompletion = { prompt, images, model in
        try await rpc.complete(prompt: prompt, images: images, model: model)
    }
    let nativeChecker = SessionMapChecker(completion: completion)
    let generator = SessionMapGenerator(completion: completion, checker: nativeChecker)
    var prior: SessionMapRecord?
    var planningIDs: Set<String> = []
    var evidence: [SessionMapContractEvidence] = []
    for (index, corpusCase) in sessionMapContractCases.enumerated() {
        let start = Date()
        let result = await generator.generate(SessionMapGenerationInput(
            sessionKey: "contract-\(corpusCase.name)",
            lineage: "synthetic-contract",
            revision: UInt64(index + 1),
            digest: corpusCase.digest,
            priorRecord: corpusCase.usesPrior ? prior : nil,
            scope: .wholeSession,
            model: writer,
            checkerModel: checker,
            isCheckerConfigured: checkerSelection != nil,
            paneWidth: 440,
            projectURL: projectURL,
            force: true))
        let document = result.document
        let ids = Set(document?.graph.nodes.map(\.id) ?? [])
        let firstSeenOrder = result.record?.firstSeenOrder ?? []
        let layout = document.map {
            SessionMapLayout.layout(
                graph: $0.graph,
                firstSeenOrder: firstSeenOrder,
                measuredHeights: SessionMapGraphView.measuredHeights(for: $0.graph))
        }
        if let document, let layout,
           corpusCase.name == "planning" || corpusCase.name == "incremental"
        {
            let png = try await nativeChecker.render(
                document: document, layout: layout, width: 440)
            let filename = corpusCase.name == "planning"
                ? "planning-native-before.png"
                : "incremental-native-after.png"
            try png.write(to: runDirectory.appending(path: filename), options: .atomic)
        }
        if corpusCase.name == "planning" {
            planningIDs = ids
            prior = result.record
        }
        evidence.append(SessionMapContractEvidence(
            name: corpusCase.name,
            sourceSHA: sourceSHA,
            xml: result.xml,
            diagnostics: result.diagnostics.map { "\($0.code): \($0.detail)" },
            layoutDiagnostics: layout?.diagnostics.map { "\($0.code): \($0.message)" } ?? [],
            durationMilliseconds: Int(Date().timeIntervalSince(start) * 1_000),
            modelCallCount: result.modelCallCount,
            writerProvider: writer.provider,
            writerModel: writer.modelID,
            writerEffort: writer.effort,
            checkerProvider: checker?.provider,
            checkerModel: checker?.modelID,
            checkerEffort: checker?.effort,
            checkOutcome: result.checkOutcome.rawValue,
            disposition: String(describing: result.disposition),
            retainedPlanningIDs: corpusCase.usesPrior ? planningIDs.intersection(ids).sorted() : [],
            firstSeenOrder: firstSeenOrder,
            canvasWidth: layout.map { Double($0.size.width) },
            canvasHeight: layout.map { Double($0.size.height) }))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    for item in evidence {
        try encoder.encode(item).write(
            to: runDirectory.appending(path: "\(item.name).json"), options: .atomic)
    }
    try encoder.encode(evidence).write(
        to: runDirectory.appending(path: "summary.json"), options: .atomic)
}

private struct SessionMapContractCase: Sendable {
    let name: String
    let digest: SessionMapDigest
    let usesPrior: Bool
}

private struct SessionMapContractEvidence: Codable {
    let name: String
    let sourceSHA: String
    let xml: String?
    let diagnostics: [String]
    let layoutDiagnostics: [String]
    let durationMilliseconds: Int
    let modelCallCount: Int
    let writerProvider: String
    let writerModel: String
    let writerEffort: String?
    let checkerProvider: String?
    let checkerModel: String?
    let checkerEffort: String?
    let checkOutcome: String
    let disposition: String
    let retainedPlanningIDs: [String]
    let firstSeenOrder: [String]
    let canvasWidth: Double?
    let canvasHeight: Double?
}

private let sessionMapContractCases: [SessionMapContractCase] = [
    contractCase(
        name: "planning",
        text: "Plan a native session map with a source, writer, validated document, graph renderer, and complete supporting details.",
        refs: ["planning-1"],
        facts: ["finishedTurns": SessionMapFact(value: "1", number: 1)]),
    contractCase(
        name: "incremental",
        text: "Implementation followed the plan. Preserve IDs for the source, writer, document, and renderer while updating their statuses and adding checker work.",
        refs: ["implementation-1"],
        facts: ["finishedTurns": SessionMapFact(value: "2", number: 2)],
        usesPrior: true),
    contractCase(
        name: "wide-cyclic",
        text: "Map a wide architecture with seven roots, a dependent service, a two-component cycle, a self edge, and a disconnected audit store.",
        refs: ["architecture-1"],
        facts: ["filesChanged": SessionMapFact(value: "12", number: 12)]),
    contractCase(
        name: "failure-catch-up",
        text: "A test tool failed after earlier implementation completed. Show the failure evidence, completed work, pending attention, and concise catch-up next steps.",
        refs: ["failure-1", "done-1"],
        facts: [
            "finishedTurns": SessionMapFact(value: "4", number: 4),
            "failedTools": SessionMapFact(value: "1", number: 1),
            "pendingAttention": SessionMapFact(value: "1", number: 1),
        ])
]

private func contractCase(
    name: String,
    text: String,
    refs: Set<String>,
    facts: [String: SessionMapFact],
    usesPrior: Bool = false
) -> SessionMapContractCase {
    SessionMapContractCase(
        name: name,
        digest: SessionMapDigest(
            text: "Synthetic case: \(name)\n\(text)",
            hash: "contract-\(name)",
            cacheStateHash: "contract-state-\(name)",
            facts: facts,
            knownRefs: refs,
            cursor: SessionMapCursor(lineage: "synthetic-contract", entryID: name),
            sourceFingerprintManifest: [name: "synthetic-\(name)"],
            statusEvidence: []),
        usesPrior: usesPrior)
}

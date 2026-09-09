import Foundation
import OmpKit
import Testing
@testable import TenXApp

private let isSessionMapLiveContractEnabled = {
    let environment = ProcessInfo.processInfo.environment
    return environment["TEST_RUNNER_TENX_SESSION_MAP_LIVE_CONTRACT"] == "1"
        || environment["TENX_SESSION_MAP_LIVE_CONTRACT"] == "1"
}()

@Test func sessionMapContractCorpusUsesProductionDigestEvidence() throws {
    let planning = try #require(sessionMapContractCases.first { $0.name == "planning" })
    let incremental = try #require(sessionMapContractCases.first { $0.name == "incremental" })
    let failure = try #require(sessionMapContractCases.first { $0.name == "failure-catch-up" })
    let planningDigest = SessionMapDigestBuilder.build(
        source: planning.source, scope: .wholeSession)
    let incrementalDigest = SessionMapDigestBuilder.build(
        source: incremental.source,
        previousManifest: planningDigest.sourceFingerprintManifest,
        scope: .wholeSession)
    let failureDigest = SessionMapDigestBuilder.build(
        source: failure.source, scope: .wholeSession)
    let planningPrompt = SessionMapPrompt.writer(digest: planningDigest, previousXML: nil)
    let incrementalPrompt = SessionMapPrompt.writer(digest: incrementalDigest, previousXML: nil)

    #expect(planningPrompt.contains("planning-1"))
    #expect(planningPrompt.contains("- filesChanged: 0 number=0.0"))
    #expect(incrementalPrompt.contains("implementation-1"))
    #expect(incrementalDigest.knownRefs.contains("planning-1"))

    let validation = SessionMapDocumentParser.parse(Data("""
        <sessionmap headline="Evidence" phase="mixed"><map>
        <node id="failed" label="Failed check" kind="component" status="failed" ref="failure-1"/>
        <node id="done" label="Completed work" kind="component" status="done" ref="done-1"/>
        </map></sessionmap>
        """.utf8), context: SessionMapValidationContext(
            knownRefs: failureDigest.knownRefs,
            facts: failureDigest.facts,
            previous: nil,
            projectURL: nil,
            statusEvidence: failureDigest.statusEvidence))
    let document = try #require(validation.document)
    #expect(document.graph.nodes.first { $0.id == "failed" }?.status == .failed)
    #expect(document.graph.nodes.first { $0.id == "done" }?.status == .done)
}

@Test func sessionMapContractEvidenceSurvivesLaterRenderFailure() throws {
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "session-map-contract-evidence-\(UUID().uuidString)",
        directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = SessionMapContractEvidenceStore(directory: directory)
    var evidence: [SessionMapContractEvidence] = []
    let first = contractEvidence(name: "planning", xml: "<sessionmap/>")
    try store.persist(first, evidence: &evidence)
    var later = contractEvidence(name: "incremental", xml: "<sessionmap/>")
    try store.persist(later, evidence: &evidence)

    do {
        throw SessionMapContractTestError.simulatedRenderFailure
    } catch {
        later = later.withRender(
            nativeImage: nil,
            failure: "[SessionMap:Contract.render] Native render failed: \(error)")
        try store.persist(later, evidence: &evidence)
    }

    let decoder = JSONDecoder()
    let savedFirst = try decoder.decode(
        SessionMapContractEvidence.self,
        from: Data(contentsOf: directory.appending(path: "planning.json")))
    let summary = try decoder.decode(
        [SessionMapContractEvidence].self,
        from: Data(contentsOf: directory.appending(path: "summary.json")))
    #expect(savedFirst.xml == "<sessionmap/>")
    #expect(summary.count == 2)
    #expect(summary.last?.renderFailure?.contains("simulatedRenderFailure") == true)
}

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
    let evidenceStore = SessionMapContractEvidenceStore(directory: runDirectory)
    var prior: SessionMapRecord?
    var planningIDs: Set<String> = []
    var evidence: [SessionMapContractEvidence] = []
    for (index, corpusCase) in sessionMapContractCases.enumerated() {
        let start = Date()
        let digest = SessionMapDigestBuilder.build(
            source: corpusCase.source,
            previousManifest: corpusCase.usesPrior ? prior?.sourceManifest ?? [:] : [:],
            scope: .wholeSession)
        let result = await generator.generate(SessionMapGenerationInput(
            sessionKey: corpusCase.source.sessionKey,
            lineage: corpusCase.source.lineage,
            revision: UInt64(index + 1),
            digest: digest,
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
        if corpusCase.name == "planning" {
            planningIDs = ids
            prior = result.record
        }
        var item = SessionMapContractEvidence(
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
            canvasHeight: layout.map { Double($0.size.height) },
            nativeImage: nil,
            renderFailure: nil)
        try evidenceStore.persist(item, evidence: &evidence)
        if let document, let layout,
           corpusCase.name == "planning" || corpusCase.name == "incremental"
        {
            let filename = corpusCase.name == "planning"
                ? "planning-native-before.png"
                : "incremental-native-after.png"
            do {
                let png = try await nativeChecker.render(
                    document: document, layout: layout, width: 440)
                try png.write(to: runDirectory.appending(path: filename), options: .atomic)
                item = item.withRender(nativeImage: filename, failure: nil)
            } catch {
                item = item.withRender(
                    nativeImage: nil,
                    failure: "[SessionMap:Contract.render] Native render failed: \(error)")
            }
            try evidenceStore.persist(item, evidence: &evidence)
        }
    }
}

private struct SessionMapContractCase: Sendable {
    let name: String
    let source: SessionMapSource
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
    let nativeImage: String?
    let renderFailure: String?

    func withRender(nativeImage: String?, failure: String?) -> Self {
        Self(
            name: name, sourceSHA: sourceSHA, xml: xml, diagnostics: diagnostics,
            layoutDiagnostics: layoutDiagnostics, durationMilliseconds: durationMilliseconds,
            modelCallCount: modelCallCount, writerProvider: writerProvider,
            writerModel: writerModel, writerEffort: writerEffort,
            checkerProvider: checkerProvider, checkerModel: checkerModel,
            checkerEffort: checkerEffort, checkOutcome: checkOutcome,
            disposition: disposition, retainedPlanningIDs: retainedPlanningIDs,
            firstSeenOrder: firstSeenOrder, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
            nativeImage: nativeImage, renderFailure: failure)
    }
}

private struct SessionMapContractEvidenceStore {
    let directory: URL

    func persist(
        _ item: SessionMapContractEvidence,
        evidence: inout [SessionMapContractEvidence]
    ) throws {
        if let index = evidence.firstIndex(where: { $0.name == item.name }) {
            evidence[index] = item
        } else {
            evidence.append(item)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(item).write(
            to: directory.appending(path: "\(item.name).json"), options: .atomic)
        try encoder.encode(evidence).write(
            to: directory.appending(path: "summary.json"), options: .atomic)
    }
}

private enum SessionMapContractTestError: Error {
    case simulatedRenderFailure
}

private func contractEvidence(name: String, xml: String?) -> SessionMapContractEvidence {
    SessionMapContractEvidence(
        name: name,
        sourceSHA: "sha",
        xml: xml,
        diagnostics: [],
        layoutDiagnostics: [],
        durationMilliseconds: 1,
        modelCallCount: 1,
        writerProvider: "fixture",
        writerModel: "writer",
        writerEffort: nil,
        checkerProvider: nil,
        checkerModel: nil,
        checkerEffort: nil,
        checkOutcome: "off",
        disposition: "generated",
        retainedPlanningIDs: [],
        firstSeenOrder: [],
        canvasWidth: nil,
        canvasHeight: nil,
        nativeImage: nil,
        renderFailure: nil)
}

private let sessionMapContractCases: [SessionMapContractCase] = [
    SessionMapContractCase(
        name: "planning",
        source: contractSource(entries: [contractEntry(
            id: "planning-1",
            kind: .prompt,
            text: "Plan a native session map with a source, writer, validated document, graph renderer, and complete supporting details.",
            facts: ["filesChanged": SessionMapFact(value: "0", number: 0)])]),
        usesPrior: false),
    SessionMapContractCase(
        name: "incremental",
        source: contractSource(entries: [
            contractEntry(
                id: "planning-1",
                kind: .prompt,
                text: "Plan a native session map with a source, writer, validated document, graph renderer, and complete supporting details.",
                facts: ["filesChanged": SessionMapFact(value: "0", number: 0)]),
            contractEntry(
                id: "implementation-1",
                kind: .assistant,
                text: "Implementation followed the plan. Preserve IDs for the source, writer, document, and renderer while updating their statuses and adding checker work.",
                facts: ["filesChanged": SessionMapFact(value: "6", number: 6)]),
        ]),
        usesPrior: true),
    SessionMapContractCase(
        name: "wide-cyclic",
        source: contractSource(entries: [contractEntry(
            id: "architecture-1",
            kind: .prompt,
            text: "Map a wide architecture with seven roots, a dependent service, a two-component cycle, a self edge, and a disconnected audit store.",
            facts: ["filesChanged": SessionMapFact(value: "12", number: 12)])]),
        usesPrior: false),
    SessionMapContractCase(
        name: "failure-catch-up",
        source: contractSource(
            entries: [
                contractEntry(
                    id: "done-1", kind: .tool,
                    text: "Completed work passed its focused verification.",
                    outcome: "completed"),
                contractEntry(
                    id: "failure-1", kind: .attention,
                    text: "A later checker failed and needs attention before catch-up.",
                    outcome: "failed",
                    facts: [
                        "failedTool.checker": SessionMapFact(value: "1", number: 1),
                        "pendingAttention.checker": SessionMapFact(value: "1", number: 1),
                    ]),
            ],
            statusEvidence: [
                SessionMapStatusEvidence(
                    sourceRef: "failure-1", status: .failed, target: .label("Failed check")),
                SessionMapStatusEvidence(
                    sourceRef: "done-1", status: .done, target: .label("Completed work")),
            ]),
        usesPrior: false)
]

private func contractSource(
    entries: [SessionMapSourceEntry],
    statusEvidence: [SessionMapStatusEvidence] = []
) -> SessionMapSource {
    SessionMapSource(
        sessionKey: "synthetic-contract",
        lineage: "synthetic-contract",
        entries: entries,
        finishedTurnIDs: entries.map(\.id),
        knownRefs: Set(entries.map(\.id)),
        statusEvidence: statusEvidence)
}

private func contractEntry(
    id: String,
    kind: SessionMapSourceEntry.Kind,
    text: String,
    outcome: String? = nil,
    facts: [String: SessionMapFact] = [:]
) -> SessionMapSourceEntry {
    SessionMapSourceEntry(
        id: id,
        kind: kind,
        text: text,
        outcome: outcome,
        facts: facts,
        contentFingerprint: "synthetic-\(id)")
}

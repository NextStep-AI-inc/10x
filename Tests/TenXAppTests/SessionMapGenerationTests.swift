import Foundation
import OmpKit
import Testing
@testable import TenXApp

private actor MapWriterScript {
    private var outputs: [String]
    private(set) var prompts: [String] = []

    init(_ outputs: [String]) { self.outputs = outputs }

    func complete(prompt: String, images: [PromptImage], model: SessionMapResolvedModel) throws -> String {
        prompts.append(prompt)
        guard !outputs.isEmpty else { throw MapWriterError.exhausted }
        return outputs.removeFirst()
    }
}

private enum MapWriterError: Error { case exhausted }

private actor SuspendedMapWriter {
    private var completion: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func complete(prompt: String, images: [PromptImage], model: SessionMapResolvedModel) async -> String {
        hasStarted = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { completion = $0 }
        return "<sessionmap headline=\"Late map\" phase=\"planning\"><summary>Late.</summary></sessionmap>"
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        completion?.resume()
        completion = nil
    }
}

@Test func sessionMapGenerationUsesCacheAndOneRepair() async throws {
    let invalid = "<sessionmap><map></sessionmap>"
    let valid = "<sessionmap headline=\"Generated map\" phase=\"planning\"><summary>Current work.</summary></sessionmap>"
    let script = MapWriterScript([invalid, valid, valid, invalid, invalid])
    let generator = SessionMapGenerator { prompt, images, model in
        try await script.complete(prompt: prompt, images: images, model: model)
    }
    let base = generationInput()

    let repaired = await generator.generate(base)
    #expect(repaired.disposition == .generated)
    #expect(await script.prompts.count == 2)
    #expect(await script.prompts.last?.contains("malformed-xml") == true)

    let cached = await generator.generate(generationInput(priorRecord: repaired.record))
    #expect(cached.disposition == .cached)
    #expect(await script.prompts.count == 2)

    let forced = await generator.generate(generationInput(
        priorRecord: repaired.record, force: true, revision: 2))
    #expect(forced.disposition == .generated)
    #expect(await script.prompts.count == 3)

    let failed = await generator.generate(generationInput(
        priorRecord: forced.record, force: true, revision: 3))
    #expect(failed.disposition == .retainedLastGood)
    #expect(failed.document?.headline == "Generated map")
    #expect(await script.prompts.count == 5)
}

@Test func sessionMapGenerationCacheIncludesConfigurationAndPreviousXML() async throws {
    let valid = "<sessionmap headline=\"Generated map\" phase=\"planning\"><summary>Current work.</summary></sessionmap>"
    let changed = "<sessionmap headline=\"Changed prior\" phase=\"planning\"><summary>Different.</summary></sessionmap>"
    let script = MapWriterScript([valid, valid, valid, valid])
    let generator = SessionMapGenerator { prompt, images, model in
        try await script.complete(prompt: prompt, images: images, model: model)
    }
    let first = await generator.generate(generationInput())
    let record = try #require(first.record)

    _ = await generator.generate(generationInput(
        priorRecord: record,
        model: SessionMapResolvedModel(
            provider: "fixture", modelID: "writer", effort: "high", acceptsImages: false),
        revision: 2))
    _ = await generator.generate(generationInput(
        priorRecord: record,
        model: SessionMapResolvedModel(
            provider: "fixture", modelID: "writer-v2", effort: "low", acceptsImages: false),
        revision: 3))
    let changedRecord = SessionMapRecord(
        xml: changed,
        cacheKey: record.cacheKey,
        generatedThrough: record.generatedThrough,
        sourceManifest: record.sourceManifest,
        caughtUpAt: record.caughtUpAt,
        caughtUpCursor: record.caughtUpCursor,
        caughtUpGraph: record.caughtUpGraph,
        firstSeenOrder: record.firstSeenOrder,
        updatedAt: record.updatedAt,
        writerConfiguration: record.writerConfiguration,
        checkerConfiguration: record.checkerConfiguration,
        checkOutcome: record.checkOutcome,
        dismissedThrough: record.dismissedThrough)
    _ = await generator.generate(generationInput(priorRecord: changedRecord, revision: 4))

    #expect(await script.prompts.count == 4)
}

@Test func sessionMapGenerationPersistsReconciledXMLAsNextPrior() async throws {
    let priorXML = """
    <sessionmap headline="Prior" phase="planning"><map>
      <node id="stable" label="Writer" kind="component" status="planned" file="App/Writer.swift">Old.</node>
    </map></sessionmap>
    """
    let candidateXML = """
    <sessionmap headline="Updated" phase="implementing"><map>
      <node id="writer-new" label="Writer" kind="component" status="active" file="App/Writer.swift" ref="entry-1">New.</node>
    </map></sessionmap>
    """
    let script = MapWriterScript([candidateXML, candidateXML])
    let generator = SessionMapGenerator { prompt, images, model in
        try await script.complete(prompt: prompt, images: images, model: model)
    }
    let prior = generationRecord(xml: priorXML, cacheKey: "old")
    let result = await generator.generate(generationInput(priorRecord: prior))
    let record = try #require(result.record)

    #expect(record.xml.contains("id=\"stable\""))
    #expect(!record.xml.contains("id=\"writer-new\""))
    #expect(record.caughtUpAt == prior.caughtUpAt)
    #expect(record.caughtUpCursor == prior.caughtUpCursor)
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "session-map-generation-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SessionMapStore(directory: directory)
    try await store.save(record, sessionKey: "session")
    let loaded = try #require(try await store.load(sessionKey: "session"))
    _ = await generator.generate(generationInput(priorRecord: loaded, force: true, revision: 2))
    #expect(await script.prompts.last?.contains("id=\"stable\"") == true)
}

@Test func sessionMapGenerationUsesFactsFallbackWithoutFabricatedStatuses() async {
    let script = MapWriterScript(["bad", "still bad"])
    let generator = SessionMapGenerator { prompt, images, model in
        try await script.complete(prompt: prompt, images: images, model: model)
    }
    let result = await generator.generate(generationInput())

    #expect(result.disposition == .factsFallback)
    #expect(result.document?.graph.nodes.isEmpty == true)
    #expect(result.document?.blocks.contains { block in
        if case .stat(let fact, _, _, _) = block { return fact == "finishedTurns" }
        return false
    } == true)
}

@Test func sessionMapLateGenerationCannotOverwriteNewerCoverage() async {
    let writer = SuspendedMapWriter()
    let generator = SessionMapGenerator { prompt, images, model in
        await writer.complete(prompt: prompt, images: images, model: model)
    }
    let generation = Task { await generator.generate(generationInput(revision: 1)) }
    await writer.waitUntilStarted()
    await generator.invalidate(sessionKey: "session", lineage: "lineage", revision: 2)
    await writer.release()

    let result = await generation.value
    #expect(result.disposition == .obsolete)
    #expect(result.record == nil)
    #expect(result.document == nil)
}

@Test func sessionMapValidatedXMLSerializerRoundTripsDenseDocument() throws {
    let first = SessionMapDocumentParser.parse(
        Data(SessionMapFixtures.denseXML.utf8), context: SessionMapFixtures.context)
    let document = try #require(first.document)
    let xml = SessionMapXMLSerializer.serialize(
        document,
        facts: SessionMapFixtures.context.facts)
    let second = SessionMapDocumentParser.parse(
        Data(xml.utf8), context: SessionMapFixtures.context)

    #expect(second.fatal.isEmpty)
    #expect(second.document == document)
}

@MainActor
@Test func sessionMapManualActionsDistinguishCacheAwareUpdatesFromForcedRegeneration() {
    var requests: [(SessionMapGenerationScope, Bool)] = []
    let model = SessionMapPaneModel(onGenerate: { scope, force in
        requests.append((scope, force))
    })

    model.generate(.sinceCaughtUp)
    model.generate(.recentThreeTurns)
    model.regenerate(.wholeSession)

    #expect(requests.map(\.0) == [.sinceCaughtUp, .recentThreeTurns, .wholeSession])
    #expect(requests.map(\.1) == [false, false, true])
}

private func generationInput(
    priorRecord: SessionMapRecord? = nil,
    force: Bool = false,
    model: SessionMapResolvedModel = SessionMapResolvedModel(
        provider: "fixture", modelID: "writer", effort: "low", acceptsImages: false),
    revision: UInt64 = 1
) -> SessionMapGenerationInput {
    SessionMapGenerationInput(
        sessionKey: "session",
        lineage: "lineage",
        revision: revision,
        digest: SessionMapDigest(
            text: "Session delta\n[prompt] entry-1 | Build the map.\nFacts\n- finishedTurns: 1 number=1.0\n",
            hash: "digest",
            facts: ["finishedTurns": SessionMapFact(value: "1", number: 1)],
            knownRefs: ["entry-1"],
            cursor: SessionMapCursor(lineage: "lineage", entryID: "entry-1"),
            sourceFingerprintManifest: ["entry-1": "fingerprint"],
            statusEvidence: []),
        priorRecord: priorRecord,
        scope: .sinceCaughtUp,
        model: model,
        projectURL: URL(filePath: "/tmp/session-map-project", directoryHint: .isDirectory),
        force: force)
}

private func generationRecord(xml: String, cacheKey: String) -> SessionMapRecord {
    SessionMapRecord(
        xml: xml,
        cacheKey: cacheKey,
        generatedThrough: SessionMapCursor(lineage: "lineage", entryID: "entry-0"),
        sourceManifest: ["entry-0": "old"],
        caughtUpAt: Date(timeIntervalSince1970: 100),
        caughtUpCursor: SessionMapCursor(lineage: "lineage", entryID: "entry-0"),
        caughtUpGraph: nil,
        firstSeenOrder: ["stable"],
        updatedAt: Date(timeIntervalSince1970: 100),
        writerConfiguration: SessionMapResolvedModel(
            provider: "fixture", modelID: "writer", effort: "low", acceptsImages: false),
        checkerConfiguration: nil,
        checkOutcome: .off,
        dismissedThrough: nil)
}

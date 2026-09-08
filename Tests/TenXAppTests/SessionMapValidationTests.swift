import Foundation
import Testing
@testable import TenXApp

@Test func sessionMapRejectsEntitiesAndDuplicateIDs() {
    let entityXML = """
        <!DOCTYPE sessionmap [<!ENTITY note "unsafe">]>
        <sessionmap headline="Unsafe" phase="planning"><summary>&note;</summary></sessionmap>
        """
    let duplicateXML = """
        <sessionmap headline="Duplicate" phase="planning"><map>
        <node id="view" label="First" kind="view" status="planned"/>
        <node id="view" label="Second" kind="view" status="planned"/>
        </map></sessionmap>
        """

    #expect(SessionMapDocumentParser.parse(
        Data(entityXML.utf8), context: SessionMapFixtures.context
    ).document == nil)
    #expect(SessionMapDocumentParser.parse(
        Data(duplicateXML.utf8), context: SessionMapFixtures.context
    ).document == nil)
}

@Test func sessionMapDropsDanglingEdgesAndFalseFacts() throws {
    let xml = """
    <sessionmap headline="Request" phase="planning"><summary>A request.</summary>
    <map><node id="view" label="View" kind="view" status="planned"/>
    <edge from="view" to="missing" kind="flow"/></map>
    <stat fact="finishedTurns" label="Turns" value="999"/></sessionmap>
    """
    let result = SessionMapDocumentParser.parse(Data(xml.utf8), context: SessionMapFixtures.context)
    let document = try #require(result.document)
    #expect(document.graph.edges.isEmpty)
    #expect(document.blocks.isEmpty)
    #expect(!result.warnings.isEmpty)
}

@Test func sessionMapPreservesIDsAcrossReorderedXML() throws {
    let previous = try SessionMapFixtures.document(SessionMapFixtures.identityPreviousXML)
    let context = SessionMapValidationContext(
        knownRefs: ["u1"], facts: [:], previous: previous,
        projectURL: FileManager.default.temporaryDirectory
    )
    let result = SessionMapDocumentParser.parse(
        Data(SessionMapFixtures.identityReorderedXML.utf8), context: context
    )
    let document = try #require(result.document)

    #expect(document.graph.nodes.map(\.id) == ["service", "view"])
    #expect(document.graph.edges == [
        SessionMapEdge(from: "view", to: "service", kind: .flow, label: nil),
    ])
    #expect(document.flow?.steps.map(\.node) == ["view", "service"])
    #expect(document.plan?.tasks.map(\.node) == ["service"])
    #expect(SessionMapIdentity.structureSignature(document)
        == SessionMapIdentity.structureSignature(previous))
}

@Test func sessionMapRewireChangesStructureSignature() throws {
    let original = try SessionMapFixtures.document(SessionMapFixtures.identityPreviousXML)
    let rewiredXML = SessionMapFixtures.identityPreviousXML.replacingOccurrences(
        of: "kind=\"flow\"", with: "kind=\"depends\""
    )
    let rewired = try SessionMapFixtures.document(rewiredXML)

    #expect(original.graph.nodes.count == rewired.graph.nodes.count)
    #expect(original.graph.edges.count == rewired.graph.edges.count)
    #expect(SessionMapIdentity.structureSignature(original)
        != SessionMapIdentity.structureSignature(rewired))
}

@Test func sessionMapDoesNotMergeAmbiguousLabelsOrRestoreRemovedNodes() throws {
    let previous = try SessionMapFixtures.document(SessionMapFixtures.identityPreviousXML)
    let xml = """
        <sessionmap headline="Changed" phase="implementing"><summary>Changed.</summary><map>
        <node id="new-a" label="Repeated" kind="component" status="planned"/>
        <node id="new-b" label="Repeated" kind="component" status="planned"/>
        </map></sessionmap>
        """
    let context = SessionMapValidationContext(
        knownRefs: [], facts: [:], previous: previous, projectURL: nil
    )
    let result = SessionMapDocumentParser.parse(Data(xml.utf8), context: context)
    let document = try #require(result.document)

    #expect(document.graph.nodes.map(\.id) == ["new-a", "new-b"])
    #expect(!document.graph.nodes.map(\.id).contains("view"))
    #expect(result.warnings.contains { $0.code == "identityChurn" })
}

@Test func sessionMapEditCannotMarkDone() throws {
    let evidence = SessionMapStatusEvidence(
        sourceRef: "tool-1", status: .active,
        target: .file("App/RequestView.swift")
    )
    let context = SessionMapValidationContext(
        knownRefs: ["tool-1"], facts: [:], previous: nil,
        projectURL: FileManager.default.temporaryDirectory,
        statusEvidence: [evidence]
    )
    let xml = """
        <sessionmap headline="Edit" phase="implementing"><map>
        <node id="view" label="View" kind="view" file="App/RequestView.swift" status="done" ref="tool-1"/>
        </map></sessionmap>
        """
    let result = SessionMapDocumentParser.parse(Data(xml.utf8), context: context)
    let node = try #require(result.document?.graph.nodes.first)

    #expect(node.status == .planned)
    #expect(node.ref == nil)
    #expect(result.warnings.contains { $0.code == "unsupportedStatus" })
}

@Test func sessionMapPriorSupportedDoneSurvivesUnrelatedDelta() throws {
    let supported = SessionMapValidationContext(
        knownRefs: ["proof"], facts: [:], previous: nil, projectURL: nil,
        statusEvidence: [SessionMapStatusEvidence(
            sourceRef: "proof", status: .done, target: .label("View")
        )]
    )
    let xml = """
        <sessionmap headline="Done" phase="implementing"><map>
        <node id="view" label="View" kind="view" status="done" ref="proof"/>
        </map></sessionmap>
        """
    let previous = try #require(SessionMapDocumentParser.parse(
        Data(xml.utf8), context: supported
    ).document)
    let update = xml.replacingOccurrences(of: "ref=\"proof\"", with: "ref=\"new\"")
    let context = SessionMapValidationContext(
        knownRefs: ["new"], facts: [:], previous: previous, projectURL: nil
    )
    let result = SessionMapDocumentParser.parse(Data(update.utf8), context: context)
    let node = try #require(result.document?.graph.nodes.first)

    #expect(node.status == .done)
    #expect(node.ref == "proof")
    #expect(!result.warnings.contains { $0.code == "unsupportedStatus" })
}

@Test func sessionMapUnsupportedNewCompletionKeepsPriorStatus() throws {
    let previousXML = """
        <sessionmap headline="Plan" phase="planning"><map>
        <node id="view" label="View" kind="view" status="active" ref="u1"/>
        </map></sessionmap>
        """
    let previous = try SessionMapFixtures.document(previousXML)
    let update = previousXML
        .replacingOccurrences(of: "status=\"active\"", with: "status=\"failed\"")
        .replacingOccurrences(of: "ref=\"u1\"", with: "ref=\"tool-1\"")
    let context = SessionMapValidationContext(
        knownRefs: ["u1", "tool-1"], facts: [:], previous: previous, projectURL: nil
    )
    let result = SessionMapDocumentParser.parse(Data(update.utf8), context: context)
    let node = try #require(result.document?.graph.nodes.first)

    #expect(node.status == .active)
    #expect(node.ref == "u1")
    #expect(result.warnings.contains { $0.code == "unsupportedStatus" })
}

@Test func sessionMapFiltersOverCapsAndDependentReferences() throws {
    let nodes = (1...25).map { index in
        #"<node id="n\#(index)" label="Node \#(index)" kind="component" status="planned"/>"#
    }.joined()
    let xml = """
        <sessionmap headline="Bounded" phase="planning"><summary>Bounded.</summary><map>
        \(nodes)<edge from="n1" to="n25" kind="flow"/></map>
        <flow title="Flow"><step node="n25">Dropped.</step></flow>
        <plan title="Plan"><task status="todo" node="n25">Detached.</task></plan>
        </sessionmap>
        """
    let result = SessionMapDocumentParser.parse(Data(xml.utf8), context: SessionMapFixtures.context)
    let document = try #require(result.document)

    #expect(document.graph.nodes.count == 24)
    #expect(document.graph.edges.isEmpty)
    #expect(document.flow?.steps.isEmpty == true)
    #expect(document.plan?.tasks.first?.node == nil)
    #expect(result.warnings.contains { $0.code == "limitExceeded" })
    #expect(result.warnings.contains { $0.code == "danglingReference" })
}

@Test func sessionMapRejectsEscapingPathsAndInvalidStructure() throws {
    let xml = """
        <sessionmap headline="Paths" phase="planning"><summary>Paths.</summary><map>
        <node id="view" label="View" kind="view" file="../Outside.swift" status="planned"/>
        </map><files><file path="/tmp/Outside.swift" change="edited"/></files>
        <section title="Invalid"><row><text>Only one leaf.</text><row><text>Nested.</text><text>Row.</text></row></row></section>
        <unknown><stat fact="finishedTurns" label="Turns" value="1"/></unknown>
        </sessionmap>
        """
    let result = SessionMapDocumentParser.parse(Data(xml.utf8), context: SessionMapFixtures.context)
    let document = try #require(result.document)

    #expect(document.graph.nodes.first?.file == nil)
    #expect(document.blocks.count == 2)
    #expect(result.warnings.contains { $0.code == "danglingReference" })
    #expect(result.warnings.contains { $0.code == "limitExceeded" })
}

@Test func sessionMapEnforcesMultibyteXMLByteBoundary() {
    let prefix = "<sessionmap headline=\"Boundary\" phase=\"planning\"><summary>🙂</summary><!--"
    let suffix = "--></sessionmap>"
    let fillerCount = SessionMapLimits.xmlBytes - prefix.utf8.count - suffix.utf8.count
    let boundary = prefix + String(repeating: "x", count: fillerCount) + suffix
    let overBoundary = boundary + "x"

    #expect(Data(boundary.utf8).count == 65_536)
    #expect(SessionMapDocumentParser.parse(
        Data(boundary.utf8), context: SessionMapFixtures.context
    ).document != nil)
    let oversized = SessionMapDocumentParser.parse(
        Data(overBoundary.utf8), context: SessionMapFixtures.context
    )
    #expect(oversized.document == nil)
    #expect(oversized.fatal.map(\.code) == ["limitExceeded"])
}

@Test func sessionMapDropsNonfiniteChartNumbers() throws {
    let context = SessionMapValidationContext(
        knownRefs: [],
        facts: ["value": SessionMapFact(value: "nan", number: .nan)],
        previous: nil,
        projectURL: nil
    )
    let xml = """
        <sessionmap headline="Chart" phase="planning"><summary>Chart.</summary>
        <chart kind="line"><point fact="value" label="Value" value="nan"/></chart>
        </sessionmap>
        """
    let result = SessionMapDocumentParser.parse(Data(xml.utf8), context: context)
    let document = try #require(result.document)

    #expect(document.blocks == [.chart(kind: .line, points: [])])
    #expect(result.warnings.contains { $0.code == "factMismatch" })
}

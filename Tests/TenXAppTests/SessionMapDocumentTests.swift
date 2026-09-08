import Foundation
import Testing
@testable import TenXApp

@Test func sessionMapParsesGraphAndSupportingBlocks() throws {
    let result = SessionMapDocumentParser.parse(
        Data(SessionMapFixtures.chainXML.utf8), context: SessionMapFixtures.context)
    let document = try #require(result.document)
    #expect(document.graph.nodes.map(\.id) == ["view", "service"])
    #expect(document.graph.edges.count == 1)
    #expect(document.flow?.steps.count == 2)
    #expect(document.plan?.tasks.count == 1)
    #expect(document.blocks.count == 1)
    #expect(result.fatal.isEmpty)
}

@Test func sessionMapFixturesExerciseTheBoundedContract() throws {
    let planning = try SessionMapFixtures.document(SessionMapFixtures.planningXML)
    let implementing = try SessionMapFixtures.document(SessionMapFixtures.implementingXML)
    let dense = try SessionMapFixtures.document(SessionMapFixtures.denseXML)
    let empty = try SessionMapFixtures.document(SessionMapFixtures.emptyXML)
    let supporting = try SessionMapFixtures.document(SessionMapFixtures.supportingXML)

    #expect(planning.phase == .planning)
    #expect(implementing.graph.nodes.map(\.id) == planning.graph.nodes.map(\.id))
    #expect(implementing.graph.nodes.first { $0.id == "document" }?.status == .done)
    #expect(dense.graph.nodes.count == 24)
    #expect(dense.graph.edges.count == 40)
    #expect(empty.graph.nodes.isEmpty)
    #expect(supporting.blocks.count == 6)
}

@Test func sessionMapRejectsDeclarationBearingXML() {
    let xml = """
        <!DOCTYPE sessionmap [<!ENTITY note "unsafe">]>
        <sessionmap headline="Unsafe" phase="planning"><summary>&note;</summary></sessionmap>
        """

    let result = SessionMapDocumentParser.parse(
        SessionMapFixtures.data(xml), context: SessionMapFixtures.context)

    #expect(result.document == nil)
    #expect(result.fatal.map(\.code) == ["xml-declaration-forbidden"])
}

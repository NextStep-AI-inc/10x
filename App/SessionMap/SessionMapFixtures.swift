import Foundation

enum SessionMapFixtures {
    static let context = SessionMapValidationContext(
        knownRefs: ["u1", "tool-1", "tool-2"],
        facts: [
            "finishedTurns": SessionMapFact(value: "1", number: 1),
            "filesChanged": SessionMapFact(value: "2", number: 2),
            "testsRun": SessionMapFact(value: "3", number: 3),
        ],
        previous: nil,
        projectURL: FileManager.default.temporaryDirectory
    )

    static let chainXML = """
        <sessionmap headline="Request path" phase="planning">
          <summary>Two components carry the request.</summary>
          <map>
            <node id="view" label="Request view" kind="view" status="planned" ref="u1"/>
            <node id="service" label="Service" kind="service" status="proposed" ref="u1"/>
            <edge from="view" to="service" kind="flow" label="request"/>
          </map>
          <flow title="Request"><step node="view">Enter the request.</step><step node="service">Handle it.</step></flow>
          <plan title="Build"><task status="todo" node="view">Build the view.</task></plan>
          <stat fact="finishedTurns" label="Finished turns" value="1"/>
        </sessionmap>
        """

    static let planningXML = """
        <sessionmap headline="Session map architecture" phase="planning">
          <summary>The pane reads a validated native document produced from bounded session context.</summary>
          <map>
            <node id="pane" label="Map pane" kind="view" status="planned" ref="u1">Displays the graph before supporting details.</node>
            <node id="source" label="Session source" kind="actor" status="exists" ref="u1">Collects installed transcript snapshots.</node>
            <node id="writer" label="Map writer" kind="service" status="proposed" ref="u1">Produces a bounded XML document.</node>
            <node id="document" label="Native map document" kind="component" status="planned" ref="u1">Carries graph and supporting blocks.</node>
            <edge from="source" to="writer" kind="data" label="bounded context"/>
            <edge from="writer" to="document" kind="flow" label="XML"/>
            <edge from="document" to="pane" kind="flow" label="native views"/>
          </map>
          <flow title="Create a map"><step node="source" ref="u1">Collect the current session context.</step><step node="writer" ref="u1">Write the document.</step><step node="document" ref="u1">Parse the typed content.</step><step node="pane" ref="u1">Display the map.</step></flow>
          <plan title="Implementation"><task status="todo" node="document" ref="u1">Define and validate the document contract.</task><task status="todo" node="pane" ref="u1">Lay out and render the graph.</task></plan>
          <callout title="Open decisions" tone="warn" ref="u1">Confirm the layout against dense labels and a compact window.</callout>
        </sessionmap>
        """

    static let implementingXML = """
        <sessionmap headline="Session map implementation" phase="implementing">
          <summary>The native document is complete and deterministic layout work is active.</summary>
          <map>
            <node id="pane" label="Map pane" kind="view" status="planned" ref="u1">Displays the graph before supporting details.</node>
            <node id="source" label="Session source" kind="actor" status="exists" ref="u1">Collects installed transcript snapshots.</node>
            <node id="writer" label="Map writer" kind="service" status="planned" ref="tool-1">Produces a bounded XML document.</node>
            <node id="document" label="Native map document" kind="component" status="done" ref="tool-2">Carries graph and supporting blocks.</node>
            <edge from="source" to="writer" kind="data" label="bounded context"/>
            <edge from="writer" to="document" kind="flow" label="XML"/>
            <edge from="document" to="pane" kind="flow" label="native views"/>
          </map>
          <flow title="Create a map"><step node="source" ref="u1">Collect the current session context.</step><step node="writer" ref="tool-1">Write the document.</step><step node="document" ref="tool-2">Parse the typed content.</step><step node="pane" ref="u1">Display the map.</step></flow>
          <plan title="Implementation"><task status="done" node="document" ref="tool-2">Define and validate the document contract.</task><task status="active" node="pane" ref="tool-1">Lay out and render the graph.</task></plan>
          <timeline><event time="Now" ref="tool-2" tone="good">The document parser passed its focused tests.</event></timeline>
        </sessionmap>
        """

    static let denseXML: String = {
        let nodes = (1...24).map { index in
            let id = String(format: "component-%02d", index)
            return #"<node id="\#(id)" label="Component \#(index) handles a deliberately long pipeline stage" kind="component" status="planned" ref="u1"/>"#
        }
        let chainEdges = (1...23).map { index in
            let from = String(format: "component-%02d", index)
            let to = String(format: "component-%02d", index + 1)
            return #"<edge from="\#(from)" to="\#(to)" kind="flow" label="continues to the next processing stage"/>"#
        }
        let crossEdges = (1...17).map { index in
            let from = String(format: "component-%02d", index)
            let to = String(format: "component-%02d", index + 2)
            return #"<edge from="\#(from)" to="\#(to)" kind="data" label="shares bounded session context"/>"#
        }
        return """
            <sessionmap headline="Dense session architecture" phase="mixed">
              <summary>Twenty-four components and forty connections exercise the accepted graph limits.</summary>
              <map>\((nodes + chainEdges + crossEdges).joined())</map>
            </sessionmap>
            """
    }()

    static let emptyXML = """
        <sessionmap headline="No mapped components" phase="planning">
          <summary>The current session has context but no architecture to display.</summary>
          <map></map>
        </sessionmap>
        """

    static let supportingXML = """
        <sessionmap headline="Supporting session details" phase="mixed">
          <summary>Compact details support the architecture.</summary>
          <map><node id="document" label="Map document" kind="component" status="active" ref="u1"/></map>
          <section title="Current work">
            <row>
              <text>The document parser handles bounded native content.</text>
              <stat fact="filesChanged" label="Files changed" value="2" tone="neutral"/>
              <chart kind="bar"><point fact="testsRun" label="Focused tests" value="3"/></chart>
            </row>
          </section>
          <timeline><event time="Earlier" ref="u1" tone="neutral">The document contract was approved.</event><event time="Now" ref="tool-1" tone="good">Parser work is active.</event></timeline>
          <files><file path="App/SessionMap/SessionMapDocument.swift" change="created">Defines the typed vocabulary.</file><file path="App/SessionMap/SessionMapDocumentParser.swift" change="edited">Parses bounded XML.</file></files>
          <checklist><item done="true">Define the graph vocabulary.</item><item done="false">Verify the native layout.</item></checklist>
          <callout title="Layout check" tone="warn" ref="u1">Dense labels still need native snapshot coverage.</callout>
          <next><step prompt="Show the dense graph layout.">Review the dense fixture.</step></next>
        </sessionmap>
        """

    static func data(_ xml: String) -> Data {
        Data(xml.utf8)
    }

    static func document(_ xml: String) throws -> SessionMapDocument {
        let validation = SessionMapDocumentParser.parse(data(xml), context: context)
        guard let document = validation.document else {
            throw SessionMapFixtureError.invalidDocument(validation.fatal)
        }
        return document
    }
}

private enum SessionMapFixtureError: Error {
    case invalidDocument([SessionMapDiagnostic])
}

import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func disclosureDefaultsMatchActivityStateAndKind() {
    let state = ToolDisclosureState()
    #expect(!state.isExpanded(for: tool(id: "read", name: "read", phase: .complete)))
    #expect(state.isExpanded(for: tool(id: "running", name: "bash", phase: .running)))
    #expect(state.isExpanded(for: tool(id: "failed", name: "bash", phase: .failed)))
    #expect(state.isExpanded(for: tool(id: "diff", name: "edit", phase: .complete)))
}

@Test func userDisclosureChoicePersistsAcrossPhaseChanges() {
    let state = ToolDisclosureState()
    let running = tool(id: "same", name: "bash", phase: .running)
    state.setExpanded(false, for: running)

    #expect(!state.isExpanded(for: running))
    #expect(!state.isExpanded(for: tool(id: "same", name: "bash", phase: .complete)))

    state.setExpanded(true, for: tool(id: "same", name: "bash", phase: .complete))
    #expect(state.isExpanded(for: tool(id: "same", name: "bash", phase: .complete)))
}

@Test func transcriptDisclosureCommandsAffectOnlyTheirIntendedRows() {
    let state = ToolDisclosureState()
    let complete = tool(id: "complete", name: "read", phase: .complete)
    let running = tool(id: "running", name: "bash", phase: .running)
    let failed = tool(id: "failed", name: "bash", phase: .failed)

    state.collapseAll(ids: [complete.id, running.id, failed.id])
    #expect(!state.isExpanded(for: running))
    #expect(!state.isExpanded(for: failed))

    state.expand(ids: [running.id, failed.id])
    #expect(!state.isExpanded(for: complete))
    #expect(state.isExpanded(for: running))
    #expect(state.isExpanded(for: failed))
}

@Test func boundedToolOutputOffersDisclosureOnlyWhenContentMayBeClipped() {
    #expect(!BoundedToolOutputView.shouldOfferDisclosure("one\ntwo", lineLimit: 3))
    #expect(BoundedToolOutputView.shouldOfferDisclosure(
        (1...13).map(String.init).joined(separator: "\n"),
        lineLimit: 12))
    #expect(BoundedToolOutputView.shouldOfferDisclosure(
        String(repeating: "wrapped output ", count: 80),
        lineLimit: 6))
}

private func tool(id: String, name: String, phase: ToolPhase) -> ToolPresentation {
    ToolPresentation(
        id: id,
        name: name,
        arguments: .object([:]),
        result: nil,
        phase: phase,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: phase == .running ? nil : Date(timeIntervalSince1970: 2))
}

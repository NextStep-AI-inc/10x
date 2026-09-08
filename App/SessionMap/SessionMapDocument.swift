import Foundation

struct SessionMapDocument: Equatable, Sendable {
    let headline: String
    let phase: SessionMapPhase
    let summary: String?
    let graph: SessionMapGraph
    let flow: SessionMapFlow?
    let plan: SessionMapPlan?
    let blocks: [SessionMapBlock]
}

enum SessionMapPhase: String, Equatable, Sendable {
    case planning
    case implementing
    case mixed
}

struct SessionMapGraph: Equatable, Sendable {
    let nodes: [SessionMapNode]
    let edges: [SessionMapEdge]
}

struct SessionMapNode: Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let kind: SessionMapNodeKind
    let file: String?
    let status: SessionMapNodeStatus
    let group: String?
    let ref: String?
    let note: String?
}

enum SessionMapNodeKind: String, Equatable, Sendable {
    case component
    case file
    case module
    case service
    case store
    case view
    case actor
    case external
    case concept
}

enum SessionMapNodeStatus: String, Equatable, Sendable {
    case exists
    case proposed
    case planned
    case active
    case done
    case failed
}

struct SessionMapEdge: Equatable, Sendable, Hashable {
    let from: String
    let to: String
    let kind: SessionMapEdgeKind
    let label: String?
}

enum SessionMapEdgeKind: String, Equatable, Sendable, Hashable {
    case depends
    case calls
    case data
    case flow
}

struct SessionMapFlow: Equatable, Sendable {
    let title: String
    let steps: [SessionMapFlowStep]
}

struct SessionMapFlowStep: Equatable, Sendable {
    let node: String
    let ref: String?
    let text: String
}

struct SessionMapPlan: Equatable, Sendable {
    let title: String
    let tasks: [SessionMapPlanTask]
}

struct SessionMapPlanTask: Equatable, Sendable {
    let status: SessionMapPlanTaskStatus
    let node: String?
    let ref: String?
    let text: String
}

enum SessionMapPlanTaskStatus: String, Equatable, Sendable {
    case todo
    case active
    case done
    case blocked
}

enum SessionMapTone: String, Equatable, Sendable {
    case neutral
    case good
    case warn
    case bad
}

indirect enum SessionMapBlock: Equatable, Sendable {
    case section(title: String, blocks: [SessionMapBlock])
    case row(blocks: [SessionMapBlock])
    case text(text: String)
    case stat(fact: String, label: String, value: String, tone: SessionMapTone)
    case timeline(events: [SessionMapTimelineEvent])
    case files(files: [SessionMapFile])
    case chart(kind: SessionMapChartKind, points: [SessionMapChartPoint])
    case checklist(items: [SessionMapChecklistItem])
    case callout(title: String, tone: SessionMapTone, ref: String?, text: String)
    case next(steps: [SessionMapNextStep])
}

struct SessionMapTimelineEvent: Equatable, Sendable {
    let time: String
    let ref: String?
    let tone: SessionMapTone
    let text: String
}

struct SessionMapFile: Equatable, Sendable {
    let path: String
    let change: SessionMapFileChange
    let note: String?
}

enum SessionMapFileChange: String, Equatable, Sendable {
    case edited
    case created
    case read
}

enum SessionMapChartKind: String, Equatable, Sendable {
    case bar
    case line
}

struct SessionMapChartPoint: Equatable, Sendable {
    let fact: String
    let label: String
    let value: Double
}

struct SessionMapChecklistItem: Equatable, Sendable {
    let done: Bool
    let text: String
}

struct SessionMapNextStep: Equatable, Sendable {
    let prompt: String
    let text: String
}

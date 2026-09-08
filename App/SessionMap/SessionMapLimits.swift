enum SessionMapLimits {
    static let xmlBytes = 64 * 1024
    static let xmlDepth = 5
    static let diagnosticDetail = 240

    static let headline = 90
    static let summary = 600
    static let nodeID = 64
    static let nodeLabel = 60
    static let nodeGroup = 40
    static let nodeNote = 240
    static let edgeLabel = 60
    static let title = 90
    static let stepText = 240
    static let taskText = 240
    static let text = 1_200
    static let statLabel = 60
    static let statValue = 24
    static let timelineText = 240
    static let fileNote = 240
    static let pointLabel = 60
    static let checklistText = 240
    static let calloutText = 400
    static let nextText = 240
    static let nextPrompt = 1_200

    static let nodes = 24
    static let edges = 40
    static let flowSteps = 12
    static let planTasks = 24
    static let blocks = 8
    static let rowLeaves = 3
    static let timelineEvents = 12
    static let files = 12
    static let chartPoints = 12
    static let checklistItems = 10
    static let nextSteps = 5

    static let promptTable = """
        | Part | Limit |
        | --- | ---: |
        | XML | \(xmlBytes) bytes |
        | Headline | \(headline) characters |
        | Summary | \(summary) characters |
        | Node ID | \(nodeID) characters |
        | Node label | \(nodeLabel) characters |
        | Node group | \(nodeGroup) characters |
        | Node note | \(nodeNote) characters |
        | Edge label | \(edgeLabel) characters |
        | Titles | \(title) characters |
        | Flow step text | \(stepText) characters |
        | Plan task text | \(taskText) characters |
        | Text block | \(text) characters |
        | Stat label | \(statLabel) characters |
        | Stat value | \(statValue) characters |
        | Nodes | \(nodes) |
        | Edges | \(edges) |
        | Flow steps | \(flowSteps) |
        | Plan tasks | \(planTasks) |
        | Supporting blocks | \(blocks) |
        | Row leaves | 2–\(rowLeaves) |
        | Timeline events | \(timelineEvents) |
        | Timeline event text | \(timelineText) characters |
        | Files | \(files) |
        | File note | \(fileNote) characters |
        | Chart points | \(chartPoints) |
        | Chart point label | \(pointLabel) characters |
        | Checklist items | \(checklistItems) |
        | Checklist item text | \(checklistText) characters |
        | Callout text | \(calloutText) characters |
        | Next steps | \(nextSteps) |
        | Next step text | \(nextText) characters |
        | Next step prompt | \(nextPrompt) characters |
        """
}

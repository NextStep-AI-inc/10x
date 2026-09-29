import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func toolBudgetBoundsNestedAndMediaPayloads() throws {
    let megabyte = String(repeating: "a", count: 1_024 * 1_024)
    let limitedScalar = ToolPayloadBudget.limit(.string(megabyte))
    #expect(Data(limitedScalar.stringValue!.utf8).count <= ToolPayloadBudget.Limits.scalarBytes)
    #expect(limitedScalar.stringValue!.contains("…") || isTruncationMarked(limitedScalar))

    var children: [JSONValue] = []
    children.reserveCapacity(10_000)
    for index in 0..<10_000 {
        children.append(.string("item-\(index)"))
    }
    let limitedArray = ToolPayloadBudget.limit(.array(children))
    guard case .array = limitedArray else {
        Issue.record("Root truncated arrays must stay arrays")
        return
    }
    #expect(arrayChildCount(limitedArray) <= ToolPayloadBudget.Limits.arrayChildren)
    #expect(isTruncationMarked(limitedArray))

    var nested = JSONValue.string("leaf")
    for _ in 0..<8 {
        nested = .object(["child": nested])
    }
    let limitedDepth = ToolPayloadBudget.limit(nested)
    #expect(containerDepth(limitedDepth) <= ToolPayloadBudget.Limits.containerDepth)
    #expect(isTruncationMarked(limitedDepth))

    let ompPhaseSnapshot = ompPhaseOnlyTodoSnapshot()
    let limitedOMP = ToolPayloadBudget.limit(ompPhaseSnapshot)
    guard let tasks = limitedOMP["details"]?.objectValue?["phases"]?.arrayValue?.first?
        .objectValue?["tasks"]?.arrayValue
    else {
        Issue.record("OMP phase-only todo snapshot should keep a tasks array at the depth limit")
        return
    }
    #expect(tasks.count == 2)
    #expect(tasks[0]["content"]?.stringValue == "Repair CLI parsing")
    #expect(tasks[0]["status"]?.stringValue == "completed")
    #expect(tasks[1]["content"]?.stringValue == "Verify output file")
    #expect(tasks[1]["status"]?.stringValue == "blocked")
    #expect(tasks[1]["blocker"]?.stringValue == "Waiting for fixture")
    #expect(limitedOMP["details"]?.objectValue?["phases"]?.arrayValue?.first?
        .objectValue?["name"]?.stringValue == "Implementation")

    let overLimit = JSONValue.object([
        "details": .object(["phases": .array([
            .object(["name": .string("Implementation"), "tasks": .array([
                .object(["payload": .object([
                    "content": .string("nested too deep"),
                    "status": .string("pending"),
                ])]),
            ])]),
        ])]),
    ])
    let limitedOver = ToolPayloadBudget.limit(overLimit)
    let nestedPayload = limitedOver["details"]?.objectValue?["phases"]?.arrayValue?.first?
        .objectValue?["tasks"]?.arrayValue?.first?.objectValue?["payload"]
    #expect(nestedPayload?.stringValue?.contains("depth limit") == true
        || isTruncationMarked(limitedOver))

    let oversizedMedia = String(repeating: "A", count: ToolPayloadBudget.Limits.inlineMediaBytes + 1)
    let mediaPayload = JSONValue.object([
        "content": .array([.object([
            "type": .string("image"),
            "mimeType": .string("image/png"),
            "name": .string("screenshot.png"),
            "data": .string(oversizedMedia),
        ])]),
    ])
    let limitedMedia = ToolPayloadBudget.limit(mediaPayload)
    let mediaBlock = limitedMedia["content"]?.arrayValue?.first
    let dataField = mediaBlock?["data"]?.stringValue ?? mediaBlock?["base64"]?.stringValue
    #expect(dataField != oversizedMedia)
    #expect(dataField?.contains("omitted") == true)
    #expect(dataField?.contains("KiB") == true)
    #expect(inlineMediaBytes(limitedMedia) <= ToolPayloadBudget.Limits.inlineMediaBytes)
}

@Test func toolBudgetPreservesSummaryKeysWhenTruncating() {
    let hugeContent = String(repeating: "z", count: 64 * 1_024)
    let payload = JSONValue.object([
        "path": .string("/tmp/App.swift"),
        "command": .string("swift test"),
        "content": .string(hugeContent),
        "noise": .array((0..<500).map { .string("fill-\($0)") }),
    ])
    let limited = ToolPayloadBudget.limit(payload)
    guard case .object(let object) = limited else {
        Issue.record("Expected object payload")
        return
    }
    #expect(object["path"]?.stringValue == "/tmp/App.swift")
    #expect(object["command"]?.stringValue == "swift test")
    #expect(isTruncationMarked(limited))
}

@Test func toolBudgetMarksExplicitTruncationMetadata() {
    let limited = ToolPayloadBudget.limit(.array((0..<64).map { .int($0) }))
    guard case .array(let values) = limited else {
        Issue.record("Truncated root arrays must remain arrays")
        return
    }
    #expect(values.count <= ToolPayloadBudget.Limits.arrayChildren)
    #expect(values.contains { ToolPayloadBudget.isTruncationMarker($0) })
}

@Test func toolBudgetNestedArraysRespectNodeCap() {
    let outer = (0..<32).map { row in
        JSONValue.array((0..<32).map { col in JSONValue.string("row-\(row)-\(col)") })
    }
    let limited = ToolPayloadBudget.limit(.array(outer))
    #expect(visitedNodeCount(limited) <= ToolPayloadBudget.Limits.totalNodes)
}

@Test func toolBudgetCapsLongObjectKeysAndMIMELabels() {
    let longKey = String(repeating: "k", count: 16_384)
    let longMIME = String(repeating: "m", count: 16_384)
    let oversized = String(repeating: "A", count: ToolPayloadBudget.Limits.inlineMediaBytes + 1)

    let limitedKeyPayload = ToolPayloadBudget.limit(.object([longKey: .string("value")]))
    guard case .object(let keyed) = limitedKeyPayload, let storedKey = keyed.keys.first else {
        Issue.record("Expected capped object key")
        return
    }
    #expect(Data(storedKey.utf8).count <= ToolPayloadBudget.Limits.scalarBytes)

    let limitedMedia = ToolPayloadBudget.limit(.object([
        "content": .array([.object([
            "type": .string("image"),
            "mimeType": .string(longMIME),
            "data": .string(oversized),
        ])]),
    ]))
    let placeholder = limitedMedia["content"]?.arrayValue?.first?["data"]?.stringValue
    guard let placeholder else {
        Issue.record("Expected capped media placeholder")
        return
    }
    #expect(Data(placeholder.utf8).count <= ToolPayloadBudget.Limits.scalarBytes)
}

@Test func toolBudgetRootArrayMarkerCountsSingleNodeAtNodeLimit() {
    var values: [JSONValue] = []
    values.reserveCapacity(33)
    for _ in 0..<30 {
        var object: [String: JSONValue] = [:]
        for index in 0..<7 {
            object["field-\(index)"] = .string("value")
        }
        values.append(.object(object))
    }
    var heavyObject: [String: JSONValue] = [:]
    for index in 0..<13 {
        heavyObject["field-\(index)"] = .string("value")
    }
    values.append(.object(heavyObject))
    values.append(.string("tail-31"))
    values.append(.string("tail-32"))

    let limited = ToolPayloadBudget.limit(.array(values))
    guard case .array(let kept) = limited else {
        Issue.record("Expected root array")
        return
    }
    #expect(kept.count <= ToolPayloadBudget.Limits.arrayChildren)
    #expect(isTruncationMarked(limited))
    #expect(visitedNodeCount(limited) <= ToolPayloadBudget.Limits.totalNodes)
}

@Test func toolBudgetRootArrayMarkerNearNodeLimitStillCountsMarker() {
    var values: [JSONValue] = []
    values.reserveCapacity(33)
    for _ in 0..<30 {
        var object: [String: JSONValue] = [:]
        for index in 0..<7 {
            object["field-\(index)"] = .string("value")
        }
        values.append(.object(object))
    }
    var lighterObject: [String: JSONValue] = [:]
    for index in 0..<12 {
        lighterObject["field-\(index)"] = .string("value")
    }
    values.append(.object(lighterObject))
    values.append(.string("tail-31"))
    values.append(.string("tail-32"))

    let limited = ToolPayloadBudget.limit(.array(values))
    guard case .array = limited else {
        Issue.record("Expected root array")
        return
    }
    #expect(visitedNodeCount(limited) <= ToolPayloadBudget.Limits.totalNodes)
}

@Test func toolBudgetThirtyThreeMatchArrayStaysArrayWithParentMetadata() {
    let matches = (0..<33).map { index in JSONValue.string("match-\(index)") }
    let limited = ToolPayloadBudget.limit(.object([
        "details": .object(["matches": .array(matches)]),
    ]))
    guard case .object(let root) = limited,
          case .object(let details) = root["details"],
          case .array(let kept) = details["matches"]
    else {
        Issue.record("Expected bounded matches array under details")
        return
    }
    #expect(kept.count == 32)
    #expect(details[ToolPayloadBudget.truncatedKey]?.boolValue == true)
    #expect(details[ToolPayloadBudget.omittedCountKey]?.intValue == 1)
}

// MARK: - Helpers

private func ompPhaseOnlyTodoSnapshot() -> JSONValue {
    .object(["details": .object(["phases": .array([
        .object(["name": .string("Implementation"), "tasks": .array([
            .object(["content": .string("Repair CLI parsing"), "status": .string("completed")]),
            .object([
                "content": .string("Verify output file"),
                "status": .string("blocked"),
                "blocker": .string("Waiting for fixture"),
            ]),
        ])]),
    ])])])
}

private func isTruncationMarked(_ value: JSONValue) -> Bool {
    if ToolPayloadBudget.isTruncationMarker(value) { return true }
    switch value {
    case .object(let object):
        if object[ToolPayloadBudget.truncatedKey]?.boolValue == true { return true }
        return object.values.contains { isTruncationMarked($0) }
    case .array(let values):
        return values.contains { isTruncationMarked($0) }
    case .string(let text):
        return text.contains("truncated") || text.contains("omitted") || text.contains("…")
    default:
        return false
    }
}

private func arrayChildCount(_ value: JSONValue) -> Int {
    switch value {
    case .array(let values):
        return values.count
    default:
        return 0
    }
}

private func containerDepth(_ value: JSONValue) -> Int {
    func depth(_ value: JSONValue, current: Int) -> Int {
        switch value {
        case .object(let object):
            let childDepth = object.values.map { depth($0, current: current + 1) }.max() ?? current
            return max(current, childDepth)
        case .array(let values):
            let childDepth = values.map { depth($0, current: current + 1) }.max() ?? current
            return max(current, childDepth)
        default:
            return current
        }
    }
    return depth(value, current: 0)
}

private func inlineMediaBytes(_ value: JSONValue) -> Int {
    var total = 0
    func visit(_ value: JSONValue) {
        switch value {
        case .object(let object):
            for (key, child) in object {
                if key == "data" || key == "base64", let text = child.stringValue {
                    total = max(total, text.utf8.count)
                }
                visit(child)
            }
        case .array(let values):
            values.forEach(visit)
        default:
            break
        }
    }
    visit(value)
    return total
}

private func visitedNodeCount(_ value: JSONValue) -> Int {
    var count = 0
    func visit(_ value: JSONValue) {
        count += 1
        switch value {
        case .object(let object):
            object.values.forEach(visit)
        case .array(let values):
            values.forEach(visit)
        default:
            break
        }
    }
    visit(value)
    return count
}

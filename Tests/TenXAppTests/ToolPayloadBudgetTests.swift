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
    #expect(arrayChildCount(limitedArray) <= ToolPayloadBudget.Limits.arrayChildren)
    #expect(isTruncationMarked(limitedArray))

    var nested = JSONValue.string("leaf")
    for _ in 0..<8 {
        nested = .object(["child": nested])
    }
    let limitedDepth = ToolPayloadBudget.limit(nested)
    #expect(containerDepth(limitedDepth) <= ToolPayloadBudget.Limits.containerDepth)

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
    #expect(isTruncationMarked(limited))
    if case .object(let object) = limited {
        #expect(object[ToolPayloadBudget.omittedCountKey]?.intValue != nil)
    }
}

@Test func toolBudgetNodeCapReturnsPlaceholder() {
    var nodes: [JSONValue] = []
    for index in 0..<512 {
        nodes.append(.object(["i": .int(index), "text": .string("v-\(index)")]))
    }
    let limited = ToolPayloadBudget.limit(.array(nodes))
    #expect(visitedNodeCount(limited) <= ToolPayloadBudget.Limits.totalNodes)
}

// MARK: - Helpers

private func isTruncationMarked(_ value: JSONValue) -> Bool {
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
    case .object(let object):
        if let items = object[ToolPayloadBudget.itemsKey]?.arrayValue { return items.count }
        return object.count
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

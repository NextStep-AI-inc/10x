import Testing
import OmpKit
@testable import TenXApp

struct RecordSettingEditorTests {
    @Test func textKindSerializesStrings() {
        let object = RecordSettingEditor.jsonObject(
            from: [RecordEntry(key: "task", value: "on")], kind: .text)
        #expect(object == .object(["task": .string("on")]))
    }

    @Test func numberKindSerializesNumbers() {
        let object = RecordSettingEditor.jsonObject(
            from: [RecordEntry(key: "openai", value: "4")], kind: .number)
        #expect(object == .object(["openai": .int(4)]))
    }

    @Test func stringListKindSerializesArrays() {
        let object = RecordSettingEditor.jsonObject(
            from: [RecordEntry(key: "default", value: "openai/gpt-4o-mini, google/*")], kind: .stringList)
        #expect(object == .object(["default": .array([.string("openai/gpt-4o-mini"), .string("google/*")])]))
    }

    @Test func emptyKeysAreDropped() {
        let object = RecordSettingEditor.jsonObject(
            from: [RecordEntry(key: "", value: "x")], kind: .text)
        #expect(object == .object([:]))
    }

    @Test func valueKindAssignments() {
        #expect(RecordSettingEditor.valueKind(for: "tools.approval") == .policy)
        #expect(RecordSettingEditor.valueKind(for: "providers.maxInFlightRequests") == .number)
        #expect(RecordSettingEditor.valueKind(for: "task.agentModelOverrides") == .model)
        #expect(RecordSettingEditor.valueKind(for: "retry.fallbackChains") == .stringList)
        #expect(RecordSettingEditor.valueKind(for: "modelTags") == .text)
        #expect(RecordSettingEditor.valueKind(for: "anything.else") == .text)
    }

    @Test func stringListEntriesJoinWithCommas() {
        let value: JSONValue = .object(["default": .array([.string("a"), .string("b")])])
        #expect(RecordSettingEditor.entries(from: value, kind: .stringList)
            == [RecordEntry(key: "default", value: "a, b")])
    }

    @Test func shouldResyncReturnsFalseForOwnSaveEcho() {
        let entries = RecordSettingEditor.entries(from: .object(["task": .string("on")]), kind: .text)
        let incoming = RecordSettingEditor.jsonObject(from: entries, kind: .text)
        #expect(!RecordSettingEditor.shouldResync(entries: entries, incoming: incoming, kind: .text))
    }

    @Test func shouldResyncReturnsTrueForExternalChange() {
        let entries = RecordSettingEditor.entries(from: .object(["task": .string("on")]), kind: .text)
        let incoming: JSONValue = .object(["task": .string("off")])
        #expect(RecordSettingEditor.shouldResync(entries: entries, incoming: incoming, kind: .text))
    }
}

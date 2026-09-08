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

    @Test func emptyValuesAreDropped() {
        let object = RecordSettingEditor.jsonObject(
            from: [RecordEntry(key: "task", value: "")], kind: .text)
        #expect(object == .object([:]))
    }

    @Test func renamingAKeyMovesTheValue() {
        var entries = RecordSettingEditor.entries(from: .object(["old": .string("on")]), kind: .text)
        entries[0].key = "renamed"
        let object = RecordSettingEditor.jsonObject(from: entries, kind: .text)
        #expect(object == .object(["renamed": .string("on")]))
        #expect(object["old"] == nil)
    }

    @Test func numberEntriesLoadFromIntAndDouble() {
        let value: JSONValue = .object(["openai": .int(4), "ratio": .double(4.5)])
        #expect(RecordSettingEditor.entries(from: value, kind: .number) == [
            RecordEntry(key: "openai", value: "4"),
            RecordEntry(key: "ratio", value: "4.5"),
        ])
    }

    @Test func invalidNumberBlocksSave() {
        #expect(RecordSettingEditor.validateSave(
            entries: [RecordEntry(key: "openai", value: "abc")], kind: .number) == .invalidNumber)
    }

    @Test func oversizedIntegerBlocksSave() {
        #expect(RecordSettingEditor.validateSave(
            entries: [RecordEntry(key: "openai", value: "1e20")], kind: .number) == .invalidNumber)
    }

    @Test func whitespaceOnlyKeyIsDropped() {
        let object = RecordSettingEditor.jsonObject(
            from: [RecordEntry(key: "   ", value: "on")], kind: .text)
        #expect(object == .object([:]))
    }

    @Test func duplicateKeysBlockSave() {
        #expect(RecordSettingEditor.validateSave(entries: [
            RecordEntry(key: "a", value: "1"),
            RecordEntry(key: "a", value: "2"),
        ], kind: .text) == .duplicateKeys)
    }

    @Test func stringListDropsEmptySegments() {
        let object = RecordSettingEditor.jsonObject(
            from: [RecordEntry(key: "default", value: "a, , b")], kind: .stringList)
        #expect(object == .object(["default": .array([.string("a"), .string("b")])]))
    }

    @Test func shouldResyncTreatsWholeDoubleAsInt() {
        let entries = RecordSettingEditor.entries(from: .object(["openai": .double(4.0)]), kind: .number)
        #expect(!RecordSettingEditor.shouldResync(
            entries: entries, incoming: .object(["openai": .double(4.0)]), kind: .number))
    }

    @Test func objectValueRoundTripsThroughTextKindEditor() {
        let incoming: JSONValue = .object([
            "default": .object([
                "name": .string("Default"),
                "color": .string("blue"),
                "hidden": .bool(false),
            ]),
        ])
        let entries = RecordSettingEditor.entries(from: incoming, kind: .text)
        let serialized = RecordSettingEditor.jsonObject(from: entries, kind: .text)
        #expect(serialized == incoming)
    }

    @Test func preservedRawDoesNotTriggerResyncWhenIncomingMatches() {
        let incoming: JSONValue = .object([
            "default": .object(["name": .string("Default")]),
        ])
        let entries = RecordSettingEditor.entries(from: incoming, kind: .text)
        #expect(!RecordSettingEditor.shouldResync(entries: entries, incoming: incoming, kind: .text))
    }
}

import Testing
import OmpKit
@testable import TenXApp

struct ObjectArraySettingEditorTests {
    @Test func roundTripsInterceptorPatterns() {
        let value: JSONValue = .array([
            .object(["pattern": .string("^\\s*cat\\s+"), "tool": .string("read"), "message": .string("Use read")]),
        ])
        let entries = ObjectArraySettingEditor.interceptorEntries(from: value)
        #expect(entries.count == 1)
        #expect(entries[0].pattern == "^\\s*cat\\s+")
        #expect(ObjectArraySettingEditor.jsonArray(from: entries, preserving: value) == value)
    }

    @Test func rejectsBadRegex() {
        #expect(ObjectArraySettingEditor.isValidPattern("[unclosed") == false)
        #expect(ObjectArraySettingEditor.isValidPattern("^ok$") == true)
    }

    @Test func shouldResyncReturnsFalseForOwnSaveEcho() {
        let original: JSONValue = .array([
            .object(["pattern": .string("^cat"), "tool": .string("read"), "message": .string("")]),
        ])
        let entries = ObjectArraySettingEditor.interceptorEntries(from: original)
        let incoming = ObjectArraySettingEditor.jsonArray(from: entries, preserving: original)
        #expect(!ObjectArraySettingEditor.shouldResync(entries: entries, incoming: incoming))
    }

    @Test func shouldResyncReturnsTrueForExternalChange() {
        let entries = ObjectArraySettingEditor.interceptorEntries(from: .array([
            .object(["pattern": .string("^cat"), "tool": .string("read"), "message": .string("")]),
        ]))
        let incoming: JSONValue = .array([
            .object(["pattern": .string("^dog"), "tool": .string("bash"), "message": .string("")]),
        ])
        #expect(ObjectArraySettingEditor.shouldResync(entries: entries, incoming: incoming))
    }

    @Test func malformedItemSurfacesAsUnrecognized() {
        let value: JSONValue = .array([
            .string("legacy"),
            .object(["pattern": .string("^ok"), "tool": .string("grep"), "message": .string("")]),
        ])
        let entries = ObjectArraySettingEditor.interceptorEntries(from: value)
        #expect(entries.count == 2)
        #expect(entries[0].isUnrecognized)
        #expect(entries[1].pattern == "^ok")
    }

    @Test func removingMalformedItemDeletesOnSave() {
        let value: JSONValue = .array([
            .string("legacy"),
            .object(["pattern": .string("^ok"), "tool": .string("grep"), "message": .string("")]),
        ])
        var entries = ObjectArraySettingEditor.interceptorEntries(from: value)
        entries.removeAll { $0.isUnrecognized }
        let saved = ObjectArraySettingEditor.jsonArray(from: entries, preserving: value)
        #expect(saved == .array([
            .object(["pattern": .string("^ok"), "tool": .string("grep"), "message": .string("")]),
        ]))
    }

    @Test func malformedItemsPreservedOnSaveWhenNotRemoved() {
        let value: JSONValue = .array([
            .string("legacy"),
            .object(["pattern": .string("^ok"), "tool": .string("grep"), "message": .string("")]),
        ])
        let entries = ObjectArraySettingEditor.interceptorEntries(from: value)
        let saved = ObjectArraySettingEditor.jsonArray(from: entries, preserving: value)
        #expect(saved == value)
    }

    @Test func canSaveReturnsFalseWhenInvalidPattern() {
        let entries = [
            InterceptorPatternEntry(pattern: "[unclosed", tool: "read", message: ""),
        ]
        #expect(!ObjectArraySettingEditor.canSave(entries: entries))
    }

    @Test func canSaveReturnsFalseWhenEmptyPattern() {
        let entries = [
            InterceptorPatternEntry(pattern: "", tool: "read", message: ""),
        ]
        #expect(!ObjectArraySettingEditor.canSave(entries: entries))
    }

    @Test func canSaveReturnsTrueWhenAllValid() {
        let entries = [
            InterceptorPatternEntry(pattern: "^cat", tool: "read", message: "Use read"),
        ]
        #expect(ObjectArraySettingEditor.canSave(entries: entries))
    }

    @Test func preservesFlagsAndExtrasOnSave() {
        let value: JSONValue = .array([
            .object([
                "pattern": .string("^cat"),
                "tool": .string("read"),
                "message": .string(""),
                "flags": .string("i"),
                "allowSubcommands": .bool(true),
            ]),
        ])
        var entries = ObjectArraySettingEditor.interceptorEntries(from: value)
        entries[0].pattern = "^dog"
        let saved = ObjectArraySettingEditor.jsonArray(from: entries, preserving: value)
        let object = saved.arrayValue?[0].objectValue
        #expect(object?["pattern"] == .string("^dog"))
        #expect(object?["flags"] == .string("i"))
        #expect(object?["allowSubcommands"] == .bool(true))
    }

    @Test func canSaveReturnsFalseForMixedValidAndInvalidEntries() {
        let entries = [
            InterceptorPatternEntry(pattern: "^ok", tool: "read", message: ""),
            InterceptorPatternEntry(pattern: "[unclosed", tool: "read", message: ""),
        ]
        #expect(!ObjectArraySettingEditor.canSave(entries: entries))
    }

    @Test func missingToolDefaultsToRead() {
        let value: JSONValue = .array([
            .object(["pattern": .string("^cat"), "message": .string("Use read")]),
        ])
        let entries = ObjectArraySettingEditor.interceptorEntries(from: value)
        #expect(entries[0].tool == "read")
    }

    @Test func shouldResyncReturnsFalseWhenExtrasPreserved() {
        let original: JSONValue = .array([
            .object([
                "pattern": .string("^cat"),
                "tool": .string("read"),
                "message": .string(""),
                "flags": .string("i"),
            ]),
        ])
        let entries = ObjectArraySettingEditor.interceptorEntries(from: original)
        let incoming = ObjectArraySettingEditor.jsonArray(from: entries, preserving: original)
        #expect(!ObjectArraySettingEditor.shouldResync(entries: entries, incoming: incoming))
    }
}

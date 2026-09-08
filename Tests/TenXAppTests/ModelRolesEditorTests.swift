import Testing
import OmpKit
@testable import TenXApp

struct ModelRolesEditorTests {
    @Test func entriesFollowKnownRoleOrderThenAlphabetical() {
        let value: JSONValue = .object([
            "vision": .string("anthropic/claude-opus-4-8:xhigh"),
            "plan": .string("anthropic/claude-fable-5:max"),
            "custom-role": .string("cursor/composer-2.5-fast"),
        ])
        let entries = ModelRolesEditor.entries(from: value)
        #expect(entries.map(\.role) == ["plan", "vision", "custom-role"])
    }

    @Test func unparseableValuesAreDroppedFromEditingButPreservedOnSave() {
        // A value that fails to parse stays in the record untouched.
        let value: JSONValue = .object([
            "plan": .string("anthropic/claude-fable-5:max"),
            "weird": .string("garbage"),
        ])
        var entries = ModelRolesEditor.entries(from: value)
        entries[0].value.effort = "high"
        let object = ModelRolesEditor.jsonObject(from: entries, preserving: value)
        #expect(object["plan"] == .string("anthropic/claude-fable-5:high"))
        #expect(object["weird"] == .string("garbage"))
    }

    @Test func catalogModelsBecomeOptions() {
        let models = [ComposerModelInfo(modelID: "composer-2.5-fast", name: "Composer 2.5 Fast",
                                        provider: "cursor", api: nil, thinkingEfforts: [], requiresEffort: false)]
        let options = ModelRolesEditor.modelOptions(from: models)
        #expect(options == [SettingOption("cursor/composer-2.5-fast", label: "Composer 2.5 Fast", detail: "cursor")])
    }

    @Test func removedParsedRoleIsDeletedOnSave() {
        let value: JSONValue = .object([
            "plan": .string("anthropic/claude-fable-5:max"),
            "vision": .string("anthropic/claude-opus-4-8:xhigh"),
        ])
        var entries = ModelRolesEditor.entries(from: value)
        entries.removeAll { $0.role == "vision" }
        let object = ModelRolesEditor.jsonObject(from: entries, preserving: value)
        #expect(object["vision"] == nil)
        #expect(object["plan"] == .string("anthropic/claude-fable-5:max"))
    }
}

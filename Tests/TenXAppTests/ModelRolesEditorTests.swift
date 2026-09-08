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

    @Test func unparseableValuesAreSurfacedAndPreservedOnSave() {
        let value: JSONValue = .object([
            "plan": .string("anthropic/claude-fable-5:max"),
            "weird": .string("garbage"),
        ])
        let entries = ModelRolesEditor.entries(from: value)
        #expect(entries.map(\.role) == ["plan", "weird"])
        #expect(entries.first { $0.role == "weird" }?.isUnrecognized == true)

        var editable = entries
        editable[0].value.effort = "high"
        let object = ModelRolesEditor.jsonObject(from: editable, preserving: value)
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

    @Test func removedUnrecognizedRoleIsDeletedOnSave() {
        let value: JSONValue = .object([
            "plan": .string("anthropic/claude-fable-5:max"),
            "weird": .string("garbage"),
        ])
        var entries = ModelRolesEditor.entries(from: value)
        entries.removeAll { $0.role == "weird" }
        let object = ModelRolesEditor.jsonObject(from: entries, preserving: value)
        #expect(object["weird"] == nil)
        #expect(object["plan"] == .string("anthropic/claude-fable-5:max"))
    }

    @Test func jsonObjectSkipsInvalidDraftEntries() {
        let value: JSONValue = .object([
            "plan": .string("anthropic/claude-fable-5:max"),
        ])
        let entries = [
            ModelRoleEntry(role: "plan", value: ModelRoleValue(provider: "anthropic", modelID: "claude-fable-5", effort: "max")),
            ModelRoleEntry(role: "vision", value: ModelRoleValue(provider: "", modelID: "", effort: nil)),
        ]
        #expect(ModelRolesEditor.hasInvalidDraft(entries: entries))
        let object = ModelRolesEditor.jsonObject(from: entries, preserving: value)
        #expect(object["plan"] == .string("anthropic/claude-fable-5:max"))
        #expect(object["vision"] == nil)
    }

    @Test func nonStringRoleValueRoundTripsByteIdentically() {
        let value: JSONValue = .object([
            "weird": .object(["provider": .string("openai"), "model": .string("gpt-4")]),
        ])
        let entries = ModelRolesEditor.entries(from: value)
        #expect(entries.first { $0.role == "weird" }?.isUnrecognized == true)
        let object = ModelRolesEditor.jsonObject(from: entries, preserving: value)
        #expect(object == value)
    }

    @Test func catalogNonThinkingModelHasNoEffortOptions() {
        let models = [ComposerModelInfo(modelID: "composer-2.5-fast", name: "Composer 2.5 Fast",
                                        provider: "cursor", api: nil, thinkingEfforts: [], requiresEffort: false)]
        let value = ModelRoleValue(provider: "cursor", modelID: "composer-2.5-fast", effort: nil)
        #expect(ModelRolesEditor.effortOptions(for: value, catalog: models).isEmpty)
        #expect(!ModelRolesEditor.showsEffortDropdown(for: value, catalog: models))
    }

    @Test func unknownModelFallsBackToStandardEfforts() {
        let value = ModelRoleValue(provider: "custom", modelID: "mystery", effort: nil)
        #expect(ModelRolesEditor.effortOptions(for: value, catalog: []).map(\.value) == ModelRoleValue.efforts)
    }

    @Test func existingEffortSuffixShowsPickerForNonThinkingCatalogModel() {
        let models = [ComposerModelInfo(modelID: "composer-2.5-fast", name: "Composer 2.5 Fast",
                                        provider: "cursor", api: nil, thinkingEfforts: [], requiresEffort: false)]
        let value = ModelRoleValue(provider: "cursor", modelID: "composer-2.5-fast", effort: "high")
        #expect(ModelRolesEditor.showsEffortDropdown(for: value, catalog: models))
    }

    @Test func shouldResyncReturnsFalseForOwnSaveEcho() {
        let entries = ModelRolesEditor.entries(from: .object([
            "plan": .string("anthropic/claude-fable-5:max"),
        ]))
        let incoming = ModelRolesEditor.jsonObject(from: entries, preserving: .object([:]))
        #expect(!ModelRolesEditor.shouldResync(entries: entries, incoming: incoming))
    }

    @Test func shouldResyncReturnsTrueForExternalChange() {
        let entries = ModelRolesEditor.entries(from: .object([
            "plan": .string("anthropic/claude-fable-5:max"),
        ]))
        let incoming: JSONValue = .object([
            "plan": .string("cursor/composer-2.5-fast"),
        ])
        #expect(ModelRolesEditor.shouldResync(entries: entries, incoming: incoming))
    }
}

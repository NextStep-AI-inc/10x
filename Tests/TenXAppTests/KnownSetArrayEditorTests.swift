import Testing
import OmpKit
@testable import TenXApp

struct KnownSetArrayEditorTests {
    @Test func remainingValuesExcludeCurrentItems() {
        let remaining = KnownSetArrayEditor.remaining(known: ["a", "b", "c"], items: ["b"])
        #expect(remaining == ["a", "c"])
    }

    @Test func moveUpSwapsNeighbors() {
        #expect(KnownSetArrayEditor.movingUp(["a", "b", "c"], index: 1) == ["b", "a", "c"])
        #expect(KnownSetArrayEditor.movingUp(["a", "b"], index: 0) == ["a", "b"])
    }

    @Test func movingUpIgnoresOutOfBoundsAndEmptyArray() {
        #expect(KnownSetArrayEditor.movingUp([], index: 0) == [])
        #expect(KnownSetArrayEditor.movingUp(["a"], index: 1) == ["a"])
        #expect(KnownSetArrayEditor.movingUp(["a", "b"], index: 2) == ["a", "b"])
    }

    @Test func serializesToStringArray() {
        #expect(KnownSetArrayEditor.jsonArray(from: ["smol", "default"])
            == .array([.string("smol"), .string("default")]))
    }

    @Test func catalogValuesAreSelectors() {
        let models = [ComposerModelInfo(modelID: "m1", name: "M1", provider: "p1",
                                        api: nil, thinkingEfforts: [], requiresEffort: false),
                      ComposerModelInfo(modelID: "m2", name: "M2", provider: "p2",
                                        api: nil, thinkingEfforts: [], requiresEffort: false)]
        #expect(KnownSetArrayEditor.modelSelectors(from: models) == ["p1/m1", "p2/m2"])
        #expect(KnownSetArrayEditor.providerIDs(from: models) == ["p1", "p2"])
    }

    @Test func providerIDsAreUniqueWhenModelsShareProvider() {
        let models = [ComposerModelInfo(modelID: "m1", name: "M1", provider: "p1",
                                        api: nil, thinkingEfforts: [], requiresEffort: false),
                      ComposerModelInfo(modelID: "m2", name: "M2", provider: "p1",
                                        api: nil, thinkingEfforts: [], requiresEffort: false)]
        #expect(KnownSetArrayEditor.providerIDs(from: models) == ["p1"])
    }

    @Test func catalogValuesRoutesKeysCorrectly() {
        let models = [ComposerModelInfo(modelID: "m1", name: "M1", provider: "p1",
                                        api: nil, thinkingEfforts: [], requiresEffort: false),
                      ComposerModelInfo(modelID: "m2", name: "M2", provider: "p2",
                                        api: nil, thinkingEfforts: [], requiresEffort: false)]
        #expect(KnownSetArrayEditor.catalogValues(for: "enabledModels", models: models)
            == ["p1/m1", "p2/m2"])
        #expect(KnownSetArrayEditor.catalogValues(for: "modelProviderOrder", models: models)
            == ["p1", "p2"])
        #expect(KnownSetArrayEditor.catalogValues(for: "enabledProviders", models: models)
            == ["p1", "p2"])
        #expect(KnownSetArrayEditor.catalogValues(for: "disabledProviders", models: models)
            == ["p1", "p2"])
    }

    @Test func shouldResyncReturnsFalseForOwnSaveEcho() {
        let items = ["smol", "default"]
        let incoming = KnownSetArrayEditor.jsonArray(from: items)
        #expect(!KnownSetArrayEditor.shouldResync(items: items, incoming: incoming))
    }

    @Test func shouldResyncReturnsTrueForExternalChange() {
        let items = ["smol", "default"]
        let incoming: JSONValue = .array([.string("plan"), .string("default")])
        #expect(KnownSetArrayEditor.shouldResync(items: items, incoming: incoming))
    }

    @Test func shouldResyncTreatsNilIncomingAsEmptyArray() {
        #expect(KnownSetArrayEditor.shouldResync(items: ["a"], incoming: nil))
    }

    @Test func appendingIgnoresDuplicatesAndEmptyValues() {
        #expect(KnownSetArrayEditor.appending(items: ["a"], value: "a") == ["a"])
        #expect(KnownSetArrayEditor.appending(items: ["a"], value: "b") == ["a", "b"])
        #expect(KnownSetArrayEditor.appending(items: ["a"], value: "") == ["a"])
        #expect(KnownSetArrayEditor.appending(items: ["a"], value: "   ") == ["a"])
    }
}

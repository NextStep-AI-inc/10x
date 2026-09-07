import OmpKit
import Testing
@testable import TenXApp

struct SettingsCatalogMetadataTests {
    private func entry(_ key: String, type: String = "enum", description: String = "") -> JSONValue {
        .object(["value": .string("x"), "type": .string(type), "description": .string(description)])
    }

    @Test func curatedEnumOptionsAttachToDefinition() {
        let catalog = SettingsCatalog.build(from: .object(["followUpMode": entry("followUpMode")]))
        #expect(catalog.definition(key: "followUpMode")?.enumOptions.map(\.value) == ["all", "one-at-a-time"])
    }

    @Test func uncuratedEnumGetsNoOptions() {
        let catalog = SettingsCatalog.build(from: .object(["some.unknownEnum": entry("some.unknownEnum")]))
        #expect(catalog.definition(key: "some.unknownEnum")?.enumOptions == [])
    }

    @Test func runtimeDescriptionWinsOverCurated() {
        let catalog = SettingsCatalog.build(from: .object(["modelRoles": entry("modelRoles", type: "record", description: "OMP text")]))
        #expect(catalog.definition(key: "modelRoles")?.description == "OMP text")
    }

    @Test func curatedDescriptionFillsGap() {
        // Requires "modelRoles" to have a hand-written entry in SettingMetadata.descriptions (Task 11).
        let catalog = SettingsCatalog.build(from: .object(["modelRoles": entry("modelRoles", type: "record")]))
        #expect(catalog.definition(key: "modelRoles")?.description.isEmpty == false)
    }
}

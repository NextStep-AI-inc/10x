import OmpKit
import Testing
@testable import TenXApp

struct SettingsCatalogMetadataTests {
    private func entry(type: String = "enum", description: String = "") -> JSONValue {
        .object(["value": .string("x"), "type": .string(type), "description": .string(description)])
    }

    @Test func curatedEnumOptionsAttachToDefinition() {
        let catalog = SettingsCatalog.build(from: .object(["followUpMode": entry()]))
        #expect(catalog.definition(key: "followUpMode")?.enumOptions.map(\.value) == ["all", "one-at-a-time"])
    }

    @Test func uncuratedEnumGetsNoOptions() {
        let catalog = SettingsCatalog.build(from: .object(["some.unknownEnum": entry()]))
        #expect(catalog.definition(key: "some.unknownEnum")?.enumOptions == [])
    }

    @Test func runtimeDescriptionWinsOverCurated() {
        let catalog = SettingsCatalog.build(from: .object(["modelRoles": entry(type: "record", description: "OMP text")]))
        #expect(catalog.definition(key: "modelRoles")?.description == "OMP text")
    }

    // Task 11: remove .disabled once SettingMetadata.descriptions is populated.
    @Test(.disabled("Task 11 fills SettingMetadata.descriptions"))
    func curatedDescriptionFillsGap() {
        let catalog = SettingsCatalog.build(from: .object(["modelRoles": entry(type: "record")]))
        #expect(catalog.definition(key: "modelRoles")?.description.isEmpty == false)
    }
}

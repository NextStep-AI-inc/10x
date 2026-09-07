import Testing
@testable import TenXApp

struct EnumPresentationTests {
    private let options = [
        SettingOption("always-ask", label: "Always ask", detail: "read-only auto-approved"),
        SettingOption("write", label: "Write"),
        SettingOption("yolo", label: "Yolo"),
    ]

    @Test func knownValueHasNoCustomMarker() {
        let p = EnumPresentation(options: options, currentValue: "write")
        #expect(p.customValue == nil)
        #expect(p.displayText(for: "write") == "Write")
    }

    @Test func unknownValueSurfacesAsCustom() {
        let p = EnumPresentation(options: options, currentValue: "ultra")
        #expect(p.customValue == "ultra")
        #expect(p.displayText(for: "ultra") == "ultra")
    }

    @Test func emptyValueIsNotCustom() {
        #expect(EnumPresentation(options: options, currentValue: "").customValue == nil)
    }
}

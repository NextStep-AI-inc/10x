import Foundation
import Testing
@testable import TenXApp

@MainActor
@Test func preferredIDERowSearchMatchesItsContentAndSelectedApplication() {
    #expect(PreferredIDESettingRowView.matches(query: "", applicationName: nil))
    #expect(PreferredIDESettingRowView.matches(query: "preferred", applicationName: nil))
    #expect(PreferredIDESettingRowView.matches(query: "editor", applicationName: nil))
    #expect(PreferredIDESettingRowView.matches(query: "Missing IDE", applicationName: "Missing IDE"))
    #expect(!PreferredIDESettingRowView.matches(query: "unrelated", applicationName: "Cursor"))
    #expect(PreferredIDESettingRowView.matches(query: "Cursor", applicationName: "Cursor"))
}

@Test func preferredIDERowMatcherCanRunOutsideTheMainActor() async {
    let matchesEditor = await Task.detached {
        PreferredIDESettingRowView.matches(query: "editor", applicationName: nil)
    }.value

    #expect(matchesEditor)
}

@MainActor
@Test func preferredIDERowUsesExactStateLabels() {
    let cursor = IDEApplication(
        displayName: "Cursor",
        url: URL(filePath: "/Applications/Cursor.app"),
        source: .custom)

    #expect(PreferredIDESettingRowView.valueLabel(for: .none) == "Choose IDE")
    #expect(PreferredIDESettingRowView.valueLabel(for: .available(cursor)) == "Cursor")
    #expect(PreferredIDESettingRowView.valueLabel(for: .unavailable(displayName: "Cursor")) == "Cursor · Unavailable")
}

import Testing
@testable import TenXApp

@MainActor
@Test func openSettingsSelectsSettingsRoute() {
    let model = AppModel()

    model.openSettings()

    #expect(model.route == .settings)
}

@MainActor
@Test func chooseIDESelectsSettingsAndRequestsPreferredIDEFocus() {
    let model = AppModel()

    model.openSettings(focus: .preferredIDE)

    #expect(model.route == .settings)
    #expect(model.settingsFocusTarget == .preferredIDE)
    model.consumeSettingsFocus()
    #expect(model.settingsFocusTarget == nil)
}

@MainActor
@Test func openNewSessionSelectsNewSessionRoute() {
    let model = AppModel()
    model.route = .settings

    model.openNewSession()

    #expect(model.route == .newSession)
}

@MainActor
@Test func openSearchPresentsSearchWithoutChangingRoute() {
    let model = AppModel()
    model.route = .session("/tmp/session.jsonl")

    model.openSearch()

    #expect(model.isSearchPresented)
    #expect(model.route == .session("/tmp/session.jsonl"))
}

import Foundation
import Testing
@testable import TenXApp

@Suite @MainActor struct SettingsOwnershipTests {
    @Test func nativeSearchFindsOnlyMatchingOwnedCategories() {
        let composerMatches = TenXSettingsCategory.allCases.filter {
            $0.matches(query: "Command-Enter", preferredIDEName: nil)
        }
        let ideMatches = TenXSettingsCategory.allCases.filter {
            $0.matches(query: "Cursor", preferredIDEName: "Cursor")
        }

        #expect(composerMatches == [.composer])
        #expect(ideMatches == [.general])

        let hiddenMatches = TenXSettingsCategory.allCases.filter {
            $0.matches(query: "hidden", preferredIDEName: nil)
        }
        let noticeMatches = TenXSettingsCategory.allCases.filter {
            $0.matches(query: "notice", preferredIDEName: nil)
        }
        #expect(hiddenMatches == [.general])
        #expect(noticeMatches == [.general])
    }

    @Test func preferredIDEFocusClearsSearchForNativeNavigation() {
        let model = SettingsViewModel(service: OmpConfigService(runner: FailingSettingsRunner()))
        model.query = "shell"

        #expect(model.prepareForFocus(.preferredIDE))
        #expect(model.query.isEmpty)
    }

    @Test func nativeCategoriesRemainAvailableWhenOMPLoadFails() async {
        let model = SettingsViewModel(service: OmpConfigService(runner: FailingSettingsRunner()))

        #expect(await model.load() == false)
        #expect(model.settingCount == 0)
        #expect(model.loadError != nil)
        #expect(TenXSettingsCategory.allCases == [.general, .composer, .computerUse])
    }
}

private struct FailingSettingsRunner: OmpConfigRunning {
    func run(arguments: [String]) async throws -> Data {
        throw FailingSettingsError()
    }
}

private struct FailingSettingsError: Error {}

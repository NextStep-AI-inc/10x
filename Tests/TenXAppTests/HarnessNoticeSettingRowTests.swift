import Testing
@testable import TenXApp

@Test func harnessNoticeRowSearchMatching() {
    #expect(HarnessNoticeSettingRowView.matches(query: ""))
    #expect(HarnessNoticeSettingRowView.matches(query: "  hidden  "))
    #expect(HarnessNoticeSettingRowView.matches(query: "notice"))
    #expect(HarnessNoticeSettingRowView.matches(query: "threshold"))
    #expect(HarnessNoticeSettingRowView.matches(query: "summary"))
    #expect(!HarnessNoticeSettingRowView.matches(query: "proxy"))
}

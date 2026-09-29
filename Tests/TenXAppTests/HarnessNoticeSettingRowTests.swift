import Testing
@testable import TenXApp

@Test func harnessNoticeRowSearchMatching() {
    #expect(HarnessNoticeSettingRowView.matches(query: ""))
    #expect(HarnessNoticeSettingRowView.matches(query: "  agent guidance  "))
    #expect(HarnessNoticeSettingRowView.matches(query: "advisor"))
    #expect(HarnessNoticeSettingRowView.matches(query: "internal instructions"))
    #expect(HarnessNoticeSettingRowView.matches(query: "Show compact advisor notes"))
    #expect(!HarnessNoticeSettingRowView.matches(query: "threshold"))
    #expect(!HarnessNoticeSettingRowView.matches(query: "summary model"))
    #expect(!HarnessNoticeSettingRowView.matches(query: "proxy"))
}

@Test func harnessNoticeSettingUsesApprovedCopy() {
    #expect(HarnessNoticeSettingRowView.title == "Show agent guidance")
    #expect(HarnessNoticeSettingRowView.supportingText ==
        "Show compact advisor notes, internal instructions, and extra activity in the transcript.")
}

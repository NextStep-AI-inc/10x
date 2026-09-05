import Testing
@testable import TenXApp

@Test func questionSubmissionRejectsDuplicatesAndAllowsRetryAfterFailure() {
    var state = ExtensionQuestionSubmissionState()

    let firstAttempt = state.begin()
    let duplicateAttempt = state.begin()
    #expect(firstAttempt)
    #expect(!duplicateAttempt)
    state.finish(succeeded: false)
    #expect(state.errorMessage == "Couldn’t send response. Try again.")
    let retryAttempt = state.begin()
    #expect(retryAttempt)
    state.finish(succeeded: true)
    let attemptAfterSuccess = state.begin()
    #expect(!attemptAfterSuccess)
}

@Test func multilineOptionUsesItsFirstLineAsTitleWithoutChangingTheResponseValue() {
    let option = ExtensionSelectOption(
        label: "Use the existing parser\nKeeps behavior consistent with imported sessions.",
        detail: nil)

    let presentation = ExtensionQuestionOptionPresentation(option: option)

    #expect(presentation.title == "Use the existing parser")
    #expect(presentation.detail == "Keeps behavior consistent with imported sessions.")
    #expect(presentation.responseValue == option.label)
}

@Test func structuredOptionDetailTakesPriorityOverAnEmbeddedExplanation() {
    let option = ExtensionSelectOption(
        label: "Use the existing parser\nEmbedded explanation",
        detail: "The server-provided justification")

    let presentation = ExtensionQuestionOptionPresentation(option: option)

    #expect(presentation.title == "Use the existing parser")
    #expect(presentation.detail == "The server-provided justification")
    #expect(presentation.responseValue == option.label)
}

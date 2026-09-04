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

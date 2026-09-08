import Testing
@testable import TenXApp

private let computerUseInstruction =
    "Use the computer for this task. Claim a window with computer_claim (or launch one with computer_launch), work there, and keep computer_status updated so I can follow along."

@Test func computerUsePromptWrapsTaskText() {
    #expect(ComputerUsePrompt.wrap("check my email")
        == "\(computerUseInstruction)\n\nTask: check my email")
}

@Test func computerUsePromptWithoutTaskReturnsInstructionOnly() {
    #expect(ComputerUsePrompt.wrap("") == computerUseInstruction)
    #expect(ComputerUsePrompt.wrap("   \n  ") == computerUseInstruction)
}

@Test func computerUsePromptPreservesMultilineTaskText() {
    let task = "line one\nline two"
    #expect(ComputerUsePrompt.wrap(task)
        == "\(computerUseInstruction)\n\nTask: line one\nline two")
}

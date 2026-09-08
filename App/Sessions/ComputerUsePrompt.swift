import Foundation

enum ComputerUsePrompt {
    private static let instruction =
        "Use the computer for this task. Claim a window with computer_claim (or launch one with computer_launch), work there, and keep computer_status updated so I can follow along."

    static func wrap(_ task: String) -> String {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return instruction }
        return "\(instruction)\n\nTask: \(trimmed)"
    }
}

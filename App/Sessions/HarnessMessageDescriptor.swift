/// A harness message the transcript gate kept out of the conversation —
/// developer instruction walls, display:false steering customs, or a role a
/// future omp adds. Collected so the UI can notice the drop instead of
/// staying silent.
struct HarnessMessageDescriptor: Equatable, Sendable {
    let role: String?
    let customType: String?
    /// Character count of the extracted text — what the threshold compares against.
    let byteCount: Int
    let text: String

    /// Dedup key: identical content hidden twice (message_start + message_end,
    /// or repeated nudges) is one notice.
    var signature: String {
        "\(role ?? "")\u{0}\(customType ?? "")\u{0}\(text)"
    }

    /// Human-facing kind for the notice label: "nudge", "developer", "unknown".
    var kindLabel: String {
        customType ?? role ?? "unknown"
    }
}

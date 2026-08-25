enum ApprovalAccessibility {
    static func actionLabel(name: String, scope: String) -> String {
        [name, scope].joined(separator: ", ")
    }
}

import AppKit

@MainActor
final class AgentDesktopProbeWindow {
    struct Target: Sendable {
        let windowID: String
        let verificationText: String
    }

    private(set) var window: NSPanel
    private let field: NSTextField

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 96),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        let field = NSTextField(string: "10x Agent Desktop probe")
        field.frame = NSRect(x: 20, y: 30, width: 280, height: 24)
        field.isEditable = true
        field.setAccessibilityLabel("Probe text")
        panel.identifier = NSUserInterfaceItemIdentifier("tenx-agent-desktop-probe")
        panel.contentView?.addSubview(field)
        window = panel
        self.field = field
    }

    func open() throws -> Target {
        let verificationText = "10x-probe-\(UUID().uuidString.lowercased())"
        field.stringValue = verificationText
        window.level = .normal
        window.collectionBehavior = [.transient]
        window.orderBack(nil)
        let windowID = String(window.windowNumber)
        guard !windowID.isEmpty, window.windowNumber > 0 else {
            throw AgentDesktopProviderError.probeFailed(.background)
        }
        return Target(windowID: windowID, verificationText: verificationText)
    }

    func close() { window.close() }
}

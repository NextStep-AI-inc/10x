import SwiftUI

struct ComputerUseMenuBarView: View {
    let phase: ComputerUsePhase
    let onStop: () -> Void

    var body: some View {
        Text(status)
        Divider()
        Button("Stop Computer", action: onStop)
            .accessibilityLabel("Stop computer control for this session")
    }

    private var status: String {
        switch phase {
        case .off: "Computer: Off"
        case .preparing: "Computer: Preparing"
        case .ready: "Computer: Ready"
        case .controlling(let target): "Controlling: \(target)"
        case .needsHandoff(let target, _): "Needs handoff: \(target)"
        case .unavailable: "Computer: Unavailable"
        case .stopping: "Computer: Stopping"
        }
    }
}

import SwiftUI

struct ComputerUseMenuBarView: View {
    let client: SupervisionClient

    var body: some View {
        if client.hasAnyActivity {
            Text("Computer use active")
        } else {
            Text("No windows in use")
        }
        Divider()
        Button("Stop All Computer Use") { client.stopAll() }
            .accessibilityLabel("Stop all computer use, all apps")
    }
}

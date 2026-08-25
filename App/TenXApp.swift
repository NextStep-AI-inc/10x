import SwiftUI

@main
struct TenXApp: App {
    var body: some Scene {
        WindowGroup {
            Text("10x")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
    }
}

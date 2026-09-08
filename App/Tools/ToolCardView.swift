import SwiftUI

struct ToolCardView: View, Equatable {
    let presentation: ToolPresentation

    var body: some View {
        ToolCardScaffold(
            presentation: presentation,
            cardContent: presentation.content
        ) {
            ToolSurfaceView(body: presentation.content.body)
        }
    }
}

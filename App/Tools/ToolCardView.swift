import SwiftUI

struct ToolCardView: View {
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

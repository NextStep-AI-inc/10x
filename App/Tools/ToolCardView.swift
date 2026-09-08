import SwiftUI

struct ToolCardView: View, Equatable {
    let presentation: ToolPresentation

    var body: some View {
        ToolCardScaffold(
            presentation: presentation,
            cardContent: presentation.content
        ) {
            ToolSurfaceView(
                body: presentation.content.body,
                phase: presentation.phase,
                topFilePath: topFilePath)
        }
    }

    private var topFilePath: String? {
        if case .file(let path, _) = presentation.content.reference {
            return path
        }
        return presentation.content.primary
    }
}

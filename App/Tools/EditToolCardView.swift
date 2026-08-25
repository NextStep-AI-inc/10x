import SwiftUI

struct EditToolCardView: View {
    let presentation: ToolPresentation

    var body: some View {
        if let content = ToolContentExtractor.edit(presentation) {
            ToolCardScaffold(
                presentation: presentation,
                title: "Edit",
                fileReference: .file(path: content.path, line: nil)
            ) {
                if let diff = content.unifiedDiff {
                    DiffView(diff: diff, fallbackPath: content.path)
                } else {
                    Text(content.diff)
                        .font(TenXTypography.mono(size: 10))
                        .textSelection(.enabled)
                }
            }
        } else {
            GenericToolCardView(presentation: presentation)
        }
    }

}

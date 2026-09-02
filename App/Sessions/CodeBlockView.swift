import SwiftUI

struct CodeBlockView: View {
    let source: SourcePresentation

    var body: some View {
        SourceCard(presentation: source, lines: source.lines)
    }
}

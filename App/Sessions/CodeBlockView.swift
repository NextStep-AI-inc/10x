import SwiftUI

struct CodeBlockView: View {
    let source: SourcePresentation

    var body: some View {
        SourceSurface(presentation: source)
    }
}

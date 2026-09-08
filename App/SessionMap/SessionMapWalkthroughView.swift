import SwiftUI

struct SessionMapWalkthroughView: View {
    let flow: SessionMapFlow
    @Binding var focus: SessionMapFocus
    let onAction: (SessionMapAction) -> Void

    @FocusState private var isWalkthroughFocused: Bool

    var body: some View {
        if flow.steps.isEmpty {
            EmptyView()
        } else {
            let stepIndex = min(max(0, focus.flowStepIndex ?? 0), flow.steps.count - 1)
            let step = flow.steps[stepIndex]
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(flow.title)
                        .font(TenXTypography.body(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(stepIndex + 1) of \(flow.steps.count)")
                        .font(TenXTypography.body(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
                Text(step.text)
                    .font(TenXTypography.body(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Button("Previous") { select(stepIndex - 1) }
                        .buttonStyle(GhostActionStyle())
                        .disabled(stepIndex == 0)
                    Button("Next") { select(stepIndex + 1) }
                        .buttonStyle(GhostActionStyle())
                        .disabled(stepIndex == flow.steps.count - 1)
                    if let ref = step.ref {
                        Button("Jump") { onAction(.jump(ref: ref)) }
                            .buttonStyle(GhostActionStyle())
                    }
                }
            }
            .padding(10)
            .background(TenXPalette.color(TenXPalette.hoverNeutralHex))
            .focusable()
            .focusEffectDisabled()
            .focused($isWalkthroughFocused)
            .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { press in
                guard isWalkthroughFocused else { return .ignored }
                if press.key == .leftArrow {
                    if stepIndex > 0 { select(stepIndex - 1) }
                    return .handled
                }
                if press.key == .rightArrow {
                    if stepIndex < flow.steps.count - 1 { select(stepIndex + 1) }
                    return .handled
                }
                return .ignored
            }
            .onAppear {
                if focus.flowStepIndex == nil { select(0) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(flow.title), step \(stepIndex + 1) of \(flow.steps.count)")
        }
    }

    private func select(_ index: Int) {
        guard let updatedFocus = Self.focus(
            afterSelecting: index,
            in: flow,
            from: focus
        ) else { return }
        focus = updatedFocus
    }

    static func focus(
        afterSelecting index: Int,
        in flow: SessionMapFlow,
        from focus: SessionMapFocus
    ) -> SessionMapFocus? {
        guard flow.steps.indices.contains(index) else { return nil }
        var updatedFocus = focus
        updatedFocus.flowStepIndex = index
        updatedFocus.selectedNodeID = flow.steps[index].node
        return updatedFocus
    }
}

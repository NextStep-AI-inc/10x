import SwiftUI

struct ExtensionInputSheet: View {
    let request: ExtensionUIState
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var value: String

    init(
        request: ExtensionUIState,
        onSubmit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        if case .editor(_, _, let prefill, _) = request {
            _value = State(initialValue: prefill ?? "")
        } else {
            _value = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(TenXTypography.title(size: 24))

            if isEditor {
                TextEditor(text: $value)
                    .font(TenXTypography.mono(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 180)
                    .overlay {
                        Rectangle().stroke(
                            TenXPalette.color(TenXPalette.nearBlackHex), lineWidth: 1)
                    }
            } else {
                TextField(placeholder, text: $value)
                    .textFieldStyle(.plain)
                    .font(TenXTypography.body(size: 14))
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(TenXPalette.color(TenXPalette.nearBlackHex))
                            .frame(height: 1)
                    }
                    .onSubmit(submit)
            }

            HStack(spacing: 4) {
                Button("Submit", action: submit)
                    .buttonStyle(GhostActionStyle())
                    .disabled(value.isEmpty)
                Button("Cancel", action: onCancel)
                    .buttonStyle(GhostActionStyle(
                        color: TenXPalette.color(TenXPalette.nearBlackHex)))
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(TenXPalette.surfaceElevated)
    }

    private var title: String {
        switch request {
        case .input(_, let title, _, _), .editor(_, let title, _, _): return title
        default: return "Input requested"
        }
    }

    private var placeholder: String {
        if case .input(_, _, let placeholder, _) = request {
            return placeholder ?? "Enter a value"
        }
        return "Enter a value"
    }

    private var isEditor: Bool {
        if case .editor = request { return true }
        return false
    }

    private func submit() {
        guard !value.isEmpty else { return }
        onSubmit(value)
    }
}

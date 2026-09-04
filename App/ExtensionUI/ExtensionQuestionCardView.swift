import SwiftUI

struct ExtensionQuestionSubmissionState: Equatable {
    private(set) var isSubmitting = false
    private(set) var didSucceed = false
    private(set) var errorMessage: String?

    mutating func begin() -> Bool {
        guard !isSubmitting, !didSucceed else { return false }
        isSubmitting = true
        errorMessage = nil
        return true
    }

    mutating func finish(succeeded: Bool) {
        isSubmitting = false
        didSucceed = succeeded
        errorMessage = succeeded ? nil : "Couldn’t send response. Try again."
    }
}

struct ExtensionQuestionCardView: View {
    let state: ExtensionUIState
    let onRespond: (ExtensionUIResponse) async -> Bool

    @State private var value: String
    @State private var submission = ExtensionQuestionSubmissionState()
    @FocusState private var focusedField: QuestionFocus?

    init(
        state: ExtensionUIState,
        onRespond: @escaping (ExtensionUIResponse) async -> Bool
    ) {
        self.state = state
        self.onRespond = onRespond
        if case .editor(_, _, let prefill, _) = state {
            _value = State(initialValue: prefill ?? "")
        } else {
            _value = State(initialValue: "")
        }
    }

    var body: some View {
        CornerCard(color: TenXPalette.color(TenXPalette.nearBlackHex)) {
            VStack(alignment: .leading, spacing: 10) {
                questionContent

                if let errorMessage = submission.errorMessage {
                    Text(errorMessage)
                        .font(TenXTypography.body(size: 10, weight: .medium))
                        .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                        .accessibilityLabel(errorMessage)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(submission.isSubmitting || submission.didSucceed)
        .task {
            await Task.yield()
            focusedField = .primary
        }
    }

    @ViewBuilder
    private var questionContent: some View {
        switch state {
        case .select(_, let title, let options, _):
            Text(title)
                .font(TenXTypography.body(size: 12, weight: .semibold))
                .textSelection(.enabled)
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    submit(.value(option.label))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let detail = option.detail {
                            Text(detail)
                                .font(TenXTypography.body(size: 10))
                                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .buttonStyle(GhostActionStyle())
                .focusable()
                .focusEffectDisabled()
                .focused($focusedField, equals: index == 0 ? .primary : .option(index))
                .accessibilityLabel(ApprovalAccessibility.actionLabel(
                    name: option.label,
                    scope: option.detail ?? "Select option"))
            }
            cancelButton(scope: "Selection")
        case .input(_, let title, let placeholder, _):
            titleText(title)
            TextField(placeholder ?? "Enter a value", text: $value)
                .textFieldStyle(.plain)
                .font(TenXTypography.body(size: 13))
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(TenXPalette.color(TenXPalette.nearBlackHex))
                        .frame(height: 1)
                }
                .focused($focusedField, equals: .primary)
                .onSubmit(submitValue)
            actions
        case .editor(_, let title, _, _):
            titleText(title)
            TextEditor(text: $value)
                .font(TenXTypography.body(size: 12))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 92, maxHeight: 180)
                .overlay {
                    Rectangle().stroke(
                        TenXPalette.color(TenXPalette.separatorHex), lineWidth: 1)
                }
                .focused($focusedField, equals: .primary)
            actions
        default:
            EmptyView()
        }
    }

    private func titleText(_ title: String) -> some View {
        Text(title)
            .font(TenXTypography.body(size: 12, weight: .semibold))
            .textSelection(.enabled)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Button("Submit", action: submitValue)
                .buttonStyle(GhostActionStyle())
                .keyboardShortcut(.return, modifiers: isEditor ? .command : [])
                .disabled(value.isEmpty)
            cancelButton(scope: "Response")
        }
    }

    private func cancelButton(scope: String) -> some View {
        Button("Cancel") { submit(.cancelled(timedOut: false)) }
            .buttonStyle(GhostActionStyle(
                color: TenXPalette.color(TenXPalette.nearBlackHex)))
            .keyboardShortcut(.cancelAction)
            .focusable()
            .focusEffectDisabled()
            .focused($focusedField, equals: .cancel)
            .accessibilityLabel(ApprovalAccessibility.actionLabel(
                name: "Cancel",
                scope: scope))
    }

    private var isEditor: Bool {
        if case .editor = state { return true }
        return false
    }

    private func submitValue() {
        guard !value.isEmpty else { return }
        submit(.value(value))
    }

    private func submit(_ response: ExtensionUIResponse) {
        guard submission.begin() else { return }
        Task {
            let succeeded = await onRespond(response)
            submission.finish(succeeded: succeeded)
        }
    }
}

private enum QuestionFocus: Hashable {
    case primary
    case option(Int)
    case cancel
}

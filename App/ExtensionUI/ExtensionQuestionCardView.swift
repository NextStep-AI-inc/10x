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

struct ExtensionQuestionOptionPresentation: Equatable {
    let title: String
    let detail: String?
    let responseValue: String

    init(option: ExtensionSelectOption) {
        responseValue = option.label
        let lines = option.label.split(
            omittingEmptySubsequences: false,
            whereSeparator: \Character.isNewline)
        let firstLine = lines.first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        title = firstLine.isEmpty ? option.label : firstLine
        let embeddedDetail = lines.dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let structuredDetail = option.detail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        detail = if let structuredDetail, !structuredDetail.isEmpty {
            structuredDetail
        } else if !embeddedDetail.isEmpty {
            embeddedDetail
        } else {
            nil
        }
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
            VStack(alignment: .leading, spacing: 16) {
                questionContent

                if let errorMessage = submission.errorMessage {
                    Text(errorMessage)
                        .font(TenXTypography.body(size: 12, weight: .medium))
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
            questionHeader(title)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    let focus = index == 0 ? QuestionFocus.primary : .option(index)
                    let presentation = ExtensionQuestionOptionPresentation(option: option)
                    ExtensionQuestionOptionButton(
                        presentation: presentation,
                        isFocused: focusedField == focus
                    ) {
                        submit(.value(presentation.responseValue))
                    }
                    .focused($focusedField, equals: focus)
                }
            }
            cancelButton(scope: "Selection")
        case .input(_, let title, let placeholder, _):
            questionHeader(title)
            TextField(placeholder ?? "Enter a value", text: $value)
                .textFieldStyle(.plain)
                .font(TenXTypography.body(size: 13))
                .padding(.horizontal, 10)
                .frame(minHeight: 38)
                .background(TenXPalette.surfaceElevated)
                .overlay {
                    Rectangle().stroke(
                        focusedField == .primary
                            ? TenXPalette.color(TenXPalette.interactiveCyanHex)
                            : TenXPalette.color(TenXPalette.separatorHex),
                        lineWidth: 1)
                }
                .focused($focusedField, equals: .primary)
                .onSubmit(submitValue)
            actions
        case .editor(_, let title, _, _):
            questionHeader(title)
            TextEditor(text: $value)
                .font(TenXTypography.body(size: 13))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 112, maxHeight: 220)
                .background(TenXPalette.surfaceElevated)
                .overlay {
                    Rectangle().stroke(
                        focusedField == .primary
                            ? TenXPalette.color(TenXPalette.interactiveCyanHex)
                            : TenXPalette.color(TenXPalette.separatorHex),
                        lineWidth: 1)
                }
                .focused($focusedField, equals: .primary)
            actions
        default:
            EmptyView()
        }
    }

    private func questionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("RESPONSE NEEDED")
                .font(TenXTypography.mono(size: 9, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
                .accessibilityHidden(true)
            Text(title)
                .font(TenXTypography.body(size: 16, weight: .semibold))
                .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
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

private struct ExtensionQuestionOptionButton: View {
    let presentation: ExtensionQuestionOptionPresentation
    let isFocused: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(presentation.title)
                    .font(TenXTypography.body(size: 13, weight: .medium))
                    .foregroundStyle(isEnabled
                        ? TenXPalette.color(TenXPalette.nearBlackHex)
                        : TenXPalette.color(TenXPalette.mutedTextHex))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = presentation.detail {
                    Text(detail)
                        .font(TenXTypography.body(size: 12))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isActive ? TenXPalette.color(TenXPalette.hoverNeutralHex) : .clear)
            .overlay {
                Rectangle().stroke(
                    isActive
                        ? TenXPalette.color(TenXPalette.interactiveCyanHex)
                        : TenXPalette.color(TenXPalette.separatorHex),
                    lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(TenXPalette.color(TenXPalette.interactiveCyanHex))
                    .frame(width: 2)
                    .opacity(isActive ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .onHover { isHovering = isEnabled && $0 }
        .accessibilityLabel(ApprovalAccessibility.actionLabel(
            name: presentation.title,
            scope: presentation.detail ?? "Select option"))
    }

    private var isActive: Bool {
        isEnabled && (isFocused || isHovering)
    }
}

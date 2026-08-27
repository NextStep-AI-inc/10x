import SwiftUI

enum ProviderAccountSwitchConfirmationFocusTarget: Equatable, Sendable {
    case cancel
}

@MainActor
enum ProviderAccountSwitchConfirmationFocus {
    static func assignInitialFocus(
        _ assign: (ProviderAccountSwitchConfirmationFocusTarget) -> Void
    ) async {
        await Task.yield()
        assign(.cancel)
    }
}

enum ProviderAccountScopeOption: CaseIterable, Hashable, Identifiable, Sendable {
    case thisSession
    case allCurrentSessions
    case allNewSessions

    var id: Self { self }

    var routingScope: ProviderAccountScope {
        switch self {
        case .thisSession: .thisSession
        case .allCurrentSessions: .allCurrentSessions
        case .allNewSessions: .allNewSessions
        }
    }
}

struct ProviderAccountScopeSatisfaction: Equatable, Sendable {
    let isThisSessionSatisfied: Bool
    let areAllCurrentSessionsSatisfied: Bool
    let isAllNewSessionsSatisfied: Bool

    static let none = ProviderAccountScopeSatisfaction(
        isThisSessionSatisfied: false,
        areAllCurrentSessionsSatisfied: false,
        isAllNewSessionsSatisfied: false)
    static let all = ProviderAccountScopeSatisfaction(
        isThisSessionSatisfied: true,
        areAllCurrentSessionsSatisfied: true,
        isAllNewSessionsSatisfied: true)

    var areAllScopesSatisfied: Bool {
        isThisSessionSatisfied
            && areAllCurrentSessionsSatisfied
            && isAllNewSessionsSatisfied
    }

    var firstUnsatisfiedScope: ProviderAccountScopeOption? {
        ProviderAccountScopeOption.allCases.first(where: { !isSatisfied($0) })
    }

    func isSatisfied(_ scope: ProviderAccountScopeOption) -> Bool {
        switch scope {
        case .thisSession: isThisSessionSatisfied
        case .allCurrentSessions: areAllCurrentSessionsSatisfied
        case .allNewSessions: isAllNewSessionsSatisfied
        }
    }
}

struct ProviderAccountSwitchScopePresentation: Equatable, Sendable {
    let scope: ProviderAccountScopeOption
    let title: String
    let message: String
}

struct ProviderAccountSwitchConfirmationPresentation: Equatable, Sendable {
    let title: String
    let message = "Choose where this account should be used."
    let options = [
        ProviderAccountSwitchScopePresentation(
            scope: .thisSession,
            title: "This session",
            message: "Switch the open session. If it is generating, switch after the current turn."),
        ProviderAccountSwitchScopePresentation(
            scope: .allCurrentSessions,
            title: "All current sessions",
            message: "Switch every 10x-managed session using this provider. Generating sessions finish their current turn first."),
        ProviderAccountSwitchScopePresentation(
            scope: .allNewSessions,
            title: "All new sessions",
            message: "Set this as the provider's primary account. Existing sessions stay unchanged."),
    ]
    let cancelActionLabel = "Cancel"
    let confirmActionLabel = "Switch account"
    let usesRadioGroupSemantics = true

    init(accountLabel: String) {
        title = "Use \(accountLabel)?"
    }

    /// What actually restarts, spelled out per scope rather than one
    /// constant string reused for both (task-10b final fix, Finding 3):
    /// `.allCurrentSessions` restarts every 10x-managed session on this
    /// provider, not just the one this dialog was opened from
    /// (`ProviderAccountCoordinator.useAccount`'s `.allCurrentSessions`
    /// case enumerates every managed session for the provider), so a
    /// single "this session" notice understated what that scope actually
    /// does. `.allNewSessions` has no case here because the view never
    /// shows this notice for that scope in the first place — it restarts
    /// nothing (see that option's own message, "Existing sessions stay
    /// unchanged").
    static func restartNoticeText(for scope: ProviderAccountScopeOption) -> String? {
        switch scope {
        case .thisSession:
            "Switching now restarts this session. Your conversation is kept."
        case .allCurrentSessions:
            "Switching now restarts every 10x-managed session using this provider. Conversations are kept."
        case .allNewSessions:
            nil
        }
    }
}

struct ProviderAccountSwitchConfirmationView: View {
    let accountLabel: String
    let satisfaction: ProviderAccountScopeSatisfaction
    let isSwitchAvailable: Bool
    let requiresRestartToSwitch: Bool
    @Binding var selectedScope: ProviderAccountScopeOption
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @FocusState private var isCancelFocused: Bool
    @AccessibilityFocusState private var isCancelAccessibilityFocused: Bool

    private var presentation: ProviderAccountSwitchConfirmationPresentation {
        ProviderAccountSwitchConfirmationPresentation(accountLabel: accountLabel)
    }

    /// `nil` whenever there is nothing to warn about: `requiresRestartToSwitch`
    /// is false (the extension-backed tier switches in place), or the
    /// selected scope is `.allNewSessions`, which restarts nothing (see its
    /// own option message: "Existing sessions stay unchanged"). Otherwise
    /// delegates to `ProviderAccountSwitchConfirmationPresentation
    /// .restartNoticeText(for:)` for copy that actually matches the
    /// selected scope.
    private var restartNoticeText: String? {
        guard requiresRestartToSwitch else { return nil }
        return ProviderAccountSwitchConfirmationPresentation.restartNoticeText(for: selectedScope)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(presentation.title)
                    .font(TenXTypography.accent(size: 20))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                Text(presentation.message)
                    .font(TenXTypography.body(size: 13))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }

            Picker(presentation.message, selection: $selectedScope) {
                ForEach(presentation.options, id: \.scope) { option in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.title)
                            .font(TenXTypography.body(size: 13, weight: .medium))
                            .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                        Text(option.message)
                            .font(TenXTypography.body(size: 11))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            .fixedSize(horizontal: false, vertical: true)
                        // Consequence of the selected choice, told the same
                        // way the choice itself is: an indented continuation
                        // of this option's own description, not a page-level
                        // statement. Gated on the selected scope, not shown
                        // for every option — showing every scope's
                        // consequence at once would change what information
                        // is on screen, not just where it sits.
                        if option.scope == selectedScope, let restartNoticeText {
                            Text(restartNoticeText)
                                .font(TenXTypography.body(size: 11))
                                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tag(option.scope)
                    .disabled(satisfaction.isSatisfied(option.scope))
                    .accessibilityElement(children: .combine)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .accessibilityLabel(presentation.message)

            HStack(spacing: 10) {
                Spacer()
                Button(presentation.cancelActionLabel, action: onCancel)
                    .buttonStyle(GhostActionStyle(
                        color: TenXPalette.color(TenXPalette.nearBlackHex)))
                    .keyboardShortcut(.cancelAction)
                    .focused($isCancelFocused)
                    .accessibilityFocused($isCancelAccessibilityFocused)
                    .onKeyPress(.escape) {
                        onCancel()
                        return .handled
                    }
                Button(presentation.confirmActionLabel, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(TenXPalette.color(TenXPalette.interactiveCyanHex))
                    .disabled(satisfaction.areAllScopesSatisfied || !isSwitchAvailable)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.title)
        .accessibilityAddTraits(.isModal)
        .onExitCommand(perform: onCancel)
        .task {
            await ProviderAccountSwitchConfirmationFocus.assignInitialFocus { target in
                guard target == .cancel else { return }
                isCancelFocused = true
                isCancelAccessibilityFocused = true
            }
        }
    }
}

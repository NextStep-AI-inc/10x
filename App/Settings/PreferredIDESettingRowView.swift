import Foundation
import os
import SwiftUI

struct PreferredIDESettingRowView: View {
    let registry: IDERegistry
    let store: IDEPreferenceStore
    @FocusState.Binding var focusedControl: SettingsFocusTarget?

    @State private var saveError: String?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tannerpham.tenx",
        category: "Settings")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Preferred IDE")
                        .font(TenXTypography.body(size: 13, weight: .semibold))
                    Text("Open file references in this application")
                        .font(TenXTypography.body(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    ForEach(registry.installedApplications()) { application in
                        Button(application.displayName) {
                            select(application)
                        }
                    }

                    if let application = selectedCustomApplication {
                        Button(application.displayName) {
                            select(application)
                        }
                    }

                    Divider()

                    Button("Choose application…") {
                        guard let application = registry.chooseApplication() else { return }
                        select(application)
                    }

                    Button("None") {
                        store.clear()
                        saveError = nil
                    }
                } label: {
                    Text(Self.valueLabel(for: store.state))
                        .font(TenXTypography.body(size: 12))
                        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                }
                .menuStyle(.borderlessButton)
                .focused($focusedControl, equals: .preferredIDE)
                .frame(width: 300, alignment: .trailing)
                .accessibilityLabel(Self.accessibilitySemantics(for: store.state).label)
                .accessibilityValue(Self.accessibilitySemantics(for: store.state).value)
            }

            if let saveError {
                Text(saveError)
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            }
        }
        .padding(.vertical, 15)
        .accessibilityElement(children: .contain)
    }

    nonisolated static func valueLabel(for state: IDEPreferenceState) -> String {
        switch state {
        case .none: "Choose IDE"
        case .available(let application): application.displayName
        case .unavailable(let displayName): "\(displayName) · Unavailable"
        }
    }

    nonisolated static func accessibilitySemantics(
        for state: IDEPreferenceState
    ) -> (label: String, value: String) {
        (label: "Preferred IDE", value: valueLabel(for: state))
    }

    nonisolated static func matches(query: String, applicationName: String?) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return ["Preferred IDE", "editor", "Open file references in this application", applicationName]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private var selectedCustomApplication: IDEApplication? {
        guard case .available(let application) = store.state, application.source == .custom else {
            return nil
        }
        return application
    }

    private func select(_ application: IDEApplication) {
        saveError = nil
        do {
            try store.select(application)
        } catch {
            Self.logger.error("[Settings:PreferredIDESettingRowView] Could not save preferred application")
            saveError = "Couldn’t save the application"
        }
    }
}

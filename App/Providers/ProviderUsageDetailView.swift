import SwiftUI

struct ProviderUsageDetailView: View {
    let usage: ProviderUsagePresentation
    let providers: [ProviderLoginProvider]
    let usageMessage: String?
    let hasSuccessfulUsage: Bool
    let onRefresh: () -> Void
    let onReconnect: (ProviderLoginProvider) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let usageMessage, hasSuccessfulUsage {
                    usageRecovery(message: usageMessage)
                }

                if hasContent {
                    providerSections
                    unavailableSections
                    credentialSections
                } else if !hasSuccessfulUsage {
                    initialFailure
                } else {
                    Text("No usage data available.")
                        .font(TenXTypography.body(size: 12))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .padding(.vertical, 30)
                }
            }
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
    }

    private var hasContent: Bool {
        !usage.providers.isEmpty
            || !usage.accountsWithoutUsage.isEmpty
            || !usage.credentialIssues.isEmpty
    }

    private var providerSections: some View {
        ForEach(usage.providers) { provider in
            providerSection(name: provider.name, accounts: provider.accounts)
        }
    }

    private var unavailableSections: some View {
        ForEach(groupedUnavailableAccounts, id: \.providerID) { group in
            providerSection(name: providerName(for: group.providerID), accounts: group.accounts)
        }
    }

    private var credentialSections: some View {
        ForEach(usage.credentialIssues) { issue in
            VStack(alignment: .leading, spacing: 9) {
                sectionHeader(issue.providerName)
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.label)
                            .font(TenXTypography.body(size: 13, weight: .medium))
                        Text("Reconnect to update usage.")
                            .font(TenXTypography.body(size: 12))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    }
                    Spacer()
                    if let provider = providers.first(where: { $0.id == issue.providerID }) {
                        Button("Reconnect") { onReconnect(provider) }
                            .buttonStyle(GhostActionStyle())
                            .disabled(!provider.isAvailable)
                            .accessibilityLabel("Reconnect \(provider.name)")
                    }
                }
                .padding(.bottom, 17)
            }
        }
    }

    private func providerSection(name: String, accounts: [ProviderUsageAccount]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(name)
            ForEach(accounts) { account in
                accountSection(account)
            }
        }
    }

    private func sectionHeader(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(TenXTypography.accent(size: 19))
                .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
            Rectangle()
                .fill(TenXPalette.color(TenXPalette.cyanHex))
                .frame(height: 2)
        }
        .padding(.top, 26)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func accountSection(_ account: ProviderUsageAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(account.label)
                .font(TenXTypography.body(size: 13, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))

            if account.isUsageAvailable {
                ForEach(account.limits) { limit in
                    ProviderUsageLimitDetailView(providerName: account.label, limit: limit)
                }
                ForEach(account.amounts) { amount in
                    Text("\(formattedAmount(amount.value)) \(amount.unit) used")
                        .font(TenXTypography.body(size: 12))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
                ForEach(uniqueNotes(account.notes), id: \.self) { note in
                    Text(note)
                        .font(TenXTypography.body(size: 12))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
            } else {
                Text("Usage data unavailable.")
                    .font(TenXTypography.body(size: 12))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
        }
        .padding(.bottom, 18)
    }

    private func usageRecovery(message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(message)
                .font(TenXTypography.body(size: 12))
                .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            Spacer()
            Button("Try again", action: onRefresh)
                .buttonStyle(GhostActionStyle())
        }
        .padding(.top, 16)
    }

    private var initialFailure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage couldn’t be loaded.")
                .font(TenXTypography.body(size: 13))
                .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            Button("Try again", action: onRefresh)
                .buttonStyle(GhostActionStyle())
        }
        .padding(.vertical, 30)
    }

    private var groupedUnavailableAccounts: [UnavailableAccountGroup] {
        Dictionary(grouping: usage.accountsWithoutUsage, by: providerID(for:))
            .map { UnavailableAccountGroup(providerID: $0.key, accounts: $0.value) }
            .sorted { $0.providerID.localizedStandardCompare($1.providerID) == .orderedAscending }
    }

    private func providerID(for account: ProviderUsageAccount) -> String {
        account.id.split(separator: ":", maxSplits: 1).first.map(String.init) ?? account.id
    }

    private func providerName(for providerID: String) -> String {
        providers.first(where: { $0.id == providerID })?.name ?? providerID
    }

    private func uniqueNotes(_ notes: [String]) -> [String] {
        notes.reduce(into: [String]()) { result, note in
            if !result.contains(note) { result.append(note) }
        }
    }

    private func formattedAmount(_ amount: Double) -> String {
        amount.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private struct UnavailableAccountGroup: Identifiable {
    let providerID: String
    let accounts: [ProviderUsageAccount]

    var id: String { providerID }
}

private struct ProviderUsageLimitDetailView: View {
    let providerName: String
    let limit: ProviderUsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(limit.label)
                    .font(TenXTypography.body(size: 12))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                Spacer()
                Text("\(min(max(limit.percentage, 0), 100))% remaining")
                    .font(TenXTypography.mono(size: 10, weight: .medium))
                    .foregroundStyle(toneColor)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(TenXPalette.color(TenXPalette.separatorHex))
                    Rectangle()
                        .fill(toneColor)
                        .frame(width: proxy.size.width * limit.normalizedFraction)
                }
            }
            .frame(height: 4)
            if let detailReset = limit.detailReset {
                Text("Resets \(detailReset)")
                    .font(TenXTypography.body(size: 11))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
        }
        .padding(.bottom, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let reset = limit.detailReset.map { ", resets \($0)" } ?? ""
        return "\(providerName), \(limit.label), \(min(max(limit.percentage, 0), 100)) percent remaining\(reset)"
    }

    private var toneColor: Color {
        switch limit.tone {
        case .standard:
            TenXPalette.color(TenXPalette.cyanHex)
        case .warning:
            TenXPalette.color(TenXPalette.yellowHex)
        case .exhausted:
            TenXPalette.color(TenXPalette.signalRedHex)
        }
    }
}

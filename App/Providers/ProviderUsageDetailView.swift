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

                if !groups.isEmpty {
                    ForEach(groups) { group in
                        providerSection(group)
                    }
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

    private func providerSection(_ group: ProviderUsageDetailGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(group.name)
            ForEach(group.accounts) { account in
                accountSection(account)
            }
            ForEach(group.credentialIssues) { issue in
                credentialIssueRow(issue)
            }
        }
    }

    private func credentialIssueRow(_ issue: ProviderCredentialIssue) -> some View {
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

    private var groups: [ProviderUsageDetailGroup] {
        ProviderUsageDetailGroup.make(usage: usage, providers: providers)
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

struct ProviderUsageDetailGroup: Identifiable, Equatable, Sendable {
    let providerID: String
    let name: String
    let accounts: [ProviderUsageAccount]
    let credentialIssues: [ProviderCredentialIssue]

    var id: String { providerID }

    static func make(
        usage: ProviderUsagePresentation,
        providers: [ProviderLoginProvider]
    ) -> [ProviderUsageDetailGroup] {
        var providerIDs: [String] = []
        var names: [String: String] = [:]
        var accounts: [String: [ProviderUsageAccount]] = [:]
        var credentialIssues: [String: [ProviderCredentialIssue]] = [:]

        func ensureProvider(_ providerID: String, name: String) {
            guard names[providerID] == nil else { return }
            providerIDs.append(providerID)
            names[providerID] = name
        }

        for provider in usage.providers {
            ensureProvider(provider.id, name: provider.name)
            accounts[provider.id, default: []].append(contentsOf: provider.accounts)
        }
        for account in usage.accountsWithoutUsage {
            let providerID = providerID(for: account)
            ensureProvider(providerID, name: providerName(providerID, providers: providers))
            accounts[providerID, default: []].append(account)
        }
        for issue in usage.credentialIssues {
            ensureProvider(issue.providerID, name: issue.providerName)
            credentialIssues[issue.providerID, default: []].append(issue)
        }

        return providerIDs.map { providerID in
            ProviderUsageDetailGroup(
                providerID: providerID,
                name: names[providerID] ?? providerID,
                accounts: accounts[providerID] ?? [],
                credentialIssues: credentialIssues[providerID] ?? [])
        }
    }

    private static func providerID(for account: ProviderUsageAccount) -> String {
        account.id.split(separator: ":", maxSplits: 1).first.map(String.init) ?? account.id
    }

    private static func providerName(
        _ providerID: String,
        providers: [ProviderLoginProvider]
    ) -> String {
        providers.first(where: { $0.id == providerID })?.name ?? providerID
    }
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

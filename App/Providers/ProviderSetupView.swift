import SwiftUI

struct ProviderSetupView: View {
    let model: ProviderManagementViewModel
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            BrandWordmark(width: 48)

            VStack(alignment: .leading, spacing: 8) {
                Text("Connect a provider")
                    .font(TenXTypography.title(size: 38))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                Text("Choose at least one provider to start sessions.")
                    .font(TenXTypography.body(size: 14))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }

            providerList

            Button("Continue", action: onContinue)
                .buttonStyle(GhostActionStyle())
                .disabled(!model.hasAuthenticatedProvider)
        }
        .frame(width: 470, alignment: .leading)
        .padding(56)
        .sheet(item: extensionSheetBinding) { request in
            ExtensionInputSheet(
                request: request,
                onSubmit: { value in
                    Task { await model.respond(to: request, with: .value(value)) }
                },
                onCancel: {
                    Task {
                        await model.respond(
                            to: request,
                            with: .cancelled(timedOut: false))
                    }
                })
        }
    }

    @ViewBuilder
    private var providerList: some View {
        if let providerMessage = model.providerMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text(providerMessage)
                    .font(TenXTypography.body(size: 13))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                Button("Try again") {
                    Task { await model.load() }
                }
                .buttonStyle(GhostActionStyle())
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if model.isShowingAllProviders {
                    TextField("Search providers", text: queryBinding)
                        .textFieldStyle(.plain)
                        .font(TenXTypography.body(size: 14))
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(TenXPalette.color(TenXPalette.nearBlackHex))
                                .frame(height: 1)
                        }
                }

                if let loginMessage = model.loginMessage {
                    Text(loginMessage)
                        .font(TenXTypography.body(size: 13))
                        .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                }

                if model.isShowingAllProviders {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            providerRows
                        }
                    }
                    .scrollIndicators(.visible)
                    .frame(height: 144)
                } else {
                    providerRows
                }

                if !model.isShowingAllProviders {
                    Button("Browse all providers", action: model.showAllProviders)
                        .buttonStyle(GhostActionStyle())
                }
            }
        }
    }

    private var providerRows: some View {
        ForEach(model.visibleProviders) { provider in
            ProviderSetupRowView(provider: provider, model: model)
        }
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { model.query },
            set: { model.query = $0 })
    }

    private var extensionSheetBinding: Binding<ExtensionUIState?> {
        Binding(
            get: { model.sheetRequest },
            set: { state in
                guard state == nil, let request = model.sheetRequest else { return }
                Task {
                    await model.respond(
                        to: request,
                        with: .cancelled(timedOut: false))
                }
            })
    }
}

private struct ProviderSetupRowView: View {
    let provider: ProviderLoginProvider
    let model: ProviderManagementViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text(provider.name)
                .font(TenXTypography.body(size: 14, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))

            Spacer(minLength: 12)

            if model.activeLoginProviderID == provider.id {
                Text("Connecting…")
                    .font(TenXTypography.body(size: 12))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                Button("Cancel") {
                    Task { await model.cancelLogin() }
                }
                .buttonStyle(GhostActionStyle(
                    color: TenXPalette.color(TenXPalette.nearBlackHex)))
            } else if provider.isAuthenticated {
                Text("Connected")
                    .font(TenXTypography.body(size: 12))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            } else {
                Button("Connect") {
                    Task { await model.login(provider) }
                }
                .buttonStyle(GhostActionStyle())
                .disabled(!provider.isAvailable || model.activeLoginProviderID != nil)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TenXPalette.color(TenXPalette.separatorHex))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

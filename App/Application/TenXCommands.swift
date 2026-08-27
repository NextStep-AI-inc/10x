import OmpKit
import SwiftUI

struct TenXCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session", action: model.openNewSession)
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!model.menuState.isWorkspaceAvailable)

            Button("Choose Project…", action: model.chooseNewProject)
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!model.menuState.isWorkspaceAvailable)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                model.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(!model.menuState.isWorkspaceAvailable)
        }

        CommandMenu("Navigate") {
            Button("Search Sessions…", action: model.openSearch)
                .keyboardShortcut("k", modifiers: .command)
                .disabled(!model.menuState.isWorkspaceAvailable)

            Divider()

            Button("Previous Session", action: model.openPreviousSession)
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(model.menuState.previousSession == nil)

            Button("Next Session", action: model.openNextSession)
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(model.menuState.nextSession == nil)

            Divider()

            Button("Archived Sessions", action: model.openArchivedSessions)
                .disabled(!model.menuState.isWorkspaceAvailable)

            Divider()

            Button("Provider Connections") {
                model.openProviders(.connections)
            }
            .disabled(!model.menuState.isWorkspaceAvailable || model.providerModel == nil)

            Button("Provider Usage") {
                model.openProviders(.usage)
            }
            .disabled(!model.menuState.isWorkspaceAvailable || model.providerModel == nil)
        }

        CommandMenu("Session") {
            Button("Stop Response") {
                Task { await model.activeSession?.abort() }
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!model.menuState.canStopResponse)

            Picker("Message Behavior", selection: messageBehavior) {
                Text("Steer").tag(StreamingBehavior.steer)
                Text("Follow Up").tag(StreamingBehavior.followUp)
            }
            .disabled(!model.menuState.canChooseMessageBehavior)

            Divider()

            Button("Archive Session") {
                Task { await model.archiveCurrentSession() }
            }
            .disabled(!model.menuState.canArchiveSession)
        }
    }

    private var messageBehavior: Binding<StreamingBehavior> {
        Binding(
            get: { model.activeSession?.streamingBehavior ?? .steer },
            set: { model.activeSession?.selectStreamingBehavior($0) })
    }
}

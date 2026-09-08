import OmpKit

enum ComposerCommandCatalogState: Equatable, Sendable {
    case loading
    case available([AvailableSlashCommand])
    case unavailable
}

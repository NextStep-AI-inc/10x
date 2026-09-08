import Foundation

struct Flyer: Equatable, Sendable {
    enum Scope: Equatable, Hashable, Sendable {
        case global
        case session(String)
    }

    enum Tone: Equatable, Sendable {
        case information
        case attention
        case error
    }

    struct Action: Equatable, Sendable, Identifiable {
        let id: String
        let title: String
    }

    struct Key: Equatable, Hashable, Sendable {
        let scope: Scope
        let id: String
    }

    let id: String
    let scope: Scope
    let tone: Tone
    let title: String
    let detail: String
    let actions: [Action]
    let isDismissible: Bool
    let expiresAt: Date?

    var key: Key {
        Key(scope: scope, id: id)
    }
}
